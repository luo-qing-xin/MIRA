import Foundation

@main struct ScheduledTasksTests {
    static func main() throws {
        let source = """
        id = "review"
        name = "每周回顾"
        prompt = "检查本周的任务"
        status = "ACTIVE"
        rrule = "RRULE:FREQ=WEEKLY;BYHOUR=16;BYMINUTE=0;BYDAY=FR"
        """
        let plan = try DesktopSchedules.parse(source)[0]
        assert(plan.title == "每周回顾" && plan.weekdays == [6] && plan.hour == 16)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 18))!
        let due = Schedule.due(plan, now: friday, calendar: calendar)!
        assert(due.date < friday && due.id == Schedule.due(plan, now: friday.addingTimeInterval(300), calendar: calendar)!.id)
        assert(!Schedule.active(due, now: due.expires!))
        assert(Schedule.due(plan, now: friday.addingTimeInterval(-86400), calendar: calendar) == nil)
        let paused = try DesktopSchedules.parse(source.replacingOccurrences(of: "ACTIVE", with: "PAUSED"))
        assert(paused.isEmpty)
        var entries = [due]
        entries[0].notified = true
        entries[0].snooze = friday.addingTimeInterval(600)
        assert(DesktopSchedules.reconcile(&entries, plans: [], now: friday, calendar: calendar) == [due.id])
        assert(!Schedule.active(entries[0], now: friday) && entries[0].snooze == nil)
        _ = DesktopSchedules.reconcile(&entries, plans: [plan], now: friday, calendar: calendar)
        assert(Schedule.active(entries[0], now: friday) && !entries[0].notified)
        entries[0].done = true
        assert(DesktopSchedules.reconcile(&entries, plans: [], now: friday, calendar: calendar).isEmpty)
        assert(entries[0].done)
        var postponed = plan
        postponed.hour = 20
        entries = [due]
        _ = DesktopSchedules.reconcile(&entries, plans: [postponed], now: friday, calendar: calendar)
        assert(!Schedule.active(entries[0], now: friday))
        _ = DesktopSchedules.reconcile(&entries, plans: [postponed], now: friday.addingTimeInterval(10800), calendar: calendar)
        assert(Schedule.active(entries[0], now: friday.addingTimeInterval(10800)))
        let encoded = try JSONEncoder().encode(plan)
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "origin")
        let restored = try JSONDecoder().decode(Plan.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(restored.origin == nil)
        for rule in ["FREQ=MONTHLY;BYHOUR=16;BYMINUTE=0", "FREQ=DAILY;INTERVAL=2;BYHOUR=16;BYMINUTE=0", "FREQ=DAILY;BYHOUR=16;BYMINUTE=0;COUNT=3"] {
            let input = source.replacingOccurrences(of: "FREQ=WEEKLY;BYHOUR=16;BYMINUTE=0;BYDAY=FR", with: rule)
            do { _ = try DesktopSchedules.parse(input); fatalError("Unsupported rule accepted") } catch {}
        }
        let real = try DesktopSchedules.load(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/automations"))
        print("PASS: source parsing, paused schedules, weekdays, missed occurrence, stable identity, expiry and unsupported-rule rejection")
        print("Local schedules: \(real.plans.map(\.title)), issues: \(real.issues)")
    }
}
