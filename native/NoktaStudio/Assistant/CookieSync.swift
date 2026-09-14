import Foundation
import WebKit

/// The user only ever logs in once, inside the WKWebView (there is no
/// separate native login screen). The Assistant's tool calls go out over a
/// plain URLSession, which has its own cookie jar — so before any tool call
/// we copy the session cookie set by the web login over into URLSession's
/// shared storage. Same account, same session, no second auth flow.
enum CookieSync {
    static func syncFromWebView() async {
        let wkCookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        for cookie in wkCookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
}

private extension WKHTTPCookieStore {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            getAllCookies { continuation.resume(returning: $0) }
        }
    }
}
