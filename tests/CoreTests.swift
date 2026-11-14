import Foundation

private func writeEntryJSON(_ entry: Entry, to inbox: URL) throws -> URL {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let url = inbox.appendingPathComponent(entry.id + ".json")
    try encoder.encode(entry).write(to: url)
    return url
}

private func encodeEvent(_ event: AdapterEvent, _ transform: (inout [String: Any]) -> Void = { _ in }) throws -> String {
    var object: [String: Any] = [
        "adapter": ["id": event.adapter.id, "name": event.adapter.name ?? event.adapter.id, "version": event.adapter.version],
        "kind": event.kind,
        "session": event.session,
    ]
    if let time = event.time { object["time"] = time }
    if let turn = event.turn { object["turn"] = turn }
    if let cwd = event.cwd { object["cwd"] = cwd }
    if let hint = event.titleHint { object["titleHint"] = hint }
    if let title = event.title { object["title"] = title }
    if let reason = event.reason { object["reason"] = reason }
    if let requiresPlanCheck = event.requiresPlanCheck { object["requiresPlanCheck"] = requiresPlanCheck }
    if let link = event.link { object["link"] = link }
    if let key = event.dedupeKey { object["dedupeKey"] = key }
    if let closes = event.closes { object["closes"] = closes }
    if let approval = event.approval {
        var value: [String: Any] = [:]
        if let token = approval.token { value["token"] = token }
        if let ttl = approval.ttlMs { value["ttlMs"] = ttl }
        if let tool = approval.tool { value["tool"] = tool }
        if let why = approval.reason { value["reason"] = why }
        object["approval"] = value
    }
    if let questions = event.questions {
        object["questions"] = questions.map { question -> [String: Any] in
            var value: [String: Any] = [:]
            if let id = question.id { value["id"] = id }
            if let text = question.question { value["question"] = text }
            if let header = question.header { value["header"] = header }
            return value
        }
    }
    transform(&object)
    object["protocol"] = AdapterEvent.protocolName
    return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}
private func startEventJSON(_ event: AdapterEvent) -> String { try! encodeEvent(event) { _ in } }
private func approvalEventJSON(_ event: AdapterEvent) -> String { try! encodeEvent(event) { _ in } }
private func closeEventJSON(_ event: AdapterEvent) -> String { try! encodeEvent(event) { _ in } }

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
        // Prompt-derived titles may arrive as Markdown headings; clean them for
        // display without rewriting the stored history.
        assert(Titles.display("# 任务：对当前项目进行长期") == "对当前项目进行长期")
        assert(Titles.display("##   修复登录  ") == "修复登录")
        assert(Titles.display("- 整理周报") == "整理周报")
        assert(Titles.display("> 任务: 上线检查") == "上线检查")
        assert(Titles.display("任务中心改版") == "任务中心改版", "a label without a colon is part of the name")
        assert(Titles.display("#") == "#", "an empty cleanup keeps the original")
        assert(Titles.display("设计 AI 任务与提醒中心") == "设计 AI 任务与提醒中心")
        let headed = Entry(id: "headed", title: "# 任务：对当前项目进行长期", body: "", source: "DSH · MIRA", status: "本轮结束", link: "dsh://open", date: now)
        assert(headed.displayTitle == "对当前项目进行长期")
        assert(headed.title == "# 任务：对当前项目进行长期", "display cleanup never rewrites the stored title")
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
        assert(DSHLink.installed(patch: "rows:\r\n  - id: 'mira-bridge' # pinned\r\n"))
        assert(!DSHLink.installed(patch: "  # - id: mira-bridge\n  - other-id: mira-bridge\n  - id: mira-bridge#suffix\n"))

        let failedInstall = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-dsh-failure-\(UUID().uuidString)")
        let failedPatch = failedInstall.appendingPathComponent("cordis.patch.yml")
        let oldPlugin = failedInstall.appendingPathComponent("plugins/mira-bridge")
        let oldIndex = oldPlugin.appendingPathComponent("index.js")
        try FileManager.default.createDirectory(at: oldPlugin, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: failedInstall.appendingPathComponent("package.json"))
        try Data("previous".utf8).write(to: oldIndex)
        try Data([0xff]).write(to: failedPatch)
        do {
            try DSHLink.install(profile: failedInstall, files: ["index.js": Data("new".utf8)])
            assertionFailure("a malformed patch must abort before updating the plugin")
        } catch {}
        let oldIndexAfterMalformedPatch = try Data(contentsOf: oldIndex)
        assert(oldIndexAfterMalformedPatch == Data("previous".utf8))
        try FileManager.default.removeItem(at: failedPatch)
        if geteuid() != 0 {
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: failedInstall.path)
            do {
                try DSHLink.install(profile: failedInstall, files: ["index.js": Data("new".utf8)])
                assertionFailure("an unwritable patch location must fail")
            } catch {}
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: failedInstall.path)
            let restoredPlugin = try Data(contentsOf: oldIndex)
            assert(restoredPlugin == Data("previous".utf8), "failed patch publication restores the previous plugin")
        }
        try FileManager.default.removeItem(at: failedInstall)

        // A disabled layer (`[]`) must be replaced, not appended to, or DSH cannot boot.
        let emptyLayer = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-empty-\(UUID().uuidString)")
        let emptyProfile = emptyLayer.appendingPathComponent("desktop")
        let emptyPatch = emptyProfile.appendingPathComponent("cordis.patch.yml")
        try FileManager.default.createDirectory(at: emptyProfile, withIntermediateDirectories: true)
        try "{}".write(to: emptyProfile.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try "# keep\n[] # disabled\n".write(to: emptyPatch, atomically: true, encoding: .utf8)
        try DSHLink.install(profile: emptyProfile, files: ["index.js": Data("// bridge".utf8)], now: now)
        let replaced = try String(contentsOf: emptyPatch, encoding: .utf8)
        assert(!replaced.contains("[]"), "disabled layer is replaced")
        assert(replaced.hasPrefix("# keep\n# disabled\n"), "comments from the disabled layer survive")
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
        assert(preserved == "# keep\n# disabled\n- other: 1\n", "unrelated rows are preserved intact")
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

        let hookConfig = backupFolder.appendingPathComponent("hooks.json")
        let receiver = backupFolder.appendingPathComponent("user's MIRA/receive.py")
        try FileManager.default.createDirectory(at: receiver.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ownedCommand = CodexHooks.command(for: receiver)
        assert(ownedCommand.contains("user'\\''s MIRA/receive.py"))
        let mixedGroup: [String: Any] = [
            "matcher": "custom", "custom": true,
            "hooks": [
                ["type": "command", "command": ownedCommand, "timeout": 7],
                ["type": "command", "command": "echo MIRA/receive.py"],
                ["type": "prompt", "prompt": "user hook"]
            ]
        ]
        let hooksBefore = try JSONSerialization.data(withJSONObject: [
            "userSetting": "keep", "hooks": ["Stop": [mixedGroup], "SessionStart": ["preserve"]]
        ])
        try hooksBefore.write(to: hookConfig)
        try CodexHooks.install(config: hookConfig, script: receiver, receiver: Data("old".utf8), emitter: Data("sdk".utf8), now: now)
        let firstHooks = try Data(contentsOf: hookConfig)
        let firstConfig = try JSONSerialization.jsonObject(with: firstHooks) as! [String: Any]
        let events = firstConfig["hooks"] as! [String: Any]
        assert(firstConfig["userSetting"] as? String == "keep" && events["SessionStart"] as? [String] == ["preserve"])
        assert(NSArray(array: events["Stop"] as! [Any]).isEqual(to: [mixedGroup]), "mixed group, options and matcher survive intact")
        let preTool = (events["PreToolUse"] as! [[String: Any]])[0]
        assert(preTool["matcher"] as? String == ".*request_user_input.*")
        assert(CodexHooks.installed(config: hookConfig, script: receiver))
        try CodexHooks.install(config: hookConfig, script: receiver, receiver: Data("new".utf8), emitter: Data("sdk".utf8), now: now)
        let repeatedHooks = try Data(contentsOf: hookConfig)
        let updatedReceiver = try Data(contentsOf: receiver)
        assert(firstHooks == repeatedHooks && updatedReceiver == Data("new".utf8))
        try Data(#"{"hooks":{"Stop":"invalid"}}"#.utf8).write(to: hookConfig)
        do {
            try CodexHooks.install(config: hookConfig, script: receiver, receiver: Data("broken".utf8), emitter: Data(), now: now)
            assertionFailure("an invalid event shape must not be replaced")
        } catch {}
        let receiverAfterInvalidConfig = try Data(contentsOf: receiver)
        assert(receiverAfterInvalidConfig == updatedReceiver)
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
        let approvalJSON = Data("{\"id\":\"a\",\"title\":\"t\",\"body\":\"\",\"source\":\"DSH · MIRA\",\"status\":\"待确认\",\"link\":\"dsh://open\",\"date\":100,\"done\":false,\"notified\":false,\"token\":\"abcd-1234\",\"adapterVersion\":\"0.4.0\"}".utf8)
        let decodedApproval = try decoderForToken.decode(Entry.self, from: approvalJSON)
        assert(decodedApproval.token == "abcd-1234", "token decodes from inbox JSON")
        assert(decodedApproval.adapterVersion == "0.4.0", "adapter version decodes from inbox JSON")
        let legacyJSON = Data("{\"id\":\"b\",\"title\":\"t\",\"body\":\"\",\"source\":\"Codex\",\"status\":\"本轮结束\",\"link\":\"\",\"date\":100,\"done\":false,\"notified\":false}".utf8)
        let legacyEntry = try decoderForToken.decode(Entry.self, from: legacyJSON)
        assert(legacyEntry.adapterVersion == nil, "older entries without a version still decode")

        // MARK: Adapter version handshake
        assert(IntegrationVersion.marker(in: "export const ADAPTER_VERSION = \"0.3.0\";") == "0.3.0")
        assert(IntegrationVersion.marker(in: "ADAPTER_VERSION = '0.3.0'") == "0.3.0")
        assert(IntegrationVersion.marker(in: "const name = 'mira';") == nil)
        assert(IntegrationVersion.compare("0.2.1", "0.3.0") < 0)
        assert(IntegrationVersion.compare("0.3", "0.3.0") == 0, "missing components count as zero")
        assert(IntegrationVersion.compare("0.10.0", "0.9.9") > 0, "numeric, not lexical comparison")
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for adapter in ["integrations/emit/emit.js", "integrations/emit/mira_emit.py"] {
            let text = try String(contentsOf: repo.appendingPathComponent(adapter), encoding: .utf8)
            assert(IntegrationVersion.marker(in: text) == IntegrationVersion.current,
                   "\(adapter) must ship the version MIRA expects")
        }
        func health(_ installed: Bool, _ version: String?, _ event: Date?, _ eventVersion: String?) -> AdapterHealth.State {
            AdapterHealth.evaluate(installed: installed, installedVersion: version, expected: IntegrationVersion.current,
                                   lastEvent: event, lastEventVersion: eventVersion).state
        }
        assert(health(false, nil, nil, nil) == .missing)
        assert(health(true, nil, now, nil) == .legacy, "an installed copy without a marker predates version reporting")
        assert(health(true, "0.2.1", now, "0.2.1") == .outdated)
        assert(health(true, "0.5.0", now, "0.5.0") == .ahead)
        assert(health(true, IntegrationVersion.current, nil, nil) == .waiting)
        assert(health(true, IntegrationVersion.current, now, nil) == .restart, "files were updated but the running client still speaks the old protocol")
        assert(health(true, IntegrationVersion.current, now, IntegrationVersion.current) == .ready)
        let legacyStatus = AdapterHealth.evaluate(installed: true, installedVersion: nil, expected: "0.3.0",
                                                 lastEvent: nil, lastEventVersion: nil)
        let legacyText = AdapterStatusText.message(legacyStatus, noun: "插件", update: "点「更新 DSH 连接」", restart: "重启后生效")
        assert(legacyText.contains("旧版") && legacyText.contains("0.3.0"), "a legacy install is told what to do")

        // MARK: Retention keeps pending work and archives settled records
        let retentionNow = now
        let archivedEntry = Entry(id: "archived", title: "旧记录", body: "", source: "Codex · MIRA", status: "本轮结束", link: "codex://threads/x", date: retentionNow.addingTimeInterval(-120 * 86400))
        let pendingEntry = Entry(id: "pending", title: "还没处理", body: "", source: "DSH · MIRA", status: "待确认", link: "dsh://open", date: retentionNow.addingTimeInterval(-200 * 86400))
        let runningEntry = Entry(id: "running", title: "运行", body: "", source: "DSH · MIRA", status: "运行中", link: "dsh://open", date: retentionNow.addingTimeInterval(-3 * 86400))
        let staleRunning = Entry(id: "stale-running", title: "早就该结束", body: "", source: "DSH · MIRA", status: "运行中", link: "dsh://open", date: retentionNow.addingTimeInterval(-100 * 86400))
        let recentEntry = Entry(id: "recent", title: "上周", body: "", source: "Codex", status: "本轮结束", link: "", date: retentionNow.addingTimeInterval(-7 * 86400))
        let retained = Retention.plan(entries: [recentEntry, archivedEntry, pendingEntry, runningEntry, staleRunning],
                                      seen: ["recent", "archived", "pending", "running", "stale-running", "ghost"],
                                      policy: RetentionPolicy(), now: retentionNow)
        assert(retained.archived.map(\.id) == ["archived", "stale-running"], "old settled records are archived; a stuck running entry settles after two days and then ages out")
        assert(retained.kept.map(\.id) == ["recent", "pending", "running"], "pending work, fresh records and a live run stay")
        assert(retained.seen == ["recent", "pending", "running"], "seen follows the records that remain")

        let capped = (0..<5).map { index in
            Entry(id: "cap-\(index)", title: "第\(index)条", body: "", source: "Codex", status: "本轮结束", link: "",
                  date: retentionNow.addingTimeInterval(-Double(index + 1) * 60))
        }
        let cappedPlan = Retention.plan(entries: capped, seen: Set(capped.map(\.id)),
                                        policy: RetentionPolicy(maxAgeDays: 90, maxEntries: 3), now: retentionNow)
        assert(cappedPlan.kept.map(\.id) == ["cap-0", "cap-1", "cap-2"], "the cap keeps the newest settled records")
        assert(cappedPlan.archived.map(\.id) == ["cap-4", "cap-3"], "archived rows are ordered oldest first")

        let delayed = [capped[4], capped[0], pendingEntry, capped[1], capped[3], capped[2]]
        let delayedPlan = Retention.plan(entries: delayed, seen: Set(delayed.map(\.id)),
                                         policy: RetentionPolicy(maxAgeDays: 90, maxEntries: 4), now: retentionNow)
        assert(delayedPlan.archived.map(\.id) == ["cap-4", "cap-3"], "late deliveries are ranked by event date")
        assert(delayedPlan.kept.map(\.id) == ["cap-0", "pending", "cap-1", "cap-2"])

        // MARK: Monthly markdown archive is grouped, escaped and idempotent
        let archiveDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-records-\(UUID().uuidString)")
        let sameMonthA = Entry(id: "same-a", title: "第一条 | 竖线", body: "", source: "Codex · MIRA", status: "本轮结束", link: "", date: retentionNow.addingTimeInterval(-100 * 86400))
        let sameMonthB = Entry(id: "same-b", title: "第二条\n换行", body: "", source: "DSH · MIRA", status: "已拦截", link: "", date: retentionNow.addingTimeInterval(-95 * 86400))
        let files = try RecordArchive.append([sameMonthB, sameMonthA], directory: archiveDir, calendar: calendar)
        assert(files.count == 1 && files[0].lastPathComponent == "records-2026-08.md", "rows are grouped by the month they happened")
        let markdown = try String(contentsOf: files[0], encoding: .utf8)
        assert(markdown.contains("| 2026-08-03 10:30 <!-- mira-id:"), "local date and time are preserved")
        assert(markdown.contains("第一条 \\| 竖线"), "pipes are escaped so the table stays valid")
        assert(markdown.contains("第二条 换行"), "newlines stay on one row")
        assert(markdown.hasPrefix("# MIRA 记录 · 2026-08"), "one monthly header is written")
        assert(RecordArchive.existingRows(in: markdown).count == 2, "only data rows are treated as archived")
        let firstRow = markdown.range(of: "第一条")!.lowerBound
        let secondRow = markdown.range(of: "第二条")!.lowerBound
        assert(firstRow < secondRow, "rows are chronological")
        let repeated = try RecordArchive.append([sameMonthA, sameMonthB], directory: archiveDir, calendar: calendar)
        assert(repeated.isEmpty, "an already archived record is not appended twice")
        let retried = try String(contentsOf: files[0], encoding: .utf8)
        assert(retried.components(separatedBy: "第一条").count == 2, "no duplicate row after a retry")

        var sameMinute = sameMonthA
        sameMinute.id = "different-id | 中文 -->"
        sameMinute.date = sameMonthA.date.addingTimeInterval(20)
        _ = try RecordArchive.append([sameMinute, sameMinute], directory: archiveDir, calendar: calendar)
        let withCollision = try String(contentsOf: files[0], encoding: .utf8)
        assert(RecordArchive.existingRows(in: withCollision).count == 3, "different ids with the same displayed row survive")
        let sameMinuteRetry = try RecordArchive.append([sameMinute], directory: archiveDir, calendar: calendar)
        assert(sameMinuteRetry.isEmpty)

        let legacyDir = archiveDir.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyFile = legacyDir.appendingPathComponent(files[0].lastPathComponent)
        let legacyRow = "| 2026-08-03 10:30 | Codex · MIRA | 本轮结束 | 第一条 \\| 竖线 |"
        let legacyArchiveText = RecordArchive.template(name: legacyFile.lastPathComponent) + "\n" + legacyRow + "\n"
        try legacyArchiveText.write(to: legacyFile, atomically: true, encoding: .utf8)
        _ = try RecordArchive.append([sameMonthA], directory: legacyDir, calendar: calendar)
        let legacyUpdated = try String(contentsOf: legacyFile, encoding: .utf8)
        assert(legacyUpdated.hasPrefix(legacyArchiveText) && RecordArchive.existingRows(in: legacyUpdated).count == 2)

        var nextMonth = sameMonthA
        nextMonth.id = "next-month"
        nextMonth.date = calendar.date(byAdding: .month, value: 1, to: sameMonthA.date)!
        let blockedFile = legacyDir.appendingPathComponent(RecordArchive.fileName(for: nextMonth.date, calendar: calendar))
        try Data([0xff]).write(to: blockedFile)
        do {
            _ = try RecordArchive.append([sameMinute, nextMonth], directory: legacyDir, calendar: calendar)
            assertionFailure("unreadable month must stop retention before state can be trimmed")
        } catch {}
        try FileManager.default.removeItem(at: blockedFile)
        let recovered = try RecordArchive.append([sameMinute, nextMonth], directory: legacyDir, calendar: calendar)
        assert(recovered == [blockedFile], "retry skips the month written before the failure")
        let recoveredText = try String(contentsOf: legacyFile, encoding: .utf8)
        assert(RecordArchive.existingRows(in: recoveredText).count == 3)

        // MARK: Derived caches expire
        let cacheDir = archiveDir.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let oldCache = cacheDir.appendingPathComponent("old.json")
        try Data("{}".utf8).write(to: oldCache)
        try FileManager.default.setAttributes([.modificationDate: retentionNow.addingTimeInterval(-10 * 86400)], ofItemAtPath: oldCache.path)
        try Data("{}".utf8).write(to: cacheDir.appendingPathComponent("fresh.json"))
        assert(CacheCleanup.stale(in: cacheDir, now: retentionNow, ttl: 7 * 86400).map(\.lastPathComponent) == ["old.json"])
        try FileManager.default.removeItem(at: archiveDir)

        // MARK: Titles move into the receiver
        assert(Titles.prompt("# 任务：把今日已完成改成下拉\n\n第二段不进入标题") == "把今日已完成改成下拉")
        assert(Titles.prompt("修复登录按钮的对比度") == "修复登录按钮的对比度")
        let longPrompt = "这是一个非常长的提示词，前半部分描述背景和目标，后半部分给出真正的具体要求：把左下角印章删除，并且默认展开。"
        assert(Titles.prompt(longPrompt) == "这是一个非常长的提示词，前半部分描述背景和目标，后半部分…印章删除，并且默认展开。")
        assert(Titles.prompt("   ") == "")
        assert(Titles.label("会话标题") == "会话标题")
        assert(Titles.label(String(repeating: "长", count: 90)).count == 81, "labels are bounded to 80 characters plus an ellipsis")
        assert(Titles.fallback(project: "MIRA", adapter: "DSH", session: "abcdefgh-uuid", turn: 3) == "MIRA · 第 3 轮")
        assert(Titles.fallback(project: "", adapter: "Codex", session: "abcdefgh-uuid", turn: nil) == "Codex · 任务 abcdefgh")

        // MARK: Adapter contract becomes one reminder here, not in the adapter
        var store = TitleStore()
        func contract(_ json: String) throws -> AdapterEvent {
            try JSONDecoder().decode(AdapterEvent.self, from: Data(json.utf8))
        }
        let startEvent = try contract(##"{"adapter":{"id":"dsh","name":"DSH","version":"0.4.0"},"kind":"turn.start","session":"s1","turn":2,"time":1000000,"cwd":"/Users/x/MIRA","titleHint":"# 任务：整理记录","link":"dsh://open","dedupeKey":"turn:s1:2:start"}"##)
        let startEntry = AdapterContract.entry(startEvent, now: now, titles: &store)!
        assert(startEntry.status == "运行中" && startEntry.thread == "s1")
        assert(startEntry.title == "整理记录", "the prompt is cleaned and clipped by the receiver")
        assert(startEntry.source == "DSH · MIRA")
        assert(startEntry.adapterVersion == "0.4.0")
        assert(startEntry.date == Date(timeIntervalSince1970: 1000))
        assert(startEntry.body.contains("正在处理"))

        let stopEvent = try contract(##"{"adapter":{"id":"dsh","name":"DSH","version":"0.4.0"},"kind":"turn.end","session":"s1","turn":2,"time":1001000,"reason":"error","cwd":"/Users/x/MIRA","link":"dsh://open"}"##)
        let stopEntry = AdapterContract.entry(stopEvent, now: now, titles: &store)!
        assert(stopEntry.title == "整理记录", "the prompt title is reused for later events of the same turn")
        assert(stopEntry.status == "任务失败")

        let nextTurn = try contract(##"{"adapter":{"id":"dsh","name":"DSH","version":"0.4.0"},"kind":"turn.end","session":"s1","turn":3,"time":1002000,"cwd":"/Users/x/MIRA"}"##)
        assert(AdapterContract.entry(nextTurn, now: now, titles: &store)!.title == "MIRA · 第 3 轮",
               "a cached title never leaks into another turn")

        let pointer = try contract(##"{"adapter":{"id":"claude-code","name":"Claude Code","version":"0.4.0"},"kind":"turn.end","session":"s2","reason":"aborted"}"##)
        let pointerEntry = AdapterContract.entry(pointer, now: now, titles: &store)!
        assert(pointerEntry.source == "Claude Code", "an adapter without cwd falls back to its display name")
        assert(pointerEntry.title == "Claude Code · 任务 s2", "no hint, no label, no turn")
        assert(pointerEntry.status == "已中断")

        let unknown = try contract(##"{"adapter":{"id":"x","version":"0.4.0"},"kind":"turn.paused","session":"s"}"##)
        assert(AdapterContract.entry(unknown, now: now, titles: &store) == nil, "a newer kind is ignored, not quarantined")

        let approvalEvent = try contract(##"{"adapter":{"id":"dsh","name":"DSH","version":"0.4.0"},"kind":"approval.asked","session":"s1","turn":2,"time":1003000,"approval":{"token":"abcd-1234","ttlMs":60000,"tool":"shell","reason":"读取文件"},"link":"dsh://open","dedupeKey":"approval:s1:a1"}"##)
        let contractApproval = AdapterContract.entry(approvalEvent, now: now, titles: &store)!
        assert(contractApproval.status == "待确认" && contractApproval.token == "abcd-1234")
        assert(contractApproval.expires == contractApproval.date.addingTimeInterval(60))
        assert(contractApproval.body.contains("shell") && contractApproval.body.contains("读取文件"))
        let closeEvent = try contract(##"{"adapter":{"id":"dsh","name":"DSH","version":"0.4.0"},"kind":"approval.closed","session":"s1","time":1004000,"closes":"approval:s1:a1"}"##)
        assert(AdapterContract.closeTarget(closeEvent) == contractApproval.id, "a close event resolves the same id")
        assert(AdapterContract.closeTarget(startEvent) == nil)

        let invalidToken = try contract(##"{"adapter":{"id":"dsh","version":"0.4.0"},"kind":"approval.asked","session":"s1","time":1005000,"approval":{"token":"not a token!","tool":"shell"},"link":"dsh://open","dedupeKey":"approval:s1:a2"}"##)
        let invalidEntry = AdapterContract.entry(invalidToken, now: now, titles: &store)!
        assert(invalidEntry.token == nil && invalidEntry.expires == nil, "an invalid token never becomes actionable")

        let noKeyA = try contract(##"{"adapter":{"id":"codex","version":"0.4.0"},"kind":"turn.end","session":"s3","turn":1,"time":1006000}"##)
        let noKeyB = try contract(##"{"adapter":{"id":"codex","version":"0.4.0"},"kind":"turn.end","session":"s3","turn":1,"time":1006001}"##)
        let noKeyC = try contract(##"{"adapter":{"id":"codex","version":"0.4.0"},"kind":"turn.end","session":"s3","turn":2,"time":1006002}"##)
        assert(AdapterContract.entry(noKeyA, now: now, titles: &store)!.id == AdapterContract.entry(noKeyB, now: now, titles: &store)!.id,
               "a repeated delivery without a dedupe key collapses")
        assert(AdapterContract.entry(noKeyA, now: now, titles: &store)!.id != AdapterContract.entry(noKeyC, now: now, titles: &store)!.id)

        // MARK: Contract events flow through the same inbox rules
        let contractInbox = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-contract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: contractInbox, withIntermediateDirectories: true)
        var contractData = HubData()
        var contractTitles = TitleStore()
        let contractDecoder = JSONDecoder(); contractDecoder.dateDecodingStrategy = .secondsSince1970
        try Data(startEventJSON(startEvent).utf8).write(to: contractInbox.appendingPathComponent("1.json"))
        let firstDrain = Inbox.drain(inbox: contractInbox, data: &contractData, now: now, decoder: contractDecoder, titles: &contractTitles)
        assert(firstDrain.consumed.count == 1 && contractData.entries.count == 1)
        assert(contractData.entries[0].title == "整理记录")
        assert(contractTitles.title(adapter: "dsh", session: "s1", turn: 2, now: now) == "整理记录")

        try Data(startEventJSON(startEvent).utf8).write(to: contractInbox.appendingPathComponent("2.json"))
        let secondDrain = Inbox.drain(inbox: contractInbox, data: &contractData, now: now, decoder: contractDecoder, titles: &contractTitles)
        assert(contractData.entries.count == 1 && !secondDrain.changed, "a duplicate contract event is consumed silently")

        try Data(approvalEventJSON(approvalEvent).utf8).write(to: contractInbox.appendingPathComponent("3.json"))
        _ = Inbox.drain(inbox: contractInbox, data: &contractData, now: now, decoder: contractDecoder, titles: &contractTitles)
        assert(contractData.entries.first(where: { $0.id == contractApproval.id })?.status == "待确认")
        try Data(closeEventJSON(closeEvent).utf8).write(to: contractInbox.appendingPathComponent("4.json"))
        let closedDrain = Inbox.drain(inbox: contractInbox, data: &contractData, now: now, decoder: contractDecoder, titles: &contractTitles)
        assert(closedDrain.dismissed == [contractApproval.id])
        assert(contractData.entries.first(where: { $0.id == contractApproval.id })?.done == true)
        assert(contractData.entries.count == 2, "the close event never becomes a reminder of its own")
        for url in closedDrain.consumed { try FileManager.default.removeItem(at: url) }

        let codexHookJSON = ##"{"protocol":"mira.adapter/1","adapter":{"id":"codex","name":"Codex","version":"0.4.0"},"kind":"approval.asked","session":"codex-thread","time":1000000,"dedupeKey":"permission-hint","approval":{"tool":"Bash"},"link":"codex://threads/codex-thread"}"##
        let codexHook = try contract(codexHookJSON)
        let legacyHint = AdapterContract.entry(codexHook, now: now, titles: &contractTitles)!
        let codexPlanJSON = codexHookJSON
            .replacingOccurrences(of: "\"Bash\"", with: "\"实施计划\"")
            .replacingOccurrences(of: "permission-hint", with: "plan-fallback")
        let planFallback = AdapterContract.entry(try contract(codexPlanJSON), now: now, titles: &contractTitles)!
        var liveApproval = legacyHint
        liveApproval.id = "codex-live-test"
        liveApproval.codexID = liveApproval.id
        contractData.entries += [legacyHint, liveApproval, planFallback]
        assert(contractData.closeCodexToolApprovalHints() == [legacyHint.id])
        assert(contractData.entries.suffix(3).map(\.done) == [true, false, false])
        assert(contractData.closeCodexToolApprovalHints().isEmpty)

        // A queued PermissionRequest can watch a session that has no other
        // entries. It must never become a popup or supersede an existing entry.
        let hookURL = contractInbox.appendingPathComponent("5.json")
        try Data(codexHookJSON.utf8).write(to: hookURL)
        let hookDrain = Inbox.drain(inbox: contractInbox, data: &contractData,
                                    now: legacyHint.date, decoder: contractDecoder, titles: &contractTitles)
        assert(hookDrain.consumed.map(\.lastPathComponent) == [hookURL.lastPathComponent] && hookDrain.errors.isEmpty)
        assert(hookDrain.codexApprovalSessions == ["codex-thread"])
        assert(!hookDrain.changed && contractData.entries.count == 5)
        assert(contractData.entries.suffix(3).map(\.done) == [true, false, false])

        let stopJSON = ##"{"protocol":"mira.adapter/1","adapter":{"id":"codex","name":"Codex","version":"0.4.0"},"kind":"turn.end","session":"codex-thread","time":1000001,"dedupeKey":"execution-stop","link":"codex://threads/codex-thread"}"##
        let legacyStop = AdapterContract.entry(try contract(stopJSON), now: legacyHint.date, titles: &contractTitles)!
        assert(legacyStop.waitsForCodexPlan, "older receivers cannot identify execution mode")
        let executionStop = try encodeEvent(contract(stopJSON)) { $0["requiresPlanCheck"] = false }
        liveApproval.codexKind = "plan"
        var executionData = HubData()
        executionData.entries = [liveApproval]
        try Data(executionStop.utf8).write(to: contractInbox.appendingPathComponent("6.json"))
        let stopTime = legacyHint.date.addingTimeInterval(1)
        _ = Inbox.drain(inbox: contractInbox, data: &executionData, now: stopTime,
                        decoder: contractDecoder, titles: &contractTitles)
        let executionCompletion = executionData.entries[0]
        assert(executionCompletion.id == legacyStop.id && !executionCompletion.waitsForCodexPlan)
        assert(Notify.due(executionData.entries, now: stopTime).contains(0),
               "execution completion is eligible even with an older plan approval in the same session")

        let cacheURL = contractInbox.appendingPathComponent("title-cache.json")
        let cacheEncoder = JSONEncoder(); cacheEncoder.dateEncodingStrategy = .secondsSince1970
        let cacheDecoder = JSONDecoder(); cacheDecoder.dateDecodingStrategy = .secondsSince1970
        try contractTitles.flush(to: cacheURL, encoder: cacheEncoder, now: now)
        var restoredTitles = TitleStore()
        restoredTitles.load(from: cacheURL, decoder: cacheDecoder)
        assert(restoredTitles.title(adapter: "dsh", session: "s1", turn: 2, now: now) == "整理记录")
        assert(restoredTitles.title(adapter: "dsh", session: "s1", turn: 9, now: now) == nil)
        let expired = now.addingTimeInterval(TitleStore.ttl + 1)
        let unavailableCache = contractInbox.appendingPathComponent("missing/cache.json")
        do {
            try restoredTitles.flush(to: unavailableCache, encoder: cacheEncoder, now: expired)
            assertionFailure("expired titles must be removed from disk even without new events")
        } catch {
            assert(restoredTitles.changed, "a failed write must remain pending")
        }
        try restoredTitles.flush(to: cacheURL, encoder: cacheEncoder, now: expired)
        assert(!restoredTitles.changed)
        let persistedTitles = try cacheDecoder.decode([TitleStore.Record].self, from: Data(contentsOf: cacheURL))
        assert(persistedTitles.isEmpty, "expiration survives restart after a successful retry")
        try FileManager.default.removeItem(at: contractInbox)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        var data = HubData(); data.entries = [done]; data.seen = ["event-1"]
        let restored = try decoder.decode(HubData.self, from: encoder.encode(data))
        assert(restored.entries[0].done && restored.seen.contains("event-1"))
        print("PASS: missed reminder, dedup, weekday, future, expiration, completion, disabled, URL validation, persistence, dismissal, DSH link install, approval decisions, adapter version, retention archive")
    }
}
