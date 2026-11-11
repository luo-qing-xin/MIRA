import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement

let terracotta = Color(red: 0.64, green: 0.30, blue: 0.19)
let teal = terracotta // Shared accent retained for the existing plan editor.
let paper = Color(red: 0.98, green: 0.97, blue: 0.95)
let ink = Color(red: 0.19, green: 0.18, blue: 0.16)
let oatmeal = Color(red: 0.94, green: 0.92, blue: 0.88)
let quiet = Color(red: 0.43, green: 0.40, blue: 0.36)

// Native prominent buttons can lose their fill in non-activating panels.
// Draw both layers explicitly so inactive windows keep the same contrast.
struct MiraPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(configuration.isPressed ? Color(red: 0.48, green: 0.21, blue: 0.13) : teal)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

@MainActor final class Hub: ObservableObject {
    @Published var data = HubData()
    @Published var section = "今日"
    @Published var error = ""
    @Published var notice = ""
    @Published var notificationStatus = "检查中"
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var installed = false
    @Published var dshInstalled = false
    let root: URL
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    var timer: Timer?
    var storageReady = true
    @Published var desktopPlans: [Plan] = []
    @Published var scheduleStatus = "等待同步桌面定时任务"
    var lastScheduleSync = Date.distantPast
    var desktopUnavailable: Set<String> = []
    var desktopRemovalsAllowed = true
    var scheduleLoaded = false

    var allPlans: [Plan] { data.plans + desktopPlans }

    func syncSchedules() {
        let base = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        do {
            let snapshot = try DesktopSchedules.load(directory: base.appendingPathComponent("automations"))
            desktopPlans = snapshot.plans
            desktopUnavailable = snapshot.unavailable
            desktopRemovalsAllowed = snapshot.removalsAllowed
            scheduleLoaded = true
            scheduleStatus = "已同步 \(snapshot.plans.count) 项桌面计划 · " + Date().formatted(date: .omitted, time: .shortened)
            if !snapshot.issues.isEmpty { scheduleStatus += "\n" + snapshot.issues.joined(separator: "\n") }
        } catch {
            desktopPlans = []
            desktopUnavailable = []
            desktopRemovalsAllowed = false
            scheduleLoaded = false
            scheduleStatus = "桌面计划读取失败：\(error.localizedDescription)"
        }
        lastScheduleSync = Date()
    }
    /// Set when a state write failed; retried on the next tick even without new events.
    var savePending = false
    var showPopup: ((Entry) -> Void)?
    var closePopup: ((String) -> Void)?
    var showMain: (() -> Void)?
    var showTray: (() -> Void)?
    var file: URL { root.appendingPathComponent("state.json") }
    init() {
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MIRA")
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("inbox"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: file.path) { data = try decoder.decode(HubData.self, from: Data(contentsOf: file)) }
        } catch { storageReady = false; self.error = "无法读取本地数据，已停止写入以保护原文件：\(error.localizedDescription)" }
        checkHooks()
        checkDSH()
    }

    var dshProfile: URL { DSHLink.profile(ProcessInfo.processInfo.environment, home: FileManager.default.homeDirectoryForCurrentUser) }

    var dshStatus: String {
        if !dshInstalled { return "尚未连接" }
        if let event = data.entries.first(where: { $0.source.hasPrefix("DSH") }) {
            return "已配置 · 最近事件 " + event.date.formatted(date: .abbreviated, time: .shortened)
        }
        return "已配置 · 重启 DSH 后等待第一轮事件"
    }

    func checkDSH() {
        let patch = dshProfile.appendingPathComponent("cordis.patch.yml")
        let text = try? String(contentsOf: patch, encoding: .utf8)
        dshInstalled = text.map(DSHLink.installed(patch:)) ?? false
    }

    func installDSH() {
        notice = ""
        do {
            var files: [String: Data] = [:]
            for name in ["index", "entry"] {
                guard let source = Bundle.main.url(forResource: name, withExtension: "js") else {
                    throw NSError(domain: "发行包缺少 DSH 插件文件，请重新构建。", code: 1)
                }
                files[name + ".js"] = try Data(contentsOf: source)
            }
            try DSHLink.install(profile: dshProfile, files: files)
            checkDSH()
            error = ""
            notice = "已配置 DSH 连接。重启 DeepSeek Harness 后生效。"
        } catch { self.error = "DSH 连接配置失败：\(error.localizedDescription)" }
    }

    func removeDSH() {
        notice = ""
        do {
            try DSHLink.remove(profile: dshProfile)
            checkDSH()
            error = ""
            notice = "已移除 DSH 连接，重启 DeepSeek Harness 后完全生效。"
        } catch { self.error = "移除 DSH 连接失败：\(error.localizedDescription)" }
    }
    func save() -> Bool {
        guard storageReady else { return false }
        do {
            try encoder.encode(data).write(to: file, options: .atomic)
            savePending = false
            return true
        } catch {
            savePending = true
            self.error = "保存失败：\(error.localizedDescription)"
            return false
        }
    }
    func start() {
        refreshPermission()
        tick()
        timer?.invalidate()
        // `.common` keeps the 3-second loop alive while a window is dragged,
        // a menu is tracked, or a modal panel is open. The default mode alone
        // pauses reminders in those states.
        let ticker = Timer(timeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(ticker, forMode: .common)
        timer = ticker
        // Notification permission, hooks.json and the DSH profile can all change
        // while MIRA is in the background (System Settings or install scripts).
        // Re-read them on return instead of keeping a stale "已允许"/未连接 state
        // until the next launch.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermission()
                self?.checkHooks()
                self?.checkDSH()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func refreshPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in self.notificationStatus = settings.authorizationStatus == .authorized ? "已允许" : "未允许 · 使用应用内弹窗" }
        }
    }
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in Task { @MainActor in self.refreshPermission() } }
    }
    /// The DSH bridge only claims approvals while this heartbeat is fresh.
    func writeHeartbeat() {
        let url = root.appendingPathComponent("heartbeat")
        try? Data(String(Int(Date().timeIntervalSince1970 * 1000)).utf8).write(to: url, options: .atomic)
    }

    func tick() {
        writeHeartbeat()
        guard storageReady else { return }
        let now = Date()
        if now.timeIntervalSince(lastScheduleSync) >= 30 { syncSchedules() }
        let inbox = root.appendingPathComponent("inbox")
        let drained = Inbox.drain(inbox: inbox, data: &data, now: now, decoder: decoder)
        if !drained.errors.isEmpty { error = drained.errors[drained.errors.count - 1] }
        var changed = drained.changed
        let revised = scheduleLoaded ? DesktopSchedules.reconcile(&data.entries, plans: desktopPlans, unavailable: desktopUnavailable, allowRemovals: desktopRemovalsAllowed, now: now) : []
        changed = changed || !revised.isEmpty
        for plan in allPlans {
            if let entry = Schedule.due(plan, now: now), !data.entries.contains(where: { $0.id == entry.id }) {
                data.entries.insert(entry, at: 0); changed = true
            }
        }
        var ready: [Entry] = []
        let dueIndices = Notify.due(data.entries, now: now)
        if !dueIndices.isEmpty {
            Notify.mark(&data.entries, at: dueIndices)
            changed = true
            ready = dueIndices.map { data.entries[$0] }
        }
        // One state write per tick, however many inbox files arrived. Files are
        // only deleted after the save succeeded, so a failure retries next tick;
        // savePending also retries writes that failed outside the inbox path.
        if !drained.consumed.isEmpty || changed || savePending, !save() {
            // Without this rollback the in-memory entries would stay `notified`
            // while the notification was never shown, so the reminder would be
            // lost once a later tick manages to save.
            Notify.rollback(&data.entries, at: dueIndices)
            return
        }
        for url in drained.consumed { try? FileManager.default.removeItem(at: url) }
        for target in drained.dismissed + revised {
            closePopup?(target)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [target])
        }
        // Approvals must be actionable: show the card even when system
        // notifications are allowed, and skip the duplicate system banner.
        var showedApproval = false
        for entry in ready {
            if entry.token != nil {
                showPopup?(entry)
                showedApproval = true
            } else {
                notify(entry, popup: false)
            }
        }
        // One popup per batch; all items remain available in the inbox.
        if !showedApproval, notificationStatus != "已允许",
           let entry = ready.sorted(by: { $0.status == "待确认" && $1.status != "待确认" }).first {
            showPopup?(entry)
        }
    }
    var active: [Entry] { data.entries.filter { Schedule.needsAttention($0, now: Date()) }.sorted { a, b in a.status == "待确认" && b.status != "待确认" } }
    func notify(_ e: Entry, popup: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = e.status == "待确认" ? "需要你确认 · \(e.title)" : e.title
        content.body = e.body.isEmpty ? e.status : String(e.body.prefix(160))
        content.sound = .default
        content.userInfo = ["entryId": e.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: e.id, content: content, trigger: nil)) { _ in }
        if popup && notificationStatus != "已允许" { showPopup?(e) }
    }
    func test() {
        let entry = Entry(id: UUID().uuidString, title: "通知通道测试", body: "这是一条测试通知，真实任务连接状态请查看「连接与设置」。", source: "测试", status: "测试", link: "", date: Date(), expires: Date().addingTimeInterval(600))
        notify(entry)
    }
    @discardableResult
    func finish(_ id: String) -> Bool {
        guard let index = data.entries.firstIndex(where: { $0.id == id }) else { return false }
        let original = data.entries[index]
        data.entries[index].done = true
        data.entries[index].snooze = nil
        guard save() else {
            data.entries[index] = original
            return false
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        return true
    }
    @discardableResult
    func decide(_ entry: Entry, _ decision: String) -> Bool {
        guard let token = entry.token else { return false }
        if let expires = entry.expires, expires < Date() {
            closePopup?(entry.id)
            _ = finish(entry.id)
            return false
        }
        do {
            try Decisions.write(root: root, token: token, decision: decision)
            closePopup?(entry.id)
            return finish(entry.id)
        } catch {
            self.error = "确认未发送：\(error.localizedDescription)"
            return false
        }
    }

    func snooze(_ id: String) {
        if let i = data.entries.firstIndex(where: { $0.id == id && $0.canSnooze && !$0.done }) {
            data.entries[i].snooze = Date().addingTimeInterval(600); data.entries[i].notified = false; _ = save()
        }
    }
    func open(_ e: Entry) {
        guard !e.link.isEmpty else { showMain?(); return }
        guard Links.valid(e.link), let url = URL(string: e.link), NSWorkspace.shared.open(url) else {
            error = "无法打开任务。请复制任务标识，在 ChatGPT / Codex / DSH 中查找。"; showMain?(); return
        }
    }
    func toggleLogin(_ value: Bool) {
        do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = SMAppService.mainApp.status == .enabled }
        catch { self.error = "登录启动设置失败：\(error.localizedDescription)" }
    }
    func checkHooks() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
        if let bytes = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], let hooks = object["hooks"] as? [String: Any] {
            installed = hooks.values.contains { value in
                (value as? [[String: Any]] ?? []).contains { group in
                    (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String ?? "").contains("MIRA/receive.py") }
                }
            }
        } else { installed = false }
    }
    func installHooks() {
        notice = ""
        do {
            let script = root.appendingPathComponent("receive.py")
            guard let original = Bundle.main.url(forResource: "receive", withExtension: "py") else {
                throw NSError(domain: "发行包缺少 hook 接收器，请重新构建。", code: 1)
            }
            try Data(contentsOf: original).write(to: script, options: .atomic)
            let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
            var object: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: config.path) {
                let bytes = try Data(contentsOf: config)
                guard let parsed = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw NSError(domain: "hooks.json 不是对象", code: 1) }
                object = parsed
                let stamp = Int(Date().timeIntervalSince1970)
                let backup = Backups.unique(in: config.deletingLastPathComponent(), stem: "hooks.mira-backup-\(stamp)", extension: "json")
                try bytes.write(to: backup, options: .atomic)
            }
            var hooks = object["hooks"] as? [String: Any] ?? [:]
            let command = "/usr/bin/python3 '" + script.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            for event in ["Stop", "PermissionRequest", "UserPromptSubmit", "Interrupt", "PreToolUse"] {
                var list = hooks[event] as? [[String: Any]] ?? []
                list.removeAll { group in (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String ?? "").contains("MIRA/receive.py") } }
                var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 3]]]
                if event == "PreToolUse" { group["matcher"] = ".*request_user_input.*" }
                list.append(group); hooks[event] = list
            }
            object["hooks"] = hooks
            try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: config, options: .atomic)
            checkHooks()
            error = ""
            notice = "已写入本机连接配置。请在 Codex 中信任 MIRA 接收器，再开启新会话。"
        } catch { self.error = "连接配置失败：\(error.localizedDescription)" }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var hub: Hub!
    var window: NSWindow!
    var status: NSStatusItem!
    var popup: NSPanel?
    var popupEntryId: String?
    let popover = NSPopover()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "local.mira.taskhub").count > 1 { NSApp.terminate(nil); return }
        hub = Hub()
        UNUserNotificationCenter.current().delegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MIRA · AI Task Hub"; window.backgroundColor = NSColor(paper); window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false; window.contentView = NSHostingView(rootView: HubView(hub: hub)); window.center()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "MIRA 任务中心")
        status.button?.target = self; status.button?.action = #selector(toggleTray)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: TrayView(hub: hub))
        hub.showTray = { [weak self] in self?.toggleTray() }
        hub.showMain = { [weak self] in self?.showWindow() }
        hub.showPopup = { [weak self] entry in self?.showPopup(entry) }
        hub.closePopup = { [weak self] id in
            guard let self, self.popupEntryId == id else { return }
            self.popup?.close()
            self.popup = nil
            self.popupEntryId = nil
        }
        showWindow(); hub.start()
    }
    @objc func showWindow() { popover.performClose(nil); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggleTray() {
        guard let button = status.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); popover.contentViewController?.view.window?.makeKey() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func showPopup(_ entry: Entry) {
        popup?.close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 230), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.title = "MIRA · \(entry.status)"; panel.level = .floating
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = true
        let content = NSHostingView(rootView: ReminderView(hub: hub, entry: entry, dismiss: { [weak self, weak panel] in
            panel?.close()
            self?.popup = nil
            self?.popupEntryId = nil
        }))
        panel.contentView = content
        let size = content.fittingSize
        panel.setContentSize(NSSize(width: 470, height: max(190, size.height)))
        if let frame = NSScreen.main?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.maxX - 494, y: frame.maxY - panel.frame.height - 20)) }
        popup = panel; popupEntryId = entry.id; panel.orderFrontRegardless()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) { completion([.banner, .sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completion: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["entryId"] as? String
        Task { @MainActor in if let e = self.hub.data.entries.first(where: { $0.id == id }) { self.hub.open(e) } else { self.showWindow() }; completion() }
    }
}
@main struct MiraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
