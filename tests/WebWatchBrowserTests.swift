import Foundation
import AppKit

enum WebLoginLog { static func append(_ text: String) {} }
@main struct BrowserTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        Task { @MainActor in
            do {
                let base = "http://127.0.0.1:18763/"
                var route = WebWatchRoute()
                route.entrySelector = "#work"
                route.titleSelector = ".title"
                route.dueSelector = ".due"
                route.statusSelector = ".status"
                route.nextSelector = "#next"
                route.courseURLs = [base + "course.html?course=1", base + "course.html?course=2"]
                var watch = WebWatch(url: route.courseURLs[0], selector: "#list")
                watch.route = route
                let result = await WebWatchConnection.check(watch)
                guard result.error == nil, result.items.count == 4,
                      Set(result.items.map(\.key)).count == 4,
                      result.coverage?.contains("4 页") == true else {
                    fatalError("Traversal failed: \(result.error ?? "none") \(result.items) \(result.coverage ?? "")")
                }
                route = WebWatchRoute()
                route.frameSelector = "#frame"
                route.titleSelector = ".title"
                route.dueSelector = ".due"
                watch = WebWatch(url: base + "frame.html", selector: "#list")
                watch.route = route
                let frame = await WebWatchConnection.check(watch)
                guard frame.error == nil, frame.items.first?.title == "框架作业" else { fatalError("Frame failed: \(frame.error ?? "none")") }
                watch.selector = "#missing"
                let failed = try await WebWatchLoader().load(url: URL(string: base + "rows.html")!, selector: WebWatchSelector(selector: "#missing", signature: nil), timeout: 3)
                _ = failed
                fatalError("Missing selector must fail")
            } catch {
                print("PASS: WKWebView multi-course, delayed content, pagination, same-origin iframe and missing-list failure")
                exit(0)
            }
        }
        app.run()
    }
}
