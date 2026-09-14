import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Thin cross-platform wrapper around WKWebView. This is deliberately not a
/// re-implementation of the panel — it loads the real, live admin panel
/// (same HTML/CSS/JS the browser gets), so there is exactly one version of
/// the product to keep in sync, not two. What makes it feel like a native
/// app rather than "a website in a box" is entirely in how this wrapper is
/// configured: no visible browser chrome, no white flashes, safe-area-aware,
/// a native pull-to-refresh gesture, and no text-selection callouts.
struct NoktaWebView: PlatformViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    let webView: WKWebView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView {
        configure(webView, context: context)

        let refresh = UIRefreshControl()
        refresh.tintColor = NoktaUIColor.ember
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.pulledToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        webView.scrollView.bounces = true

        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    #else
    func makeNSView(context: Context) -> WKWebView {
        configure(webView, context: context)
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    #endif

    private func configure(_ webView: WKWebView, context: Context) {
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Kill the "this is a webpage" tells: no white flash while loading
        // or overscrolling, no text-selection magnifier/callout menu.
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = NoktaUIColor.bg
        webView.scrollView.backgroundColor = NoktaUIColor.bg
        if #available(iOS 15.0, *) { webView.underPageBackgroundColor = NoktaUIColor.bg }
        #else
        webView.setValue(false, forKey: "drawsBackground")
        #endif

        if webView.url == nil {
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: NoktaWebView
        init(_ parent: NoktaWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.canGoBack = webView.canGoBack
            #if os(iOS)
            webView.scrollView.refreshControl?.endRefreshing()
            #endif
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            #if os(iOS)
            webView.scrollView.refreshControl?.endRefreshing()
            #endif
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            #if os(iOS)
            webView.scrollView.refreshControl?.endRefreshing()
            #endif
        }

        #if os(iOS)
        @objc func pulledToRefresh() {
            parent.webView.reload()
        }
        #endif

        // MARK: - WKUIDelegate (alert/confirm/prompt)
        //
        // Without a uiDelegate, WKWebView silently no-ops every
        // window.alert/confirm/prompt call — no dialog, no error, the call
        // just resolves as if cancelled. The web panel gates several
        // destructive actions (eliminarGasto, eliminarCliente, ...) behind
        // `confirm(...)`, so without this those buttons looked broken:
        // nothing happened when tapped.

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            presentAlert(message: message, style: .alert) { _, _ in completionHandler() }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            presentAlert(message: message, style: .confirm) { confirmed, _ in completionHandler(confirmed) }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            presentAlert(message: prompt, style: .prompt, defaultText: defaultText) { confirmed, text in
                completionHandler(confirmed ? (text ?? "") : nil)
            }
        }

        private enum DialogStyle { case alert, confirm, prompt }

        private func presentAlert(message: String, style: DialogStyle, defaultText: String? = nil, completion: @escaping (Bool, String?) -> Void) {
            #if os(macOS)
            let alert = NSAlert()
            alert.messageText = "Nokta Studio"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            if style != .alert { alert.addButton(withTitle: "Cancelar") }

            var inputField: NSTextField?
            if style == .prompt {
                let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
                field.stringValue = defaultText ?? ""
                alert.accessoryView = field
                inputField = field
            }

            let response = alert.runModal()
            let confirmed = response == .alertFirstButtonReturn
            completion(confirmed, inputField?.stringValue)
            #else
            guard let root = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?.rootViewController
            else {
                completion(false, nil)
                return
            }
            var topController = root
            while let presented = topController.presentedViewController { topController = presented }

            let alertController = UIAlertController(title: "Nokta Studio", message: message, preferredStyle: .alert)
            if style == .prompt {
                alertController.addTextField { $0.text = defaultText }
            }
            if style != .alert {
                alertController.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completion(false, nil) })
            }
            alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completion(true, alertController.textFields?.first?.text)
            })
            topController.present(alertController, animated: true)
            #endif
        }
    }
}

/// One script, injected client-side only (never touches the server's
/// actual HTML), that makes the mobile web layout sit correctly inside a
/// native app chrome: the hamburger sidebar toggle gets pushed below the
/// notch/Dynamic Island via `env(safe-area-inset-top)`, and long-press
/// text-selection callouts are disabled outside of actual form fields so
/// interactions read as "app" rather than "webpage".
func makeNoktaWebViewConfiguration() -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    let css = """
    :root { --nokta-safe-top: env(safe-area-inset-top, 0px); --nokta-safe-bottom: env(safe-area-inset-bottom, 0px); }
    .sb-toggle { top: calc(14px + var(--nokta-safe-top)) !important; }
    .sb.open { padding-top: var(--nokta-safe-top); }
    body, .main { padding-bottom: max(var(--nokta-safe-bottom), 0px); }
    body, p, div, span, td, th, li, label, button, a {
      -webkit-touch-callout: none;
      -webkit-user-select: none;
      user-select: none;
    }
    input, textarea { -webkit-user-select: text; user-select: text; }
    """
    let js = """
    (function() {
      var style = document.createElement('style');
      style.textContent = \(String(reflecting: css));
      document.head.appendChild(style);
      var viewport = document.querySelector('meta[name="viewport"]');
      if (viewport) { viewport.setAttribute('content', viewport.content + ', viewport-fit=cover'); }
    })();
    """
    let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    config.userContentController.addUserScript(script)
    return config
}

#if os(iOS)
enum NoktaUIColor {
    static let bg = UIColor(red: 0x1C/255.0, green: 0x1C/255.0, blue: 0x1A/255.0, alpha: 1)
    static let ember = UIColor(red: 0xB8/255.0, green: 0x52/255.0, blue: 0x28/255.0, alpha: 1)
}
protocol PlatformViewRepresentable: UIViewRepresentable {}
#else
protocol PlatformViewRepresentable: NSViewRepresentable {}
#endif
