import SwiftUI
import AppKit

struct PlanEditor: View {
    @ObservedObject var hub: Hub
    var plan: Plan?
    @Environment(\.dismiss) var dismiss
    @State var title = ""
    @State var notes = ""
    @State var time = Date()
    @State var days: Set<Int> = []
    @State var link = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(plan == nil ? "新建个人计划" : "编辑个人计划").font(.title2.bold())
            TextField("计划名称，例如：上肢 A · 40 分钟", text: $title)
            DatePicker("提醒时间", selection: $time, displayedComponents: .hourAndMinute)
            Text("重复星期 · 不选择表示每天").font(.caption).foregroundStyle(.secondary)
            HStack { ForEach([2,3,4,5,6,7,1], id: \.self) { day in Button(["", "日", "一", "二", "三", "四", "五", "六"][day]) { if days.contains(day) { days.remove(day) } else { days.insert(day) } }.tint(days.contains(day) ? teal : .gray).buttonStyle(.borderedProminent) } }
            Text("计划内容").font(.caption)
            TextEditor(text: $notes).frame(height: 100).border(Color.gray.opacity(0.2))
            TextField("ChatGPT 对话或 codex://threads/… 链接（可选）", text: $link)
            if !Links.valid(link) { Text("请填写 ChatGPT HTTPS 对话链接或 Codex 任务链接。").font(.caption).foregroundStyle(.red) }
            Text("如果今天的时间已过，保存后立即补提醒。每个计划每天只生成一条记录。").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("取消") { dismiss() }; Button("保存计划") {
                let parts = PlanTime.components(time)
                var p = Plan(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes, hour: parts.hour, minute: parts.minute, weekdays: Array(days), link: link)
                if let old = plan { p.id = old.id; p.created = old.created; p.enabled = old.enabled }
                if let i = hub.data.plans.firstIndex(where: { $0.id == p.id }) { hub.data.plans[i] = p } else { hub.data.plans.append(p) }
                if hub.save() { hub.tick(); dismiss() }
            }.buttonStyle(.borderedProminent).tint(teal).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !Links.valid(link)) }
        }.padding(28).frame(width: 490).background(paper).foregroundStyle(ink).preferredColorScheme(.light).tint(terracotta).onAppear { if let p = plan { title = p.title; notes = p.notes; time = PlanTime.date(hour: p.hour, minute: p.minute); days = Set(p.weekdays); link = p.link } }
    }
}

