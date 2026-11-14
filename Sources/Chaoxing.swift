import Foundation

// MARK: - 配置

struct ChaoxingSettings: Codable, Equatable {
    var enabled = false
    var cookie = ""
    var intervalMinutes = 30
    var importHomework = true
    var includeExams = true
    var baselineAt: Date?
    var lastCheck: Date?
    var lastError: String?
    /// 失败后的下一次重试时间；间隔档位很长时避免一次断网等一整天。
    var retryAt: Date?
    var seen: [String] = []

    static let intervalChoices = SyncInterval.choices

    var signedIn: Bool { !cookie.isEmpty }
    var interval: TimeInterval { TimeInterval(max(5, intervalMinutes)) * 60 }
}

enum ChaoxingStore {
    static func url(root: URL) -> URL { root.appendingPathComponent("chaoxing.json") }

    static func load(root: URL, decoder: JSONDecoder) -> ChaoxingSettings {
        guard let data = try? Data(contentsOf: url(root: root)),
              var settings = try? decoder.decode(ChaoxingSettings.self, from: data) else {
            return ChaoxingSettings()
        }
        settings.intervalMinutes = SyncInterval.normalize(settings.intervalMinutes)
        return settings
    }

    static func save(_ settings: ChaoxingSettings, root: URL, encoder: JSONEncoder) throws {
        let target = url(root: root)
        try encoder.encode(settings).write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
}

// MARK: - 条目

struct ChaoxingCourse: Equatable {
    var courseID: String
    var classID: String
    var name: String
}

struct ChaoxingTask: Equatable, Identifiable {
    enum Kind: String { case work, exam }
    enum State: String { case pending, submitted, expired }

    /// `work:<courseId>:<workId>`，没有作业 id 时用标题 + 链接的哈希兜底。
    var key: String
    var courseID: String
    var classID: String
    var courseName: String
    var title: String
    var kind: Kind
    var state: State
    /// 状态是「已过期未交」：仍算未交，但不一定有可提交入口。
    var overdue: Bool
    var statusText: String
    var due: Date?
    var link: String

    var id: String { key }
}

// MARK: - 解析

/// 学习通的作业列表在 H5 页面里：`/phone/moocAnalysis/workList?courseId&classId`，
/// 每行是 `<dt data="<做作业链接>" status="n"><h3>标题</h3><p>日期</p>…<b>动作</b>`；
/// 考试是 `<tr data=… title=…>` 加几个 `<td>`。课程/班级来自 `backclazzdata`。
enum ChaoxingFeed {
    static let apiBase = "https://mooc1-api.chaoxing.com"
    static let webBase = "https://mooc1.chaoxing.com"
    static let loginStart = URL(string: "https://i.chaoxing.com/base")!

    static func coursesURL() -> URL {
        URL(string: apiBase + "/mycourse/backclazzdata?view=json&getTchClazzType=1&mcode=")!
    }

    static func workListURL(_ course: ChaoxingCourse) -> URL {
        URL(string: apiBase + "/phone/moocAnalysis/workList?courseId=\(course.courseID)&classId=\(course.classID)")!
    }

    static func examListURL(_ course: ChaoxingCourse) -> URL {
        URL(string: apiBase + "/phone/moocAnalysis/examList?courseId=\(course.courseID)&classId=\(course.classID)")!
    }

    // MARK: 课程

    static func courses(fromJSON data: Data) -> [ChaoxingCourse] {
        var payload = data
        if payload.starts(with: [0xEF, 0xBB, 0xBF]) { payload = payload.dropFirst(3) }
        guard let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              number(root["result"]) == 1,
              let channels = root["channelList"] as? [[String: Any]] else { return [] }

        var result: [ChaoxingCourse] = []
        var seen = Set<String>()
        for channel in channels {
            var content = channel["content"]
            if let text = content as? String {
                content = try? JSONSerialization.jsonObject(with: Data(text.utf8))
            }
            guard let clazz = content as? [String: Any] else { continue }
            let classID = string(clazz["id"]) ?? string(channel["key"]) ?? ""
            guard !classID.isEmpty else { continue }
            let className = string(clazz["name"]) ?? ""

            if let courseBox = clazz["course"] as? [String: Any],
               let list = courseBox["data"] as? [[String: Any]], !list.isEmpty {
                for entry in list {
                    guard let courseID = string(entry["id"]), !courseID.isEmpty else { continue }
                    let name = string(entry["name"]) ?? className
                    let key = courseID + "|" + classID
                    guard seen.insert(key).inserted else { continue }
                    result.append(ChaoxingCourse(courseID: courseID, classID: classID, name: name))
                }
                continue
            }

            // 旧版 course-centric：content 是课程，clazz[] 是班级。
            if let list = clazz["clazz"] as? [[String: Any]], !list.isEmpty {
                for entry in list {
                    guard let clazzID = string(entry["id"]), !clazzID.isEmpty else { continue }
                    let name = string(clazz["name"]) ?? className
                    let key = classID + "|" + clazzID
                    guard seen.insert(key).inserted else { continue }
                    result.append(ChaoxingCourse(courseID: classID, classID: clazzID, name: name))
                }
            }
        }
        return result
    }

    // MARK: 作业

    private static let workRow = try! NSRegularExpression(pattern: "(?is)<dt\\b([^>]*)>(.*?)</dt>")

    static func tasks(fromWorkListHTML html: String, course: ChaoxingCourse) -> [ChaoxingTask] {
        let ns = html as NSString
        var result: [ChaoxingTask] = []
        var seen = Set<String>()
        for match in workRow.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let attributes = ns.substring(with: match.range(at: 1))
            let inner = ns.substring(with: match.range(at: 2))
            guard let data = attribute("data", in: attributes), !data.isEmpty else { continue }
            let title = clean(innerTag("h3", in: inner))
            guard !title.isEmpty else { continue }
            let text = clean(inner)
            let statusText = clean(innerTag("b", in: inner))
            let (state, overdue) = classification(number(attribute("status", in: attributes)),
                                                  statusText: statusText, text: text)
            let link = absolute(data)
            let key = taskKey(kind: .work, course: course, title: title, link: link)
            guard seen.insert(key).inserted else { continue }
            result.append(ChaoxingTask(key: key, courseID: course.courseID, classID: course.classID,
                                       courseName: course.name, title: title, kind: .work,
                                       state: state, overdue: overdue, statusText: statusText,
                                       due: due(in: text), link: link))
        }
        return result
    }

    // MARK: 考试

    private static let examRow = try! NSRegularExpression(pattern: "(?is)<tr\\b([^>]*)>(.*?)</tr>")

    static func tasks(fromExamListHTML html: String, course: ChaoxingCourse) -> [ChaoxingTask] {
        let ns = html as NSString
        var result: [ChaoxingTask] = []
        var seen = Set<String>()
        for match in examRow.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let attributes = ns.substring(with: match.range(at: 1))
            let inner = ns.substring(with: match.range(at: 2))
            guard let data = attribute("data", in: attributes), !data.isEmpty else { continue }
            let cells = cellTexts(inner)
            var title = attribute("title", in: attributes) ?? ""
            if title.isEmpty { title = cells.first ?? "" }
            title = clean(title)
            guard !title.isEmpty else { continue }
            let text = clean(inner)
            let statusText = cells.count > 2 ? cells[2] : ""
            let (state, overdue) = classification(number(attribute("status", in: attributes)),
                                                  statusText: statusText, text: text)
            let link = absolute(data)
            let key = taskKey(kind: .exam, course: course, title: title, link: link)
            guard seen.insert(key).inserted else { continue }
            result.append(ChaoxingTask(key: key, courseID: course.courseID, classID: course.classID,
                                       courseName: course.name, title: title, kind: .exam,
                                       state: state, overdue: overdue, statusText: statusText,
                                       due: due(in: text), link: link))
        }
        return result
    }

    // MARK: 状态与时间

    /// 列表行的 `status` 才是准的：1=未交、2=已过期未交、3=待批阅、4=已完成。
    /// 只看 `<b>` 会把「已完成」（只有分数、没有动作文字）误判成待做。
    static func classification(_ status: Int?, statusText: String,
                               text: String) -> (ChaoxingTask.State, Bool) {
        if let status {
            switch status {
            case 3, 4: return (.submitted, false)
            case 1: return (.pending, false)
            case 2: return (.pending, true)
            default: break
            }
        }
        let probe = statusText.isEmpty ? text : statusText
        if probe.contains("已完成") || probe.contains("已提交") || probe.contains("已交")
            || probe.contains("已批阅") || probe.contains("查看") || probe.contains("重做") {
            return (.submitted, false)
        }
        if probe.contains("已过期") || probe.contains("已结束") || probe.contains("已关闭") {
            return (.pending, true)
        }
        return (.pending, false)
    }

    private static let duePatterns = [
        "截止(?:时间|日期)?[：:]?\\s*(20\\d{2}[-/年]\\d{1,2}[-/月]\\d{1,2}日?(?:\\s+\\d{1,2}:\\d{2}(?::\\d{2})?)?)",
        "(20\\d{2}[-/年]\\d{1,2}[-/月]\\d{1,2}日?(?:\\s+\\d{1,2}:\\d{2}(?::\\d{2})?)?)\\s*(?:截止|结束)",
    ]

    static func due(in text: String) -> Date? {
        for pattern in duePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
                  match.numberOfRanges > 1 else { continue }
            let raw = (text as NSString).substring(with: match.range(at: 1))
            if let value = date(raw) { return value }
        }
        return nil
    }

    static func date(_ raw: String) -> Date? {
        let text = raw.replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["yyyy-M-d HH:mm:ss", "yyyy-M-d HH:mm", "yyyy-M-d"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let value = formatter.date(from: text) {
                // 只给日期时按当天结束算，避免提前判逾期。
                return format == "yyyy-M-d" ? value.addingTimeInterval(86399) : value
            }
        }
        return nil
    }

    // MARK: 键与链接

    static func taskKey(kind: ChaoxingTask.Kind, course: ChaoxingCourse, title: String, link: String) -> String {
        for name in ["workId", "examId", "workid", "examid"] {
            if let value = queryValue(name, in: link), !value.isEmpty {
                return "\(kind.rawValue):\(course.courseID):\(value)"
            }
        }
        return "\(kind.rawValue):\(course.courseID):h:\(fingerprint(course.classID + "|" + title + "|" + link))"
    }

    static func queryValue(_ name: String, in link: String) -> String? {
        guard let url = URL(string: link), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        return items.first(where: { $0.name.lowercased() == name.lowercased() })?.value
    }

    static func absolute(_ path: String) -> String {
        let raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
        if raw.hasPrefix("//") { return "https:" + raw }
        return apiBase + (raw.hasPrefix("/") ? "" : "/") + raw
    }

    // MARK: 文本

    static func attribute(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\(name)\\s*=\\s*[\"']([^\"']*)[\"']", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)),
              match.numberOfRanges > 1 else { return nil }
        return decodeEntities((tag as NSString).substring(with: match.range(at: 1)))
    }

    static func innerTag(_ tag: String, in html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?is)<\(tag)\\b[^>]*>(.*?)</\(tag)>"),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
              match.numberOfRanges > 1 else { return "" }
        return (html as NSString).substring(with: match.range(at: 1))
    }

    static func cellTexts(_ html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "(?is)<td\\b[^>]*>(.*?)</td>") else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map {
            clean(ns.substring(with: $0.range(at: 1)))
        }
    }

    static func clean(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let decoded = decodeEntities(stripped)
        return decoded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        var value = text
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "]
        for (key, replacement) in map { value = value.replacingOccurrences(of: key, with: replacement) }
        return value
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    static func number(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: return value
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value)
        default: return nil
        }
    }

    static func fingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - 抓取

enum ChaoxingConnection {
    struct Outcome {
        var courses: [ChaoxingCourse] = []
        var tasks: [ChaoxingTask] = []
        var signedOut = false
        var error: String?
        var warning: String?
        var checkedAt = Date()
        var updatedCookie: String?
        /// 首次同步时留一份作业页样本，便于页面改版后校准（0600，不含 Cookie）。
        var sampleHTML: String?
    }

    private static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func sync(cookie: String, includeExams: Bool, now: Date = Date()) async -> Outcome {
        var outcome = Outcome(checkedAt: now)
        var current = cookie

        do {
            let (coursesReply, afterCourses) = try await request(ChaoxingFeed.coursesURL(), cookie: current,
                                                                 accepting: .json)
            current = afterCourses
            if coursesReply.signedOut {
                outcome.signedOut = true
                outcome.updatedCookie = current == cookie ? nil : current
                return outcome
            }
            let courses = ChaoxingFeed.courses(fromJSON: coursesReply.data)
            outcome.courses = courses
            guard !courses.isEmpty else {
                outcome.error = "没有读到课程列表"
                outcome.sampleHTML = String(decoding: coursesReply.data, as: UTF8.self).prefix(4000).description
                outcome.updatedCookie = current == cookie ? nil : current
                return outcome
            }

            var failures = 0
            var firstWorkList: String?
            for course in courses {
                do {
                    let (page, afterWork) = try await request(ChaoxingFeed.workListURL(course), cookie: current,
                                                              accepting: .html)
                    current = afterWork
                    if page.signedOut {
                        outcome.signedOut = true
                        break
                    }
                    let html = String(decoding: page.data, as: UTF8.self)
                    if firstWorkList == nil, !html.isEmpty { firstWorkList = html }
                    outcome.tasks += ChaoxingFeed.tasks(fromWorkListHTML: html, course: course)
                } catch {
                    failures += 1
                }
                if includeExams, !outcome.signedOut {
                    do {
                        let (page, afterExam) = try await request(ChaoxingFeed.examListURL(course), cookie: current,
                                                                  accepting: .html)
                        current = afterExam
                        if page.signedOut { outcome.signedOut = true; break }
                        let html = String(decoding: page.data, as: UTF8.self)
                        outcome.tasks += ChaoxingFeed.tasks(fromExamListHTML: html, course: course)
                    } catch {
                        failures += 1
                    }
                }
            }
            if failures > 0 { outcome.warning = "\(failures) 个页面读取失败" }
            outcome.sampleHTML = firstWorkList
        } catch {
            outcome.error = "网络请求失败：\(error.localizedDescription)"
        }

        outcome.updatedCookie = current == cookie ? nil : current
        return outcome
    }

    private enum Accept { case json, html }

    private struct Reply {
        var data: Data
        var url: URL?
        var status: Int
        var signedOut: Bool
    }

    private static func request(_ url: URL, cookie: String, accepting: Accept) async throws -> (Reply, String) {
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(ChaoxingFeed.webBase + "/", forHTTPHeaderField: "Referer")
        switch accepting {
        case .json:
            request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        case .html:
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                             forHTTPHeaderField: "Accept")
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let final = response.url
        let host = final?.host?.lowercased() ?? ""
        let path = final?.path.lowercased() ?? ""
        let prefix = String(decoding: data.prefix(4096), as: UTF8.self)
        // 学习通在会话失效时常常返回 200 + {"result":0,"msg":"请重新登录"}，不跳转。
        let signedOut = host.contains("passport") || path.contains("login")
            || prefix.contains("请重新登录") || prefix.contains("用户登录")
        let refreshed = http.flatMap { WebCookie.merged(cookie, response: $0, url: final ?? url) } ?? cookie
        let reply = Reply(data: data, url: final, status: http?.statusCode ?? 0, signedOut: signedOut)
        return (reply, refreshed)
    }
}
