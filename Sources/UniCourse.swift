import Foundation

// MARK: - 配置

/// UniCourse 连接只落在本机：Cookie 与去重键写在 0600 的 `unicourse.json`，
/// 不进 `state.json`，也不会被写进日志或诊断文件。
struct UniCourseSettings: Codable, Equatable {
    var enabled = false
    var cookie = ""
    var intervalMinutes = 30
    /// 未提交的作业写进任务库「课程」分类。
    var importHomework = true
    /// 公告也提醒；课件、讨论不提醒。
    var notifyAnnouncements = true
    var baselineAt: Date?
    var lastCheck: Date?
    var lastError: String?
    /// 失败后的下一次重试时间；间隔档位很长时避免一次断网等一整天。
    var retryAt: Date?
    var seen: [String] = []

    static let intervalChoices = SyncInterval.choices
    static let seenLimit = 400

    var signedIn: Bool { !cookie.isEmpty }
    var interval: TimeInterval { TimeInterval(max(5, intervalMinutes)) * 60 }
}

enum UniCourseStore {
    static func url(root: URL) -> URL { root.appendingPathComponent("unicourse.json") }

    static func load(root: URL, decoder: JSONDecoder) -> UniCourseSettings {
        guard let data = try? Data(contentsOf: url(root: root)),
              var settings = try? decoder.decode(UniCourseSettings.self, from: data) else {
            return UniCourseSettings()
        }
        settings.intervalMinutes = SyncInterval.normalize(settings.intervalMinutes)
        return settings
    }

    static func save(_ settings: UniCourseSettings, root: URL, encoder: JSONEncoder) throws {
        let target = url(root: root)
        try encoder.encode(settings).write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
}

// MARK: - 条目

struct UniCourseCourse: Equatable {
    var id: String
    var name: String
}

struct UniCourseAssignment: Equatable, Identifiable {
    /// `cno:hno`，同一门课的同一次作业跨次抓取不变。
    var key: String
    var courseID: String
    var courseName: String
    var hno: String
    var title: String
    var type: String
    var due: Date?
    var submitted: Bool
    var link: String

    var id: String { key }
}

struct UniCourseAnnouncement: Equatable, Identifiable {
    var id: String
    var courseID: String
    var courseName: String
    var actor: String
    var title: String
    var date: Date
    var link: String
}

// MARK: - 解析

/// 首页给出课程与 `cno`；每门课的作业页是服务端渲染的 `.panel` 列表：
/// `id="panel-5805"`、`id="hno-5805"`、`class="hw-check unfinished"`、
/// `<span class="hide deadline">2026-11-24 23:55:00</span>`。
/// 只读这两个页面，不猜不存在的数据。
enum UniCourseFeed {
    static let home = URL(string: "https://unicourse.ruc.edu.cn/index/home/index.html")!
    static let news = URL(string: "https://unicourse.ruc.edu.cn/index/home/morenews.html")!
    static let host = "unicourse.ruc.edu.cn"

    static func homeworkURL(_ cno: String) -> URL {
        URL(string: "https://unicourse.ruc.edu.cn/index/homework/index/cno/\(cno).html")!
    }

    // MARK: 课程

    private static let courseTag = try! NSRegularExpression(pattern: "(?is)<a\\b[^>]*courseitem[^>]*>")
    private static let courseLink = try! NSRegularExpression(
        pattern: "(?is)<a\\b[^>]*href\\s*=\\s*[\"'][^\"']*/homework/index/cno/([^\"'?#/]+)[\"'][^>]*>(.*?)</a>")

    static func courses(fromHTML html: String) -> [UniCourseCourse] {
        let ns = html as NSString
        var result: [UniCourseCourse] = []
        var seen = Set<String>()
        for match in courseTag.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            guard let id = group("data-id\\s*=\\s*[\"']([^\"']+)[\"']", in: tag),
                  let raw = group("title\\s*=\\s*[\"']([^\"']+)[\"']", in: tag) else { continue }
            let name = cleanText(raw)
            guard isValidCourse(id: id, name: name), seen.insert(id).inserted else { continue }
            result.append(UniCourseCourse(id: id, name: name))
        }
        // 首页结构变了时，用任意页面的「课程切换」侧栏兜底。
        if result.isEmpty {
            for match in courseLink.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let id = ns.substring(with: match.range(at: 1))
                let name = cleanText(stripTags(ns.substring(with: match.range(at: 2))))
                guard isValidCourse(id: id, name: name), seen.insert(id).inserted else { continue }
                result.append(UniCourseCourse(id: id, name: name))
            }
        }
        return result
    }

    private static func isValidCourse(id: String, name: String) -> Bool {
        !id.isEmpty && id != "0" && !name.isEmpty
            && !["作业", "课程", "公告", "课件", "问答", "小组", "全部"].contains(name)
    }

    // MARK: 作业

    private static let panelMark = try! NSRegularExpression(pattern: "id=\"panel-(\\d+)\"")

    static func assignments(fromHTML html: String, course: UniCourseCourse,
                            now: Date = Date()) -> [UniCourseAssignment] {
        let ns = html as NSString
        let marks = panelMark.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var result: [UniCourseAssignment] = []
        var seen = Set<String>()

        for (index, mark) in marks.enumerated() {
            let hno = ns.substring(with: mark.range(at: 1))
            guard !hno.isEmpty, seen.insert(hno).inserted else { continue }
            let start = mark.range.location
            let end = index + 1 < marks.count ? marks[index + 1].range.location : ns.length
            let block = ns.substring(with: NSRange(location: start, length: end - start))

            guard let rawTitle = group("id=\"hno-\(hno)\"[^>]*>(.*?)</a>", in: block) else { continue }
            let title = cleanText(stripTags(rawTitle))
            guard !title.isEmpty else { continue }

            let heading = group("panel-heading\">([\\s\\S]*?)</div>", in: block) ?? block
            let type = cleanText(group("<small>\\s*(.*?)</small>", in: heading) ?? "")

            let classes = group("hw-check\\s+([^\"]+)\"", in: block) ?? ""
            let tokens = Set(classes.split(separator: " ").map(String.init))
            guard tokens.contains("unfinished") || tokens.contains("finished") else { continue }
            let submitted = tokens.contains("finished") && !tokens.contains("unfinished")

            let deadline = group("class=\"hide deadline\">([^<]+)<", in: block)
                ?? group("id=\"deadline-\(hno)\">([^<]+)<", in: block)
            let due = deadline.flatMap { date($0) }

            result.append(UniCourseAssignment(key: "\(course.id):\(hno)", courseID: course.id,
                                              courseName: course.name, hno: hno, title: title,
                                              type: type, due: due, submitted: submitted,
                                              link: homeworkURL(course.id).absoluteString + "#panel-\(hno)"))
        }
        return result
    }

    // MARK: 公告

    /// `/index/home/morenews.html` 返回 `{status, data:[{n_type:"2", n_cname, n_content, ...}]}`。
    /// n_type：1 提问、2 公告、3 作业、4 课件、5 大纲。这里只取公告。
    static func announcements(fromJSON data: Data, now: Date = Date()) -> [UniCourseAnnouncement] {
        var payload = data
        if payload.starts(with: [0xEF, 0xBB, 0xBF]) { payload = payload.dropFirst(3) }
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let rows = object["data"] as? [[String: Any]] else { return [] }

        var result: [UniCourseAnnouncement] = []
        var seen = Set<String>()
        for row in rows {
            guard text(row["n_type"]) == "2" else { continue }
            let title = cleanText(text(row["n_content"]) ?? "")
            guard !title.isEmpty else { continue }
            let course = cleanText(text(row["n_cname"]) ?? "")
            let actor = cleanText(text(row["n_sname"]) ?? "")
            let no = text(row["n_no"]) ?? ""
            let key = no.isEmpty ? "\(course):\(title)" : "news:" + no
            guard seen.insert(key).inserted else { continue }
            let path = text(row["n_curl"]) ?? text(row["n_contenturl"]) ?? ""
            let link = path.hasPrefix("/") ? "https://unicourse.ruc.edu.cn" + path
                                           : (path.isEmpty ? home.absoluteString : path)
            let stamp = text(row["n_time"]).flatMap { date($0) } ?? now
            result.append(UniCourseAnnouncement(id: key, courseID: text(row["n_cno"]) ?? "",
                                                courseName: course, actor: actor, title: title,
                                                date: stamp, link: link))
        }
        return result
    }

    // MARK: 工具

    static func group(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              match.numberOfRanges > 1 else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    static func cleanText(_ text: String) -> String {
        var value = stripTags(text)
        // 站点里存在 `&nbsp&nbsp普通作业` 这种没有分号的写法，浏览器能容错。
        value = value.replacingOccurrences(of: "&nbsp;?", with: " ", options: .regularExpression)
        value = decodeEntities(value)
        value = value.replacingOccurrences(of: "\u{00a0}", with: " ")
        value = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
                                       "nbsp": " ", "hellip": "…", "mdash": "—", "ldquo": "“", "rdquo": "”"]
        guard let regex = try? NSRegularExpression(pattern: "&(#x?[0-9a-fA-F]+|[a-zA-Z]+);") else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let token = ns.substring(with: match.range(at: 1))
            if token.hasPrefix("#") {
                let hex = token.hasPrefix("#x") || token.hasPrefix("#X")
                let digits = String(token.dropFirst(hex ? 2 : 1))
                if let value = UInt32(digits, radix: hex ? 16 : 10), let scalar = UnicodeScalar(value) {
                    result.append(Character(scalar))
                } else {
                    result += ns.substring(with: match.range)
                }
            } else {
                result += named[token] ?? ns.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    static func text(_ value: Any?) -> String? {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func date(_ raw: String) -> Date? {
        formatter.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - 抓取

enum UniCourseConnection {
    struct Outcome {
        var courses: [UniCourseCourse] = []
        var assignments: [UniCourseAssignment] = []
        var announcements: [UniCourseAnnouncement] = []
        var signedOut = false
        var error: String?
        var warning: String?
        var checkedAt = Date()
        /// 页面刷新过的会话 Cookie；非空时需要写回配置。
        var updatedCookie: String?
        /// 解析失败时的页面片段，只用于本机诊断，不含 Cookie。
        var diagnostic: String?
    }

    private struct Reply {
        var body: String
        var url: URL?
        var status: Int
        var signedOut: Bool
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func sync(cookie: String, includeNews: Bool, now: Date = Date()) async -> Outcome {
        var outcome = Outcome(checkedAt: now)
        var current = cookie

        do {
            let (home, afterHome) = try await request(UniCourseFeed.home, cookie: current)
            current = afterHome
            if home.signedOut {
                outcome.signedOut = true
            } else if home.status >= 400 {
                outcome.error = "首页返回 HTTP \(home.status)"
            } else {
                let courses = UniCourseFeed.courses(fromHTML: home.body)
                outcome.courses = courses
                if courses.isEmpty {
                    outcome.error = "没有读到课程列表"
                    outcome.diagnostic = String(home.body.prefix(4000))
                } else {
                    var failures = 0
                    for course in courses {
                        do {
                            let (page, afterCourse) = try await request(homeworkURL(course), cookie: current)
                            current = afterCourse
                            if page.signedOut {
                                outcome.signedOut = true
                                break
                            }
                            outcome.assignments += UniCourseFeed.assignments(fromHTML: page.body, course: course, now: now)
                        } catch {
                            failures += 1
                        }
                    }
                    if failures > 0 { outcome.warning = "\(failures) 门课读取失败" }
                    if includeNews, !outcome.signedOut {
                        do {
                            let (news, afterNews) = try await request(UniCourseFeed.news, method: "POST",
                                                                      form: "page=0&cno=&type=0", cookie: current)
                            current = afterNews
                            if news.signedOut {
                                outcome.signedOut = true
                            } else {
                                outcome.announcements = UniCourseFeed.announcements(fromJSON: Data(news.body.utf8), now: now)
                            }
                        } catch {
                            // 公告失败不影响作业同步。
                        }
                    }
                }
            }
        } catch {
            outcome.error = "网络请求失败：\(error.localizedDescription)"
        }

        outcome.updatedCookie = current == cookie ? nil : current
        return outcome
    }

    private static func homeworkURL(_ course: UniCourseCourse) -> URL {
        UniCourseFeed.homeworkURL(course.id)
    }

    private static func request(_ url: URL, method: String = "GET", form: String? = nil,
                                cookie: String) async throws -> (Reply, String) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(UniCourseFeed.home.absoluteString, forHTTPHeaderField: "Referer")
        if let form {
            request.httpBody = Data(form.utf8)
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        } else {
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                             forHTTPHeaderField: "Accept")
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let body = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let final = response.url
        let wrongHost = final?.host?.lowercased() != UniCourseFeed.host
        let loginPath = final?.path.hasPrefix("/index/index/") ?? true
        let signedOut = wrongHost || loginPath || body.contains("caslogin") || body.contains("统一身份认证")
        let refreshed = http.flatMap { refresh(cookie: cookie, response: $0) } ?? cookie
        let reply = Reply(body: body, url: final, status: http?.statusCode ?? 0, signedOut: signedOut)
        return (reply, refreshed)
    }

    /// 服务端可能在每次请求后轮换会话 Cookie；把 Set-Cookie 并回存储的头，
    /// 否则下一次还带着已经作废的旧值，表现为「突然登录过期」。
    private static func refresh(cookie: String, response: HTTPURLResponse) -> String? {
        WebCookie.merged(cookie, response: response, url: UniCourseFeed.home)
    }
}
