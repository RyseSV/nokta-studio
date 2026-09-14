import Foundation
import WebKit

enum PDFRenderError: LocalizedError {
    case loadFailed(Error)
    case renderFailed(Error)
    var errorDescription: String? {
        switch self {
        case .loadFailed(let e): return "No se pudo preparar el documento: \(e.localizedDescription)"
        case .renderFailed(let e): return "No se pudo generar el PDF: \(e.localizedDescription)"
        }
    }
}

/// Renders a `PDFTemplates` HTML string to a real PDF file via an
/// off-screen WKWebView — same approach the web uses (html2pdf.js renders
/// HTML to a canvas/PDF in-browser), just using WebKit's own PDF export
/// instead of that JS library.
@MainActor
final class PDFRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?

    func renderToPDF(html: String, suggestedName: String) async throws -> URL {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123))
        self.webView = webView
        webView.navigationDelegate = self

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            webView.loadHTMLString(html, baseURL: nil)
        }

        let data: Data
        do {
            data = try await webView.pdf(configuration: WKPDFConfiguration())
        } catch {
            throw PDFRenderError.renderFailed(error)
        }

        let safeName = safeFileNameComponent(suggestedName)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).pdf")
        try data.write(to: url)
        self.webView = nil
        return url
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: PDFRenderError.loadFailed(error))
        continuation = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: PDFRenderError.loadFailed(error))
        continuation = nil
    }
}

private func safeFileNameComponent(_ s: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let cleaned = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.reduce(into: "") { $0.append($1) }
    return cleaned.isEmpty ? "documento" : cleaned
}
