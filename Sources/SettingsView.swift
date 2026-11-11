import SwiftUI
import AppKit

extension HubView {
    var settings: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Codex / ChatGPT 桌面客户端", systemImage: "desktopcomputer").font(.headline)
                Text(hub.data.lastEvent.map { "最近收到事件：\($0.formatted())" } ?? (hub.installed ? "已配置 · 尚未收到真实事件" : "尚未连接")).foregroundStyle(teal)
                Text("接收本机 Codex 轮次结束、权限请求、运行与中断事件。补充信息请求取决于客户端的工具 hook 覆盖。云端任务和普通 ChatGPT 对话状态暂不支持。").font(.callout).foregroundStyle(.secondary)
                Button(hub.installed ? "更新连接配置" : "配置本机连接") { hub.installHooks() }
                Text("配置会保留原有 hooks 并备份。随后需在 Codex 的 hooks 审核界面信任 MIRA 接收器，再开启新会话。MIRA 从不代你批准执行。").font(.caption).foregroundStyle(.secondary)
                Button("查看官方 hooks 说明 ↗") { NSWorkspace.shared.open(URL(string: "https://learn.chatgpt.com/docs/hooks")!) }
            }.padding(22).background(oatmeal.opacity(0.45)).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 14) {
                Label("DeepSeek Harness 桌面端", systemImage: "sparkle").font(.headline)
                Text(hub.dshStatus).foregroundStyle(teal)
                Text("接收 DSH 轮次结束、待确认与待补充信息事件。MIRA 运行时可在弹窗选择「允许一次 / 拒绝」；超时或选择「去 DSH 处理」会交还 DSH 原生对话框。点击提醒会把 DSH 窗口切到前台。").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(hub.dshInstalled ? "更新 DSH 连接" : "配置 DSH 连接") { hub.installDSH() }
                    if hub.dshInstalled { Button("移除") { hub.removeDSH() } }
                    Button("打开 profile 文件夹") {
                        let profile = hub.dshProfile
                        if FileManager.default.fileExists(atPath: profile.path) { NSWorkspace.shared.open(profile) }
                        else { hub.error = "还没有 DSH 桌面 profile，请先启动一次 DeepSeek Harness。"; }
                    }
                }
                Text("配置会保留 profile 原有补丁并备份；重启 DeepSeek Harness 后生效。应用里的「禁用第三方插件」会停用补丁层，需要重新配置。").font(.caption).foregroundStyle(.secondary)
            }.padding(22).background(oatmeal.opacity(0.45)).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 15) {
                Text("通知与启动").font(.headline)
                HStack { Text("系统通知"); Spacer(); Text(hub.notificationStatus).font(.caption).foregroundStyle(.secondary); Button("授权通知") { hub.requestPermission() } }
                Toggle("登录电脑时启动 MIRA", isOn: Binding(get: { hub.loginEnabled }, set: { hub.toggleLogin($0) }))
                Text("关闭窗口后仍在菜单栏运行。首次建议固定应用位置，再启用登录启动。当天错过的计划会补发，过去日期的计划不会连续轰炸。").font(.caption).foregroundStyle(.secondary)
                HStack { Button("测试弹窗") { hub.test() }; Button("打开数据文件夹") { NSWorkspace.shared.open(hub.root) }; Spacer(); Button("退出 MIRA") { NSApp.terminate(nil) } }
            }.padding(22).background(oatmeal.opacity(0.45)).clipShape(RoundedRectangle(cornerRadius: 12))
            Text("ChatGPT 计划：本版在本地创建和保存，可关联对话链接；尚未自动同步 ChatGPT 定时任务。数据仅保存在这台电脑，不需要 API Key。").font(.caption).foregroundStyle(.secondary)
        }
    }
}
