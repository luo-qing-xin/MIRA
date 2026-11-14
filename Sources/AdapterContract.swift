import Foundation

/// One adapter event, `mira.adapter/1`. Adapters only map their client's
/// payload onto these fields; every reminder rule lives in this file.
struct AdapterEvent: Decodable {
    static let protocolName = "mira.adapter/1"

    struct Adapter: Decodable {
        var id: String
        var name: String?
        var version: String
    }

    struct Approval: Decodable {
        var token: String?
        var ttlMs: Double?
        var tool: String?
        var reason: String?
    }

    struct Question: Decodable {
        var id: String?
        var question: String?
        var header: String?
    }

    var adapter: Adapter
    var kind: String
    var time: Double?
    var session: String
    var turn: Int?
    var cwd: String?
    var title: String?
    var titleHint: String?
    var reason: String?
    var requiresPlanCheck: Bool?
    var link: String?
    var dedupeKey: String?
    var closes: String?
    var approval: Approval?
    var questions: [Question]?
}

/// The single receiver's mapping table: contract kind -> reminder status/body,
/// title resolution, stable ids and silent dismissals. Kept pure so every rule
/// can be asserted without a filesystem.
enum AdapterContract {
    /// Target of an `approval.closed` / `question.closed` event, or nil.
    static func closeTarget(_ event: AdapterEvent) -> String? {
        guard event.kind.hasSuffix(".closed"), let closes = trimmed(event.closes) else { return nil }
        return identifier(adapter: event.adapter.id, key: closes)
    }

    /// The reminder this event describes, or nil for a kind newer than this app.
    static func entry(_ event: AdapterEvent, now: Date, titles: inout TitleStore) -> Entry? {
        guard let content = content(for: event) else { return nil }
        let name = displayName(event)
        let project = projectName(event.cwd)
        let source = project.isEmpty ? name : "\(name) · \(project)"
        let date = eventDate(event, now: now)
        var entry = Entry(
            id: identifier(adapter: event.adapter.id, key: trimmed(event.dedupeKey) ?? defaultKey(event)),
            title: title(for: event, name: name, project: project, now: now, titles: &titles),
            body: content.body,
            source: String(source.prefix(80)),
            status: content.status,
            link: event.link ?? "",
            date: date,
            thread: event.session
        )
        entry.adapterVersion = event.adapter.version
        entry.requiresPlanCheck = event.requiresPlanCheck
        // Only a valid one-shot token lets MIRA answer; everything else is an
        // informational reminder that expires with its own TTL (or never).
        if content.status == "待确认", let approval = event.approval,
           let token = approval.token, Decisions.valid(token) {
            entry.token = token
            let ttl = approval.ttlMs ?? 60_000
            entry.expires = date.addingTimeInterval(max(ttl, 1) / 1000)
        }
        return entry
    }

    static func identifier(adapter: String, key: String) -> String {
        "ev-" + String(fnv1a(adapter + "|" + key), radix: 16)
    }

    static func projectName(_ cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return "" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name == "/" ? "" : name
    }

    static func displayName(_ event: AdapterEvent) -> String {
        if let name = trimmed(event.adapter.name) { return name }
        return trimmed(event.adapter.id) ?? "AI"
    }

    // MARK: - Content

    private static func content(for event: AdapterEvent) -> (status: String, body: String)? {
        let name = displayName(event)
        switch event.kind {
        case "turn.start":
            return ("运行中", "\(name) 正在处理这一轮，完成后会更新结果。")
        case "turn.end":
            switch event.reason ?? "completed" {
            case "error":
                return ("任务失败", "\(name) 本轮执行失败，可打开原会话查看原因。")
            case "aborted", "interrupted":
                return ("已中断", "\(name) 本轮已被中断，可返回会话继续。")
            case "blocked":
                return ("已拦截", "本轮在提交阶段被拦截，没有执行。")
            case "max-tokens":
                return ("已达上限", "本轮达到输出上限后结束，请检查结果是否完整。")
            default:
                return ("本轮结束", "\(name) 本轮已结束，请打开原会话查看结果。")
            }
        case "approval.asked":
            let tool = trimmed(event.approval?.tool) ?? "工具"
            var body = "\(name) 需要你确认「\(tool)」的操作"
            if let why = trimmed(event.approval?.reason) { body += "：\(why)" } else { body += "。" }
            return ("待确认", body + " 点击回到原会话处理。")
        case "question.asked":
            let list = event.questions ?? []
            let first = trimmed(list.first?.question)
            var body = "\(name) 需要你补充信息"
            body += first.map { "：\($0)" } ?? "。"
            if list.count > 1 { body += "（共 \(list.count) 个问题）" }
            return ("待补充信息", body + " 点击回到原会话回答。")
        default:
            return nil
        }
    }

    // MARK: - Titles

    private static func title(for event: AdapterEvent, name: String, project: String,
                              now: Date, titles: inout TitleStore) -> String {
        // A prompt from this turn is the best name and also seeds the cache for
        // the follow-up events of the same turn (Stop, Interrupt, approvals).
        if let hint = trimmed(event.titleHint) {
            let clipped = Titles.prompt(hint)
            if !clipped.isEmpty {
                titles.remember(adapter: event.adapter.id, session: event.session,
                                turn: event.turn, title: clipped, now: now)
                return clipped
            }
        }
        if let cached = titles.title(adapter: event.adapter.id, session: event.session,
                                     turn: event.turn, now: now) {
            return cached
        }
        if let label = trimmed(event.title) {
            let cleaned = Titles.label(label)
            if !cleaned.isEmpty { return cleaned }
        }
        return Titles.fallback(project: project, adapter: name, session: event.session, turn: event.turn)
    }

    private static func eventDate(_ event: AdapterEvent, now: Date) -> Date {
        guard let time = event.time, time > 0 else { return now }
        return Date(timeIntervalSince1970: time / 1000)
    }

    private static func defaultKey(_ event: AdapterEvent) -> String {
        var parts = [event.session, event.kind]
        if let turn = event.turn { parts.append(String(turn)) }
        if let reason = trimmed(event.reason) { parts.append(reason) }
        return parts.joined(separator: ":")
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// Prompt titles remembered per adapter session and turn. Mirrors the old
/// per-adapter `titles/` cache, but written and expired in one place.
struct TitleStore {
    struct Record: Codable, Equatable {
        var adapter: String
        var session: String
        var turn: Int?
        var title: String
        var date: Date
    }

    static let ttl: TimeInterval = 86_400
    private(set) var records: [String: Record] = [:]
    private(set) var changed = false
    private var nextExpiration = Date.distantFuture

    static func key(adapter: String, session: String) -> String { adapter + "|" + session }

    func title(adapter: String, session: String, turn: Int?, now: Date) -> String? {
        guard let record = records[Self.key(adapter: adapter, session: session)] else { return nil }
        guard now.timeIntervalSince(record.date) <= Self.ttl else { return nil }
        if let stored = record.turn, let incoming = turn, stored != incoming { return nil }
        return record.title
    }

    mutating func remember(adapter: String, session: String, turn: Int?, title: String, now: Date) {
        let record = Record(adapter: adapter, session: session, turn: turn, title: title, date: now)
        let key = Self.key(adapter: adapter, session: session)
        guard records[key] != record else { return }
        records[key] = record
        nextExpiration = min(nextExpiration, now.addingTimeInterval(Self.ttl))
        changed = true
    }

    mutating func prune(now: Date) {
        guard now > nextExpiration else { return }
        let count = records.count
        records = records.filter { now.timeIntervalSince($0.value.date) <= Self.ttl }
        if records.count != count { changed = true }
        nextExpiration = records.values.lazy.map(\.date).min()?.addingTimeInterval(Self.ttl) ?? .distantFuture
    }

    mutating func load(from url: URL, decoder: JSONDecoder) {
        guard let data = try? Data(contentsOf: url),
              let list = try? decoder.decode([Record].self, from: data) else { return }
        records = Dictionary(list.map { (Self.key(adapter: $0.adapter, session: $0.session), $0) },
                             uniquingKeysWith: { $0.date >= $1.date ? $0 : $1 })
        nextExpiration = records.values.lazy.map(\.date).min()?.addingTimeInterval(Self.ttl) ?? .distantFuture
    }

    mutating func flush(to url: URL, encoder: JSONEncoder, now: Date) throws {
        prune(now: now)
        guard changed else { return }
        let list = records.values.sorted { $0.date < $1.date }
        try encoder.encode(list).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        changed = false
    }
}

extension Inbox {
    /// Inbox files carry either a contract event or a legacy reminder written by
    /// an adapter that has not been updated yet. Both stay readable.
    enum Incoming {
        case event(AdapterEvent)
        case legacy(Entry)
    }

    static func decode(_ data: Data, decoder: JSONDecoder) throws -> Incoming {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["protocol"] as? String == AdapterEvent.protocolName {
            return .event(try decoder.decode(AdapterEvent.self, from: data))
        }
        return .legacy(try decoder.decode(Entry.self, from: data))
    }
}
