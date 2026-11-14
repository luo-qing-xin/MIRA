import SwiftUI
import WebKit

/// 通用「在 MIRA 里登录一次，只取 Cookie」的窗口。
/// UniCourse 与学习通共用这套抓取逻辑：登录成功时把指定域下的 Cookie 拼成一个头，
/// 交给各自的 Hub 方法落盘（0600），密码不离开这个 WebView。
struct WebLoginSheet: View {
    let title: String
    let subtitle: String
    let start: URL
    let cookieDomain: String
    let isSignedIn: (URL) -> Bool
    let onSession: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = WebLoginModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(editorial(16, .semibold))
                    Text(subtitle).font(ui(10.5)).foregroundStyle(quiet)
                }
                Spacer()
                Button("已登录，保存会话") { model.capture(cookieDomain: cookieDomain) }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                Button("取消") { dismiss() }
                    .buttonStyle(EditorialButtonStyle(kind: .text))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Rectangle().fill(oatmeal.opacity(0.6)).frame(height: 1)
            WebLoginView(model: model, start: start, cookieDomain: cookieDomain, isSignedIn: isSignedIn)
            Rectangle().fill(oatmeal.opacity(0.6)).frame(height: 1)
            Text(model.trace.isEmpty
                 ? "登录成功后窗口会自动关闭；MIRA 只保存会话 Cookie，不保存密码。过期时在设置页点「重新登录」再走一次。"
                 : "最近：" + String(model.trace.prefix(180)))
                .font(ui(9)).foregroundStyle(model.trace.isEmpty ? faint : quiet)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .frame(width: 900, height: 620)
        .background(paper)
        .onAppear { model.onCookie = { cookie in onSession(cookie); dismiss() } }
    }
}

/// 登录窗口的诊断日志：本机 0600，只记事件与 URL，不记密码。
enum WebLoginLog {
    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MIRA/web-login-debug.log")

    static func append(_ line: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        guard let data = (stamp + " " + line + "\n").data(using: .utf8) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: path) {
            defer { try? handle.close() }
            if let size = try? handle.seekToEnd(), size > 300_000 { try? handle.truncate(atOffset: 0) }
            handle.write(data)
        } else {
            try? data.write(to: path)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        }
    }
}

@MainActor final class WebLoginModel: ObservableObject {
    weak var webView: WKWebView?
    var onCookie: ((String) -> Void)?
    private(set) var captured = false
    @Published var trace = ""

    func resetCapture() { captured = false }

    func record(_ line: String) {
        trace = line
        WebLoginLog.append(line)
    }

    func capture(cookieDomain: String) {
        guard !captured, let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        captured = true
        store.getAllCookies { [weak self] cookies in
            var names = Set<String>()
            var pairs: [(String, String)] = []
            for cookie in cookies where cookie.domain.hasSuffix(cookieDomain) {
                if names.insert(cookie.name).inserted {
                    pairs.append((cookie.name, cookie.value))
                } else if let index = pairs.firstIndex(where: { $0.0 == cookie.name }) {
                    pairs[index].1 = cookie.value
                }
            }
            let header = pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
            Task { @MainActor in
                guard let self else { return }
                if header.isEmpty { self.resetCapture(); return }
                self.onCookie?(header)
            }
        }
    }
}

private struct WebLoginView: NSViewRepresentable {
    let model: WebLoginModel
    let start: URL
    let cookieDomain: String
    let isSignedIn: (URL) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, cookieDomain: cookieDomain, isSignedIn: isSignedIn)
    }

    private static let instrumentation = """
    (function(){
      if (window.__miraLoginHooked) { return; }
      window.__miraLoginHooked = true;
      function post(kind, text) {
        try { window.webkit.messageHandlers.miraLoginLog.postMessage(kind + " " + String(text).slice(0, 300)); } catch (e) {}
      }
      window.addEventListener("error", function (e) {
        post("js", (e.message || "") + " @" + (e.filename || "") + ":" + (e.lineno || 0));
      });
      window.addEventListener("unhandledrejection", function (e) {
        post("reject", (e.reason && (e.reason.message || e.reason)) || "");
      });
      document.addEventListener("click", function (e) {
        var t = e.target || {};
        post("click", (t.id || "") + " " + (t.className || "") + " <" + (t.tagName || "") + ">");
      }, true);
      var open = XMLHttpRequest.prototype.open;
      var send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (m, u) { this.__mira = m + " " + u; return open.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function () {
        var xhr = this;
        xhr.addEventListener("loadend", function () {
          post("xhr", (xhr.__mira || "") + " -> " + xhr.status + " " + String(xhr.responseText || "").slice(0, 200));
        });
        return send.apply(this, arguments);
      };
      var fetch = window.fetch;
      if (fetch) {
        window.fetch = function () {
          var args = arguments;
          return fetch.apply(this, args).then(function (r) {
            post("fetch", String(args[0]) + " -> " + r.status);
            return r;
          }).catch(function (e) {
            post("fetch", String(args[0]) + " error " + e);
            throw e;
          });
        };
      }
    })();
    """

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.instrumentation, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(context.coordinator, name: "miraLoginLog")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) { web.isInspectable = true }
        model.webView = web
        context.coordinator.startWatching(web)
        web.load(URLRequest(url: start))
        return web
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopWatching()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "miraLoginLog")
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let model: WebLoginModel
        let cookieDomain: String
        let isSignedIn: (URL) -> Bool
        private var watch: Timer?

        init(model: WebLoginModel, cookieDomain: String, isSignedIn: @escaping (URL) -> Bool) {
            self.model = model
            self.cookieDomain = cookieDomain
            self.isSignedIn = isSignedIn
        }

        /// 登录后可能是 SPA 的客户端路由跳转，不会触发 didFinish；
        /// 每秒读一次 location，等路径离开登录页再取 Cookie。
        func startWatching(_ webView: WKWebView) {
            watch?.invalidate()
            watch = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                webView.evaluateJavaScript("location.href") { value, _ in
                    guard let text = value as? String, let url = URL(string: text),
                          self.isSignedIn(url) else { return }
                    self.model.capture(cookieDomain: self.cookieDomain)
                    self.watch?.invalidate()
                }
            }
            RunLoop.main.add(watch!, forMode: .common)
        }

        func stopWatching() {
            watch?.invalidate()
            watch = nil
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "miraLoginLog" else { return }
            model.record((message.body as? String) ?? "")
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.record("navigate " + (webView.url?.absoluteString ?? ""))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.record("loaded " + (webView.url?.absoluteString ?? ""))
            guard let url = webView.url, isSignedIn(url) else { return }
            model.capture(cookieDomain: cookieDomain)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            model.record("popup " + (navigationAction.request.url?.absoluteString ?? ""))
            // 表单可能以 POST 打开新窗口，保留原始 request 而不是只取 URL。
            webView.load(navigationAction.request)
            return nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.record("failed " + error.localizedDescription)
            model.resetCapture()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            model.record("failed " + error.localizedDescription)
        }
    }
}
