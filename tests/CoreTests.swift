import Foundation

private func writeEntryJSON(_ entry: Entry, to inbox: URL) throws -> URL {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let url = inbox.appendingPathComponent(entry.id + ".json")
    try encoder.encode(entry).write(to: url)
    return url
}

@main struct Tests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 10, minute: 30))!
        var plan = Plan(title: "训练", notes: "", hour: 8, minute: 0, weekdays: [4], link: "")
        let missed = Schedule.due(plan, now: now, calendar: calendar)!
        var ended = Entry(id: "ended", title: "任务", body: "", source: "Codex", status: "本轮结束", link: "", date: now)
        assert(Schedule.active(ended, now: now) && !ended.notified, "completion remains eligible for its initial notification")
        assert(!Schedule.needsAttention(ended, now: now) && Schedule.inHistory(ended, now: now), "completion auto-archives without user acknowledgement")
        ended.notified = true
        let restoredEnd = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(ended))
        assert(restoredEnd.notified && !Schedule.needsAttention(restoredEnd, now: now), "restart preserves notification dedup and auto-archive")
        assert(restoredEnd.historyStatus == "本轮结束", "auto-archiving does not claim manual handling or expiry")
        for status in ["待确认", "待补充信息", "待完成", "任务失败"] {
            var actionable = ended; actionable.status = status
            assert(Schedule.needsAttention(actionable, now: now) && !Schedule.inHistory(actionable, now: now), "actionable states remain pending")
        }
        // Announcement selection is pure; rolling the flags back after a failed
        // save must make the next tick retry the same reminders.
        var queued = [
            Entry(id: "due", title: "到点", body: "", source: "个人计划", status: "待完成", link: "", date: now),
            Entry(id: "already", title: "已通知", body: "", source: "个人计划", status: "待完成", link: "", date: now, notified: true),
            Entry(id: "running", title: "运行", body: "", source: "Codex", status: "运行中", link: "", date: now),
            Entry(id: "snoozed", title: "延后", body: "", source: "个人计划", status: "待完成", link: "", date: now, snooze: now.addingTimeInterval(600)),
            Entry(id: "expired", title: "过期", body: "", source: "个人计划", status: "待完成", link: "", date: now, expires: now.addingTimeInterval(-1)),
            Entry(id: "resumed", title: "延后到点", body: "", source: "个人计划", status: "待完成", link: "", date: now, snooze: now.addingTimeInterval(-1)),
        ]
        let firstDue = Notify.due(queued, now: now)
        assert(firstDue == [0, 5], "only active, unsnoozed, unannounced entries are due")
        Notify.mark(&queued, at: firstDue)
        assert(queued[0].notified && queued[5].notified && Notify.due(queued, now: now).isEmpty)
        Notify.rollback(&queued, at: firstDue)
        assert(Notify.due(queued, now: now) == firstDue, "a failed save retries the same reminders")
        assert(!queued[0].notified && !queued[5].notified, "rollback clears only the attempted flags")
        var completion = Entry(id: "auto", title: "完成", body: "", source: "DSH · MIRA", status: "本轮结束", link: "dsh://open", date: now)
        assert(Notify.due([completion], now: now) == [0], "completion notifies once before auto-archiving")
        completion.done = true
        assert(Notify.due([completion], now: now).isEmpty)
        assert(Notify.due([], now: now).isEmpty)
        // Closing an approval card hands the request back to DSH immediately;
        // closing an ordinary notice must keep it pending.
        var approvalCard = Entry(id: "approval-card", title: "确认", body: "", source: "DSH · MIRA", status: "待确认", link: "dsh://open", date: now, token: "abcd-1234")
        assert(ReminderClose.decision(for: approvalCard) == "defer", "closing an approval defers it to DSH")
        approvalCard.token = nil
        assert(ReminderClose.decision(for: approvalCard) == nil, "closing a normal reminder keeps it")
        approvalCard.token = "abcd-1234"; approvalCard.status = "待完成"
        assert(ReminderClose.decision(for: approvalCard) == nil, "only a live approval produces a decision")
        assert(missed.date < now, "startup catches today's missed occurrence")
        assert(Schedule.due(plan, now: now.addingTimeInterval(60), calendar: calendar)!.id == missed.id, "stable dedup key")
        assert(Schedule.due(plan, now: now.addingTimeInterval(-4 * 3600), calendar: calendar) == nil)
        assert(Schedule.due(plan, now: now.addingTimeInterval(86400), calendar: calendar) == nil, "wrong weekday")
        assert(!Schedule.active(missed, now: missed.expires!), "expires at midnight")
        var done = missed; done.done = true
        assert(!Schedule.active(done, now: now))
        plan.enabled = false
        assert(Schedule.due(plan, now: now, calendar: calendar) == nil)
        // The plan editor must not crash when the chosen wall-clock time is skipped
        // by a DST spring-forward.
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let springForward = pacific.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let skipped = PlanTime.date(hour: 2, minute: 30, now: springForward, calendar: pacific)
        assert(PlanTime.components(skipped, calendar: pacific).hour == 3, "missing DST time moves forward")
        let ordinary = PlanTime.date(hour: 9, minute: 15, now: springForward, calendar: pacific)
        let ordinaryParts = PlanTime.components(ordinary, calendar: pacific)
        assert(ordinaryParts.hour == 9 && ordinaryParts.minute == 15, "an existing time is preserved")
        assert(Links.valid("codex://threads/test"))
        assert(Links.valid("dsh://open"))
        assert(!Links.valid("dsh://open/../../etc/passwd"))
        assert(!Links.valid("dsh://other"))
        assert(Links.valid("https://chatgpt.com/c/test"))
        assert(!Links.valid("file:///etc/passwd"))
        assert(!Links.valid("https://chatgpt.com.evil.example/c/test"))
        assert(!Links.valid("javascript:alert(1)"))
        assert(Links.valid("HTTPS://CHATGPT.COM/c/test"), "scheme and host are case-insensitive")
        assert(Links.valid("Codex://threads/ABC"))
        assert(Links.valid("DSH://open"))
        assert(!Links.valid("HTTPS://chatgpt.com.evil.example/c/test"))
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
        assert(DSHLink.installed(patch: "rows:\n  - id: \"mira-bridge\"\n"), "quoted ids still refer to the plugin")
        assert(DSHLink.installed(patch: "rows:\n  id: 'mira-bridge'\n"))
        assert(!DSHLink.installed(patch: "rows:\n  - id: \"mira-bridge-2\"\n"))

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
        assert(secondBackup.lastPathComponent == firstBackup.lastPathComponent + "-2")
        assert(secondBackup.lastPathComponent.hasPrefix("cordis.patch.yml.mira-backup-"))
        assert(!FileManager.default.fileExists(atPath: secondBackup.path))
        let hooksBackup = Backups.unique(in: backupFolder, stem: "hooks.mira-backup-100", extension: "json")
        try Data("{}".utf8).write(to: hooksBackup)
        let hooksBackupAgain = Backups.unique(in: backupFolder, stem: "hooks.mira-backup-100", extension: "json")
        assert(hooksBackup.lastPathComponent == "hooks.mira-backup-100.json")
        assert(hooksBackupAgain.lastPathComponent == "hooks.mira-backup-100-2.json", "extension stays last")
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

        // Inbox drain: bad events are quarantined, old events archived, and every
        // applied file is reported once so the caller can save a single time.
        let inboxBox = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-inbox-\(UUID().uuidString)")
        let inboxDir = inboxBox.appendingPathComponent("inbox")
        try FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        let inboxNow = Date(timeIntervalSince1970: 1_764_000_000)
        let good = Entry(id: "event-1", title: "本轮结束", body: "", source: "Codex · MIRA", status: "本轮结束", link: "codex://threads/s1", date: inboxNow.addingTimeInterval(-30), thread: "s1")
        let goodURL = try writeEntryJSON(good, to: inboxDir)
        let old = Entry(id: "event-old", title: "旧事件", body: "", source: "Codex · MIRA", status: "本轮结束", link: "codex://threads/s2", date: inboxNow.addingTimeInterval(-90000), thread: "s2")
        let oldURL = try writeEntryJSON(old, to: inboxDir)
        let badLink = Entry(id: "event-bad", title: "坏链接", body: "", source: "Codex · MIRA", status: "本轮结束", link: "file:///etc/passwd", date: inboxNow, thread: "s3")
        let badURL = try writeEntryJSON(badLink, to: inboxDir)
        let brokenURL = inboxDir.appendingPathComponent("broken.json")
        try Data("{not json".utf8).write(to: brokenURL)
        let inboxDecoder = JSONDecoder()
        inboxDecoder.dateDecodingStrategy = .secondsSince1970
        var inboxData = HubData()
        let outcome = Inbox.drain(inbox: inboxDir, data: &inboxData, now: inboxNow, decoder: inboxDecoder)
        assert(outcome.changed)
        assert(outcome.consumed.count == 2, "valid events are reported for deletion")
        let consumedNames = Set(outcome.consumed.map(\.lastPathComponent))
        assert(consumedNames == [goodURL.lastPathComponent, oldURL.lastPathComponent])
        assert(outcome.errors.count == 2, "bad link and malformed JSON are reported")
        assert(inboxData.seen.contains("event-1") && inboxData.seen.contains("event-old"))
        assert(!inboxData.seen.contains("event-bad"), "invalid events are never inserted")
        assert(inboxData.entries.count == 2)
        assert(inboxData.entries.first(where: { $0.id == "event-old" })?.done == true, "old event is archived")
        assert(FileManager.default.fileExists(atPath: goodURL.path), "drain leaves deletion to the caller")
        assert(!FileManager.default.fileExists(atPath: badURL.path), "bad link is quarantined")
        assert(!FileManager.default.fileExists(atPath: brokenURL.path), "malformed JSON is quarantined")
        let rejectedDir = inboxDir.appendingPathComponent("rejected")
        let rejectedNames = try FileManager.default.contentsOfDirectory(atPath: rejectedDir.path)
        assert(rejectedNames.count == 2)
        let rejectedBad = rejectedDir.appendingPathComponent(badURL.lastPathComponent)
        assert(FileManager.default.fileExists(atPath: rejectedBad.path))
        let rejectedPerms = try FileManager.default.attributesOfItem(atPath: rejectedBad.path)[.posixPermissions] as? Int
        assert(rejectedPerms == 0o600, "quarantined events stay private")
        for url in outcome.consumed { try FileManager.default.removeItem(at: url) }

        let approvalEntry = Entry(id: "approval-1", title: "确认", body: "", source: "DSH · MIRA", status: "待确认", link: "dsh://open", date: inboxNow, thread: "s1")
        inboxData.entries.append(approvalEntry)
        let dismissal = Entry(id: "dismiss-approval-1", title: "已处理", body: "", source: "DSH", status: "已处理", link: "", date: inboxNow.addingTimeInterval(1), done: true, notified: true, thread: "s1", dismiss: "approval-1")
        let dismissalURL = try writeEntryJSON(dismissal, to: inboxDir)
        let second = Inbox.drain(inbox: inboxDir, data: &inboxData, now: inboxNow, decoder: inboxDecoder)
        assert(second.changed)
        assert(second.dismissed == ["approval-1"], "dismissal reports its target to the UI")
        assert(second.consumed.map(\.lastPathComponent) == [dismissalURL.lastPathComponent])
        assert(inboxData.entries.first(where: { $0.id == "approval-1" })?.done == true)
        try FileManager.default.removeItem(at: dismissalURL)

        let duplicateURL = try writeEntryJSON(good, to: inboxDir)
        let third = Inbox.drain(inbox: inboxDir, data: &inboxData, now: inboxNow, decoder: inboxDecoder)
        assert(!third.changed, "a duplicate is consumed without touching state")
        assert(third.consumed.map(\.lastPathComponent) == [duplicateURL.lastPathComponent])

        let collision = inboxDir.appendingPathComponent("collision.json")
        try Data("x".utf8).write(to: collision)
        let firstMove = try Inbox.quarantine(collision, inbox: inboxDir)
        try Data("y".utf8).write(to: inboxDir.appendingPathComponent("collision.json"))
        let secondMove = try Inbox.quarantine(inboxDir.appendingPathComponent("collision.json"), inbox: inboxDir)
        assert(firstMove.lastPathComponent == "collision.json")
        assert(secondMove.lastPathComponent == "collision-2.json", "quarantine never overwrites an earlier file")
        let firstBytes = try Data(contentsOf: firstMove)
        let secondBytes = try Data(contentsOf: secondMove)
        assert(firstBytes == Data("x".utf8) && secondBytes == Data("y".utf8))
        try FileManager.default.removeItem(at: inboxBox)

        // A queue that cannot be listed must report an error instead of looking empty.
        let blockedInbox = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-blocked-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blockedInbox)
        var blockedData = HubData()
        let blocked = Inbox.drain(inbox: blockedInbox, data: &blockedData, now: inboxNow, decoder: inboxDecoder)
        assert(blocked.errors.count == 1 && blocked.errors[0].contains("不是文件夹"), "a file at the inbox path is reported")
        assert(!blocked.changed && blocked.consumed.isEmpty)
        try FileManager.default.removeItem(at: blockedInbox)

        // A queue deleted while running is recreated instead of dropping events.
        let recreatedInbox = blockedInbox.appendingPathComponent("inbox")
        let recreated = Inbox.drain(inbox: recreatedInbox, data: &blockedData, now: inboxNow, decoder: inboxDecoder)
        assert(recreated.errors.isEmpty && recreated.consumed.isEmpty)
        var isDirectory: ObjCBool = false
        assert(FileManager.default.fileExists(atPath: recreatedInbox.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        let inboxPermissions = try FileManager.default.attributesOfItem(atPath: recreatedInbox.path)[.posixPermissions] as? Int
        assert(inboxPermissions == 0o700, "recreated queue stays private")
        try FileManager.default.removeItem(at: blockedInbox)

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
