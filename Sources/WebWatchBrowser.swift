import AppKit
import SwiftUI
import WebKit

// MARK: - 抓取

struct WebWatchSelector: Equatable {
    var selector: String
    var signature: WebWatchSignature?
    var route: WebWatchRoute? = nil
}

struct WebWatchOutcome {
    var scan: WebWatchScan?
    var items: [WebWatchItem] = []
    var found = true
    var error: String?
    var signedOut = false
    var coverage: String?
    var checkedAt = Date()
}

/// 无窗口的 WKWebView 抓取器：沿用 MIRA 默认 WebKit 数据仓库里的登录态，
/// 因此用户在监控编辑器里登录过一次，之后的定时检查仍然带着会话。
@MainActor
final class WebWatchLoader: NSObject, WKNavigationDelegate {
    struct Loaded {
        var scan: WebWatchScan
        var items: [WebWatchItem]
        var found: Bool
        var pages: Int = 1
    }
    private var webView: WKWebView?
    private var navigating = false
    private var navigationError: Error?
    private func failure(_ message: String) -> NSError {
        NSError(domain: "MIRA.WebWatch", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { navigating = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { navigating = false }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { navigationError = error; navigating = false }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }
    private func json(_ value: String) -> String {
        String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }
    func load(url: URL, selector: WebWatchSelector?, timeout seconds: TimeInterval = 45) async throws -> Loaded {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(WKUserScript(source: WebWatchScript.source,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        web.navigationDelegate = self
        webView = web
        defer { web.stopLoading(); web.navigationDelegate = nil; webView = nil }
        navigating = true
        web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        let route = selector?.route ?? WebWatchRoute()
        var entryDone = route.entrySelector.isEmpty
        var collected: [WebWatchItem] = []
        var fingerprints = Set<String>()
        var previousPage = ""
        for page in 1...max(1, min(route.maxPages, 100)) {
            let deadline = Date().addingTimeInterval(seconds)
            var stable = 0
            var previous = ""
            var ready: Loaded?
            while Date() < deadline {
                try await Task.sleep(nanoseconds: 500_000_000)
                try Task.checkCancellation()
                if let error = navigationError { throw error }
                guard !navigating, !web.isLoading else { continue }
                if !entryDone {
                    let clicked = try await web.evaluateJavaScript("(function(){var e=document.querySelector(" + json(route.entrySelector) + ");if(!e)return false;e.click();return true;})()")
                    guard clicked as? Bool == true else { continue }
                    entryDone = true
                    continue
                }
                _ = try await web.evaluateJavaScript(WebWatchScript.source)
                guard let raw = try await web.evaluateJavaScript(WebWatchScript.scanCall) as? String,
                      let data = raw.data(using: .utf8) else { continue }
                let scan = try JSONDecoder().decode(WebWatchScan.self, from: data)
                if scan.loginSuspected { return Loaded(scan: scan, items: [], found: false) }
                var extraction = WebWatchExtraction(items: [], found: true)
                if let selector {
                    let call = WebWatchScript.extractCall(selector: selector.selector, signature: selector.signature, route: route)
                    guard let raw = try await web.evaluateJavaScript(call) as? String, let data = raw.data(using: .utf8) else { continue }
                    extraction = try JSONDecoder().decode(WebWatchExtraction.self, from: data)
                    if !extraction.found { continue }
                    if extraction.items.isEmpty {
                        let empty = try await web.evaluateJavaScript("/暂无作业|暂无任务|暂无数据|没有作业|no assignments|no items/i.test(document.body.innerText)") as? Bool ?? false
                        if !empty { continue }
                    }
                }
                let loading = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('[aria-busy=true], .loading, .spinner')).some(e=>e.getClientRects().length>0)") as? Bool ?? false
                if loading { stable = 0; continue }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let token = selector == nil ? scan.fingerprint : String(data: try encoder.encode(extraction.items), encoding: .utf8)!
                if page > 1 && token == previousPage { continue }
                stable = token == previous ? stable + 1 : 0
                previous = token
                if stable >= 3 { ready = Loaded(scan: scan, items: extraction.items, found: extraction.found, pages: page); break }
            }
            guard var result = ready else { throw failure("页面未就绪或翻页未产生新内容；保留上次数据，请检查入口、列表与分页规则。") }
            guard fingerprints.insert(previous).inserted else { throw failure("分页出现循环，未保存本轮结果。") }
            previousPage = previous
            collected += result.items
            if selector == nil || route.nextSelector.isEmpty { result.items = collected; return result }
            let next = """
            (function(){var d=document;var f=\(json(route.frameSelector));if(f){d=document.querySelector(f).contentDocument;}
            var e=d.querySelector(\(json(route.nextSelector)));if(!e||e.disabled||e.getAttribute('aria-disabled')==='true'||/(^|\\s)disabled(\\s|$)/.test(e.className)||!e.getClientRects().length)return false;
            e.click();return true;})()
            """
            let advanced = try await web.evaluateJavaScript(next) as? Bool ?? false
            if !advanced { result.items = collected; return result }
        }
        throw failure("达到分页上限，未保存不完整结果。请提高上限或缩小范围。")
    }
}

enum WebWatchConnection {
    static func looksLikeLogin(_ url: String) -> Bool {
        let text = url.lowercased()
        return text.contains("/login") || text.contains("/signin") || text.contains("/sign-in")
            || text.contains("/sso") || text.contains("/cas/") || text.contains("/auth/")
    }

    @MainActor static func check(_ watch: WebWatch, now: Date = Date()) async -> WebWatchOutcome {
        guard WebWatchValidation.url(watch.url) != nil else {
            return WebWatchOutcome(error: "地址无效，请点「编辑」重新填写。", checkedAt: now)
        }
        let selector = watch.mode == .list
            ? WebWatchSelector(selector: watch.selector, signature: watch.signature, route: watch.route) : nil
        let urls = watch.mode == .list && !(watch.route?.courseURLs.isEmpty ?? true)
            ? watch.route!.courseURLs : [watch.url]
        var items: [WebWatchItem] = []
        var scan: WebWatchScan?
        var pages = 0
        for (index, address) in urls.enumerated() {
            guard let target = WebWatchValidation.url(address) else {
                return WebWatchOutcome(error: "课程网址无效", checkedAt: now)
            }
            do {
                let loader = WebWatchLoader()
                let loaded = try await loader.load(url: target, selector: selector)
                withExtendedLifetime(loader) {}
                if loaded.scan.loginSuspected || (loaded.items.isEmpty && looksLikeLogin(loaded.scan.pageURL)) {
                    return WebWatchOutcome(signedOut: true, coverage: "已检查 \(index)/\(urls.count) 个入口", checkedAt: Date())
                }
                scan = loaded.scan
                pages += loaded.pages
                for var item in loaded.items {
                    if urls.count > 1 { item.key = address + "::" + item.key }
                    items.append(item)
                }
            } catch {
                return WebWatchOutcome(error: "入口 \(index + 1)/\(urls.count)：\(error.localizedDescription)",
                    coverage: "已检查 \(index)/\(urls.count) 个入口；保留上次结果", checkedAt: Date())
            }
        }
        var seen = Set<String>()
        items = items.filter { seen.insert($0.key).inserted }
        return WebWatchOutcome(scan: scan, items: items,
            coverage: "已覆盖 \(urls.count)/\(urls.count) 个入口 · \(pages) 页", checkedAt: Date())
    }
}

// MARK: - 编辑器里的可见浏览器

@MainActor
final class WebWatchBrowserModel: ObservableObject {
    struct CourseLink: Identifiable, Decodable {
        var url: String
        var title: String
        var id: String { url }
    }
    @Published var courseLinks: [CourseLink] = []
    @Published var pickedSelector = ""
    @Published var pickingField = ""
    private var pickerTask: Task<Void, Never>?

    func discoverCourses() {
        guard let web = webView else { return }
        Task { @MainActor in
            do {
                let raw = try await web.evaluateJavaScript("JSON.stringify(Array.from(document.querySelectorAll('a[href]')).filter(a=>a.innerText.trim()&&/^https?:/.test(a.href)&&a.getClientRects().length).map(a=>({url:a.href,title:a.innerText.trim().slice(0,80)})).filter((a,i,all)=>all.findIndex(b=>b.url===a.url)===i).slice(0,100))") as? String ?? "[]"
                courseLinks = try JSONDecoder().decode([CourseLink].self, from: Data(raw.utf8))
                message = "请选择课程入口；所有选定课程将使用相同的作业入口和字段规则。"
            } catch { message = error.localizedDescription }
        }
    }

    func pick(_ field: String, container: String) {
        guard let web = webView else { return }
        pickerTask?.cancel()
        pickingField = field
        pickedSelector = ""
        let encoded = String(data: try! JSONEncoder().encode(container), encoding: .utf8)!
        let relative = ["titleSelector", "dueSelector", "statusSelector"].contains(field)
        let script = """
        (function(){if(window.__miraPickCancel)window.__miraPickCancel();window.__miraPicked=null;
        function path(e,stop){var p=[];while(e&&e!==stop&&e.nodeType===1){if(e.id&&!stop){p.unshift('#'+CSS.escape(e.id));break;}var t=e.tagName.toLowerCase();var siblings=e.parentElement?Array.from(e.parentElement.children).filter(x=>x.tagName===e.tagName):[];p.unshift(t+(siblings.length>1?':nth-of-type('+(siblings.indexOf(e)+1)+')':''));e=e.parentElement;}return p.join(' > ');}
        function click(ev){ev.preventDefault();ev.stopImmediatePropagation();var e=ev.target;var stop=null;
        if(\(relative ? "true" : "false")){var list=document.querySelector(\(encoded));if(!list||!list.contains(e)){window.__miraPicked={error:'请点击当前列表条目内的字段'};cleanup();return;}var row=e;while(row.parentElement!==list&&row.parentElement)row=row.parentElement;stop=row;if(e===row){window.__miraPicked={error:'请点击条目内部的具体字段'};cleanup();return;}}
        \(field == "selector" ? "e=e.parentElement;" : "")
        window.__miraPicked={selector:path(e,stop)};cleanup();}
        function cleanup(){document.removeEventListener('click',click,true);window.__miraPickCancel=null;}
        document.addEventListener('click',click,true);window.__miraPickCancel=cleanup;})()
        """
        pickerTask = Task { @MainActor in
            do {
                _ = try await web.evaluateJavaScript(script)
                message = field == "selector" ? "请点击一个条目的空白处，使用其父容器作为列表。" : "请在页面上点击对应字段或按钮（本次点击不会执行网页操作）。"
                for _ in 0..<120 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    if let result = try await web.evaluateJavaScript("window.__miraPicked") as? [String: String] {
                        if let error = result["error"] { message = error }
                        else { pickedSelector = result["selector"] ?? ""; message = "已指认，请点验证读取检查结果。" }
                        return
                    }
                }
                _ = try? await web.evaluateJavaScript("window.__miraPickCancel && window.__miraPickCancel()")
            } catch { message = "指认已结束，请重新选择。" }
        }
    }

    func preview(selector: String, route: WebWatchRoute) {
        guard let web = webView else { return }
        Task { @MainActor in
            do {
                _ = try await web.evaluateJavaScript(WebWatchScript.source)
                let raw = try await web.evaluateJavaScript(WebWatchScript.extractCall(selector: selector, signature: nil, route: route)) as? String ?? ""
                let result = try JSONDecoder().decode(WebWatchExtraction.self, from: Data(raw.utf8))
                items = result.items
                message = result.found ? "字段验证：读取 \(items.count) 条，请核对下方预览。" : "没有找到列表，请修改规则。"
            } catch { message = "验证失败：\(error.localizedDescription)" }
        }
    }

    weak var webView: WKWebView?
    @Published var address: String
    @Published var currentURL: String
    @Published var pageTitle = ""
    @Published var busy = false
    @Published var scan: WebWatchScan?
    @Published var selected: WebWatchCandidate?
    @Published var items: [WebWatchItem] = []
    @Published var message = ""
    private let autoScanOnLoad: Bool
    private var started = false
    private var scanGeneration = 0
    private var selectionGeneration = 0
    private var scanRequested = false

    init(url: String = "", autoScan: Bool = false) {
        address = url
        currentURL = url
        autoScanOnLoad = autoScan
    }

    func attach(_ web: WKWebView) {
        webView = web
        guard !started else { return }
        started = true
        if WebWatchValidation.url(address) != nil { load(address) }
    }

    func load(_ text: String) {
        guard let url = WebWatchValidation.url(text) else {
            message = "请输入完整的 http:// 或 https:// 地址。"
            return
        }
        address = url.absoluteString
        currentURL = url.absoluteString
        scan = nil
        selected = nil
        items = []
        busy = true
        message = "正在打开页面…"
        scanGeneration += 1
        selectionGeneration += 1
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 30)
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        webView?.load(request)
    }

    func finishNavigation(_ web: WKWebView) {
        if let url = web.url?.absoluteString {
            currentURL = url
            address = url
        }
        if let title = web.title, !title.isEmpty { pageTitle = title }
        busy = false
        if scan == nil {
            let wantsScan = autoScanOnLoad || scanRequested
            message = wantsScan ? "页面已打开，正在自动识别…" : "页面已打开。登录完成后点「扫描此页」。"
            if wantsScan {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    guard let self, self.scan == nil, !self.busy else { return }
                    self.rescan()
                }
            }
        }
    }

    func beginNavigation() {
        busy = true
        message = "正在打开页面…"
        scanGeneration += 1
        selectionGeneration += 1
        // 登录可能先跳登录页再回到目标页；清掉上一次扫描结果，让新页面重新识别。
        scan = nil
        selected = nil
        items = []
    }

    func rescan() {
        scanRequested = true
        rescan(attempt: 0)
    }

    private func rescan(attempt: Int) {
        guard let web = webView else { return }
        // 用户可能在页面还没加载完时就点了扫描。先等一小会儿，避免
        // 在空白文档上执行脚本得到 "A JavaScript exception occurred"。
        if web.isLoading, attempt < 3 {
            busy = true
            message = "页面还在加载，稍后自动识别…"
            scanGeneration += 1
            let generation = scanGeneration
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let self, generation == self.scanGeneration else { return }
                self.rescan(attempt: attempt + 1)
            }
            return
        }
        if let url = web.url?.absoluteString {
            currentURL = url
            address = url
        }
        busy = true
        message = "正在识别页面…"
        scanGeneration += 1
        let generation = scanGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.ensureDetector(in: web)
                let value = try await web.evaluateJavaScript(WebWatchScript.scanCall)
                guard generation == self.scanGeneration else { return }
                self.busy = false
                guard let json = value as? String, let data = json.data(using: .utf8),
                      let scan = try? JSONDecoder().decode(WebWatchScan.self, from: data) else {
                    self.message = "没有读到页面结构，请刷新后重试。"
                    return
                }
                self.scanRequested = false
                self.scan = scan
                self.currentURL = scan.pageURL
                self.address = scan.pageURL
                self.pageTitle = scan.pageTitle
                if scan.pageURL.isEmpty || scan.pageURL == "about:blank" || scan.textLength == 0 {
                    self.message = "页面还没有打开。请检查网址，或点「打开」重新加载。"
                } else if scan.loginSuspected {
                    self.message = "这看起来是登录页。请先在左侧完成登录，再点「扫描此页」。"
                } else if scan.candidates.isEmpty {
                    self.message = "没有识别到重复列表；可以把下方模式改成「整页变化」。"
                } else {
                    self.message = "识别到 \(scan.candidates.count) 个候选列表，已选中第一个。"
                    if let first = scan.candidates.first { self.select(first) }
                }
            } catch {
                self.busy = false
                self.scanRequested = false
                WebLoginLog.append("webwatch scan \(web.url?.absoluteString ?? "nil") \(error.localizedDescription)")
                self.message = web.isLoading
                    ? "页面还在加载，请稍等后再点「扫描此页」。"
                    : "识别失败：页面脚本未就绪。请刷新页面后重试。"
            }
        }
    }

    private func ensureDetector(in web: WKWebView) async throws {
        if let kind = try? await web.evaluateJavaScript("typeof window.__miraWatch"),
           (kind as? String) == "object" { return }
        _ = try await web.evaluateJavaScript(WebWatchScript.source)
    }

    func select(_ candidate: WebWatchCandidate) {
        selected = candidate
        items = []
        guard let web = webView else { return }
        let js = WebWatchScript.extractCall(selector: candidate.selector,
                                            signature: candidate.signature)
        selectionGeneration += 1
        let generation = selectionGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.ensureDetector(in: web)
                let value = try await web.evaluateJavaScript(js)
                guard generation == self.selectionGeneration else { return }
                guard let json = value as? String, let data = json.data(using: .utf8),
                      let extraction = try? JSONDecoder().decode(WebWatchExtraction.self,
                                                                 from: data) else {
                    self.message = "读取条目失败，请重试。"
                    return
                }
                self.items = extraction.items
                self.message = extraction.found
                    ? "已读取 \(extraction.items.count) 个条目。"
                    : "列表结构没有找到，请重新扫描。"
            } catch {
                WebLoginLog.append("webwatch extract \(web.url?.absoluteString ?? "nil") \(error.localizedDescription)")
                self.message = "读取条目失败，请等页面加载完成后重试。"
            }
        }
    }
}

struct WebWatchBrowserView: NSViewRepresentable {
    @ObservedObject var model: WebWatchBrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(
            WKUserScript(source: WebWatchScript.source,
                         injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) { web.isInspectable = true }
        model.attach(web)
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.navigationDelegate = nil
        nsView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: WebWatchBrowserModel

        init(model: WebWatchBrowserModel) {
            self.model = model
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in self.model.beginNavigation() }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in self.model.finishNavigation(webView) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            Task { @MainActor in
                self.model.busy = false
                self.model.message = "页面加载失败：\(error.localizedDescription)"
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            Task { @MainActor in
                self.model.busy = false
                self.model.message = "页面加载失败：\(error.localizedDescription)"
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            // 学校登录常用 POST 或新窗口；在当前窗口里继续，Cookie 仍落在同一个数据仓库。
            webView.load(navigationAction.request)
            return nil
        }
    }
}
