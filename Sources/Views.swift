import SwiftUI
import AppKit

func editorial(_ size: CGFloat) -> Font { .custom("Songti SC", size: size) }

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(quiet).padding(.horizontal, 12).padding(.vertical, 9)
            .background(oatmeal.opacity(configuration.isPressed ? 1 : 0.65))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct StatusLabel: View {
    let text: String
    var urgent: Bool { text == "待确认" || text == "待补充信息" }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium))
            .foregroundStyle(urgent ? Color(red: 0.52, green: 0.28, blue: 0.07) : quiet)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(urgent ? Color(red: 1, green: 0.9, blue: 0.72) : oatmeal)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension Hub {
    var todayPlans: [Plan] {
        let day = Calendar.current.component(.weekday, from: Date())
        return allPlans.filter { $0.enabled && ($0.weekdays.isEmpty || $0.weekdays.contains(day)) }
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }
    var running: [Entry] { data.entries.filter { !$0.done && $0.status == "运行中" } }
    func go(_ section: String) { self.section = section; showMain?() }
    func todayEntry(_ plan: Plan) -> Entry? {
        guard let occurrence = Schedule.due(plan, now: Date()) else { return nil }
        return data.entries.first { $0.id == occurrence.id }
    }
}

struct TaskRow: View {
    @ObservedObject var hub: Hub
    let entry: Entry
    var compact = false
    var history = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 11 : 14) {
            HStack {
                Label(entry.source, systemImage: entry.source == "个人计划" ? "calendar" : "cube")
                    .font(.system(size: 12)).foregroundStyle(quiet)
                Spacer()
                StatusLabel(text: history ? entry.historyStatus : entry.status)
            }
            Text(entry.displayTitle).font(compact ? .system(size: 16, weight: .semibold) : editorial(24))
                .foregroundStyle(ink).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if !entry.body.isEmpty {
                Text(entry.body).font(.system(size: 13)).foregroundStyle(quiet).lineSpacing(4)
                    .lineLimit(compact ? 2 : 3).textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Text(entry.date, style: .time).font(.system(size: 11)).foregroundStyle(quiet)
                if let snooze = entry.snooze, snooze > Date() {
                    Text("延后至 \(snooze.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(terracotta)
                }
                Spacer()
                if let thread = entry.thread {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(thread, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).foregroundStyle(quiet).help("复制任务标识").accessibilityLabel("复制任务标识")
                }
            }
            if compact && !entry.link.isEmpty {
                Button { hub.open(entry) } label: {
                    HStack { Text("打开原任务"); Spacer(); Image(systemName: "arrow.up.right") }
                }.buttonStyle(MiraPrimaryButtonStyle())
            }
            if !history && entry.status != "运行中" {
                if entry.token != nil, entry.status == "待确认" {
                    HStack(spacing: 8) {
                        Button("允许一次") { hub.decide(entry, "allow") }.buttonStyle(MiraPrimaryButtonStyle())
                        Button("拒绝") { hub.decide(entry, "deny") }.buttonStyle(QuietButtonStyle())
                        Button("去 DSH 处理") { hub.decide(entry, "defer") }.buttonStyle(QuietButtonStyle())
                        Spacer()
                    }
                } else {
                    HStack {
                        if !compact && !entry.link.isEmpty {
                            Button { hub.open(entry) } label: { Label("打开原任务", systemImage: "arrow.up.right") }.buttonStyle(MiraPrimaryButtonStyle())
                        }
                        if entry.canSnooze {
                            Button("10 分钟后") { hub.snooze(entry.id) }.buttonStyle(QuietButtonStyle())
                        }
                        Spacer()
                        if !entry.automaticallyArchived {
                            Button(entry.source == "个人计划" ? "完成" : "标为已处理") { hub.finish(entry.id) }
                                .buttonStyle(QuietButtonStyle())
                        }
                    }
                }
            }
            if !compact && (history || entry.status == "运行中") && !entry.link.isEmpty {
                Button { hub.open(entry) } label: { Label("打开原任务", systemImage: "arrow.up.right") }.buttonStyle(QuietButtonStyle())
            }
        }.padding(.vertical, compact ? 14 : 22).padding(.horizontal, compact ? 15 : 0)
            .background(compact ? paper : Color.clear)
            .overlay(alignment: .bottom) { if !compact { Rectangle().fill(oatmeal).frame(height: 1) } }
            .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 0))
            .overlay { if compact { RoundedRectangle(cornerRadius: 10).stroke(oatmeal, lineWidth: 1) } }
    }
}

struct HubView: View {
    @ObservedObject var hub: Hub
    @State var editing: Plan?
    @State var adding = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("mira.").font(.custom("Georgia", size: 34)).foregroundStyle(ink).frame(width: 150, alignment: .leading)
                Spacer()
                HStack(spacing: 30) {
                    ForEach(["今日", "计划", "记录"], id: \.self) { tab in
                        Button { hub.section = tab } label: {
                            Text(tab).font(editorial(19)).foregroundStyle(hub.section == tab ? terracotta : quiet)
                                .padding(.vertical, 12)
                                .overlay(alignment: .bottom) { if hub.section == tab { Rectangle().fill(terracotta).frame(height: 2) } }
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                HStack(spacing: 12) {
                    Circle().fill(hub.data.lastEvent == nil ? Color.orange : Color(red: 0.39, green: 0.52, blue: 0.35)).frame(width: 6, height: 6)
                    Text(hub.data.lastEvent == nil ? (hub.installed ? "等待事件" : "尚未连接") : "已收到事件").font(.system(size: 11)).foregroundStyle(quiet)
                    Button { hub.showTray?() } label: { Image(systemName: "menubar.rectangle") }.buttonStyle(.plain).help("打开菜单栏面板").accessibilityLabel("打开菜单栏面板")
                    Button { hub.section = "设置" } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("连接与设置").accessibilityLabel("连接与设置")
                }.frame(width: 185, alignment: .trailing)
            }.padding(.horizontal, 36).padding(.top, 12).padding(.bottom, 14)
            Rectangle().fill(oatmeal).frame(height: 1).padding(.horizontal, 36)
            if !hub.error.isEmpty {
                HStack { Text(hub.error).font(.caption).foregroundStyle(.red); Spacer(); Button("关闭") { hub.error = "" } }
                    .padding(12).background(Color.red.opacity(0.06)).padding(.horizontal, 36)
            }
            if !hub.notice.isEmpty {
                HStack { Text(hub.notice).font(.caption).foregroundStyle(ink); Spacer(); Button("关闭") { hub.notice = "" } }
                    .padding(12).background(oatmeal.opacity(0.7)).padding(.horizontal, 36)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if hub.section == "今日" { today }
                    if hub.section == "计划" { plans }
                    if hub.section == "记录" { history }
                    if hub.section == "设置" { settings }
                }.padding(36).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("本地优先 · 让重要的事，找到你。")
                Spacer()
                Text("MIRA 0.2")
            }.font(.system(size: 10)).foregroundStyle(quiet).padding(.horizontal, 36).padding(.vertical, 13)
        }.background(paper).foregroundStyle(ink).frame(minWidth: 960, minHeight: 670)
            .preferredColorScheme(.light).tint(terracotta)
            .sheet(isPresented: $adding) { PlanEditor(hub: hub, plan: editing) }
    }
    var today: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .firstTextBaseline) {
                Text("工作有进展，生活有安排。").font(editorial(38)).foregroundStyle(ink)
                Spacer()
                Text(Date(), format: .dateTime.month().day().weekday()).font(.system(size: 12)).foregroundStyle(quiet)
            }
            HStack(alignment: .top, spacing: 34) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack { Text("AI 留给你的消息").font(editorial(23)); Spacer(); Text("\(hub.active.filter { $0.source != "个人计划" }.count) 项待处理").font(.system(size: 11)).foregroundStyle(quiet) }
                        .padding(.bottom, 15)
                    Rectangle().fill(oatmeal).frame(height: 1)
                    let ai = hub.active.filter { $0.source != "个人计划" }
                    if ai.isEmpty { empty("暂时没有待处理的消息", "AI 需要你时，提醒会出现在这里。", "tray") }
                    ForEach(ai) { TaskRow(hub: hub, entry: $0) }
                    if !hub.running.isEmpty {
                        Text("正在进行").font(editorial(20)).padding(.top, 25)
                        ForEach(hub.running) { TaskRow(hub: hub, entry: $0) }
                    }
                    if hub.data.lastEvent == nil {
                        Button { hub.section = "设置" } label: { Label(hub.installed ? "查看连接状态" : "连接 Codex", systemImage: "link") }
                            .buttonStyle(QuietButtonStyle()).padding(.top, 18)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Text("今日安排").font(editorial(23)); Spacer(); Image(systemName: "sun.max").foregroundStyle(terracotta) }
                    if hub.todayPlans.isEmpty {
                        Text("给自己留一点时间。").font(editorial(20)).padding(.top, 24)
                        Text("添加健身、阅读或休息计划，\n到时间时，MIRA 会提醒你。").font(.system(size: 13)).foregroundStyle(quiet).lineSpacing(5)
                    }
                    ForEach(hub.todayPlans) { plan in agenda(plan) }
                    Button { editing = nil; adding = true } label: { Label("添加计划", systemImage: "plus") }
                        .buttonStyle(QuietButtonStyle()).padding(.top, 8)
                }.padding(24).frame(width: 280, alignment: .leading).background(oatmeal.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    func agenda(_ p: Plan) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(String(format: "%02d:%02d", p.hour, p.minute)).font(.custom("Georgia", size: 43)).foregroundStyle(terracotta)
            Text(p.title).font(editorial(22)).fixedSize(horizontal: false, vertical: true)
            if !p.notes.isEmpty { Text(p.notes).font(.system(size: 12)).foregroundStyle(quiet).lineSpacing(6).fixedSize(horizontal: false, vertical: true) }
            if let entry = hub.todayEntry(p) {
                if entry.done { Label("今天已完成", systemImage: "checkmark.circle").font(.caption).foregroundStyle(quiet) }
                else {
                    HStack { Button("完成") { hub.finish(entry.id) }.buttonStyle(MiraPrimaryButtonStyle()); Button("10 分钟后") { hub.snooze(entry.id) }.buttonStyle(QuietButtonStyle()) }
                }
            } else { Text("到时提醒 · 当天补发").font(.system(size: 11)).foregroundStyle(quiet) }
            if p.origin == nil {
                Button("编辑计划") { editing = p; adding = true }.buttonStyle(.plain).foregroundStyle(terracotta).font(.system(size: 11))
            } else { Text(p.origin ?? "").font(.caption).foregroundStyle(quiet) }
            Divider().padding(.top, 6)
        }
    }
    func empty(_ title: String, _ detail: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light)).foregroundStyle(terracotta)
            Text(title).font(editorial(23))
            Text(detail).font(.system(size: 13)).foregroundStyle(quiet)
        }.padding(.vertical, 42).frame(maxWidth: .infinity, alignment: .leading)
    }
    var plans: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("把时间，留给重要的事。").font(editorial(34)); Spacer(); Button("＋ 新建计划") { editing = nil; adding = true }.buttonStyle(MiraPrimaryButtonStyle()) }
            Text("每天或每周重复 · 当天错过补发 · 完成后不再打扰").font(.system(size: 12)).foregroundStyle(quiet)
            HStack { Text(hub.scheduleStatus).font(.caption).foregroundStyle(quiet); Spacer(); Button("同步桌面计划") { hub.syncSchedules(); hub.tick() }.buttonStyle(QuietButtonStyle()) }
            if hub.allPlans.isEmpty { empty("还没有个人计划", "从一个小小的日常开始。", "calendar") }
            ForEach(hub.allPlans) { p in
                HStack(alignment: .top, spacing: 25) {
                    Text(String(format: "%02d:%02d", p.hour, p.minute)).font(.custom("Georgia", size: 32)).foregroundStyle(terracotta).frame(width: 100, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(p.title).font(editorial(24))
                        Text(p.weekdays.isEmpty ? "每天" : "每周 " + p.weekdays.sorted().map { ["", "日", "一", "二", "三", "四", "五", "六"][$0] }.joined(separator: " · ")).font(.caption).foregroundStyle(quiet)
                        if !p.notes.isEmpty { Text(p.notes).font(.system(size: 13)).foregroundStyle(quiet).lineSpacing(4) }
                        if let origin = p.origin {
                            Text(origin + " · 在来源应用调整时间或暂停").font(.caption).foregroundStyle(quiet)
                        } else { HStack {
                            Button("编辑") { editing = p; adding = true }.buttonStyle(QuietButtonStyle())
                            Button("删除", role: .destructive) {
                                hub.data.plans.removeAll { $0.id == p.id }
                                hub.data.entries.removeAll { $0.id.hasPrefix("plan-\(p.id)-") && !$0.done }; _ = hub.save()
                            }.buttonStyle(.plain).font(.caption).foregroundStyle(quiet)
                        } }
                    }
                    Spacer()
                    if p.origin == nil { Toggle("启用", isOn: Binding(get: { p.enabled }, set: { value in
                        if let i = hub.data.plans.firstIndex(where: { $0.id == p.id }) { hub.data.plans[i].enabled = value; _ = hub.save(); hub.tick() }
                    })).toggleStyle(.switch).fixedSize() }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(oatmeal.opacity(0.45)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("每一步，都有迹可循。").font(editorial(34))
            let items = hub.data.entries.filter { Schedule.inHistory($0, now: Date()) }
            if items.isEmpty { empty("还没有历史记录", "本轮结束、已处理与已过期的提醒会保存在这里。", "clock") }
            ForEach(items) { TaskRow(hub: hub, entry: $0, history: true) }
        }
    }
}

struct TrayView: View {
    @ObservedObject var hub: Hub
    @State var tab = 0
    var body: some View {
        VStack(spacing: 17) {
            HStack { Text("MIRA").font(.custom("Georgia", size: 29)); Spacer(); Button { hub.go("设置") } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).accessibilityLabel("连接与设置") }
            HStack(spacing: 4) {
                ForEach(0..<2) { index in
                    Button { tab = index } label: {
                        Text(index == 0 ? "待处理 \(hub.active.count)" : "今日计划")
                            .font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 10)
                            .foregroundStyle(tab == index ? Color.white : ink)
                            .background(tab == index ? terracotta : Color.clear).clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }.padding(3).background(oatmeal).clipShape(RoundedRectangle(cornerRadius: 10))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if tab == 0 {
                        if hub.active.isEmpty { Label("暂时没有待处理的事", systemImage: "checkmark.circle").font(.system(size: 13)).foregroundStyle(quiet).frame(maxWidth: .infinity).padding(.vertical, 38) }
                        ForEach(hub.active) { TaskRow(hub: hub, entry: $0, compact: true) }
                        if !hub.running.isEmpty { Text("正在进行 · \(hub.running.count)").font(.caption).foregroundStyle(quiet); ForEach(hub.running) { TaskRow(hub: hub, entry: $0, compact: true) } }
                    } else {
                        if hub.todayPlans.isEmpty { Text("今天还没有安排").font(editorial(20)).padding(.vertical, 25) }
                        ForEach(hub.todayPlans) { p in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(String(format: "%02d:%02d", p.hour, p.minute)).font(.custom("Georgia", size: 24)).foregroundStyle(terracotta)
                                Text(p.title).font(.system(size: 15, weight: .medium))
                                if let e = hub.todayEntry(p) {
                                    if e.done { Text("今天已完成").font(.caption).foregroundStyle(quiet) }
                                    else { Button("完成") { hub.finish(e.id) }.buttonStyle(QuietButtonStyle()) }
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(oatmeal.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Button("管理个人计划") { hub.go("计划") }.buttonStyle(QuietButtonStyle())
                    }
                }.padding(2)
            }.frame(height: 370)
            Divider()
            HStack {
                Button { hub.go("今日") } label: { Label("查看全部任务", systemImage: "arrow.up.right") }.buttonStyle(.plain)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.plain).font(.caption).foregroundStyle(quiet)
            }.font(.system(size: 13))
        }.padding(20).frame(width: 400).background(paper).foregroundStyle(ink).preferredColorScheme(.light)
    }
}

struct ReminderView: View {
    @ObservedObject var hub: Hub
    let entry: Entry
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("M").font(.custom("Georgia", size: 22)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(terracotta).clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Text(entry.displayTitle).font(.system(size: 16, weight: .semibold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(action: {
                        if let decision = ReminderClose.decision(for: entry) { _ = hub.decide(entry, decision) }
                        dismiss()
                    }) { Image(systemName: "xmark").font(.system(size: 12, weight: .medium)) }
                        .buttonStyle(.plain).foregroundStyle(quiet).accessibilityLabel("关闭提醒")
                        .help(entry.token != nil ? "关闭提醒，交还 DSH 原生对话框" : "关闭提醒，保留任务记录")
                }
                StatusLabel(text: entry.status)
                Text(entry.body.isEmpty ? entry.status : entry.body).font(.system(size: 13)).foregroundStyle(quiet).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if entry.token != nil, entry.status == "待确认" {
                    HStack(spacing: 8) {
                        Button("允许一次") { if hub.decide(entry, "allow") { dismiss() } }.buttonStyle(MiraPrimaryButtonStyle())
                        Button("拒绝") { if hub.decide(entry, "deny") { dismiss() } }.buttonStyle(QuietButtonStyle())
                        Button("去 DSH 处理") { if hub.decide(entry, "defer") { dismiss() } }.buttonStyle(QuietButtonStyle())
                        Spacer(minLength: 0)
                    }.padding(.top, 7)
                } else {
                    HStack(spacing: 10) {
                        if entry.canSnooze {
                            Button("10 分钟后") { hub.snooze(entry.id); dismiss() }.buttonStyle(QuietButtonStyle())
                        } else if !entry.automaticallyArchived && hub.data.entries.contains(where: { $0.id == entry.id && !$0.done }) {
                            Button("标为已处理") {
                                if hub.finish(entry.id) { dismiss() }
                                else { hub.showMain?(); dismiss() }
                            }.buttonStyle(QuietButtonStyle())
                        }
                        Spacer(minLength: 0)
                        Button { hub.open(entry); dismiss() } label: { Label(entry.link.isEmpty ? "查看任务中心" : "打开原任务", systemImage: "arrow.up.right") }.buttonStyle(MiraPrimaryButtonStyle())
                    }.padding(.top, 7)
                }
            }
        }.padding(22).frame(width: 470, alignment: .leading).background(paper).foregroundStyle(ink)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(oatmeal, lineWidth: 1)).preferredColorScheme(.light)
    }
}
