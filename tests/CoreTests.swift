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

        // Row detection is exact: a different plugin id must not count as ours.
        assert(DSHLink.installed(patch: "rows:\n  - id: mira-bridge\n"))
        assert(!DSHLink.installed(patch: "rows:\n  - id: mira-bridge-2\n"))

        // A disabled layer (`[]`) must be replaced, not appended to, or DSH cannot boot.
        let emptyLayer = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-empty-\(UUID().uuidString)")
        let emptyProfile = emptyLayer.appendingPathComponent("desktop")
        let emptyPatch = emptyProfile.appendingPathComponent("cordis.patch.yml")
        try FileManager.default.createDirectory(at: emptyProfile, withIntermediateDirectories: true)
        try "{}".write(to: emptyProfile.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "[]\n".write(to: emptyPatch, atomically: true, encoding: .utf8)
        try DSHLink.install(profile: emptyProfile, files: ["index.js": Data("// bridge".utf8)], now: now)
        let replaced = try String(contentsOf: emptyPatch, encoding: .utf8)
        assert(!replaced.contains("[]"), "disabled layer is replaced")
        assert(DSHLink.installed(patch: replaced), "row added to the disabled layer")
        let backups = try FileManager.default.contentsOfDirectory(atPath: emptyProfile.path)
            .filter { $0.contains(".mira-backup-") }
        assert(backups.count == 1, "disabled layer is backed up before replacement")
        // Rows written after ours survive removal and are not glued to the previous line.
        let appended = try FileHandle(forWritingTo: emptyPatch)
        appended.seekToEndOfFile()
        appended.write(Data("- other: 1\n".utf8))
        try appended.close()
        try DSHLink.remove(profile: emptyProfile, now: now)
        let preserved = try String(contentsOf: emptyPatch, encoding: .utf8)
        assert(preserved == "- other: 1\n", "later rows are preserved intact")
        assert(!FileManager.default.fileExists(atPath: emptyProfile.appendingPathComponent("plugins/mira-bridge").path))
        try FileManager.default.removeItem(at: emptyLayer)

        // Unsafe layout: the plugin must be kept when the row cannot be removed safely.
        let unsafeLayer = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-unsafe-\(UUID().uuidString)")
        let unsafeProfile = unsafeLayer.appendingPathComponent("desktop")
        let unsafePatch = unsafeProfile.appendingPathComponent("cordis.patch.yml")
        let unsafeOriginal = "custom:\n  - id: mira-bridge\n    name: './plugins/mira-bridge/index.js'\n"
        try FileManager.default.createDirectory(at: unsafeProfile.appendingPathComponent("plugins/mira-bridge"), withIntermediateDirectories: true)
        try "{}".write(to: unsafeProfile.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try unsafeOriginal.write(to: unsafePatch, atomically: true, encoding: .utf8)
        try Data("// bridge".utf8).write(to: unsafeProfile.appendingPathComponent("plugins/mira-bridge/index.js"))
        var refusedUnsafe = false
        do { try DSHLink.remove(profile: unsafeProfile, now: now) } catch { refusedUnsafe = true }
        assert(refusedUnsafe, "unrecognised layout is refused")
        assert(FileManager.default.fileExists(atPath: unsafeProfile.appendingPathComponent("plugins/mira-bridge/index.js").path), "plugin is kept after refusal")
        let untouchedPatch = try String(contentsOf: unsafePatch, encoding: .utf8)
        assert(untouchedPatch == unsafeOriginal, "patch is untouched after refusal")
        try FileManager.default.removeItem(at: unsafeLayer)

        // Either installer's block can be removed by the app.
        let scriptedLayer = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-scripted-\(UUID().uuidString)")
        let scriptedProfile = scriptedLayer.appendingPathComponent("desktop")
        let scriptedPatch = scriptedProfile.appendingPathComponent("cordis.patch.yml")
        try FileManager.default.createDirectory(at: scriptedProfile.appendingPathComponent("plugins/mira-bridge"), withIntermediateDirectories: true)
        try "{}".write(to: scriptedProfile.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try DSHLink.scriptPatchBlock.write(to: scriptedPatch, atomically: true, encoding: .utf8)
        try Data("// bridge".utf8).write(to: scriptedProfile.appendingPathComponent("plugins/mira-bridge/index.js"))
        try DSHLink.remove(profile: scriptedProfile, now: now)
        let scriptedRemaining = try String(contentsOf: scriptedPatch, encoding: .utf8)
        assert(scriptedRemaining == "", "shell installer block is removable")
        assert(!FileManager.default.fileExists(atPath: scriptedProfile.appendingPathComponent("plugins/mira-bridge").path))
        try FileManager.default.removeItem(at: scriptedLayer)

        // Backups taken in the same second must not overwrite each other.
        let backupFolder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        let backupSource = backupFolder.appendingPathComponent("cordis.patch.yml")
        let firstBackup = DSHLink.backup(backupSource, now: now)
        try Data("[]".utf8).write(to: firstBackup)
        let secondBackup = DSHLink.backup(backupSource, now: now)
        assert(firstBackup != secondBackup, "second backup gets a new name")
        assert(secondBackup.lastPathComponent.hasPrefix("cordis.patch.yml.mira-backup-"))
        assert(!FileManager.default.fileExists(atPath: secondBackup.path))
        try FileManager.default.removeItem(at: backupFolder)

        let decisionBox = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-decisions-\(UUID().uuidString)")
        try Decisions.write(root: decisionBox, token: "abcd-1234", decision: "allow")
        let decisionFile = decisionBox.appendingPathComponent("decisions/abcd-1234.json")
        let decided = try JSONSerialization.jsonObject(with: Data(contentsOf: decisionFile)) as? [String: Any]
        assert(decided?["token"] as? String == "abcd-1234", "token echoed")
        assert(decided?["decision"] as? String == "allow", "decision stored")
        let permissions = try FileManager.default.attributesOfItem(atPath: decisionFile.path)[.posixPermissions] as? Int
        assert(permissions == 0o600, "decision file is private")
        var rejectedToken = false
        do { try Decisions.write(root: decisionBox, token: "../escape", decision: "allow") } catch { rejectedToken = true }
        assert(rejectedToken, "path-like tokens are refused")
        var rejectedChoice = false
        do { try Decisions.write(root: decisionBox, token: "abcd-1234", decision: "maybe") } catch { rejectedChoice = true }
        assert(rejectedChoice, "unknown decisions are refused")
        try FileManager.default.removeItem(at: decisionBox)

        let decoderForToken = JSONDecoder(); decoderForToken.dateDecodingStrategy = .secondsSince1970
        let approvalJSON = Data("{\"id\":\"a\",\"title\":\"t\",\"body\":\"\",\"source\":\"DSH · MIRA\",\"status\":\"待确认\",\"link\":\"dsh://open\",\"date\":100,\"done\":false,\"notified\":false,\"token\":\"abcd-1234\"}".utf8)
        let decodedApproval = try decoderForToken.decode(Entry.self, from: approvalJSON)
        assert(decodedApproval.token == "abcd-1234", "token decodes from inbox JSON")

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        var data = HubData(); data.entries = [done]; data.seen = ["event-1"]
        let restored = try decoder.decode(HubData.self, from: encoder.encode(data))
        assert(restored.entries[0].done && restored.seen.contains("event-1"))
        print("PASS: missed reminder, dedup, weekday, future, expiration, completion, disabled, URL validation, persistence, dismissal, DSH link install, approval decisions")
    }
}
