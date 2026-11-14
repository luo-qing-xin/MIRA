import Foundation

struct Plan: Codable, Identifiable {
    var id = UUID().uuidString
    var title: String
    var notes: String
    var hour: Int
    var minute: Int
    var weekdays: [Int] // Calendar: Sunday = 1; empty = daily
    var link: String
    var enabled = true
    var created = Date()
    var origin: String? = nil
}
struct Entry: Codable, Identifiable {
    var id: String
    var title: String
    var body: String
    var source: String
    var status: String
    var link: String
    var date: Date
    var expires: Date?
    var done = false
    var notified = false
    var snooze: Date?
    var thread: String?
    // Control entry: close this other entry id and never display this one.
    var dismiss: String? = nil
    // One-shot approval token: only present when MIRA may answer this request.
    var token: String? = nil
    // Event-protocol version reported by the adapter that produced this entry.
    // Missing means the sender predates version reporting (an old install).
    var adapterVersion: String? = nil
    // Direct Codex actions are revalidated against live IPC state after launch.
    var codexID: String? = nil
    var codexKind: String? = nil
    var requiresPlanCheck: Bool? = nil
    /// 网页监控的链接来自用户自己选择的页面，允许普通 http/https 打开；
    /// AI 事件仍只走 `Links.valid` 白名单。旧的 state.json 没有这个字段。
    var allowWebLink: Bool? = nil

    // Informational completion notices still notify once, but never require
    // acknowledgement. Keep this separate from `done` and `notified`.
    var automaticallyArchived: Bool { status == "本轮结束" }
    var waitsForCodexPlan: Bool {
        source.hasPrefix("Codex") && automaticallyArchived && requiresPlanCheck != false
    }
    /// 课程与网页监控的更新只提醒一次：任务库里有可勾选的待办，
    /// 消息流不再重复占用「待处理」。
    var courseUpdate: Bool {
        status == "新作业" || status == "课程公告" || status == "新条目" || status == "网页更新"
    }
    var historyStatus: String {
        automaticallyArchived || courseUpdate ? status : (done ? "已处理" : "已过期")
    }

    var canSnooze: Bool {
        status == "待确认" || status == "待补充信息" || status == "待完成"
    }

    // Legacy Codex tool hooks ran before the approval flow chose a reviewer.
    // The plan fallback is produced by Stop for a saved implementation plan.
    var isCodexToolApprovalHint: Bool {
        status == "待确认" && codexID == nil && source.hasPrefix("Codex")
            && link.hasPrefix("codex://threads/") && !body.contains("「实施计划」")
    }

    /// Display-only cleanup for prompt-derived titles. The stored title stays
    /// untouched, so history is not rewritten.
    var displayTitle: String { Titles.display(title) }
}
enum Titles {
    static let promptLimit = 44
    static let promptHead = 28
    static let promptTail = 12
    static let labelLimit = 80

    /// DSH's deterministic title fallback copies the first prompt verbatim,
    /// including its Markdown heading and meta label. Strip that noise only at
    /// display time so existing entries improve without a data migration.
    static func display(_ value: String) -> String {
        let cleaned = clean(value)
        return cleaned.isEmpty ? value : cleaned
    }

    /// Collapse whitespace and strip Markdown/meta prefixes; may be empty.
    static func clean(_ value: String) -> String {
        var text = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in [#"^#{1,6}\s+"#, #"^(?:[-*+]\s+|>\s+)"#, #"^任务\s*[：:]\s*"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reminder title from a prompt: first paragraph, cleaned, then head + tail
    /// when it is longer than 44 characters. Never keeps the whole prompt.
    static func prompt(_ value: String) -> String {
        let separated = value.replacingOccurrences(of: #"\n\s*\n"#, with: "\n\n", options: .regularExpression)
        let paragraph = separated.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let characters = Array(clean(paragraph))
        guard !characters.isEmpty else { return "" }
        guard characters.count > promptLimit else { return String(characters) }

        var head = String(characters.prefix(promptHead))
        if let space = head.lastIndex(of: " ") {
            let index = head.distance(from: head.startIndex, to: space)
            if index > 0 && index >= Int(Double(promptHead) * 0.6) {
                head = String(head[..<space])
            }
        }
        head = head.trimmingCharacters(in: .whitespaces)

        func asciiLetter(_ character: Character) -> Bool { character.isASCII && character.isLetter }
        var tailStart = max(0, characters.count - promptTail)
        if tailStart > 0, asciiLetter(characters[tailStart]), asciiLetter(characters[tailStart - 1]) {
            while tailStart > 0, asciiLetter(characters[tailStart - 1]),
                  characters.count - tailStart < promptTail + 16 {
                tailStart -= 1
            }
        }
        var end = String(characters[tailStart...]).trimmingCharacters(in: .whitespaces)
        if let space = end.firstIndex(of: " ") {
            let index = end.distance(from: end.startIndex, to: space)
            if index <= Int(Double(promptTail) * 0.4) {
                end = String(end[end.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        let punctuation = CharacterSet(charactersIn: "，。、；：,.;:!?！？ \t")
        while let first = end.unicodeScalars.first, punctuation.contains(first) {
            end.removeFirst()
        }
        head = head.replacingOccurrences(of: #"[…\.]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if end.isEmpty {
            return String(characters.prefix(promptLimit)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return head + "…" + end
    }

    /// Adapter-provided label (a visible session name): cleaned and bounded.
    static func label(_ value: String) -> String {
        let cleaned = clean(value)
        guard !cleaned.isEmpty else { return "" }
        let characters = Array(cleaned)
        guard characters.count > labelLimit else { return cleaned }
        return String(characters.prefix(labelLimit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Last-resort name when the adapter sent neither a prompt nor a title.
    static func fallback(project: String, adapter: String, session: String, turn: Int?) -> String {
        let base = project.isEmpty ? adapter : project
        if let turn, turn > 0 { return "\(base) · 第 \(turn) 轮" }
        return "\(base) · 任务 \(String(session.prefix(8)))"
    }
}
extension HubData {
    /// Close one entry by id. Used by silent dismissal events.
    mutating func close(_ id: String) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries[index].done = true
        entries[index].snooze = nil
        return true
    }

    mutating func closeCodexToolApprovalHints() -> [String] {
        var closed: [String] = []
        for index in entries.indices where !entries[index].done && entries[index].isCodexToolApprovalHint {
            entries[index].done = true
            entries[index].snooze = nil
            closed.append(entries[index].id)
        }
        return closed
    }
}
struct HubData: Codable {
    var plans: [Plan] = []
    var entries: [Entry] = []
    var seen: Set<String> = []
    var lastEvent: Date?
    /// Task library data lives in the same local state file. Older state files
    /// decode through the custom initializer below and are migrated on launch.
    var tasks: [TaskItem] = []
    var taskCategories: [TaskCategory] = TaskCategory.defaults
    var schemaVersion = TaskSchema.currentVersion

    init() {}

    enum CodingKeys: String, CodingKey {
        case plans, entries, seen, lastEvent, tasks, taskCategories, schemaVersion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Missing versions predate the task library. Newer state must remain
        // on disk untouched because decoding it here would discard unknown fields.
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= TaskSchema.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values,
                debugDescription: "State was saved by a newer version of MIRA.")
        }
        plans = try values.decodeIfPresent([Plan].self, forKey: .plans) ?? []
        entries = try values.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        seen = try values.decodeIfPresent(Set<String>.self, forKey: .seen) ?? []
        lastEvent = try values.decodeIfPresent(Date.self, forKey: .lastEvent)
        tasks = try values.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        taskCategories = try values.decodeIfPresent([TaskCategory].self, forKey: .taskCategories) ?? []
    }
}
enum PlanTime {
    /// Picker date for an existing plan. During a DST spring-forward the wall-clock
    /// time can be missing; move to the next valid instant instead of crashing.
    static func date(hour: Int, minute: Int, now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? now
    }

    /// Hour and minute of the picker value, with a neutral fallback if the calendar
    /// cannot produce components.
    static func components(_ value: Date, calendar: Calendar = .current) -> (hour: Int, minute: Int) {
        let parts = calendar.dateComponents([.hour, .minute], from: value)
        return (parts.hour ?? 0, parts.minute ?? 0)
    }
}

enum Schedule {
    static func occurrenceID(_ plan: Plan, now: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return "plan-\(plan.id)-\(parts.year!)-\(parts.month!)-\(parts.day!)"
    }
    static func due(_ plan: Plan, now: Date, calendar: Calendar = .current) -> Entry? {
        guard plan.enabled, plan.weekdays.isEmpty || plan.weekdays.contains(calendar.component(.weekday, from: now)) else { return nil }
        let start = calendar.startOfDay(for: now)
        guard let time = calendar.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: start), time <= now,
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let key = occurrenceID(plan, now: now, calendar: calendar)
        return Entry(id: key, title: plan.title, body: plan.notes, source: "个人计划", status: "待完成", link: plan.link, date: time, expires: end)
    }
    static func active(_ e: Entry, now: Date) -> Bool { !e.done && (e.expires == nil || e.expires! > now) }
    static func needsAttention(_ e: Entry, now: Date) -> Bool {
        active(e, now: now) && e.status != "运行中" && !e.automaticallyArchived && !e.courseUpdate
    }
    static func inHistory(_ e: Entry, now: Date) -> Bool {
        e.automaticallyArchived || e.courseUpdate || !active(e, now: now)
    }
}
enum Notify {
    /// Entries that must be announced now. Selection is pure so the caller can
    /// persist the `notified` flags and restore them if that save fails.
    static func due(_ entries: [Entry], now: Date) -> [Int] {
        entries.indices.filter { index in
            let entry = entries[index]
            let snoozed = entry.snooze.map { $0 > now } ?? false
            return Schedule.active(entry, now: now) && !entry.notified
                && entry.status != "运行中" && !snoozed
        }
    }

    /// Mark selected entries as announced in memory so the following state save
    /// records them. When that save fails, `rollback` restores the flags so the
    /// next tick announces the same entries instead of silently dropping them.
    static func mark(_ entries: inout [Entry], at indices: [Int]) {
        for index in indices where entries.indices.contains(index) { entries[index].notified = true }
    }

    static func rollback(_ entries: inout [Entry], at indices: [Int]) {
        for index in indices where entries.indices.contains(index) { entries[index].notified = false }
    }
}
enum ReminderClose {
    /// Closing an approval popup must hand the request back to DSH at once.
    /// Otherwise the native dialog stays blocked until the 60-second timeout.
    static func decision(for entry: Entry) -> String? {
        entry.token != nil && entry.status == "待确认" ? "defer" : nil
    }
}
enum Decisions {
    static let choices: Set<String> = ["allow", "deny", "defer"]

    /// Tokens come from inbox JSON; keep them to a filename-safe alphabet.
    static func valid(_ token: String) -> Bool {
        !token.isEmpty && token.count <= 64 && token.allSatisfy { $0.isHexDigit || $0 == "-" }
    }

    /// Write a one-shot decision for the DSH bridge to pick up.
    static func write(root: URL, token: String, decision: String) throws {
        guard valid(token), choices.contains(decision) else {
            throw NSError(domain: "无效的确认请求", code: 1)
        }
        let directory = root.appendingPathComponent("decisions")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let body: [String: Any] = [
            "token": token,
            "decision": decision,
            "time": Int(Date().timeIntervalSince1970 * 1000),
        ]
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let target = directory.appendingPathComponent(token + ".json")
        try data.write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
}

enum Inbox {
    struct Outcome {
        /// Files whose content was applied in memory. The caller deletes them only
        /// after the state was saved, so a failed save is retried next tick.
        var consumed: [URL] = []
        /// Reminder ids that a silent dismissal closed; the UI closes their popups.
        var dismissed: [String] = []
        var codexApprovalSessions: Set<String> = []
        var changed = false
        var errors: [String] = []
    }

    /// Drain queued events into `data`. Bad files are quarantined instead of being
    /// retried forever, and every file is reported through the outcome so the
    /// caller can batch a single state save per tick.
    static func drain(inbox: URL, data: inout HubData, now: Date, decoder: JSONDecoder) -> Outcome {
        var titles = TitleStore()
        return drain(inbox: inbox, data: &data, now: now, decoder: decoder, titles: &titles)
    }

    /// Drain queued events into `data`. Both the contract format and the legacy
    /// reminder format are accepted, so an adapter that has not been updated yet
    /// keeps delivering while the new one takes over.
    static func drain(inbox: URL, data: inout HubData, now: Date, decoder: JSONDecoder,
                      titles: inout TitleStore) -> Outcome {
        var outcome = Outcome()
        let fm = FileManager.default
        // An unreadable or missing inbox used to look like "no events", which
        // silently stopped reminder delivery. Report it, and recreate a queue
        // that disappeared while the app was running.
        var isDirectory: ObjCBool = false
        if !fm.fileExists(atPath: inbox.path, isDirectory: &isDirectory) {
            do {
                try fm.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } catch {
                outcome.errors.append("收件箱无法创建：\(error.localizedDescription)")
                return outcome
            }
        } else if !isDirectory.boolValue {
            outcome.errors.append("收件箱路径不是文件夹：\(inbox.path)")
            return outcome
        }
        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
        } catch {
            outcome.errors.append("收件箱无法读取：\(error.localizedDescription)")
            return outcome
        }
        for url in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let incoming = try decode(Data(contentsOf: url), decoder: decoder)
                switch incoming {
                case .event(let event):
                    if let target = AdapterContract.closeTarget(event) {
                        if data.close(target) { outcome.changed = true }
                        outcome.dismissed.append(target)
                    } else if let entry = AdapterContract.entry(event, now: now, titles: &titles) {
                        try accept(entry, data: &data, now: now, outcome: &outcome)
                    }
                    // Unknown kinds are consumed silently: a newer adapter must
                    // not be quarantined by an older app.
                case .legacy(let entry):
                    if let target = entry.dismiss {
                        if data.close(target) { outcome.changed = true }
                        outcome.dismissed.append(target)
                    } else {
                        try accept(entry, data: &data, now: now, outcome: &outcome)
                    }
                }
                outcome.consumed.append(url)
            } catch {
                let reason = error.localizedDescription
                do {
                    let moved = try quarantine(url, inbox: inbox)
                    outcome.errors.append("事件读取失败，已隔离 \(moved.lastPathComponent)：\(reason)")
                } catch {
                    outcome.errors.append("事件读取失败且无法隔离 \(url.lastPathComponent)：\(reason)")
                }
            }
        }
        return outcome
    }

    /// Acceptance rules shared by both formats: link allow-list, one entry per
    /// id, same-session supersede, and the 24-hour quiet rule.
    private static func accept(_ entry: Entry, data: inout HubData, now: Date, outcome: inout Outcome) throws {
        guard Links.valid(entry.link) else { throw NSError(domain: "无效事件链接", code: 1) }
        if entry.isCodexToolApprovalHint {
            if let thread = entry.thread, now.timeIntervalSince(entry.date) <= 86400 {
                outcome.codexApprovalSessions.insert(thread)
            }
            return
        }
        guard !data.seen.contains(entry.id) else { return }
        data.seen.insert(entry.id)
        if entry.source.hasPrefix("Codex"), data.entries.contains(where: {
            !$0.done && $0.codexID != nil && $0.thread == entry.thread &&
            (entry.status == "待确认" || (entry.waitsForCodexPlan && $0.codexKind == "plan"))
        }) {
            outcome.changed = true
            return
        }
        if let thread = entry.thread {
            for index in data.entries.indices
            where data.entries[index].thread == thread && data.entries[index].date <= entry.date && data.entries[index].codexID == nil {
                data.entries[index].done = true
            }
        }
        // Old AI events stay in history rather than flooding the desktop after
        // days away.
        var stored = entry
        if now.timeIntervalSince(entry.date) > 86400 { stored.done = true }
        data.entries.insert(stored, at: 0)
        data.lastEvent = now
        outcome.changed = true
    }

    /// Move an unreadable event aside instead of retrying it every tick. Keep the
    /// original bytes for diagnosis and make the copy private like a live event.
    static func quarantine(_ file: URL, inbox: URL) throws -> URL {
        let fm = FileManager.default
        let folder = inbox.appendingPathComponent("rejected")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stem = file.deletingPathExtension().lastPathComponent
        var target = folder.appendingPathComponent(file.lastPathComponent)
        var suffix = 2
        while fm.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(stem)-\(suffix).json")
            suffix += 1
        }
        try fm.moveItem(at: file, to: target)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        return target
    }
}

enum Links {
    static func valid(_ value: String) -> Bool {
        if value.isEmpty { return true }
        guard let u = URL(string: value) else { return false }
        // Schemes and hosts are case-insensitive; copy-pasted links may be uppercase.
        let scheme = u.scheme?.lowercased()
        let host = u.host?.lowercased()
        if scheme == "https" {
            // 课程更新通知需要能直接打开 UniCourse / 学习通的作业页。
            let courseHost = host == "unicourse.ruc.edu.cn"
                || host == "chaoxing.com"
                || (host?.hasSuffix(".chaoxing.com") ?? false)
                || host == "666.ruc.edu.cn"
            return host == "chatgpt.com" || host == "chat.openai.com" || courseHost
        }
        if scheme == "dsh" { return host == "open" && (u.path.isEmpty || u.path == "/") }
        return scheme == "codex" && host == "threads" && u.path.count > 1
    }
}

enum Backups {
    /// First free backup path. Two backups within the same second must not
    /// overwrite each other; `ext` is empty for suffix-only names.
    static func unique(in directory: URL, stem: String, extension ext: String = "") -> URL {
        let fm = FileManager.default
        func candidate(_ suffix: String) -> URL {
            directory.appendingPathComponent(stem + suffix + (ext.isEmpty ? "" : "." + ext))
        }
        if !fm.fileExists(atPath: candidate("").path) { return candidate("") }
        var index = 2
        while index < 1000 {
            let url = candidate("-\(index)")
            if !fm.fileExists(atPath: url.path) { return url }
            index += 1
        }
        return candidate("-" + UUID().uuidString)
    }
}

enum CodexHooks {
    private static let events = ["Stop", "PermissionRequest", "UserPromptSubmit", "Interrupt", "PreToolUse"]

    static func command(for script: URL) -> String {
        "/usr/bin/python3 '" + script.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func containsCommand(_ groups: [Any], command: String) -> Bool {
        groups.contains { group in
            let items = (group as? [String: Any])?["hooks"] as? [Any] ?? []
            return items.contains { item in
                let hook = item as? [String: Any]
                return hook?["type"] as? String == "command" && hook?["command"] as? String == command
            }
        }
    }

    static func installed(config: URL, script: URL) -> Bool {
        guard let bytes = try? Data(contentsOf: config),
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let hooks = object["hooks"] as? [String: Any] else { return false }
        let managed = command(for: script)
        return hooks.values.contains { containsCommand($0 as? [Any] ?? [], command: managed) }
    }

    static func install(config: URL, script: URL, receiver: Data, emitter: Data, now: Date = Date()) throws {
        let fm = FileManager.default
        let directory = config.deletingLastPathComponent()
        var original: Data?
        var object: [String: Any] = [:]
        if fm.fileExists(atPath: config.path) {
            let bytes = try Data(contentsOf: config)
            guard let parsed = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                throw NSError(domain: "hooks.json 不是对象", code: 1)
            }
            object = parsed
            original = bytes
        }
        guard var hooks = (object["hooks"] ?? [:]) as? [String: Any] else {
            throw NSError(domain: "hooks.json 的 hooks 不是对象", code: 1)
        }
        let managed = command(for: script)
        var configChanged = false
        for event in events {
            guard var groups = (hooks[event] ?? []) as? [Any] else {
                throw NSError(domain: "hooks.json 的 \(event) 不是数组", code: 1)
            }
            // Existing groups may contain a matcher, user settings and other
            // commands. Refresh the bundled files without changing those groups.
            guard !containsCommand(groups, command: managed) else { continue }
            var group: [String: Any] = ["hooks": [["type": "command", "command": managed, "timeout": 3]]]
            if event == "PreToolUse" { group["matcher"] = ".*request_user_input.*" }
            groups.append(group)
            hooks[event] = groups
            configChanged = true
        }
        object["hooks"] = hooks
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        if configChanged, let original {
            let stamp = Int(now.timeIntervalSince1970)
            let backup = Backups.unique(in: directory, stem: "hooks.mira-backup-\(stamp)", extension: "json")
            try original.write(to: backup, options: .atomic)
        }
        // Make the SDK available before publishing the receiver that imports it.
        try emitter.write(to: script.deletingLastPathComponent().appendingPathComponent("mira_emit.py"), options: .atomic)
        try receiver.write(to: script, options: .atomic)
        if configChanged {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try updated.write(to: config, options: .atomic)
        }
    }
}

enum DSHLink {
    static let bridgeRows = """
    - insert:
        - id: mira-bridge
          name: './plugins/mira-bridge/index.js'

    """
    static let patchBlock = "# MIRA bridge (added by MIRA)\n" + bridgeRows
    /// Same rows as the shell installer writes; kept so either installer can be undone.
    static let scriptPatchBlock = "# MIRA bridge (added by scripts/install-dsh-bridge.sh)\n" + bridgeRows
    static let patchBlocks = [patchBlock, scriptPatchBlock]
    private static let bridgeRowPattern = #"(?m)^[ \t]*(?:-[ \t]+)?id:[ \t]+(?:mira-bridge|"mira-bridge"|'mira-bridge')(?:[ \t]+#[^\r\n]*)?[ \t]*\r?$"#
    private static let disabledRowPattern = #"(?m)^[ \t]*\[\](?:[ \t]+(#[^\r\n]*(?:\r?\n|$))|[ \t]*(?:\r?\n|$))"#

    static func profile(_ environment: [String: String], home: URL) -> URL {
        let root = environment["DSH_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".dsh")
        return root.appendingPathComponent("profiles/desktop")
    }

    /// Match the row itself, not a string fragment: `id: mira-bridge-2` is a different plugin.
    /// A user may quote the id; it still refers to this plugin.
    static func installed(patch: String) -> Bool {
        patch.range(of: bridgeRowPattern, options: .regularExpression) != nil
    }

    /// `[]` is the documented way to disable the patch layer. Appending a list item
    /// after it produces invalid YAML, so the disabled layer must be replaced instead.
    static func isDisabledLayer(_ text: String) -> Bool {
        let rows = text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && $0 != "---" }
        return !rows.isEmpty && rows.allSatisfy { $0.range(of: disabledRowPattern, options: .regularExpression) != nil }
    }

    /// Copy the bridge into the profile and add its row. Never touches other rows.
    static func install(profile: URL, files: [String: Data], now: Date = Date()) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: profile.appendingPathComponent("package.json").path) else {
            throw NSError(domain: "请先启动一次 DeepSeek Harness，再配置连接。", code: 1)
        }
        let patch = profile.appendingPathComponent("cordis.patch.yml")
        // Distinguish "no patch yet" from "patch unreadable": an unreadable file
        // must fail the install instead of being silently replaced.
        let original = fm.fileExists(atPath: patch.path) ? try String(contentsOf: patch, encoding: .utf8) : nil
        var text = original ?? ""
        let needsPatch = !installed(patch: text)
        if needsPatch {
            if isDisabledLayer(text) {
                text = text.replacingOccurrences(of: disabledRowPattern, with: "$1", options: .regularExpression)
            }
            let newline = (original ?? "").contains("\r\n") ? "\r\n" : "\n"
            if !text.isEmpty && text.last?.isNewline != true { text += newline }
            text += patchBlock.replacingOccurrences(of: "\n", with: newline)
        }

        let plugins = profile.appendingPathComponent("plugins")
        let destination = plugins.appendingPathComponent("mira-bridge")
        try fm.createDirectory(at: plugins, withIntermediateDirectories: true)
        let staging = plugins.appendingPathComponent(".mira-install-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var cleanStaging = true
        defer { if cleanStaging { try? fm.removeItem(at: staging) } }
        let replacement = staging.appendingPathComponent("replacement")
        let previous = staging.appendingPathComponent("previous")
        let hadPlugin = fm.fileExists(atPath: destination.path)
        if hadPlugin {
            guard try fm.attributesOfItem(atPath: destination.path)[.type] as? FileAttributeType == .typeDirectory else {
                throw NSError(domain: "MIRA 插件路径不是文件夹", code: 1)
            }
            try fm.copyItem(at: destination, to: replacement)
        } else {
            try fm.createDirectory(at: replacement, withIntermediateDirectories: false)
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: replacement.path)
        for (name, data) in files {
            let target = replacement.appendingPathComponent(name)
            if (try? fm.destinationOfSymbolicLink(atPath: target.path)) != nil { try fm.removeItem(at: target) }
            try data.write(to: target, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        }
        if needsPatch, let original, !original.isEmpty {
            try original.write(to: backup(patch, now: now), atomically: true, encoding: .utf8)
        }
        if hadPlugin { try fm.moveItem(at: destination, to: previous) }
        var published = false
        do {
            try fm.moveItem(at: replacement, to: destination)
            published = true
            if needsPatch { try replacePatch(patch, with: text, original: original) }
        } catch {
            let installError = error
            do {
                if published { try fm.moveItem(at: destination, to: replacement) }
                if hadPlugin { try fm.moveItem(at: previous, to: destination) }
            } catch {
                cleanStaging = false
                throw NSError(domain: "MIRA.DSH", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "安装失败且无法恢复插件，备份保留在 \(staging.path)：\(error.localizedDescription)"
                ])
            }
            throw installError
        }
    }

    static func remove(profile: URL, now: Date = Date()) throws {
        let fm = FileManager.default
        let patch = profile.appendingPathComponent("cordis.patch.yml")
        if fm.fileExists(atPath: patch.path) {
            // Unreadable config must not be reported as "nothing to remove": the
            // plugin directory is deleted below, so fail before touching anything.
            let text = try String(contentsOf: patch, encoding: .utf8)
            if installed(patch: text) {
                let blocks = patchBlocks + patchBlocks.map { $0.replacingOccurrences(of: "\n", with: "\r\n") }
                guard let block = blocks.first(where: { text.contains($0) }) else {
                    throw NSError(domain: "补丁层里的 mira-bridge 行不是安装时写入的格式，无法安全移除。已保留插件目录，请手动删除该项后重试。", code: 1)
                }
                let cleaned = text.replacingOccurrences(of: block, with: "")
                // Verify with the same matcher that install uses before deleting files.
                guard !installed(patch: cleaned) else {
                    throw NSError(domain: "补丁层里的 mira-bridge 行无法安全移除。已保留插件目录，请手动删除该项后重试。", code: 1)
                }
                try text.write(to: backup(patch, now: now), atomically: true, encoding: .utf8)
                try replacePatch(patch, with: cleaned, original: text)
            }
        }
        let destination = profile.appendingPathComponent("plugins/mira-bridge")
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
    }

    private static func replacePatch(_ patch: URL, with text: String, original: String?) throws {
        let current = FileManager.default.fileExists(atPath: patch.path)
            ? try String(contentsOf: patch, encoding: .utf8) : nil
        guard current == original else {
            throw NSError(domain: "补丁文件已被其他进程修改", code: 1)
        }
        try text.write(to: patch.resolvingSymlinksInPath(), atomically: true, encoding: .utf8)
    }

    static func backup(_ patch: URL, now: Date) -> URL {
        Backups.unique(in: patch.deletingLastPathComponent(),
                       stem: patch.lastPathComponent + ".mira-backup-\(Int(now.timeIntervalSince1970))")
    }
}

// MARK: - 适配器版本

/// Protocol version spoken by the local adapters (Codex hook receiver and DSH
/// bridge). It is independent of the app's version: an adapter installed months
/// ago keeps working but cannot send fields it has never heard of, so MIRA has
/// to be able to tell the two apart without re-reading a changelog.
enum IntegrationVersion {
    static let current = "0.4.0"
    /// Label for an installed copy that predates version reporting.
    static let legacy = "旧版"

    /// Adapters declare their version on one line so MIRA can read an installed
    /// copy without executing it. JS and Python assignments both match.
    static func marker(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"ADAPTER_VERSION\s*=\s*["']([^"']+)["']"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges == 2,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    /// Numeric comparison; anything non-numeric falls back to plain text order.
    static func compare(_ lhs: String, _ rhs: String) -> Int {
        func numbers(_ value: String) -> [Int]? {
            let parts = value.split(separator: ".")
            guard !parts.isEmpty, parts.allSatisfy({ $0.allSatisfy { $0.isNumber } }) else { return nil }
            var values: [Int] = []
            for part in parts {
                guard let number = Int(part) else { return nil }
                values.append(number)
            }
            return values
        }
        guard let a = numbers(lhs), let b = numbers(rhs) else {
            return lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
        }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

/// Whether the installed adapter is current and whether the running client is
/// actually using it. "Files updated but client not restarted" is a state the
/// settings page has to show, so it is computed here and tested directly.
enum AdapterHealth {
    enum State: Equatable {
        case missing      // 未配置
        case legacy       // 已配置，但文件里没有版本标记
        case outdated     // 文件版本低于应用要求
        case ahead        // 文件版本高于应用（保留兼容）
        case waiting      // 文件就绪，但还没收到任何事件
        case restart      // 收到过事件，但没有一条来自当前版本
        case ready        // 最近一条事件来自当前版本
    }

    struct Status: Equatable {
        var state: State
        var installed: String?
        var expected: String
        var lastEvent: Date?
        var lastEventVersion: String?
    }

    static func evaluate(installed: Bool,
                         installedVersion: String?,
                         expected: String,
                         lastEvent: Date?,
                         lastEventVersion: String?) -> Status {
        func make(_ state: State) -> Status {
            Status(state: state, installed: installedVersion, expected: expected,
                   lastEvent: lastEvent, lastEventVersion: lastEventVersion)
        }
        guard installed else { return make(.missing) }
        guard let version = installedVersion else { return make(.legacy) }
        switch IntegrationVersion.compare(version, expected) {
        case ..<0: return make(.outdated)
        case 1...: return make(.ahead)
        default: break
        }
        guard lastEvent != nil else { return make(.waiting) }
        return lastEventVersion == expected ? make(.ready) : make(.restart)
    }
}

/// One-line status copy for the settings cards. Kept next to the state machine
/// so "需要更新" and "重启后生效" cannot drift from the states they describe.
enum AdapterStatusText {
    static func message(_ status: AdapterHealth.Status, noun: String, update: String, restart: String) -> String {
        switch status.state {
        case .missing:
            return "尚未连接"
        case .legacy:
            return "\(noun)是\(IntegrationVersion.legacy) → 需要 \(status.expected)，\(update)"
        case .outdated:
            return "\(noun) \(status.installed ?? "?") → 需要 \(status.expected)，\(update)"
        case .ahead:
            return "\(noun) \(status.installed ?? "?") · 比应用新"
        case .waiting:
            return "已配置 · \(noun) \(status.expected) · 等待第一条事件"
        case .restart:
            return "\(noun)已更新到 \(status.expected) · \(restart)"
        case .ready:
            let when = status.lastEvent?.formatted(date: .abbreviated, time: .shortened) ?? "已收到"
            return "\(noun) \(status.expected) · 最近事件 \(when)"
        }
    }
}

// MARK: - 记录保留

struct RetentionPolicy: Equatable {
    /// Settled entries older than this leave state.json for the text archive.
    var maxAgeDays: Int = 90
    /// Hard cap for state.json; pending work is never dropped just to fit.
    var maxEntries: Int = 500

    static let standard = RetentionPolicy()

    var maxAge: TimeInterval { TimeInterval(max(0, maxAgeDays)) * 86400 }
}

enum Retention {
    struct Outcome {
        var kept: [Entry] = []
        var archived: [Entry] = []
        /// Event ids kept for de-duplication; ids of archived entries go away with them.
        var seen: Set<String> = []
    }

    /// An entry nobody has to act on any more. Pending work is never archived:
    /// a forgotten approval must stay visible no matter how old it is.
    static func settled(_ entry: Entry, now: Date) -> Bool {
        if entry.status == "运行中" {
            // The running strip is a hint, not a queue item. A crashed client
            // can leave one behind forever, so stale ones are allowed to settle.
            return now.timeIntervalSince(entry.date) > 2 * 86400
        }
        return Schedule.inHistory(entry, now: now)
    }

    /// Pure selection so callers can archive first and then persist, and so the
    /// rule set can be asserted without touching the filesystem.
    static func plan(entries: [Entry], seen: Set<String>, policy: RetentionPolicy, now: Date) -> Outcome {
        var keep: [Entry] = []
        var archived: [Entry] = []
        let cutoff = now.addingTimeInterval(-policy.maxAge)
        for entry in entries {
            if settled(entry, now: now), entry.date < cutoff {
                archived.append(entry)
            } else {
                keep.append(entry)
            }
        }
        if policy.maxEntries > 0, keep.count > policy.maxEntries {
            // An older event may have been delivered after newer ones.
            let oldestSettled = keep.indices.filter { settled(keep[$0], now: now) }
                .sorted { lhs, rhs in
                    if keep[lhs].date != keep[rhs].date {
                        return keep[lhs].date < keep[rhs].date
                    }
                    return lhs > rhs
                }
            let dropped = Set(oldestSettled.prefix(keep.count - policy.maxEntries))
            for index in keep.indices where dropped.contains(index) { archived.append(keep[index]) }
            keep = keep.indices.filter { !dropped.contains($0) }.map { keep[$0] }
        }
        let ids = Set(keep.map(\.id))
        return Outcome(kept: keep, archived: archived.sorted { $0.date < $1.date },
                       seen: seen.intersection(ids))
    }
}

/// Markdown archive for records removed from state.json. One file per month,
/// appended in place. A retried run recognises rows it already wrote, so an
/// export that succeeded before a failed state save cannot duplicate lines.
enum RecordArchive {
    static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        "records-" + monthKey(date, calendar: calendar) + ".md"
    }

    @discardableResult
    static func append(_ entries: [Entry], directory: URL, calendar: Calendar = .current) throws -> [URL] {
        var written: [URL] = []
        guard !entries.isEmpty else { return written }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let names = Set(entries.map { fileName(for: $0.date, calendar: calendar) }).sorted()
        for name in names {
            let candidates = entries.filter { fileName(for: $0.date, calendar: calendar) == name }
            let url = directory.appendingPathComponent(name)
            // An unreadable archive must fail the whole run instead of being
            // treated as empty and overwritten.
            let existing: String
            if FileManager.default.fileExists(atPath: url.path) {
                existing = try String(contentsOf: url, encoding: .utf8)
            } else {
                existing = ""
            }
            // Legacy rows have no identity. Preserve them and append any
            // incoming record whose id cannot be confirmed in the archive.
            var archived = Set(existingRows(in: existing).compactMap(archivedID))
            let fresh = candidates.sorted { $0.date < $1.date }
                .filter { archived.insert($0.id).inserted }
            guard !fresh.isEmpty else { continue }
            var text = existing.isEmpty ? template(name: name) : existing
            if !text.hasSuffix("\n") { text += "\n" }
            for entry in fresh { text += row(entry, calendar: calendar) + "\n" }
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            written.append(url)
        }
        return written
    }

    /// Data rows already present in one archive file. Only generated rows start
    /// with a timestamp column, so headers and prose are ignored.
    static func existingRows(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("| ") && $0.dropFirst(2).first?.isNumber == true }
    }

    static func template(name: String) -> String {
        let month = name.replacingOccurrences(of: "records-", with: "")
            .replacingOccurrences(of: ".md", with: "")
        return """
        # MIRA 记录 · \(month)

        > 由 MIRA 自动整理：以下记录已从本地状态移除，在此按月份留存。

        | 时间 | 来源 | 状态 | 标题 |
        | --- | --- | --- | --- |
        """
    }

    static func row(_ entry: Entry, calendar: Calendar) -> String {
        let id = Data(entry.id.utf8).base64EncodedString()
        return "| \(timestamp(entry.date, calendar: calendar)) <!-- mira-id:\(id) --> | \(cell(entry.source)) | \(cell(entry.status)) | \(cell(entry.displayTitle)) |"
    }

    private static func archivedID(_ row: String) -> String? {
        // The timestamp cell is generated entirely by MIRA. User text in later
        // cells cannot be mistaken for a record marker.
        guard let timestampCell = row.dropFirst().split(separator: "|", maxSplits: 1).first,
              let marker = timestampCell.range(of: " <!-- mira-id:"),
              let end = timestampCell.range(of: " -->", range: marker.upperBound..<timestampCell.endIndex),
              let bytes = Data(base64Encoded: String(timestampCell[marker.upperBound..<end.lowerBound])) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    static func timestamp(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }

    /// One table cell: newlines and pipes would break the row.
    static func cell(_ value: String, limit: Int = 120) -> String {
        var text = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if text.count > limit { text = String(text.prefix(limit - 1)) + "…" }
        return text.replacingOccurrences(of: "|", with: "\\|")
    }
}

/// Caches that are pure derived data and may be deleted by age.
enum CacheCleanup {
    static func stale(in directory: URL, now: Date, ttl: TimeInterval,
                      fileManager: FileManager = .default) -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return urls.filter { url in
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return false }
            return now.timeIntervalSince(modified) > ttl
        }
    }
}
