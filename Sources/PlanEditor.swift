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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan == nil ? "新建个人计划" : "编辑个人计划")
                    .font(editorial(24))
                Spacer()
                Text("PERSONAL PLAN")
                    .font(ui(8.5, .semibold)).tracking(2).foregroundStyle(faint)
            }
            Rectangle().fill(oatmeal.opacity(0.7)).frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                label("计划名称")
                TextField("例如：上肢 A · 40 分钟", text: $title)
                    .textFieldStyle(.plain)
                    .font(ui(12))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(inputBackground)
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    label("提醒时间")
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .font(ui(12))
                        .foregroundStyle(ink)
                }
                VStack(alignment: .leading, spacing: 6) {
                    label("重复 · 不选表示每天")
                    HStack(spacing: 5) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                            Button {
                                if days.contains(day) { days.remove(day) } else { days.insert(day) }
                            } label: {
                                Text(["", "日", "一", "二", "三", "四", "五", "六"][day])
                                    .font(ui(10, .semibold))
                                    .frame(width: 26, height: 26)
                                    .foregroundStyle(days.contains(day) ? warmPaperInk : quiet)
                                    .background(Circle().fill(days.contains(day) ? terracotta : paper))
                                    .overlay(Circle().stroke(days.contains(day) ? Color.clear : oatmeal.opacity(0.8), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help(["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"][day])
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("计划内容")
                TextEditor(text: $notes)
                    .font(ui(12))
                    .foregroundStyle(ink)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(height: 88)
                    .background(inputBackground)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("关联链接 · 可选")
                TextField("ChatGPT 对话或 codex://threads/… 链接", text: $link)
                    .textFieldStyle(.plain)
                    .font(ui(11))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(inputBackground)
                if !Links.valid(link) {
                    Text("请填写 ChatGPT HTTPS 对话链接或 Codex 任务链接。")
                        .font(ui(9)).foregroundStyle(Color(red: 0.65, green: 0.20, blue: 0.15))
                }
            }

            Text("如果今天的时间已过，保存后立即补提醒。每个计划每天只生成一条记录。")
                .font(ui(9)).foregroundStyle(faint).lineSpacing(3)

            HStack(spacing: 8) {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(EditorialButtonStyle(kind: .text))
                Button("保存计划") { save() }
                    .buttonStyle(EditorialButtonStyle(kind: .rust))
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.42)
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 520)
        .background(cream)
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .tint(terracotta)
        .onAppear {
            if let p = plan {
                title = p.title
                notes = p.notes
                time = PlanTime.date(hour: p.hour, minute: p.minute)
                days = Set(p.weekdays)
                link = p.link
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Links.valid(link)
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(paper)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(oatmeal.opacity(0.75), lineWidth: 1))
    }

    private func label(_ text: String) -> some View {
        Text(text).font(ui(8.5, .semibold)).tracking(1.6).foregroundStyle(faint)
    }

    private func save() {
        let parts = PlanTime.components(time)
        var p = Plan(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                     notes: notes, hour: parts.hour, minute: parts.minute,
                     weekdays: Array(days), link: link)
        if let old = plan {
            p.id = old.id
            p.created = old.created
            p.enabled = old.enabled
        }
        if hub.savePlan(p) {
            hub.tick()
            dismiss()
        }
    }
}

extension Hub {
    func savePlan(_ plan: Plan) -> Bool {
        let previous = data.plans
        if let index = data.plans.firstIndex(where: { $0.id == plan.id }) {
            data.plans[index] = plan
        } else {
            data.plans.append(plan)
        }
        if save() { return true }
        data.plans = previous
        return false
    }
}
