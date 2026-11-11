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

    var canSnooze: Bool {
        status == "待确认" || status == "待补充信息" || status == "待完成"
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
}
struct HubData: Codable {
    var plans: [Plan] = []
    var entries: [Entry] = []
    var seen: Set<String> = []
    var lastEvent: Date?
}
enum Schedule {
    static func due(_ plan: Plan, now: Date, calendar: Calendar = .current) -> Entry? {
        guard plan.enabled, plan.weekdays.isEmpty || plan.weekdays.contains(calendar.component(.weekday, from: now)) else { return nil }
        let start = calendar.startOfDay(for: now)
        guard let time = calendar.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: start), time <= now,
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let key = "plan-\(plan.id)-\(parts.year!)-\(parts.month!)-\(parts.day!)"
        return Entry(id: key, title: plan.title, body: plan.notes, source: "个人计划", status: "待完成", link: plan.link, date: time, expires: end)
    }
    static func active(_ e: Entry, now: Date) -> Bool { !e.done && (e.expires == nil || e.expires! > now) }
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
        var changed = false
        var errors: [String] = []
    }

    /// Drain queued events into `data`. Bad files are quarantined instead of being
    /// retried forever, and every file is reported through the outcome so the
    /// caller can batch a single state save per tick.
    static func drain(inbox: URL, data: inout HubData, now: Date, decoder: JSONDecoder) -> Outcome {
        var outcome = Outcome()
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        for url in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let entry = try decoder.decode(Entry.self, from: Data(contentsOf: url))
                if let target = entry.dismiss {
                    if data.close(target) { outcome.changed = true }
                    outcome.dismissed.append(target)
                    outcome.consumed.append(url)
                    continue
                }
                guard Links.valid(entry.link) else { throw NSError(domain: "无效事件链接", code: 1) }
                if !data.seen.contains(entry.id) {
                    data.seen.insert(entry.id)
                    if let thread = entry.thread {
                        for i in data.entries.indices where data.entries[i].thread == thread && data.entries[i].date <= entry.date {
                            data.entries[i].done = true
                        }
                    }
                    // Old AI events stay in history rather than flooding the desktop after days away.
                    var event = entry
                    if now.timeIntervalSince(entry.date) > 86400 { event.done = true }
                    data.entries.insert(event, at: 0)
                    data.lastEvent = now
                    outcome.changed = true
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
        if u.scheme == "https" { return u.host == "chatgpt.com" || u.host == "chat.openai.com" }
        if u.scheme == "dsh" { return u.host == "open" && (u.path.isEmpty || u.path == "/") }
        return u.scheme == "codex" && u.host == "threads" && u.path.count > 1
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

    static func profile(_ environment: [String: String], home: URL) -> URL {
        let root = environment["DSH_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".dsh")
        return root.appendingPathComponent("profiles/desktop")
    }

    /// Match the row itself, not a string fragment: `id: mira-bridge-2` is a different plugin.
    static func installed(patch: String) -> Bool {
        patch.split(whereSeparator: \.isNewline).contains { line in
            let text = String(line).trimmingCharacters(in: .whitespaces)
            return text == "- id: mira-bridge" || text == "id: mira-bridge"
        }
    }

    /// `[]` is the documented way to disable the patch layer. Appending a list item
    /// after it produces invalid YAML, so the disabled layer must be replaced instead.
    static func isDisabledLayer(_ text: String) -> Bool {
        let rows = text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && $0 != "---" }
        return !rows.isEmpty && rows.allSatisfy { $0 == "[]" }
    }

    /// Copy the bridge into the profile and add its row. Never touches other rows.
    static func install(profile: URL, files: [String: Data], now: Date = Date()) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: profile.appendingPathComponent("package.json").path) else {
            throw NSError(domain: "请先启动一次 DeepSeek Harness，再配置连接。", code: 1)
        }
        let destination = profile.appendingPathComponent("plugins/mira-bridge")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for (name, data) in files {
            let target = destination.appendingPathComponent(name)
            try data.write(to: target, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        }
        let patch = profile.appendingPathComponent("cordis.patch.yml")
        // Distinguish "no patch yet" from "patch unreadable": an unreadable file
        // must fail the install instead of being silently replaced.
        var text = ""
        if fm.fileExists(atPath: patch.path) {
            text = try String(contentsOf: patch, encoding: .utf8)
        }
        guard !installed(patch: text) else { return }
        if !text.isEmpty {
            try text.write(to: backup(patch, now: now), atomically: true, encoding: .utf8)
        }
        if isDisabledLayer(text) { text = "" }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += patchBlock
        try text.write(to: patch, atomically: true, encoding: .utf8)
    }

    static func remove(profile: URL, now: Date = Date()) throws {
        let fm = FileManager.default
        let patch = profile.appendingPathComponent("cordis.patch.yml")
        if fm.fileExists(atPath: patch.path) {
            // Unreadable config must not be reported as "nothing to remove": the
            // plugin directory is deleted below, so fail before touching anything.
            let text = try String(contentsOf: patch, encoding: .utf8)
            if installed(patch: text) {
                guard let block = patchBlocks.first(where: { text.contains($0) }) else {
                    throw NSError(domain: "补丁层里的 mira-bridge 行不是安装时写入的格式，无法安全移除。已保留插件目录，请手动删除该项后重试。", code: 1)
                }
                let cleaned = text.replacingOccurrences(of: block, with: "")
                // Verify with the same matcher that install uses before deleting files.
                guard !installed(patch: cleaned) else {
                    throw NSError(domain: "补丁层里的 mira-bridge 行无法安全移除。已保留插件目录，请手动删除该项后重试。", code: 1)
                }
                try text.write(to: backup(patch, now: now), atomically: true, encoding: .utf8)
                try cleaned.write(to: patch, atomically: true, encoding: .utf8)
            }
        }
        let destination = profile.appendingPathComponent("plugins/mira-bridge")
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
    }

    /// Two backups within the same second must not overwrite each other.
    static func backup(_ patch: URL, now: Date) -> URL {
        let directory = patch.deletingLastPathComponent()
        let stem = patch.lastPathComponent + ".mira-backup-\(Int(now.timeIntervalSince1970))"
        var candidate = directory.appendingPathComponent(stem)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path), suffix < 1000 {
            candidate = directory.appendingPathComponent(stem + "-\(suffix)")
            suffix += 1
        }
        return candidate
    }
}
