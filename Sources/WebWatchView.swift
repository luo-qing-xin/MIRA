import SwiftUI
import AppKit

// MARK: - 监控页

struct WebWatchPage: View {
    @ObservedObject var hub: Hub

    private var busy: Bool { hub.webWatchBusyID != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if hub.webWatches.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(hub.webWatches) { watch in
                                watchCard(watch)
                                Rectangle().fill(oatmeal.opacity(0.55)).frame(height: 1)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Rectangle().fill(oatmeal.opacity(0.7)).frame(width: 1)
                .frame(maxHeight: .infinity)

            guide.frame(width: 284).padding(.leading, 26)
        }
        .padding(.horizontal, 44)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("网页监控").font(editorial(24))
                Text("接入教学系统，选择课程入口，持续同步作业和截止变化。")
                    .font(ui(10.5)).foregroundStyle(quiet)
            }
            Spacer()
            if !hub.webWatches.isEmpty {
                Button("全部检查") { hub.checkAllWebWatches() }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                    .disabled(busy)
            }
            Button("添加教学系统 / 网页") {
                hub.editingWatchID = nil
                hub.showWatchEditor = true
            }
            .buttonStyle(EditorialButtonStyle(kind: .rust))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("还没有网页监控。").font(editorial(22))
            Text("添加课程作业或公告页面，在内置浏览器完成登录并验证读取规则。不同平台的支持范围以实际验证结果为准。")
                .font(ui(11)).foregroundStyle(quiet).lineSpacing(5)
                .frame(maxWidth: 520, alignment: .leading)
            Button("添加第一个网址") {
                hub.editingWatchID = nil
                hub.showWatchEditor = true
            }
            .buttonStyle(EditorialButtonStyle(kind: .ink))
            .padding(.top, 4)
        }
        .padding(.vertical, 46)
    }

    private func watchCard(_ watch: WebWatch) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(watch.name).font(editorial(18))
                    Text(watch.url).font(ui(8.8)).foregroundStyle(faint)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 12)
                Text(statusText(watch))
                    .font(ui(9.5))
                    .foregroundStyle(statusColor(watch))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                Toggle("", isOn: Binding(
                    get: { watch.enabled },
                    set: { hub.setWebWatchEnabled(watch.id, enabled: $0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(terracotta)
            }
            HStack(spacing: 12) {
                Text(watch.coverage ?? watch.mode.label).font(ui(8.5, .semibold)).tracking(1)
                    .foregroundStyle(watch.mode == .list ? sage : plum)
                Text("每 \(SyncInterval.label(watch.intervalMinutes))").font(ui(9)).foregroundStyle(faint)
                if watch.mode == .list, watch.importTasks {
                    Text("写入任务库").font(ui(8.5)).foregroundStyle(faint)
                }
                Spacer()
                Button("立即检查") { hub.checkWebWatch(watch.id, force: true) }
                    .buttonStyle(EditorialButtonStyle(kind: .text))
                    .disabled(busy)
                Button("编辑") {
                    hub.editingWatchID = watch.id
                    hub.showWatchEditor = true
                }
                .buttonStyle(EditorialButtonStyle(kind: .text))
                Button("移除") { hub.removeWebWatch(watch.id) }
                    .buttonStyle(EditorialButtonStyle(kind: .text))
            }
            if watch.enabled, let error = watch.lastError {
                Text(error).font(ui(9)).foregroundStyle(terracotta).lineSpacing(3)
            }
        }
        .padding(.vertical, 14)
    }

    private func statusText(_ watch: WebWatch) -> String {
        if hub.webWatchBusyID == watch.id { return "正在检查…" }
        if !watch.enabled { return "已暂停" }
        if let error = watch.lastError { return error }
        let stamp = watch.lastCheck?.formatted(date: .omitted, time: .shortened) ?? "等待首次检查"
        if watch.mode == .page {
            return "整页监控 · \(watch.textLength) 字 · \(stamp)"
        }
        return "\(watch.itemCount) 个条目 · \(stamp)"
    }

    private func statusColor(_ watch: WebWatch) -> Color {
        if hub.webWatchBusyID == watch.id { return terracotta }
        if !watch.enabled { return faint }
        if watch.lastError != nil { return terracotta }
        return sage
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HOW IT WORKS").font(ui(8.5, .semibold)).tracking(2.2).foregroundStyle(faint)
            Text("不绑定学校").font(editorial(20)).padding(.top, 5)
            Text("已支持的平台可以直接使用专用连接；其他平台可选择多个课程网址，配置作业入口、列表字段和翻页按钮。所有入口成功读取后才更新任务。")
                .font(ui(10)).foregroundStyle(quiet).lineSpacing(5).padding(.top, 8)

            guideStep("01", "给网址", "公开页面直接填；需要登录的页面在左侧完成一次登录。")
            guideStep("02", "点扫描", "从课程总览勾选需要检查的入口，在一门课程上配置共用规则。")
            guideStep("03", "选规则", "可直接点选标题、截止日期和下一页按钮，再验证读取结果。")
            guideStep("04", "放着不管", "MIRA 运行时自动检查；登录过期会提示你重新登录。")

            Rectangle().fill(oatmeal.opacity(0.7)).frame(height: 1).padding(.vertical, 16)

            Text("隐私边界").font(ui(9, .semibold)).tracking(1).foregroundStyle(ink2)
            Text("登录态由 MIRA 的 WebKit 数据仓库保管，不写进 web-watches.json；配置文件只保存网址、列表选择器和已见条目的哈希。")
                .font(ui(9)).foregroundStyle(faint).lineSpacing(4).padding(.top, 6)
            Text("整页模式只保存内容指纹，不保存正文。")
                .font(ui(9)).foregroundStyle(faint).lineSpacing(4).padding(.top, 4)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func guideStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(numeral(9)).foregroundStyle(terracotta).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(ui(10, .semibold)).foregroundStyle(ink2)
                Text(detail).font(ui(9)).foregroundStyle(faint).lineSpacing(3)
            }
        }
        .padding(.top, 14)
    }
}

// MARK: - 添加 / 编辑

struct WebWatchEditor: View {
    @ObservedObject var hub: Hub
    let watchID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WebWatch
    @StateObject private var browser: WebWatchBrowserModel
    @State private var error = ""
    @State private var route: WebWatchRoute

    init(hub: Hub, watchID: String?) {
        self.hub = hub
        self.watchID = watchID
        let existing = watchID.flatMap { id in hub.webWatches.first { $0.id == id } }
        _draft = State(initialValue: existing ?? WebWatch())
        _route = State(initialValue: existing?.route ?? WebWatchRoute())
        _browser = StateObject(wrappedValue: WebWatchBrowserModel(url: existing?.url ?? "",
                                                                   autoScan: existing == nil))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(oatmeal.opacity(0.65)).frame(height: 1)
            HStack(spacing: 0) {
                browserPane.frame(width: 640)
                Rectangle().fill(oatmeal.opacity(0.65)).frame(width: 1)
                inspector.frame(width: 358)
            }
        }
        .frame(width: 1000, height: 700)
        .background(paper)
        .sheet(isPresented: $hub.showUniLogin) { UniCourseLoginSheet(hub: hub) }
        .sheet(isPresented: $hub.showCXLogin) { ChaoxingLoginSheet(hub: hub) }
        .sheet(isPresented: $hub.showTeachLogin) { TeachingLoginSheet(hub: hub) }
        .onChange(of: browser.pickedSelector) { value in
            guard !value.isEmpty else { return }
            switch browser.pickingField {
            case "selector": draft.selector = value; draft.signature = nil
            case "entrySelector": route.entrySelector = value
            case "titleSelector": route.titleSelector = value
            case "dueSelector": route.dueSelector = value
            case "statusSelector": route.statusSelector = value
            case "nextSelector": route.nextSelector = value
            default: break
            }
        }
        .onChange(of: browser.selected) { candidate in
            guard let candidate else { return }
            draft.selector = candidate.selector
            draft.signature = candidate.signature
        }
        .onChange(of: browser.scan) { scan in
            guard let scan, !scan.loginSuspected else { return }
            if !scan.pageURL.isEmpty { draft.url = scan.pageURL }
            if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.name = String(scan.pageTitle.prefix(60))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(watchID == nil ? "添加网页监控" : "编辑网页监控")
                    .font(editorial(20))
                Text("在左侧打开目标页并登录；页面加载后会自动识别，也可点「扫描此页」重试。")
                    .font(ui(10)).foregroundStyle(quiet)
            }
            Spacer()
            if !error.isEmpty {
                Text(error).font(ui(9)).foregroundStyle(terracotta).lineLimit(2)
            }
            Button("取消") { dismiss() }
                .buttonStyle(EditorialButtonStyle(kind: .text))
            Button(watchID == nil ? "保存监控" : "保存修改") { save() }
                .buttonStyle(EditorialButtonStyle(kind: .ink))
                .disabled(!canSave)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var browserPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("https://…", text: $browser.address)
                    .textFieldStyle(.plain)
                    .font(ui(10.5))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(cream.opacity(0.65)))
                    .onSubmit { openPage() }
                Button("打开") { openPage() }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                Button("扫描此页") { browser.rescan() }
                    .buttonStyle(EditorialButtonStyle(kind: .rust))
                    .disabled(browser.busy)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            ZStack {
                WebWatchBrowserView(model: browser)
                if browser.busy {
                    ProgressView().controlSize(.small)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(paper.opacity(0.92)))
                }
            }
            .background(Color.white)

            HStack(spacing: 8) {
                Circle().fill(browser.scan?.loginSuspected == true ? terracotta : sage)
                    .frame(width: 5, height: 5)
                Text(browser.message.isEmpty ? "页面加载后可登录；登录完成后点「扫描此页」。" : browser.message)
                    .font(ui(9)).foregroundStyle(quiet).lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private var inspector: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                section("1 · 认页面") {
                    Text("MIRA 会找出页面上重复的条目块。识别不到时，改用「整页变化」。")
                        .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
                    if let scan = browser.scan, !scan.loginSuspected {
                        if scan.candidates.isEmpty {
                            Text("没有识别到重复列表。").font(ui(10)).foregroundStyle(terracotta)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(scan.candidates) { candidate in
                                    candidateButton(candidate)
                                }
                            }
                        }
                    }
                    Picker("监控方式", selection: $draft.mode) {
                        ForEach(WebWatchMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: draft.mode) { mode in
                        if mode == .page {
                            draft.selector = ""
                            draft.signature = nil
                        } else if let selected = browser.selected {
                            draft.selector = selected.selector
                            draft.signature = selected.signature
                        }
                    }
                    Text(draft.mode.hint).font(ui(8.8)).foregroundStyle(faint).lineSpacing(3)
                    if let hint = builtInHint {
                        Button("使用此平台的专用连接") {
                            let host = WebWatchValidation.url(effectiveURL)?.host ?? ""
                            if host == "unicourse.ruc.edu.cn" { hub.showUniLogin = true }
                            else if host == "666.ruc.edu.cn" { hub.showTeachLogin = true }
                            else { hub.showCXLogin = true }
                        }
                        Text(hint)
                            .font(ui(8.8)).foregroundStyle(plum).lineSpacing(3)
                            .padding(.top, 2)
                    }
                }

                if draft.mode == .list {
                    section("跨课程 · 选定检查范围") {
                        Button("读取此页的课程链接") { browser.discoverCourses() }
                        Text("先在课程总览读取并勾选入口，再打开一门课程配置相同的作业列表。也可逐行粘贴课程网址。")
                            .font(ui(9)).foregroundStyle(faint)
                        ForEach(browser.courseLinks) { link in
                            Toggle(link.title, isOn: Binding(get: { route.courseURLs.contains(link.url) }, set: { enabled in
                                if enabled { if !route.courseURLs.contains(link.url) { route.courseURLs.append(link.url) } }
                                else { route.courseURLs.removeAll { $0 == link.url } }
                            })).font(ui(9))
                        }
                        TextEditor(text: Binding(get: { route.courseURLs.joined(separator: "\n") }, set: {
                            route.courseURLs = Array(NSOrderedSet(array: $0.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })) as? [String] ?? []
                        })).font(ui(9)).frame(height: 65)
                        Text("已选 \(route.courseURLs.count) 个入口；留空则只检查当前网址。")
                            .font(ui(9)).foregroundStyle(faint)
                    }
                    section("读取规则 · 点选或填写") {
                        rule("作业入口（可选）", field: "entrySelector", value: $route.entrySelector)
                        rule("列表容器", field: "selector", value: $draft.selector)
                        rule("标题字段", field: "titleSelector", value: $route.titleSelector)
                        rule("截止字段", field: "dueSelector", value: $route.dueSelector)
                        rule("状态字段", field: "statusSelector", value: $route.statusSelector)
                        rule("下一页按钮", field: "nextSelector", value: $route.nextSelector)
                        TextField("同源 iframe 选择器（可选）", text: $route.frameSelector)
                        Text("字段选择器相对于每个条目；iframe 内暂需手填选择器。跨域 iframe 请直接打开其网址。")
                            .font(ui(8.5)).foregroundStyle(faint)
                        Stepper("最多 \(route.maxPages) 页", value: $route.maxPages, in: 1...100)
                        Button("验证当前页字段") { browser.preview(selector: draft.selector, route: route) }
                    }
                }

                section("2 · 起个名字") {
                    TextField("例如：数据结构作业", text: $draft.name)
                        .textFieldStyle(.plain)
                        .font(ui(11))
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(cream.opacity(0.65)))
                    if !draft.url.isEmpty {
                        Text(draft.url).font(ui(8.3)).foregroundStyle(faint)
                            .lineLimit(2).truncationMode(.middle)
                    }
                }

                section("3 · 什么时候看") {
                    Picker("检查间隔", selection: $draft.intervalMinutes) {
                        ForEach(SyncInterval.choices, id: \.self) {
                            Text(SyncInterval.label($0)).tag($0)
                        }
                    }
                    .labelsHidden().frame(width: 130)
                    Toggle("自动检查", isOn: $draft.enabled)
                        .toggleStyle(.switch).controlSize(.small).tint(terracotta)
                    Toggle("发现新条目时提醒", isOn: $draft.notifyItems)
                        .toggleStyle(.switch).controlSize(.small).tint(terracotta)
                }

                if draft.mode == .list {
                    section("4 · 进任务库") {
                        Toggle("新条目写入任务库", isOn: $draft.importTasks)
                            .toggleStyle(.switch).controlSize(.small).tint(terracotta)
                        if draft.importTasks {
                            Picker("分类", selection: $draft.categoryID) {
                                ForEach(hub.data.taskCategories) { category in
                                    Text(category.name).tag(category.id)
                                }
                            }
                            .labelsHidden().frame(width: 150)
                            Text("仅在网页明确显示已提交时同步完成；条目消失、分页或加载失败不会自动完成任务。")
                                .font(ui(8.5)).foregroundStyle(faint).lineSpacing(3)
                        }
                    }
                }

                if !browser.items.isEmpty {
                    section("预览 · \(browser.items.count) 条") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(browser.items.prefix(8)) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle().fill(item.status == "已提交" ? faint : terracotta)
                                        .frame(width: 4, height: 4).padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(WebWatchText.title(item)).font(ui(9.5)).lineLimit(1)
                                        Text(previewDetail(item)).font(ui(8.2)).foregroundStyle(faint)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            if browser.items.count > 8 {
                                Text("还有 \(browser.items.count - 8) 条…")
                                    .font(ui(8.5)).foregroundStyle(faint)
                            }
                        }
                    }
                }

                if !canSave {
                    Text(draft.mode == .list
                         ? "先扫描并选择一个候选列表，才能保存。"
                         : "填一个 http/https 网址后即可保存。")
                        .font(ui(8.8)).foregroundStyle(terracotta).lineSpacing(3)
                }
            }
            .padding(16)
        }
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(ui(8.8, .semibold)).tracking(1.4).foregroundStyle(ink2)
            content()
        }
    }

    private func rule(_ label: String, field: String, value: Binding<String>) -> some View {
        HStack {
            TextField(label, text: value).font(ui(9))
            Button("点选") { browser.pick(field, container: draft.selector) }.font(ui(9))
        }
    }

    private func candidateButton(_ candidate: WebWatchCandidate) -> some View {
        Button {
            browser.select(candidate)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(candidate.label).font(ui(9.5, .semibold)).foregroundStyle(ink2)
                    Spacer()
                    if browser.selected?.selector == candidate.selector {
                        Text("已选").font(ui(8)).foregroundStyle(sage)
                    }
                }
                Text(candidate.sampleTitles.joined(separator: " · "))
                    .font(ui(8.5)).foregroundStyle(quiet).lineLimit(2)
                if let due = candidate.sampleDue {
                    Text("日期示例：\(due)").font(ui(8)).foregroundStyle(faint)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(browser.selected?.selector == candidate.selector ? sageWash : cream.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(browser.selected?.selector == candidate.selector ? sage.opacity(0.35) : oatmeal.opacity(0.5),
                        lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func previewDetail(_ item: WebWatchItem) -> String {
        var parts: [String] = []
        if !item.status.isEmpty { parts.append(item.status) }
        if !item.dueText.isEmpty { parts.append(item.dueText) }
        if item.link.isEmpty { parts.append("无链接") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// 对已经内置专用连接的 RUC 站点给出更准确的入口提示，避免把
    /// 登录页/门户页当成作业列表来扫。
    private var builtInHint: String? {
        guard let host = WebWatchValidation.url(effectiveURL)?.host?.lowercased() else { return nil }
        if host == "unicourse.ruc.edu.cn" {
            return "UniCourse 已有专用连接：设置 →「UniCourse 课程更新」会登录后自动同步未提交作业。通用监控适合该站的其他页面。"
        }
        if host == "666.ruc.edu.cn" {
            return "666 教学系统已有专用连接：设置 →「RUC 教学系统（666）」可自动同步未结束的考试。"
        }
        if host == "chaoxing.com" || host.hasSuffix(".chaoxing.com") {
            return "学习通已有专用连接：设置 →「学习通作业」可自动同步待做作业与考试。"
        }
        return nil
    }

    private var effectiveURL: String {
        if WebWatchValidation.url(browser.address) != nil { return browser.address }
        if WebWatchValidation.url(browser.currentURL) != nil { return browser.currentURL }
        return draft.url
    }

    private var existingWatch: WebWatch? {
        watchID.flatMap { hub.webWatch($0) }
    }

    /// 扫描结果必须对应当前地址；否则用户改了网址但没重新打开时，
    /// 不能把旧页面的条目当成新页面的基线。
    private var scanMatchesURL: Bool {
        guard let scan = browser.scan else { return true }
        guard let scanned = WebWatchValidation.normalized(scan.pageURL),
              let target = WebWatchValidation.normalized(effectiveURL) else { return false }
        return scanned == target
    }

    private var canSave: Bool {
        guard browser.scan?.loginSuspected != true, scanMatchesURL else { return false }
        guard let target = WebWatchValidation.normalized(effectiveURL) else { return false }
        if draft.mode == .list {
            guard !draft.selector.isEmpty || browser.selected != nil else { return false }
            if let existing = existingWatch, existing.url != target, browser.scan == nil {
                return false
            }
        }
        return true
    }

    private func openPage() {
        draft.url = browser.address
        browser.load(browser.address)
    }

    private func save() {
        error = ""
        if browser.scan?.loginSuspected == true {
            error = "当前页面看起来是登录页，请先完成登录再扫描。"
            return
        }
        var watch = draft
        watch.route = route
        if let url = WebWatchValidation.normalized(effectiveURL) { watch.url = url }
        guard WebWatchValidation.url(watch.url) != nil else {
            error = "地址无效，请填写 http:// 或 https:// 开头的网址。"
            return
        }
        watch.name = watch.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if watch.name.isEmpty { watch.name = watch.host }
        if watch.mode == .list {
            if watch.selector.isEmpty, let selected = browser.selected {
                watch.selector = selected.selector
                watch.signature = selected.signature
            }
            guard !watch.selector.isEmpty else {
                error = "请先点「扫描此页」并选择一个列表。"
                return
            }
        } else {
            watch.selector = ""
            watch.signature = nil
        }
        guard scanMatchesURL else {
            error = "页面地址已经改变，请先打开新页面并重新扫描。"
            return
        }
        let existing = existingWatch
        if watch.mode == .list, let existing, existing.url != watch.url, browser.scan == nil {
            error = "网址已经改变，请先打开新页面并扫描列表。"
            return
        }
        if let scan = browser.scan, scanMatchesURL {
            watch.fingerprint = scan.fingerprint
            watch.textLength = scan.textLength
        }
        guard route.courseURLs.allSatisfy({ WebWatchValidation.url($0) != nil }), route.courseURLs.count <= 40 else {
            error = "请填写有效课程网址，最多 40 个入口。"
            return
        }
        let reset = existing == nil
            || existing?.url != watch.url
            || existing?.mode != watch.mode
            || existing?.selector != watch.selector
            || existing?.route != watch.route
        // Multi-page configurations must establish their baseline through the full traversal.
        let needsTraversal = watch.mode == .list
        hub.saveWebWatch(watch, baselineItems: scanMatchesURL && !needsTraversal ? browser.items : [],
                         resetBaseline: reset)
        if needsTraversal && reset { hub.resetWebWatchBaseline(watch.id) }
        hub.checkWebWatch(watch.id, force: true)
        dismiss()
    }
}
