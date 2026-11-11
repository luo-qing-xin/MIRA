import Foundation

@main struct Tests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 10, minute: 30))!
        var plan = Plan(title: "训练", notes: "", hour: 8, minute: 0, weekdays: [4], link: "")
        let missed = Schedule.due(plan, now: now, calendar: calendar)!
        assert(missed.date < now, "startup catches today's missed occurrence")
        assert(Schedule.due(plan, now: now.addingTimeInterval(60), calendar: calendar)!.id == missed.id, "stable dedup key")
        assert(Schedule.due(plan, now: now.addingTimeInterval(-4 * 3600), calendar: calendar) == nil)
        assert(Schedule.due(plan, now: now.addingTimeInterval(86400), calendar: calendar) == nil, "wrong weekday")
        assert(!Schedule.active(missed, now: missed.expires!), "expires at midnight")
        var done = missed; done.done = true
        assert(!Schedule.active(done, now: now))
        plan.enabled = false
        assert(Schedule.due(plan, now: now, calendar: calendar) == nil)
        assert(Links.valid("codex://threads/test"))
        assert(Links.valid("dsh://open"))
        assert(!Links.valid("dsh://open/../../etc/passwd"))
        assert(!Links.valid("dsh://other"))
        assert(Links.valid("https://chatgpt.com/c/test"))
        assert(!Links.valid("file:///etc/passwd"))
        assert(!Links.valid("https://chatgpt.com.evil.example/c/test"))
        assert(!Links.valid("javascript:alert(1)"))
        var pending = HubData()
        pending.entries = [Entry(id: "dsh-ask", title: "确认", body: "", source: "DSH · MIRA", status: "待确认", link: "dsh://open", date: now)]
        assert(!pending.close("missing"), "unknown ids are ignored")
        assert(pending.close("dsh-ask") && pending.entries[0].done, "dismissal closes the pending reminder")
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-dsh-\(UUID().uuidString)")
        let profile = DSHLink.profile(["DSH_HOME": temp.path], home: temp)
        assert(profile.lastPathComponent == "desktop", "profile resolution uses DSH_HOME")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try "{}".write(to: profile.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "prefs: 1\n".write(to: profile.appendingPathComponent("cordis.patch.yml"), atomically: true, encoding: .utf8)
        try DSHLink.install(profile: profile, files: ["index.js": Data("// bridge".utf8), "entry.js": Data("// entry".utf8)])
        let installedPatch = try String(contentsOf: profile.appendingPathComponent("cordis.patch.yml"), encoding: .utf8)
        assert(DSHLink.installed(patch: installedPatch), "row added")
        assert(installedPatch.hasPrefix("prefs: 1\n"), "existing rows untouched")
        assert(FileManager.default.fileExists(atPath: profile.appendingPathComponent("plugins/mira-bridge/index.js").path))
        assert(FileManager.default.fileExists(atPath: DSHLink.backup(profile.appendingPathComponent("cordis.patch.yml"), now: now).path) == false, "backup name is timestamped")
        try DSHLink.install(profile: profile, files: ["index.js": Data("// bridge".utf8)])
        let reinstalled = try String(contentsOf: profile.appendingPathComponent("cordis.patch.yml"), encoding: .utf8)
        assert(reinstalled.components(separatedBy: "id: mira-bridge").count == 2, "install is idempotent")
        try DSHLink.remove(profile: profile)
        let removed = try String(contentsOf: profile.appendingPathComponent("cordis.patch.yml"), encoding: .utf8)
        assert(!DSHLink.installed(patch: removed), "row removed")
        assert(!FileManager.default.fileExists(atPath: profile.appendingPathComponent("plugins/mira-bridge").path), "plugin removed")
        try FileManager.default.removeItem(at: temp)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        var data = HubData(); data.entries = [done]; data.seen = ["event-1"]
        let restored = try decoder.decode(HubData.self, from: encoder.encode(data))
        assert(restored.entries[0].done && restored.seen.contains("event-1"))
        print("PASS: missed reminder, dedup, weekday, future, expiration, completion, disabled, URL validation, persistence, dismissal, DSH link install")
    }
}
