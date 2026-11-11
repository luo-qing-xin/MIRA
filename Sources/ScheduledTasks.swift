import Foundation

/// Read-only adapter for desktop automation files. Unsupported recurrence rules
/// are reported, never silently converted into daily reminders.
enum DesktopSchedules {
    /// Refresh only today's unfinished occurrences. A transient read error must
    /// not cancel stored reminders; callers use this only for a complete snapshot.
    static func reconcile(_ entries: inout [Entry], plans: [Plan], now: Date, calendar: Calendar = .current) -> [String] {
        let current = Dictionary(plans.map { (Schedule.occurrenceID($0, now: now, calendar: calendar), $0) }, uniquingKeysWith: { first, _ in first })
        var changed: [String] = []
        for i in entries.indices {
            let old = entries[i]
            guard old.id.hasPrefix("plan-desktop-"), !old.done, calendar.isDate(old.date, inSameDayAs: now) else { continue }
            if let plan = current[old.id], let due = Schedule.due(plan, now: now, calendar: calendar) {
                if old.date != due.date || old.expires != due.expires || old.title != due.title || old.body != due.body {
                    entries[i].title = due.title
                    entries[i].body = due.body
                    entries[i].date = due.date
                    entries[i].expires = due.expires
                    if old.date != due.date || !Schedule.active(old, now: now) {
                        entries[i].notified = false
                        entries[i].snooze = nil
                    }
                    changed.append(old.id)
                }
            } else if Schedule.active(old, now: now) {
                entries[i].expires = now
                entries[i].snooze = nil
                changed.append(old.id)
            }
        }
        return changed
    }
    struct Snapshot {
        var plans: [Plan] = []
        var issues: [String] = []
    }

    static func load(directory: URL) throws -> Snapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return Snapshot() }
        var snapshot = Snapshot()
        for folder in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
            let file = folder.appendingPathComponent("automation.toml")
            guard fm.fileExists(atPath: file.path) else { continue }
            do {
                snapshot.plans += try parse(String(contentsOf: file, encoding: .utf8))
            } catch {
                snapshot.issues.append("\(folder.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return snapshot
    }

    static func parse(_ text: String) throws -> [Plan] {
        func field(_ key: String) throws -> String {
            let pattern = "(?m)^" + NSRegularExpression.escapedPattern(for: key) + "\\s*=\\s*(\"(?:[^\"\\\\\\n]|\\\\.)*\")\\s*$"
            let regex = try NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else {
                throw failure("无法读取 \(key)，请检查计划格式")
            }
            return try JSONDecoder().decode(String.self, from: Data(text[range].utf8))
        }
        let id = try field("id")
        let name = try field("name")
        let status = try field("status")
        guard status == "ACTIVE" else { return [] }
        let rule = try field("rrule").replacingOccurrences(of: "RRULE:", with: "")
        var values: [String: String] = [:]
        for piece in rule.split(separator: ";") {
            let pair = piece.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, values[String(pair[0])] == nil else { throw failure("重复或无效的重复规则") }
            values[String(pair[0])] = String(pair[1])
        }
        let allowed: Set<String> = ["FREQ", "INTERVAL", "BYDAY", "BYHOUR", "BYMINUTE", "BYSECOND"]
        guard Set(values.keys).isSubset(of: allowed),
              ["DAILY", "WEEKLY"].contains(values["FREQ"] ?? ""),
              values["INTERVAL"] == nil || values["INTERVAL"] == "1",
              values["BYSECOND"] == nil || values["BYSECOND"] == "0" else {
            throw failure("暂不支持此重复规则，仅同步每天／每周固定时间")
        }
        let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        var days: [Int] = []
        if let dayList = values["BYDAY"] {
            for day in dayList.split(separator: ",") {
                guard let number = weekdays[String(day)] else { throw failure("暂不支持此星期规则") }
                days.append(number)
            }
        }
        guard values["FREQ"] != "WEEKLY" || !days.isEmpty else { throw failure("每周计划缺少星期") }
        guard let hour = Int(values["BYHOUR"] ?? ""), (0...23).contains(hour),
              let minute = Int(values["BYMINUTE"] ?? ""), (0...59).contains(minute) else {
            throw failure("仅支持每条计划一个明确的提醒时间")
        }
        var plan = Plan(title: name, notes: (try? field("prompt")) ?? "到达桌面定时任务的计划时间。", hour: hour, minute: minute, weekdays: days, link: "")
        plan.id = "desktop-" + id
        plan.origin = "Codex 桌面计划"
        return [plan]
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "MIRA.Schedule", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
