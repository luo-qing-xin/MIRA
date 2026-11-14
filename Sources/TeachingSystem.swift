import Foundation

// MARK: - 配置

struct TeachingSettings: Codable, Equatable {
    var enabled = false
    var cookie = ""
    var intervalMinutes = 30
    var baselineAt: Date?
    var lastCheck: Date?
    var lastError: String?
    var retryAt: Date?
    var seen: [String] = []

    static let intervalChoices = SyncInterval.choices

    var signedIn: Bool { !cookie.isEmpty }
    var interval: TimeInterval { TimeInterval(max(5, intervalMinutes)) * 60 }
}

enum TeachingStore {
    static func url(root: URL) -> URL { root.appendingPathComponent("teaching.json") }

    static func load(root: URL, decoder: JSONDecoder) -> TeachingSettings {
        guard let data = try? Data(contentsOf: url(root: root)),
              var settings = try? decoder.decode(TeachingSettings.self, from: data) else {
            return TeachingSettings()
        }
        settings.intervalMinutes = SyncInterval.normalize(settings.intervalMinutes)
        return settings
    }

    static func save(_ settings: TeachingSettings, root: URL, encoder: JSONEncoder) throws {
        let target = url(root: root)
        try encoder.encode(settings).write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
}

// MARK: - 条目

struct TeachingClass: Equatable {
    var id: String
    var courseName: String
}

struct TeachingExam: Equatable, Identifiable {
    var id: String
    var title: String
    var courseName: String
    var classID: String
    var start: Date?
    var end: Date?
    var status: String
    var link: String

    var ended: Bool {
        if status == "ended" { return true }
        if let end { return end <= Date() }
        return false
    }
}

// MARK: - 解析

/// 666 是 Next.js + Server Action：页面本身是 404 壳，数据由 `listMyCourses` /
/// `listMyExam` 两个 action 返回的 RSC flight 文本带回来。
/// 这里只读 flight 中的 JSON 行，不执行页面脚本。
enum TeachingFeed {
    static let host = "666.ruc.edu.cn"
    static let origin = "https://666.ruc.edu.cn"
    static let loginPage = URL(string: origin + "/user/login")!
    static let examPage = URL(string: origin + "/exam/my")!

    static let listCoursesAction = "0030ac9a50d562b5598d2f48b1650a4faac90de5d4"
    static let listExamsAction = "4017914eb7052794c10c0c9eff2e8d1071d97546c3"

    static func examLink(_ id: String) -> String { origin + "/exam/my/" + id }

    // MARK: flight

    static func values(inFlight text: String) -> [Any] {
        if let data = text.data(using: .utf8),
           let whole = try? JSONSerialization.jsonObject(with: data) {
            return [whole]
        }
        guard let regex = try? NSRegularExpression(pattern: "(?m)^([0-9a-f]+):") else { return [] }
        let ns = text as NSString
        let marks = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result: [Any] = []
        for (index, mark) in marks.enumerated() {
            let start = mark.range.location + mark.range.length
            let end = index + 1 < marks.count ? marks[index + 1].range.location : ns.length
            guard end > start else { continue }
            let payload = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload.hasPrefix("{") || payload.hasPrefix("["),
                  let data = payload.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data) else { continue }
            result.append(value)
        }
        return result
    }

    static func walk(_ value: Any, _ visit: ([String: Any]) -> Void) {
        if let dict = value as? [String: Any] {
            visit(dict)
            for child in dict.values { walk(child, visit) }
        } else if let array = value as? [Any] {
            for child in array { walk(child, visit) }
        }
    }

    static func classes(fromFlight text: String) -> [TeachingClass] {
        var result: [TeachingClass] = []
        var seen = Set<String>()
        for value in values(inFlight: text) {
            walk(value) { dict in
                guard let id = string(dict["id"]), !id.isEmpty,
                      let course = dict["course"] as? [String: Any],
                      let name = string(course["courseName"]) ?? string(course["name"]) else { return }
                guard seen.insert(id).inserted else { return }
                result.append(TeachingClass(id: id, courseName: name))
            }
        }
        return result
    }

    static func exams(fromFlight text: String, of courseClass: TeachingClass) -> [TeachingExam] {
        var result: [TeachingExam] = []
        var seen = Set<String>()
        for value in values(inFlight: text) {
            walk(value) { dict in
                guard let title = string(dict["examName"]), !title.isEmpty,
                      let id = string(dict["id"]), !id.isEmpty,
                      seen.insert(id).inserted else { return }
                result.append(TeachingExam(
                    id: id,
                    title: clean(title),
                    courseName: courseClass.courseName,
                    classID: courseClass.id,
                    start: date(dict["startedAt"]) ?? date(dict["startTime"]),
                    end: date(dict["endedAt"]) ?? date(dict["endTime"]),
                    status: string(dict["status"]) ?? "",
                    link: examLink(id)))
            }
        }
        return result
    }

    // MARK: 值

    static func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    static func clean(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            let seconds = raw > 1_000_000_000_000 ? raw / 1000 : raw
            return Date(timeIntervalSince1970: seconds)
        }
        guard let text = value as? String, !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        let formatters = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm"]
        for format in formatters {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

// MARK: - 抓取

enum TeachingConnection {
    struct Outcome {
        var classes: [TeachingClass] = []
        var exams: [TeachingExam] = []
        var signedOut = false
        var error: String?
        var warning: String?
        var checkedAt = Date()
        var updatedCookie: String?
        var sample: String?
    }

    private static let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func sync(cookie: String, now: Date = Date()) async -> Outcome {
        var outcome = Outcome(checkedAt: now)
        var current = cookie
        var samples: [String] = []

        do {
            let (coursesText, afterCourses, coursesStatus) = try await action(
                TeachingFeed.listCoursesAction, body: "[]", cookie: current)
            current = afterCourses
            if coursesStatus == 401 || coursesStatus == 403 || signedOut(coursesText) {
                outcome.signedOut = true
                outcome.updatedCookie = current == cookie ? nil : current
                return outcome
            }
            let classes = TeachingFeed.classes(fromFlight: coursesText)
            outcome.classes = classes
            samples.append(String(coursesText.prefix(2000)))

            guard !classes.isEmpty else {
                // 未登录时 action 返回的是空数组而不是 401，借助 Auth.js 的
                // session 端点区分「没课程」和「会话过期」。
                if !(await sessionActive(cookie: current)) {
                    outcome.signedOut = true
                    outcome.updatedCookie = current == cookie ? nil : current
                    return outcome
                }
                outcome.error = "没有读到课程列表"
                outcome.sample = samples.joined(separator: "\n---\n")
                outcome.updatedCookie = current == cookie ? nil : current
                return outcome
            }

            var failures = 0
            for item in classes {
                do {
                    let body = body([item.id])
                    let (text, afterExam, status) = try await action(
                        TeachingFeed.listExamsAction, body: body, cookie: current)
                    current = afterExam
                    if status == 401 || status == 403 || signedOut(text) {
                        outcome.signedOut = true
                        break
                    }
                    outcome.exams += TeachingFeed.exams(fromFlight: text, of: item)
                    if samples.count < 3 { samples.append(String(text.prefix(2000))) }
                } catch {
                    failures += 1
                }
            }
            if failures > 0 { outcome.warning = "\(failures) 门课读取失败" }
            outcome.sample = samples.joined(separator: "\n---\n")
        } catch {
            outcome.error = "网络请求失败：\(error.localizedDescription)"
        }

        outcome.updatedCookie = current == cookie ? nil : current
        return outcome
    }

    private static func sessionActive(cookie: String) async -> Bool {
        var request = URLRequest(url: URL(string: TeachingFeed.origin + "/api/auth/session")!)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await session.data(for: request) else { return true }
        let text = String(decoding: data, as: UTF8.self)
        return text.contains("\"user\"") && !text.contains("\"user\":null")
    }

    private static func body(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func signedOut(_ text: String) -> Bool {
        text.contains("/user/login") || text.contains("请先登录") || text.contains("Unauthorized")
    }

    private static func action(_ id: String, body: String,
                               cookie: String) async throws -> (String, String, Int) {
        var request = URLRequest(url: TeachingFeed.examPage)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(id, forHTTPHeaderField: "Next-Action")
        request.setValue("text/x-component", forHTTPHeaderField: "Accept")
        request.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(TeachingFeed.origin, forHTTPHeaderField: "Origin")
        request.setValue(TeachingFeed.examPage.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let refreshed = http.flatMap { WebCookie.merged(cookie, response: $0, url: TeachingFeed.examPage) } ?? cookie
        return (text, refreshed, http?.statusCode ?? 0)
    }
}
