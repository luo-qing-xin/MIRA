import SwiftUI
import AppKit
import Darwin
import UserNotifications
import ServiceManagement

private let miraSupportDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/MIRA", isDirectory: true)
private let openTasksAtLaunchKey = "openTasksAtLaunch"
private let startupLoginHandledKey = "startupLoginHandledForTasks"
private let autoEnabledLoginKey = "autoLoginEnabledForTasks"

// Warm editorial palette: cream desk, paper cards, terracotta ink.
let terracotta = Color(red: 0.706, green: 0.275, blue: 0.122) // #B4461F · 陶土红
let paper = Color(red: 0.984, green: 0.969, blue: 0.941) // #FBF7F0
let cream = Color(red: 0.945, green: 0.918, blue: 0.875) // #F1EADF
let ink = Color(red: 0.137, green: 0.102, blue: 0.071) // #231A12
let ink2 = Color(red: 0.247, green: 0.196, blue: 0.153) // #3F3227
let oatmeal = Color(red: 0.894, green: 0.847, blue: 0.780) // #E4D8C7 · 分隔线
let quiet = Color(red: 0.549, green: 0.486, blue: 0.420) // #8C7C6B
let faint = Color(red: 0.702, green: 0.643, blue: 0.573) // #B3A492
let sage = Color(red: 0.369, green: 0.478, blue: 0.369) // #5E7A5E
let sageWash = Color(red: 0.894, green: 0.921, blue: 0.867) // #E4EBDD
let butter = Color(red: 0.957, green: 0.890, blue: 0.682) // #F4E3AE
let butterInk = Color(red: 0.420, green: 0.306, blue: 0.000)
let plum = Color(red: 0.431, green: 0.247, blue: 0.333) // #6E3F55

@MainActor final class Hub: ObservableObject {
    @Published var data = HubData()
    @Published var section = "今日"
    @Published var error = ""
    @Published var notice = ""
    @Published var notificationStatus = "检查中"
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    /// Startup page preference. On by default because the task library is meant
    /// to be the morning landing page; it can be turned off in 通知与启动.
    @Published var openTasksAtLaunch = UserDefaults.standard.object(forKey: openTasksAtLaunchKey) as? Bool ?? true
    @Published var installed = false
    @Published var dshInstalled = false
    /// Protocol version declared by the installed adapter file (nil = predates it).
    @Published var codexAdapterVersion: String?
    let codexBridge = CodexBridge()
    @Published var codexConnectionStatus = "正在连接 Codex 后台"
    @Published var codexConnected = false
    @Published var codexPending: [String: CodexPending] = [:]
    @Published var codexAvailable: Set<String> = []
    @Published var codexSubmitting: Set<String> = []
    @Published var codexActionErrors: [String: String] = [:]
    @Published var codexSessionErrors: [String: String] = [:]
    var codexAccepted: Set<String> = []
    var codexSnapshotDates: [String: Date] = [:]
    var codexApprovalChecks: [String: Date] = [:]
    @Published var dshAdapterVersion: String?
    @Published var unicourse = UniCourseSettings()
    @Published var uniStatus = "未登录"
    @Published var uniBusy = false
    @Published var showUniLogin = false
    var lastUniCheck = Date.distantPast
    @Published var chaoxing = ChaoxingSettings()
    @Published var cxStatus = "未登录"
    @Published var cxBusy = false
    @Published var showCXLogin = false
    var lastCXCheck = Date.distantPast
    @Published var teaching = TeachingSettings()
    @Published var teachStatus = "未登录"
    @Published var teachBusy = false
    @Published var showTeachLogin = false
    var lastTeachCheck = Date.distantPast
    @Published var webWatches: [WebWatch] = []
    @Published var webWatchBusyID: String?
    @Published var showWatchEditor = false
    @Published var editingWatchID: String?
    let retentionPolicy = RetentionPolicy.standard
    var lastRetention = Date.distantPast
    /// Prompt titles remembered for follow-up events (Stop, approvals).
    var titles = TitleStore()
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
    var showTaskOverview: (() -> Void)?
    var stateDidChange: (() -> Void)?
    var file: URL { root.appendingPathComponent("state.json") }
    var titlesFile: URL { root.appendingPathComponent("title-cache.json") }
    init() {
        root = miraSupportDirectory
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("inbox"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: file.path) { data = try decoder.decode(HubData.self, from: Data(contentsOf: file)) }
        } catch { storageReady = false; self.error = "无法读取本地数据，已停止写入以保护原文件：\(error.localizedDescription)" }
        // Version 1 state has no task library. Migrate in memory, then write the
        // defaults back once so categories survive even before the first edit.
        if storageReady, TaskSchema.migrate(&data) {
            do {
                try encoder.encode(data).write(to: file, options: .atomic)
            } catch {
                savePending = true
                self.error = "任务库数据迁移未写回：\(error.localizedDescription)"
            }
        }
        if storageReady { titles.load(from: titlesFile, decoder: decoder) }
        unicourse = UniCourseStore.load(root: root, decoder: decoder)
        lastUniCheck = unicourse.lastCheck ?? .distantPast
        refreshUniStatus()
        chaoxing = ChaoxingStore.load(root: root, decoder: decoder)
        lastCXCheck = chaoxing.lastCheck ?? .distantPast
        refreshCXStatus()
        teaching = TeachingStore.load(root: root, decoder: decoder)
        lastTeachCheck = teaching.lastCheck ?? .distantPast
        refreshTeachStatus()
        webWatches = WebWatchStore.load(root: root, decoder: decoder)
        checkHooks()
        checkDSH()
    }

    var dshProfile: URL { DSHLink.profile(ProcessInfo.processInfo.environment, home: FileManager.default.homeDirectoryForCurrentUser) }

    var dshStatus: String {
        AdapterStatusText.message(dshAdapter, noun: "插件",
                                  update: "点「更新 DSH 连接」", restart: "重启 DeepSeek Harness 后生效")
    }
    var codexStatus: String {
        AdapterStatusText.message(codexAdapter, noun: "接收器",
                                  update: "点「更新连接配置」", restart: "完成后再开一个新的 Codex 会话")
    }
    var dshAdapter: AdapterHealth.Status {
        AdapterHealth.evaluate(installed: dshInstalled, installedVersion: dshAdapterVersion,
                               expected: IntegrationVersion.current,
                               lastEvent: lastEvent(from: "DSH")?.date,
                               lastEventVersion: lastEvent(from: "DSH")?.adapterVersion)
    }
    var codexAdapter: AdapterHealth.Status {
        AdapterHealth.evaluate(installed: installed, installedVersion: codexAdapterVersion,
                               expected: IntegrationVersion.current,
                               lastEvent: lastEvent(from: "Codex")?.date,
                               lastEventVersion: lastEvent(from: "Codex")?.adapterVersion)
    }
    /// Newest stored reminder from one adapter; `data.entries` is newest-first,
    /// but retention and manual edits must not make the order assumption load-bearing.
    private func lastEvent(from source: String) -> Entry? {
        data.entries.filter { $0.source.hasPrefix(source) }.max { $0.date < $1.date }
    }

    func checkDSH() {
        let patch = dshProfile.appendingPathComponent("cordis.patch.yml")
        let text = try? String(contentsOf: patch, encoding: .utf8)
        dshInstalled = text.map(DSHLink.installed(patch:)) ?? false
        dshAdapterVersion = installedVersion(of: dshProfile.appendingPathComponent("plugins/mira-bridge/emit.js"))
    }

    /// Read the version marker from an already installed adapter copy. This is a
    /// plain text read: nothing from the profile is executed.
    func installedVersion(of url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return IntegrationVersion.marker(in: text)
    }

    func installDSH() {
        notice = ""
        do {
            var files: [String: Data] = [:]
            for name in ["index", "entry", "emit"] {
                guard let source = Bundle.main.url(forResource: name, withExtension: "js") else {
                    throw NSError(domain: "发行包缺少 DSH 插件或适配器 SDK，请重新构建。", code: 1)
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

    // MARK: - UniCourse

    var unicourseFile: URL { UniCourseStore.url(root: root) }

    func saveUniCourse() {
        do {
            try UniCourseStore.save(unicourse, root: root, encoder: encoder)
        } catch {
            self.error = "UniCourse 配置保存失败：\(error.localizedDescription)"
        }
    }

    func refreshUniStatus() {
        if !unicourse.signedIn { uniStatus = "未登录"; return }
        if let lastError = unicourse.lastError { uniStatus = lastError; return }
        let suffix: String
        if let last = unicourse.lastCheck {
            suffix = "上次 " + last.formatted(date: .omitted, time: .shortened)
        } else {
            suffix = "等待检查"
        }
        uniStatus = (unicourse.enabled ? "已连接 · " : "已暂停自动检查 · ") + suffix
    }

    /// 登录窗口只回传 Cookie 头；这里把它和基线一起落地，然后立刻校验一次。
    func connectUniCourse(cookie: String) {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "没有取得登录凭据，请重新登录。"
            return
        }
        let firstTime = !unicourse.signedIn
        unicourse.cookie = trimmed
        unicourse.enabled = true
        unicourse.lastError = nil
        if firstTime {
            unicourse.baselineAt = nil
            unicourse.lastCheck = nil
            unicourse.seen = []
        }
        lastUniCheck = .distantPast
        uniStatus = firstTime ? "已登录 · 正在同步作业" : "已登录 · 正在同步"
        saveUniCourse()
        checkUniCourse(force: true)
    }

    func disconnectUniCourse() {
        unicourse = UniCourseSettings()
        lastUniCheck = .distantPast
        uniStatus = "未登录"
        try? FileManager.default.removeItem(at: unicourseFile)
    }

    func setUniCourseEnabled(_ value: Bool) {
        unicourse.enabled = value
        saveUniCourse()
        if value { checkUniCourse(force: true) } else { refreshUniStatus() }
    }

    func checkUniCourse(force: Bool = false) {
        guard unicourse.signedIn, !uniBusy else { return }
        // 关掉自动检查后，「立即检查」仍然可以手动触发一次。
        if !force, !unicourse.enabled { return }
        if !force, Date().timeIntervalSince(lastUniCheck) < unicourse.interval { return }
        uniBusy = true
        lastUniCheck = Date()
        uniStatus = "正在同步 UniCourse…"
        let cookie = unicourse.cookie
        // 公告即使关闭提醒也照常取一次，避免打开开关后把旧公告当成新的补发。
        Task { [weak self] in
            let outcome = await UniCourseConnection.sync(cookie: cookie, includeNews: true)
            self?.apply(outcome)
        }
    }

    private func apply(_ outcome: UniCourseConnection.Outcome) {
        uniBusy = false
        unicourse.lastCheck = outcome.checkedAt
        // 页面轮换过会话 Cookie 时先写回，避免下一次带着作废的旧值。
        if let refreshed = outcome.updatedCookie { unicourse.cookie = refreshed }
        if let failure = outcome.error {
            unicourse.lastError = failure
            // 30 分钟 / 1 天 / 7 天的档位都可能碰上临时断网；5 分钟后单独重试一次。
            unicourse.retryAt = outcome.checkedAt.addingTimeInterval(300)
            uniStatus = "检查失败 · " + failure
            // 解析不到内容多半是页面改版；留下页面片段，Cookie 不在里面。
            if let diagnostic = outcome.diagnostic {
                let target = root.appendingPathComponent("unicourse-diagnostic.html")
                try? Data(diagnostic.utf8).write(to: target, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                uniStatus += " · 已写诊断文件"
            }
            saveUniCourse()
            return
        }
        if outcome.signedOut {
            unicourse.lastError = "登录已过期 · 请点「重新登录」"
            uniStatus = unicourse.lastError!
            unicourse.retryAt = nil
            saveUniCourse()
            return
        }
        unicourse.lastError = nil
        unicourse.retryAt = nil

        let firstSync = unicourse.baselineAt == nil
        var added = 0
        var completed = 0

        for item in outcome.assignments {
            let key = "unicourse:" + item.key
            let existing = ExternalTaskSync.existingIndex(in: &data.tasks, key: key,
                                                          title: taskTitle(item), source: "UniCourse", checkedAt: outcome.checkedAt)
            if item.submitted {
                // 网页上提交了，任务库对应任务自动完成；已手动完成的保持原样。
                if let index = existing,
                   ExternalTaskSync.complete(&data.tasks[index], checkedAt: outcome.checkedAt) {
                    completed += 1
                }
                continue
            }
            if let index = existing {
                var task = data.tasks[index]
                guard task.status != .done else { continue }
                var changed = false
                if task.due != item.due { task.due = item.due; changed = true }
                if task.title != taskTitle(item) { task.title = taskTitle(item); changed = true }
                if changed { task.updatedAt = outcome.checkedAt; data.tasks[index] = task }
                continue
            }
            guard unicourse.importHomework else { continue }
            addTask(item, key: key)
            added += 1
            if !firstSync, !data.entries.contains(where: { $0.id == entryID(item) }) {
                data.entries.insert(entry(for: item), at: 0)
            }
        }

        if !outcome.announcements.isEmpty {
            let known = Set(unicourse.seen)
            if unicourse.notifyAnnouncements {
                for item in outcome.announcements where !known.contains(item.id) {
                    guard !firstSync,
                          !data.entries.contains(where: { $0.id == announcementEntryID(item) }) else { continue }
                    data.entries.insert(announcementEntry(item), at: 0)
                }
            }
            var ordered: [String] = []
            var seen = Set<String>()
            for id in outcome.announcements.map(\.id) + unicourse.seen where seen.insert(id).inserted {
                ordered.append(id)
            }
            unicourse.seen = Array(ordered.prefix(UniCourseSettings.seenLimit))
        }
        if unicourse.baselineAt == nil { unicourse.baselineAt = outcome.checkedAt }

        let saved = save()
        saveUniCourse()
        if added > 0 {
            notice = "UniCourse 新增 \(added) 个未提交作业，已加入任务库「课程」。"
        } else if completed > 0 {
            notice = "UniCourse 有 \(completed) 个作业已提交，任务已自动标记完成。"
        }
        if !saved { error = "UniCourse 同步到作业，但任务库保存失败。" }

        let open = outcome.assignments.filter { !$0.submitted }.count
        let stamp = outcome.checkedAt.formatted(date: .omitted, time: .shortened)
        var status = "已连接 · \(outcome.courses.count) 门课 · \(open) 个未提交 · 上次 \(stamp)"
        if added > 0 { status += " · 新增 \(added)" }
        if completed > 0 { status += " · 完成 \(completed)" }
        if let warning = outcome.warning { status += " · \(warning)" }
        if firstSync { status = "已连接 · \(outcome.courses.count) 门课 · 已导入 \(added) 个未提交作业" }
        uniStatus = status
    }

    private func taskTitle(_ item: UniCourseAssignment) -> String {
        // 课程名本身常带书名号，再加一层会变成《新《计算机系统基础I》-2026秋》。
        let base = item.courseName.contains("《")
            ? "\(item.courseName) · \(item.title)"
            : "《\(item.courseName)》\(item.title)"
        return String(base.prefix(120))
    }

    private func entryID(_ item: UniCourseAssignment) -> String { "unicourse-" + item.key }

    private func entry(for item: UniCourseAssignment) -> Entry {
        let due = item.due.map { "截止 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "未设置截止时间"
        return Entry(id: entryID(item), title: String(taskTitle(item).prefix(60)),
                     body: "\(item.type) · \(due)", source: "UniCourse",
                     status: "新作业", link: item.link, date: Date())
    }

    private func announcementEntryID(_ item: UniCourseAnnouncement) -> String {
        "unicourse-" + item.id.replacingOccurrences(of: ":", with: "-")
    }

    private func announcementEntry(_ item: UniCourseAnnouncement) -> Entry {
        Entry(id: announcementEntryID(item), title: String("\(item.courseName) · \(item.title)".prefix(60)),
              body: "\(item.actor) 发布了公告", source: "UniCourse", status: "课程公告",
              link: item.link, date: item.date)
    }

    private func addTask(_ item: UniCourseAssignment, key: String) {
        let link = TaskLink(url: item.link)
        let due = item.due.map { "截止 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "未设置截止时间"
        var task = TaskItem(title: taskTitle(item),
                            notes: "来自 UniCourse · \(item.type) · \(due)",
                            categoryID: TaskCategory.course.id,
                            links: Links.validTaskLink(link) ? [link] : [])
        task.due = item.due
        task.externalKey = key
        data.tasks.insert(task, at: 0)
    }

    // MARK: - 学习通

    var chaoxingFile: URL { ChaoxingStore.url(root: root) }

    func saveChaoxing() {
        do {
            try ChaoxingStore.save(chaoxing, root: root, encoder: encoder)
        } catch {
            self.error = "学习通配置保存失败：\(error.localizedDescription)"
        }
    }

    func refreshCXStatus() {
        if !chaoxing.signedIn { cxStatus = "未登录"; return }
        if let lastError = chaoxing.lastError { cxStatus = lastError; return }
        let suffix: String
        if let last = chaoxing.lastCheck {
            suffix = "上次 " + last.formatted(date: .omitted, time: .shortened)
        } else {
            suffix = "等待同步"
        }
        cxStatus = (chaoxing.enabled ? "已连接 · " : "已暂停自动同步 · ") + suffix
    }

    func connectChaoxing(cookie: String) {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "没有取得学习通登录凭据，请重试。"
            return
        }
        let firstTime = !chaoxing.signedIn
        chaoxing.cookie = trimmed
        chaoxing.enabled = true
        chaoxing.lastError = nil
        if firstTime {
            chaoxing.baselineAt = nil
            chaoxing.lastCheck = nil
        }
        lastCXCheck = .distantPast
        cxStatus = firstTime ? "已登录 · 正在同步作业" : "已登录 · 正在同步"
        saveChaoxing()
        checkChaoxing(force: true)
    }

    func disconnectChaoxing() {
        chaoxing = ChaoxingSettings()
        lastCXCheck = .distantPast
        cxStatus = "未登录"
        try? FileManager.default.removeItem(at: chaoxingFile)
    }

    func setChaoxingEnabled(_ value: Bool) {
        chaoxing.enabled = value
        saveChaoxing()
        if value { checkChaoxing(force: true) } else { refreshCXStatus() }
    }

    func checkChaoxing(force: Bool = false) {
        guard chaoxing.signedIn, !cxBusy else { return }
        if !force, !chaoxing.enabled { return }
        if !force, let retry = chaoxing.retryAt {
            if Date() < retry { return }
        } else if !force, Date().timeIntervalSince(lastCXCheck) < chaoxing.interval {
            return
        }
        cxBusy = true
        lastCXCheck = Date()
        cxStatus = "正在同步 学习通…"
        let cookie = chaoxing.cookie
        let exams = chaoxing.includeExams
        Task { [weak self] in
            let outcome = await ChaoxingConnection.sync(cookie: cookie, includeExams: exams)
            self?.applyChaoxing(outcome)
        }
    }

    private func applyChaoxing(_ outcome: ChaoxingConnection.Outcome) {
        cxBusy = false
        chaoxing.lastCheck = outcome.checkedAt
        if let refreshed = outcome.updatedCookie { chaoxing.cookie = refreshed }
        if let failure = outcome.error {
            chaoxing.lastError = failure
            chaoxing.retryAt = outcome.checkedAt.addingTimeInterval(300)
            cxStatus = "同步失败 · " + failure
            if let sample = outcome.sampleHTML {
                writeDiagnostic(sample, name: "chaoxing-diagnostic.html")
                cxStatus += " · 已写诊断文件"
            }
            saveChaoxing()
            return
        }
        if outcome.signedOut {
            chaoxing.lastError = "登录已过期 · 请点「重新登录」"
            cxStatus = chaoxing.lastError!
            chaoxing.retryAt = nil
            saveChaoxing()
            return
        }
        chaoxing.lastError = nil
        chaoxing.retryAt = nil

        let firstSync = chaoxing.baselineAt == nil
        var added = 0
        var completed = 0
        for item in outcome.tasks {
            let key = "chaoxing:" + item.key
            let existing = ExternalTaskSync.existingIndex(in: &data.tasks, key: key,
                                                        title: cxTitle(item), source: "学习通", checkedAt: outcome.checkedAt)
            switch item.state {
            case .submitted:
                // 已提交任务保留完成记录，归档位置保持不变。
                if let index = existing,
                   ExternalTaskSync.complete(&data.tasks[index], checkedAt: outcome.checkedAt) {
                    completed += 1
                }
                continue
            case .expired:
                // 已过期不能再提交，留在任务库里只会变成噪音。
                continue
            case .pending:
                break
            }
            if let index = existing {
                var task = data.tasks[index]
                guard task.status != .done else { continue }
                var changed = false
                if task.due != item.due { task.due = item.due; changed = true }
                if task.title != cxTitle(item) { task.title = cxTitle(item); changed = true }
                if changed { task.updatedAt = outcome.checkedAt; data.tasks[index] = task }
                continue
            }
            guard chaoxing.importHomework else { continue }
            cxAddTask(item, key: key)
            added += 1
            if !firstSync, !data.entries.contains(where: { $0.id == cxEntryID(item) }) {
                data.entries.insert(cxEntry(item), at: 0)
            }
        }

        if firstSync, let sample = outcome.sampleHTML {
            writeDiagnostic(sample, name: "chaoxing-worklist-sample.html")
        }
        if chaoxing.baselineAt == nil { chaoxing.baselineAt = outcome.checkedAt }

        let saved = save()
        saveChaoxing()
        if added > 0 {
            notice = "学习通新增 \(added) 个待做作业，已加入任务库「课程」。"
        } else if completed > 0 {
            notice = "学习通有 \(completed) 个作业已提交，任务已自动标记完成并保留记录。"
        }
        if !saved { error = "学习通同步到作业，但任务库保存失败。" }

        let pending = outcome.tasks.filter { $0.state == .pending }.count
        let stamp = outcome.checkedAt.formatted(date: .omitted, time: .shortened)
        var status = "已连接 · \(outcome.courses.count) 门课 · \(pending) 个待做 · 上次 \(stamp)"
        if added > 0 { status += " · 新增 \(added)" }
        if completed > 0 { status += " · 完成 \(completed)" }
        if let warning = outcome.warning { status += " · \(warning)" }
        if firstSync { status = "已连接 · \(outcome.courses.count) 门课 · 已导入 \(added) 个待做作业" }
        cxStatus = status
    }

    private func writeDiagnostic(_ text: String, name: String) {
        guard !text.isEmpty else { return }
        let target = root.appendingPathComponent(name)
        try? Data(text.utf8).write(to: target, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }

    private func cxTitle(_ item: ChaoxingTask) -> String {
        let base = item.courseName.contains("《")
            ? "\(item.courseName) · \(item.title)"
            : "《\(item.courseName)》\(item.title)"
        return String(base.prefix(120))
    }

    private func cxEntryID(_ item: ChaoxingTask) -> String {
        "chaoxing-" + item.key.replacingOccurrences(of: ":", with: "-")
    }

    private func cxEntry(_ item: ChaoxingTask) -> Entry {
        let kind = item.kind == .exam ? "考试" : "作业"
        let due = item.due.map { "截止 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "截止时间未在列表里"
        let overdue = item.overdue ? " · 已过期未交" : ""
        return Entry(id: cxEntryID(item), title: String(cxTitle(item).prefix(60)),
                     body: "学习通 · \(kind)\(overdue) · \(due)", source: "学习通",
                     status: "新作业", link: item.link, date: Date())
    }

    private func cxAddTask(_ item: ChaoxingTask, key: String) {
        let link = TaskLink(url: item.link)
        let kind = item.kind == .exam ? "考试" : "作业"
        let due = item.due.map { "截止 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "截止时间未在列表里"
        let overdue = item.overdue ? " · 已过期未交" : ""
        var task = TaskItem(title: cxTitle(item),
                            notes: "来自 学习通 · \(kind)\(overdue) · \(due)",
                            categoryID: TaskCategory.course.id,
                            links: Links.validTaskLink(link) ? [link] : [])
        task.due = item.due
        task.externalKey = key
        data.tasks.insert(task, at: 0)
    }

    // MARK: - 666 教学系统

    var teachingFile: URL { TeachingStore.url(root: root) }

    func saveTeaching() {
        do {
            try TeachingStore.save(teaching, root: root, encoder: encoder)
        } catch {
            self.error = "教学系统配置保存失败：\(error.localizedDescription)"
        }
    }

    func refreshTeachStatus() {
        if !teaching.signedIn { teachStatus = "未登录"; return }
        if let lastError = teaching.lastError { teachStatus = lastError; return }
        if let last = teaching.lastCheck {
            teachStatus = "已连接 · 上次 " + last.formatted(date: .omitted, time: .shortened)
        } else {
            teachStatus = "等待同步"
        }
    }

    func connectTeaching(cookie: String) {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "没有取得教学系统登录凭据，请重试。"
            return
        }
        let firstTime = !teaching.signedIn
        teaching.cookie = trimmed
        teaching.enabled = true
        teaching.lastError = nil
        if firstTime {
            teaching.baselineAt = nil
            teaching.lastCheck = nil
        }
        lastTeachCheck = .distantPast
        teachStatus = firstTime ? "已登录 · 正在同步考试" : "已登录 · 正在同步"
        saveTeaching()
        checkTeaching(force: true)
    }

    func disconnectTeaching() {
        teaching = TeachingSettings()
        lastTeachCheck = .distantPast
        teachStatus = "未登录"
        try? FileManager.default.removeItem(at: teachingFile)
    }

    func setTeachingEnabled(_ value: Bool) {
        teaching.enabled = value
        saveTeaching()
        if value { checkTeaching(force: true) } else { refreshTeachStatus() }
    }

    func checkTeaching(force: Bool = false) {
        guard teaching.signedIn, !teachBusy else { return }
        if !force, !teaching.enabled { return }
        if !force, let retry = teaching.retryAt {
            if Date() < retry { return }
        } else if !force, Date().timeIntervalSince(lastTeachCheck) < teaching.interval {
            return
        }
        teachBusy = true
        lastTeachCheck = Date()
        teachStatus = "正在同步 教学系统…"
        let cookie = teaching.cookie
        Task { [weak self] in
            let outcome = await TeachingConnection.sync(cookie: cookie)
            self?.applyTeaching(outcome)
        }
    }

    private func applyTeaching(_ outcome: TeachingConnection.Outcome) {
        teachBusy = false
        teaching.lastCheck = outcome.checkedAt
        if let refreshed = outcome.updatedCookie { teaching.cookie = refreshed }
        if let failure = outcome.error {
            teaching.lastError = failure
            teachStatus = "同步失败 · " + failure
            teaching.retryAt = outcome.checkedAt.addingTimeInterval(300)
            saveTeaching()
            return
        }
        if outcome.signedOut {
            teaching.lastError = "登录已过期 · 请点「重新登录」"
            teachStatus = teaching.lastError!
            teaching.retryAt = nil
            saveTeaching()
            return
        }
        teaching.lastError = nil
        teaching.retryAt = nil

        let firstSync = teaching.baselineAt == nil
        var added = 0
        var removed = 0
        for exam in outcome.exams {
            let key = "teaching:" + exam.id
            let existing = ExternalTaskSync.existingIndex(in: &data.tasks, key: key,
                                                        title: teachTitle(exam), source: "教学系统", checkedAt: outcome.checkedAt)
            if exam.ended {
                // 结束不等于已交卷：只归档，保留原状态和记录。
                if let index = existing, data.tasks[index].status != .done,
                   data.tasks[index].archivedAt == nil {
                    data.tasks[index].archivedAt = outcome.checkedAt
                    data.tasks[index].updatedAt = outcome.checkedAt
                    removed += 1
                }
                continue
            }
            if let index = existing {
                var task = data.tasks[index]
                guard task.status != .done else { continue }
                var changed = false
                if task.due != exam.end { task.due = exam.end; changed = true }
                if task.title != teachTitle(exam) { task.title = teachTitle(exam); changed = true }
                if changed { task.updatedAt = outcome.checkedAt; data.tasks[index] = task }
                continue
            }
            teachAddTask(exam, key: key)
            added += 1
            if !firstSync, !data.entries.contains(where: { $0.id == teachEntryID(exam) }) {
                data.entries.insert(teachEntry(exam), at: 0)
            }
        }

        if firstSync, let sample = outcome.sample {
            writeDiagnostic(sample, name: "teaching-sample.txt")
        }
        if teaching.baselineAt == nil { teaching.baselineAt = outcome.checkedAt }

        let saved = save()
        saveTeaching()
        if added > 0 {
            notice = "教学系统新增 \(added) 场未结束考试，已加入任务库「课程」。"
        } else if removed > 0 {
            notice = "教学系统有 \(removed) 场考试已结束，已归档并保留记录。"
        }
        if !saved { error = "教学系统同步到考试，但任务库保存失败。" }

        let open = outcome.exams.filter { !$0.ended }.count
        let stamp = outcome.checkedAt.formatted(date: .omitted, time: .shortened)
        var status = "已连接 · \(outcome.classes.count) 门课 · \(open) 场待考 · 上次 \(stamp)"
        if added > 0 { status += " · 新增 \(added)" }
        if removed > 0 { status += " · 归档 \(removed)" }
        if let warning = outcome.warning { status += " · \(warning)" }
        if firstSync { status = "已连接 · \(outcome.classes.count) 门课 · 已导入 \(added) 场待考" }
        teachStatus = status
    }

    private func teachTitle(_ exam: TeachingExam) -> String {
        let base = exam.courseName.contains("《")
            ? "\(exam.courseName) · \(exam.title)"
            : "《\(exam.courseName)》\(exam.title)"
        return String(base.prefix(120))
    }

    private func teachEntryID(_ exam: TeachingExam) -> String {
        "teaching-" + exam.id
    }

    private func teachEntry(_ exam: TeachingExam) -> Entry {
        let end = exam.end.map { "结束 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "结束时间未公布"
        return Entry(id: teachEntryID(exam), title: String(teachTitle(exam).prefix(60)),
                     body: "教学系统 · 考试 · \(end)", source: "教学系统",
                     status: "新作业", link: exam.link, date: Date())
    }

    private func teachAddTask(_ exam: TeachingExam, key: String) {
        let link = TaskLink(url: exam.link)
        let end = exam.end.map { "结束 " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "结束时间未公布"
        var task = TaskItem(title: teachTitle(exam),
                            notes: "来自 教学系统 · 考试 · \(end)",
                            categoryID: TaskCategory.course.id,
                            links: Links.validTaskLink(link) ? [link] : [])
        task.due = exam.end
        task.externalKey = key
        data.tasks.insert(task, at: 0)
    }

    func save() -> Bool {
        guard storageReady else { return false }
        do {
            try encoder.encode(data).write(to: file, options: .atomic)
            savePending = false
            stateDidChange?()
            return true
        } catch {
            savePending = true
            self.error = "保存失败：\(error.localizedDescription)"
            return false
        }
    }
    func start() {
        startCodexBridge()
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
        defer { stateDidChange?() }
        writeHeartbeat()
        guard storageReady else { return }
        let now = Date()
        if now.timeIntervalSince(lastScheduleSync) >= 30 { syncSchedules() }
        // 本轮抓取按自身间隔计时：tick 每 3 秒一次，但不会每 3 秒请求一次课程页。
        if unicourse.enabled, unicourse.signedIn, now.timeIntervalSince(lastUniCheck) >= unicourse.interval {
            checkUniCourse()
        }
        if chaoxing.enabled, chaoxing.signedIn, now.timeIntervalSince(lastCXCheck) >= chaoxing.interval {
            checkChaoxing()
        }
        if teaching.enabled, teaching.signedIn, now.timeIntervalSince(lastTeachCheck) >= teaching.interval {
            checkTeaching()
        }
        checkDueWebWatches(now: now)
        let inbox = root.appendingPathComponent("inbox")
        let drained = Inbox.drain(inbox: inbox, data: &data, now: now, decoder: decoder, titles: &titles)
        let closedCodexHints = data.closeCodexToolApprovalHints()
        watchCodex(checking: drained.codexApprovalSessions, now: now)
        if !drained.errors.isEmpty { error = drained.errors[drained.errors.count - 1] }
        do {
            try titles.flush(to: titlesFile, encoder: encoder, now: now)
        } catch {
            self.error = "标题缓存保存失败：\(error.localizedDescription)"
        }
        var changed = drained.changed || !closedCodexHints.isEmpty
        let revised = scheduleLoaded ? DesktopSchedules.reconcile(&data.entries, plans: desktopPlans, unavailable: desktopUnavailable, allowRemovals: desktopRemovalsAllowed, now: now) : []
        changed = changed || !revised.isEmpty
        for plan in allPlans {
            if let entry = Schedule.due(plan, now: now), !data.entries.contains(where: { $0.id == entry.id }) {
                data.entries.insert(entry, at: 0); changed = true
            }
        }
        // Archiving runs at most once a day and before reminders are selected,
        // so the indices handed to `Notify` always refer to the trimmed array.
        if now.timeIntervalSince(lastRetention) >= 86400 {
            lastRetention = now
            let run = runRetention(now: now)
            if let message = run.error { error = message }
            changed = changed || run.archived > 0
        }
        var ready: [Entry] = []
        let dueIndices = Notify.due(data.entries, now: now).filter { index in
            let entry = data.entries[index]
            if entry.codexID != nil {
                guard let request = codexPending[entry.id] else { return false }
                return codexConnected && codexAvailable.contains(request.session)
            }
            guard entry.waitsForCodexPlan else { return true }
            // Give the desktop snapshot time to identify a just-produced plan.
            let checked = entry.thread.flatMap { codexSnapshotDates[$0] } ?? .distantPast
            return checked > entry.date || now.timeIntervalSince(entry.date) > 30
        }
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
        for target in drained.dismissed + revised + closedCodexHints {
            closePopup?(target)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [target])
        }
        for entry in ready {
            // Keep approvals actionable and completion cards visible together.
            // macOS banners can group completions and cover the app's cards.
            if entry.token != nil || entry.codexID != nil || entry.automaticallyArchived {
                showPopup?(entry)
            } else {
                notify(entry)
            }
        }
    }
    var active: [Entry] { data.entries.filter { Schedule.needsAttention($0, now: Date()) }.sorted { a, b in a.status == "待确认" && b.status != "待确认" } }
    func notify(_ e: Entry) {
        guard notificationStatus == "已允许" else {
            showPopup?(e)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = e.status == "待确认" ? "需要你确认 · \(e.displayTitle)" : e.displayTitle
        content.body = e.body.isEmpty ? e.status : String(e.body.prefix(160))
        content.sound = .default
        content.userInfo = ["entryId": e.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: e.id, content: content, trigger: nil)) { _ in }
    }
    func test() {
        let entry = Entry(id: UUID().uuidString, title: "通知通道测试", body: "这是一条测试通知，真实任务连接状态请查看「连接与设置」。", source: "测试", status: "测试", link: "", date: Date(), expires: Date().addingTimeInterval(600))
        notify(entry)
    }

    struct RetentionRun { var archived = 0; var files = 0; var error: String? }

    /// Archive settled records first, then drop them from state. Nothing is
    /// removed unless its markdown copy was written; `tick` persists the trimmed
    /// state through the same single save as every other change.
    @discardableResult
    func runRetention(now: Date) -> RetentionRun {
        var run = RetentionRun()
        let plan = Retention.plan(entries: data.entries, seen: data.seen, policy: retentionPolicy, now: now)
        if !plan.archived.isEmpty {
            do {
                run.files = try RecordArchive.append(plan.archived, directory: root).count
                run.archived = plan.archived.count
                data.entries = plan.kept
                data.seen = plan.seen
            } catch {
                run.error = "旧记录导出失败，本次未清理：\(error.localizedDescription)"
            }
        }
        clearStaleCaches(now: now)
        return run
    }

    func archiveNow() {
        lastRetention = Date()
        let run = runRetention(now: Date())
        if let message = run.error { error = message; return }
        guard run.archived > 0 else {
            notice = "没有需要整理的记录：待处理事项和最近 \(retentionPolicy.maxAgeDays) 天的记录都保留。"
            return
        }
        guard save() else { return }
        notice = "已把 \(run.archived) 条旧记录导出到 \(run.files) 个 records-*.md 文件。"
    }

    /// Title cache and quarantined events are derived data; they must not grow
    /// without bound even though they never enter state.json.
    private func clearStaleCaches(now: Date) {
        let fm = FileManager.default
        let caches: [(String, TimeInterval)] = [("titles", 7 * 86400), ("inbox/rejected", 30 * 86400)]
        for (name, ttl) in caches {
            for url in CacheCleanup.stale(in: root.appendingPathComponent(name), now: now, ttl: ttl) {
                try? fm.removeItem(at: url)
            }
        }
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
        closePopup?(id)
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
        let allowed = Links.valid(e.link)
            || (e.allowWebLink == true && Links.validTaskLink(e.link))
        guard allowed, let url = URL(string: e.link), NSWorkspace.shared.open(url) else {
            error = e.allowWebLink == true
                ? "无法打开这个网页链接。请到「监控」页检查地址，或重新扫描。"
                : "无法打开任务。请复制任务标识，在 ChatGPT / Codex / DSH 中查找。"
            showMain?(); return
        }
    }
    func toggleLogin(_ value: Bool) {
        do {
            if value {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
                // An explicit opt-out must not be undone by the one-time
                // automatic registration on the next launch.
                UserDefaults.standard.set(true, forKey: startupLoginHandledKey)
            }
            loginEnabled = SMAppService.mainApp.status == .enabled
            UserDefaults.standard.set(true, forKey: startupLoginHandledKey)
            UserDefaults.standard.set(false, forKey: autoEnabledLoginKey)
            if value && !loginEnabled {
                notice = "已请求登录启动。若下次登录没有自动出现，请在系统设置的「登录项」中允许 MIRA。"
            }
        } catch { self.error = "登录启动设置失败：\(error.localizedDescription)" }
    }

    /// Enable login startup on behalf of the startup-task feature. Returns true
    /// only when macOS reports the login item as enabled, not merely requested.
    @discardableResult
    private func enableLoginForTasks(automatic: Bool) -> Bool {
        do {
            try SMAppService.mainApp.register()
            loginEnabled = SMAppService.mainApp.status == .enabled
            if loginEnabled {
                if automatic {
                    notice = "已开启登录启动：下次登录电脑会自动弹出待办浮窗。"
                }
                return true
            }
            notice = "已请求登录启动。若下次登录没有自动出现，请在系统设置的「登录项」中允许 MIRA。"
            return false
        } catch {
            self.error = "登录启动设置失败：\(error.localizedDescription)"
            return false
        }
    }

    /// Called once during app launch. It selects the landing page and, on the
    /// first launch after this feature arrives, asks macOS to register MIRA as a
    /// login item so the task list really appears after restarting the computer.
    func prepareStartup() {
        if UserDefaults.standard.object(forKey: openTasksAtLaunchKey) == nil {
            UserDefaults.standard.set(openTasksAtLaunch, forKey: openTasksAtLaunchKey)
        }
        // The main window is not opened at startup when the overview is shown;
        // if it is opened later, it should keep the previous 今日 default.
        section = "今日"
        // Once login is already enabled, or the user has made a choice, do not
        // silently re-register it after a later system-level opt-out.
        if loginEnabled {
            UserDefaults.standard.set(true, forKey: startupLoginHandledKey)
        }
        guard openTasksAtLaunch, !loginEnabled,
              !UserDefaults.standard.bool(forKey: startupLoginHandledKey) else { return }
        UserDefaults.standard.set(true, forKey: startupLoginHandledKey)
        if enableLoginForTasks(automatic: true) {
            UserDefaults.standard.set(true, forKey: autoEnabledLoginKey)
        }
    }

    func setOpenTasksAtLaunch(_ value: Bool) {
        openTasksAtLaunch = value
        UserDefaults.standard.set(value, forKey: openTasksAtLaunchKey)
        if value {
            if !loginEnabled {
                UserDefaults.standard.set(true, forKey: startupLoginHandledKey)
                if enableLoginForTasks(automatic: false) {
                    UserDefaults.standard.set(true, forKey: autoEnabledLoginKey)
                }
            }
        } else if UserDefaults.standard.bool(forKey: autoEnabledLoginKey) {
            // Only undo a login item that this feature enabled; a login item the
            // user enabled separately is left alone.
            UserDefaults.standard.set(false, forKey: autoEnabledLoginKey)
            toggleLogin(false)
        }
    }
    func checkHooks() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
        installed = CodexHooks.installed(config: url, script: root.appendingPathComponent("receive.py"))
        codexAdapterVersion = installedVersion(of: root.appendingPathComponent("mira_emit.py"))
    }
    func installHooks() {
        notice = ""
        do {
            let script = root.appendingPathComponent("receive.py")
            // Resolve both resources before writing either one: a bundle missing
            // the SDK must not leave a receiver behind that cannot import it.
            guard let original = Bundle.main.url(forResource: "receive", withExtension: "py") else {
                throw NSError(domain: "发行包缺少 hook 接收器，请重新构建。", code: 1)
            }
            guard let emitter = Bundle.main.url(forResource: "mira_emit", withExtension: "py") else {
                throw NSError(domain: "发行包缺少适配器 SDK，请重新构建。", code: 1)
            }
            let config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
            try CodexHooks.install(config: config, script: script, receiver: Data(contentsOf: original),
                                   emitter: Data(contentsOf: emitter))
            checkHooks()
            error = ""
            notice = "已写入本机连接配置。请在 Codex 中信任 MIRA 接收器，再开启新会话。"
        } catch { self.error = "连接配置失败：\(error.localizedDescription)" }
    }
}

// A task center can accompany a full-screen app and still support editing.
@MainActor final class TaskCenterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class InstanceLock {
    private let descriptor: Int32

    init?() throws {
        try FileManager.default.createDirectory(at: miraSupportDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let path = miraSupportDirectory.appendingPathComponent("instance.lock").path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            Darwin.close(descriptor)
            if failure == EWOULDBLOCK { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        self.descriptor = descriptor
    }

    deinit {
        // Keeping the file in place lets every launch lock the same inode.
        Darwin.close(descriptor)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var instanceLock: InstanceLock?
    var hub: Hub!
    var window: NSWindow!
    var status: NSStatusItem!
    let reminders = ReminderPopups()
    var taskOverview: TaskOverviewController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Claim the shared data directory before creating the hub or a status item,
        // even when another copy has a different bundle identifier.
        do {
            guard let lock = try InstanceLock() else { NSApp.terminate(nil); return }
            instanceLock = lock
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "MIRA 无法锁定本地数据目录"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        hub = Hub()
        hub.prepareStartup()
        UNUserNotificationCenter.current().delegate = self
        let taskCenter = TaskCenterPanel(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        taskCenter.hidesOnDeactivate = false
        taskCenter.becomesKeyOnlyIfNeeded = false
        taskCenter.isFloatingPanel = false
        taskCenter.level = .normal
        taskCenter.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window = taskCenter
        window.title = "MIRA · AI Task Hub"; window.backgroundColor = NSColor(cream); window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden; window.titlebarSeparatorStyle = .none; window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 1120, height: 740); window.contentView = NSHostingView(rootView: HubView(hub: hub)); window.center()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "MIRA 任务中心")
        status.button?.target = self; status.button?.action = #selector(openTaskCenter)
        hub.stateDidChange = { [weak self] in
            self?.reminders.removeExpired(now: Date())
            self?.updateStatusItem()
        }
        hub.showMain = { [weak self] in self?.showWindow() }
        hub.showPopup = { [weak self] entry in
            guard let self else { return }
            self.reminders.show(entry, hub: self.hub)
        }
        hub.closePopup = { [weak self] id in self?.reminders.close(id) }
        taskOverview = TaskOverviewController(hub: hub)
        reminders.insetChanged = { [weak self] inset in self?.taskOverview?.setTopInset(inset) }
        hub.showTaskOverview = { [weak self] in
            guard let self else { return }
            self.taskOverview?.show(topInset: self.reminders.topInset)
        }
        hub.start()
        if hub.openTasksAtLaunch {
            taskOverview?.show(topInset: reminders.topInset)
        } else {
            showWindow()
        }
    }
    @objc func showWindow() {
        taskOverview?.close()
        // The pointer identifies the display whose menu bar was clicked, even
        // when the existing window belongs to another display or desktop.
        let target = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let changingSpace = !window.isOnActiveSpace
        if changingSpace { window.orderOut(nil) }
        if let target, changingSpace || !window.isVisible || window.screen != target {
            let visible = target.visibleFrame
            var frame = window.frame
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
            window.setFrame(frame, display: false)
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.orderFrontRegardless()
        // Move/order the panel on this Space before activating for text input.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    @objc func openTaskCenter() {
        hub.section = "今日"
        showWindow()
    }
    func updateStatusItem() {
        let count = hub.active.filter { $0.status == "待确认" || $0.status == "待补充信息" }.count
        status.button?.title = count > 0 ? " \(count)" : ""
        status.button?.imagePosition = .imageLeading
        let description = count > 0 ? "MIRA · \(count) 项需要你处理，点击打开任务中心" : "MIRA · 点击打开任务中心"
        status.button?.toolTip = description
        status.button?.setAccessibilityLabel(description)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard window != nil else { return false }
        showWindow()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { hub?.codexBridge.stop() }
    func applicationDidChangeScreenParameters(_ notification: Notification) {
        reminders.layout()
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
