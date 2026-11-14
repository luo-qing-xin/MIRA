import SwiftUI
import AppKit

extension HubView {
    var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsCard(
                title: "Codex / ChatGPT 桌面客户端",
                status: hub.codexStatus,
                statusColor: statusColor(hub.codexAdapter)
            ) {
                Text("接收本机 Codex 轮次结束、权限请求、运行与中断事件。补充信息请求取决于客户端的工具 hook 覆盖。云端任务和普通 ChatGPT 对话状态暂不支持。")
                    .font(ui(10.5)).foregroundStyle(quiet).lineSpacing(4)
                HStack(spacing: 8) {
                    Button(hub.installed ? "更新连接配置" : "配置本机连接") { hub.installHooks() }
                        .buttonStyle(EditorialButtonStyle(kind: .ink))
                    Button("查看官方 hooks 说明 ↗") {
                        NSWorkspace.shared.open(URL(string: "https://learn.chatgpt.com/docs/hooks")!)
                    }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                }
                Text("后台确认 · " + hub.codexConnectionStatus)
                    .font(ui(10.5)).foregroundStyle(hub.codexConnected ? sage : quiet)
                Text("工具审批仅在 Codex 等待你处理时提醒。后台连接不可用时，请在 Codex 原会话查看。")
                    .font(ui(10.5)).foregroundStyle(quiet).lineSpacing(4)
                Text("配置会保留原有 hooks 并备份。随后需在 Codex 的 hooks 审核界面信任 MIRA 接收器，再开启新会话。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
                Text("状态里的版本号来自已安装文件中的 ADAPTER_VERSION 常量（只读文本，不执行）。更新文件后要新开一个会话，旧会话仍在用旧版本。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
            }

            settingsCard(
                title: "DeepSeek Harness 桌面端",
                status: hub.dshStatus,
                statusColor: statusColor(hub.dshAdapter)
            ) {
                Text("接收 DSH 轮次结束、待确认与待补充信息事件。MIRA 运行时可在弹窗选择「允许一次 / 拒绝」；超时或选择「去 DSH 处理」会交还 DSH 原生对话框。")
                    .font(ui(10.5)).foregroundStyle(quiet).lineSpacing(4)
                HStack(spacing: 8) {
                    Button(hub.dshInstalled ? "更新 DSH 连接" : "配置 DSH 连接") { hub.installDSH() }
                        .buttonStyle(EditorialButtonStyle(kind: .ink))
                    if hub.dshInstalled {
                        Button("移除") { hub.removeDSH() }
                            .buttonStyle(EditorialButtonStyle(kind: .outline))
                    }
                    Button("打开 profile 文件夹") {
                        let profile = hub.dshProfile
                        if FileManager.default.fileExists(atPath: profile.path) {
                            NSWorkspace.shared.open(profile)
                        } else {
                            hub.error = "还没有 DSH 桌面 profile，请先启动一次 DeepSeek Harness。"
                        }
                    }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                }
                Text("配置会保留 profile 原有补丁并备份；重启 DeepSeek Harness 后生效。应用里的「禁用第三方插件」会停用补丁层，需要重新配置。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
                Text("状态里的版本号来自已安装插件文件中的 ADAPTER_VERSION 常量（只读文本，不执行）。更新文件后要重启 DeepSeek Harness，旧进程仍在用旧版本。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
            }

            settingsCard(
                title: "UniCourse 课程更新",
                status: hub.uniStatus,
                statusColor: hub.unicourse.signedIn && hub.unicourse.lastError == nil ? sage : quiet
            ) {
                Text("逐门课读取作业列表，只把「未提交」的作业写进任务库「课程」，截止时间取自作业页；你在网页上提交后，对应任务会自动标成已完成。公告可选提醒，课件不打扰。")
                    .font(ui(10.5)).foregroundStyle(quiet).lineSpacing(4)
                HStack(spacing: 8) {
                    Button(hub.unicourse.signedIn ? "重新登录" : "登录 UniCourse") { hub.showUniLogin = true }
                        .buttonStyle(EditorialButtonStyle(kind: .ink))
                    Button("立即同步") { hub.checkUniCourse(force: true) }
                        .buttonStyle(EditorialButtonStyle(kind: .outline))
                        .disabled(!hub.unicourse.signedIn || hub.uniBusy)
                    if hub.unicourse.signedIn {
                        Button("断开") { hub.disconnectUniCourse() }
                            .buttonStyle(EditorialButtonStyle(kind: .text))
                    }
                    Spacer()
                }
                HStack(spacing: 18) {
                    Toggle("新作业写入任务库", isOn: Binding(
                        get: { hub.unicourse.importHomework },
                        set: { hub.unicourse.importHomework = $0; hub.saveUniCourse() }))
                        .toggleStyle(.switch).controlSize(.small).tint(terracotta)
                    Toggle("公告也提醒", isOn: Binding(
                        get: { hub.unicourse.notifyAnnouncements },
                        set: { hub.unicourse.notifyAnnouncements = $0; hub.saveUniCourse() }))
                        .toggleStyle(.switch).controlSize(.small).tint(terracotta)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Toggle("自动检查", isOn: Binding(
                        get: { hub.unicourse.enabled },
                        set: { hub.setUniCourseEnabled($0) }))
                        .toggleStyle(.switch).controlSize(.small).tint(terracotta)
                    Picker("检查间隔", selection: Binding(
                        get: { hub.unicourse.intervalMinutes },
                        set: { hub.unicourse.intervalMinutes = $0; hub.saveUniCourse() })) {
                        ForEach(UniCourseSettings.intervalChoices, id: \.self) { Text(SyncInterval.label($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: 108)
                    Spacer()
                }
                Text("只导入未提交的作业；网页提交后，下次同步会自动完成对应任务，从「未完成」移到「已完成」，保留历史记录。首次同步会把当前所有未提交作业导入一次，之后只提醒新增的。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
                Text("登录态只保存在本机 unicourse.json（0600）；MIRA 不保存密码。Cookie 过期时状态会提示「登录已过期」，重新登录即可。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
            }

            settingsCard(
                title: "学习通作业",
                status: hub.cxStatus,
                statusColor: hub.chaoxing.signedIn && hub.chaoxing.lastError == nil ? sage : quiet
            ) {
                Text("逐门课读取学习通的作业与考试列表，只把「未交」写进任务库「课程」；已完成的不会进来，网页提交后会自动标记完成并保留历史。已过期但未交的会保留并标注。")
                    .font(ui(10.5)).foregroundStyle(quiet).lineSpacing(4)
                HStack(spacing: 8) {
                    Button(hub.chaoxing.signedIn ? "重新登录" : "登录 学习通") { hub.showCXLogin = true }
                        .buttonStyle(EditorialButtonStyle(kind: .ink))
                    Button("立即同步") { hub.checkChaoxing(force: true) }
                        .buttonStyle(EditorialButtonStyle(kind: .outline))
                        .disabled(!hub.chaoxing.signedIn || hub.cxBusy)
                    if hub.chaoxing.signedIn {
                        Button("断开") { hub.disconnectChaoxing() }
                            .buttonStyle(EditorialButtonStyle(kind: .text))
                    }
                    Spacer()
                }
                HStack(spacing: 18) {
                    Toggle("写入任务库", isOn: Binding(
                        get: { hub.chaoxing.importHomework },
                        set: { hub.chaoxing.importHomework = $0; hub.saveChaoxing() }))
                        .toggleStyle(.switch).controlSize(.small).tint(terracotta)
                    Toggle("包含考试", isOn: Binding(
                        get: { hub.chaoxing.includeExams },
                        set: { hub.chaoxing.includeExams = $0; hub.saveChaoxing() }))
                        .toggleStyle(.switch).controlSize(.small).tint(terracotta)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Toggle("自动同步", isOn: Binding(
                        get: { hub.chaoxing.enabled },
                        set: { hub.setChaoxingEnabled($0) }))
                        .toggleStyle(.switch).controlSize(.small).tint(terracotta)
                    Picker("同步间隔", selection: Binding(
                        get: { hub.chaoxing.intervalMinutes },
                        set: { hub.chaoxing.intervalMinutes = $0; hub.saveChaoxing() })) {
                        ForEach(ChaoxingSettings.intervalChoices, id: \.self) { Text(SyncInterval.label($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: 108)
                    Spacer()
                }
                Text("首次同步会把当前所有待做作业导入一次，之后只提醒新增的。学习通列表里没有截止时间的作业会以「未设置」进入任务库，仍可手动补。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
                Text("登录态只保存在本机 chaoxing.json（0600）；MIRA 不保存密码。适配依赖学习通的 H5 页面结构，页面改版时会在数据目录留下样本页用于校准。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
            }
            .sheet(isPresented: $hub.showCXLogin) { ChaoxingLoginSheet(hub: hub) }

            settingsCard(
                title: "RUC 教学系统（666）",
                status: hub.teachStatus,
                statusColor: hub.teaching.signedIn && hub.teaching.lastError == nil ? sage : quiet
            ) {
                Text("读取「作业考试 → 我的考试」，只把未结束的考试写进任务库「课程」，带结束时间；考试结束后自动归档并保留历史。")
                    .font(ui(10.5)).foregroundStyle(quiet).lineSpacing(4)
                HStack(spacing: 8) {
                    Button(hub.teaching.signedIn ? "重新登录" : "登录 教学系统") { hub.showTeachLogin = true }
                        .buttonStyle(EditorialButtonStyle(kind: .ink))
                    Button("立即同步") { hub.checkTeaching(force: true) }
                        .buttonStyle(EditorialButtonStyle(kind: .outline))
                        .disabled(!hub.teaching.signedIn || hub.teachBusy)
                    if hub.teaching.signedIn {
                        Button("断开") { hub.disconnectTeaching() }
                            .buttonStyle(EditorialButtonStyle(kind: .text))
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Toggle("自动同步", isOn: Binding(
                        get: { hub.teaching.enabled },
                        set: { hub.setTeachingEnabled($0) }))
                        .toggleStyle(.switch).controlSize(.small).tint(terracotta)
                    Picker("同步间隔", selection: Binding(
                        get: { hub.teaching.intervalMinutes },
                        set: { hub.teaching.intervalMinutes = $0; hub.saveTeaching() })) {
                        ForEach(TeachingSettings.intervalChoices, id: \.self) { Text(SyncInterval.label($0)).tag($0) }
                    }
                    .labelsHidden().frame(width: 108)
                    Spacer()
                }
                Text("首次同步会把当前所有未结束的考试导入一次，之后只提醒新增的。登录态只保存在本机 teaching.json（0600），MIRA 不保存密码。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
                Text("适配依赖 666 的 Server Action 返回格式；若同步失败，数据目录会留下 teaching-sample.txt 用于校准。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
            }
            .sheet(isPresented: $hub.showTeachLogin) { TeachingLoginSheet(hub: hub) }

            settingsCard(
                title: "网页监控（通用）",
                status: hub.webWatchStatus,
                statusColor: hub.webWatches.contains(where: { $0.lastError != nil }) ? terracotta : quiet
            ) {
                Text("给一个网址就能监控：课程作业、考试安排、公告或成绩页。MIRA 在内置浏览器里打开页面，你登录一次，它自动识别重复列表；新条目写入任务库，也可以只监控整页变化。没有按学校写死的代码。")
                    .font(ui(10.5)).foregroundStyle(quiet).lineSpacing(4)
                HStack(spacing: 8) {
                    Button("打开监控") { hub.section = "监控" }
                        .buttonStyle(EditorialButtonStyle(kind: .ink))
                    Button("添加网址") {
                        hub.editingWatchID = nil
                        hub.showWatchEditor = true
                    }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                    Spacer()
                }
                Text("登录态由 MIRA 自己的 WebKit 数据仓库保管，不写进配置文件；MIRA 不保存密码。登录过期时在「监控」页点「编辑」重新登录。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
            }

            settingsCard(title: "通知与启动", status: hub.notificationStatus, statusColor: hub.notificationStatus == "已允许" ? sage : quiet) {
                HStack(spacing: 8) {
                    Button("授权通知") { hub.requestPermission() }
                        .buttonStyle(EditorialButtonStyle(kind: .outline))
                    Button("测试弹窗") { hub.test() }
                        .buttonStyle(EditorialButtonStyle(kind: .outline))
                    Spacer()
                }
                HStack {
                    Toggle("登录电脑时启动 MIRA",
                           isOn: Binding(get: { hub.loginEnabled }, set: { hub.toggleLogin($0) }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(terracotta)
                    Spacer()
                }
                HStack {
                    Toggle("开机时显示待办浮窗",
                           isOn: Binding(get: { hub.openTasksAtLaunch }, set: { hub.setOpenTasksAtLaunch($0) }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(terracotta)
                    Spacer()
                    Button("预览浮窗") { hub.showTaskOverview?() }
                        .buttonStyle(EditorialButtonStyle(kind: .text))
                }
                if hub.openTasksAtLaunch {
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(hub.loginEnabled ? sage : Color(red: 0.75, green: 0.57, blue: 0.20))
                            .frame(width: 5, height: 5)
                            .padding(.top, 4)
                        Text(hub.loginEnabled
                             ? "已开启登录启动：下次登录电脑会在屏幕右上角弹出待办浮窗。如果未出现，请在系统设置的「登录项」中允许 MIRA。"
                             : "待办浮窗设置已开启；还需要登录启动，电脑登录后才会自动出现。")
                            .font(ui(9)).foregroundStyle(hub.loginEnabled ? quiet : faint)
                            .lineSpacing(3)
                        Spacer(minLength: 4)
                        if !hub.loginEnabled {
                            Button("开启登录启动") { hub.toggleLogin(true) }
                                .buttonStyle(EditorialButtonStyle(kind: .text))
                        }
                    }
                }
                Text("浮窗最多显示 5 项待办，点圆圈完成；「打开任务库」查看全部。关闭窗口后 MIRA 仍在菜单栏运行。首次建议固定应用位置，再启用登录启动。当天错过的计划会补发，过去日期的计划不会连续轰炸。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
                HStack(spacing: 8) {
                    Button("打开数据文件夹") { NSWorkspace.shared.open(hub.root) }
                        .buttonStyle(EditorialButtonStyle(kind: .text))
                    Button("退出 MIRA") { NSApp.terminate(nil) }
                        .buttonStyle(EditorialButtonStyle(kind: .text))
                    Spacer()
                }
            }

            settingsCard(title: "定时任务提醒", status: hub.scheduleStatus, statusColor: quiet) {
                HStack(spacing: 8) {
                    Button("立即同步桌面计划") { hub.syncSchedules(); hub.tick() }
                        .buttonStyle(EditorialButtonStyle(kind: .outline))
                    Spacer()
                }
                Text("自动读取本机 Codex 定时计划，每 30 秒同步，每天和每周固定时间的计划可提醒。按本机时区当天补发，完成状态保存在 MIRA。来源计划暂停或删除后会停止提醒。")
                    .font(ui(10.5)).foregroundStyle(quiet).lineSpacing(4)
                Text("ChatGPT 网页／手机端任务尚未连接。可在 MIRA 创建同时间的本地计划并关联 ChatGPT 对话；本机桌面同步不代表云端 Tasks 已同步。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
            }

            settingsCard(
                title: "记录与存储",
                status: "\(hub.data.entries.count) 条记录 · \(hub.data.seen.count) 个去重键",
                statusColor: quiet
            ) {
                Text("已处理或已过期的记录保留 \(hub.retentionPolicy.maxAgeDays) 天，最多 \(hub.retentionPolicy.maxEntries) 条。整理时先导出到数据文件夹的 records-YYYY-MM.md，再从 state.json 移除；仍待你处理的事项不会被清理。")
                    .font(ui(10.5)).foregroundStyle(quiet).lineSpacing(4)
                HStack(spacing: 8) {
                    Button("立即整理") { hub.archiveNow() }
                        .buttonStyle(EditorialButtonStyle(kind: .outline))
                    Button("打开数据文件夹") { NSWorkspace.shared.open(hub.root) }
                        .buttonStyle(EditorialButtonStyle(kind: .text))
                    Spacer()
                }
                Text("每次启动和每天首次检查时自动整理。归档按记录发生月份分组，重复导出会被跳过；标题缓存保留 7 天，无法解析的隔离事件保留 30 天。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
            }
        }
        .sheet(isPresented: $hub.showUniLogin) { UniCourseLoginSheet(hub: hub) }
    }

    private func statusColor(_ status: AdapterHealth.Status) -> Color {
        switch status.state {
        case .ready: return sage
        case .restart, .waiting: return Color(red: 0.75, green: 0.57, blue: 0.20)
        case .legacy, .outdated: return terracotta
        case .ahead, .missing: return quiet
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        status: String,
        statusColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(editorial(16, .semibold)).tracking(0.6)
                Spacer()
                Text(status)
                    .font(ui(9.5))
                    .foregroundStyle(statusColor)
                    .lineLimit(3)
                    .multilineTextAlignment(.trailing)
            }
            Rectangle().fill(oatmeal.opacity(0.55)).frame(height: 1)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(paper))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(oatmeal.opacity(0.6), lineWidth: 1))
    }
}
