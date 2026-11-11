import SwiftUI
import AppKit

extension HubView {
    var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsCard(
                title: "Codex / ChatGPT 桌面客户端",
                status: hub.data.lastEvent.map { "最近事件 " + $0.formatted(date: .abbreviated, time: .shortened) }
                    ?? (hub.installed ? "已配置 · 尚未收到真实事件" : "尚未连接"),
                statusColor: hub.data.lastEvent == nil && !hub.installed ? quiet : terracotta
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
                Text("配置会保留原有 hooks 并备份。随后需在 Codex 的 hooks 审核界面信任 MIRA 接收器，再开启新会话。MIRA 从不代你批准执行。")
                    .font(ui(9)).foregroundStyle(faint).lineSpacing(3)
            }

            settingsCard(
                title: "DeepSeek Harness 桌面端",
                status: hub.dshStatus,
                statusColor: hub.dshInstalled ? terracotta : quiet
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
                Text("关闭窗口后仍在菜单栏运行。首次建议固定应用位置，再启用登录启动。当天错过的计划会补发，过去日期的计划不会连续轰炸。")
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
                    .lineLimit(2)
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
