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
        // A single unreadable plan must not freeze syncing for every other plan,
        // and its own reminder must not be mistaken for a deleted plan.
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-schedules-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let automations = root.appendingPathComponent("automations")
        for (folder, text) in [
            ("review", source),
            ("monthly", """
            id = "monthly"
            name = "月度回顾"
            status = "ACTIVE"
            rrule = "RRULE:FREQ=MONTHLY;BYHOUR=16;BYMINUTE=0"
            """),
            ("paused", source.replacingOccurrences(of: "id = \"review\"", with: "id = \"paused\"")
                .replacingOccurrences(of: "ACTIVE", with: "PAUSED")),
        ] {
            let dir = automations.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try text.write(to: dir.appendingPathComponent("automation.toml"), atomically: true, encoding: .utf8)
        }
        let snapshot = try DesktopSchedules.load(directory: automations)
        assert(snapshot.plans.count == 1 && snapshot.issues.count == 1, "readable plans still load beside a broken one")
        assert(snapshot.unavailable == ["desktop-monthly"], "unreadable plan id is recovered")
        assert(DesktopSchedules.planID(source) == "desktop-review")
        assert(DesktopSchedules.planID("name = \"x\"") == nil)
        var monthlyPlan = Plan(title: "月度回顾", notes: "", hour: 16, minute: 0, weekdays: [6], link: "")
        monthlyPlan.id = "desktop-monthly"
        var pausedPlan = plan; pausedPlan.id = "desktop-paused"
        let monthlyEntry = Schedule.due(monthlyPlan, now: friday, calendar: calendar)!
        let pausedEntry = Schedule.due(pausedPlan, now: friday, calendar: calendar)!
        var mixed = [monthlyEntry, pausedEntry]
        let reconciled = DesktopSchedules.reconcile(&mixed, plans: [], unavailable: snapshot.unavailable, now: friday, calendar: calendar)
        assert(reconciled == [pausedEntry.id], "only the known-removed plan is cancelled")
        assert(Schedule.active(mixed[0], now: friday), "an unreadable plan keeps its reminder")
        assert(!Schedule.active(mixed[1], now: friday), "a paused plan is still withdrawn")
        _ = DesktopSchedules.reconcile(&mixed, plans: [], unavailable: [], now: friday, calendar: calendar)
        assert(!Schedule.active(mixed[0], now: friday), "removing the unreadable file finally withdraws it")
        // Readable plans keep updating even while another file is broken.
        var renamed = plan; renamed.title = "每周回顾 · 已改名"
        var live = [due]
        _ = DesktopSchedules.reconcile(&live, plans: [renamed], unavailable: snapshot.unavailable, now: friday, calendar: calendar)
        assert(live[0].title == "每周回顾 · 已改名")
        // A file that cannot be read hides its id; such a snapshot must not
        // cancel reminders that merely look missing.
        let secretDir = automations.appendingPathComponent("secret")
        try FileManager.default.createDirectory(at: secretDir, withIntermediateDirectories: true)
        let secretFile = secretDir.appendingPathComponent("automation.toml")
        try "id = \"secret\"\nstatus = \"ACTIVE\"\nrrule = \"RRULE:FREQ=DAILY;BYHOUR=9;BYMINUTE=0\"\n".write(to: secretFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: secretFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secretFile.path) }
        let partial = try DesktopSchedules.load(directory: automations)
        assert(partial.plans.count == 1 && partial.issues.count == 2, "one unreadable file is reported")
        assert(!partial.removalsAllowed, "an unidentified unreadable plan blocks removals")
        var secretPlan = plan; secretPlan.id = "desktop-secret"
        var retained = [Schedule.due(secretPlan, now: friday, calendar: calendar)!]
        let none = DesktopSchedules.reconcile(&retained, plans: [], unavailable: partial.unavailable, allowRemovals: partial.removalsAllowed, now: friday, calendar: calendar)
        assert(none.isEmpty && Schedule.active(retained[0], now: friday), "no reminder is cancelled from an unreadable snapshot")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: secretFile.path)
        try FileManager.default.removeItem(at: secretDir)
        let complete = try DesktopSchedules.load(directory: automations)
        assert(complete.removalsAllowed)
        print("PASS: source parsing, paused schedules, weekdays, missed occurrence, stable identity, expiry, partial-snapshot reconciliation and unsupported-rule rejection")
    }
}
