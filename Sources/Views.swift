import SwiftUI
import AppKit

// MARK: - 字体

private let serifTypeScale: CGFloat = 1.08
private let numeralTypeScale: CGFloat = 1.06
private let uiTypeScale: CGFloat = 1.15

func editorial(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .custom("Songti SC", size: size * serifTypeScale).weight(weight)
}

func numeral(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .custom("Georgia", size: size * numeralTypeScale).weight(weight)
}

func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size * uiTypeScale, weight: weight)
}

private let rustGradient = LinearGradient(
    colors: [Color(red: 0.706, green: 0.275, blue: 0.122),
             Color(red: 0.541, green: 0.196, blue: 0.071)],
    startPoint: .topLeading, endPoint: .bottomTrailing)
private let peachWash = Color(red: 0.976, green: 0.906, blue: 0.855)
private let lilacWash = Color(red: 0.929, green: 0.894, blue: 0.945)
let warmPaperInk = Color(red: 0.996, green: 0.969, blue: 0.945)

// MARK: - 按钮与标签

struct EditorialButtonStyle: ButtonStyle {
    enum Kind { case ink, rust, cream, glass, outline, text, lightText }
    var kind: Kind = .outline

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ui(11.5, .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(background(pressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(stroke)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private var horizontalPadding: CGFloat { kind == .text || kind == .lightText ? 2 : 12 }
    private var verticalPadding: CGFloat { kind == .text || kind == .lightText ? 3 : 7 }

    private var foreground: Color {
        switch kind {
        case .ink, .rust, .glass: return warmPaperInk
        case .cream: return terracotta
        case .outline, .text: return quiet
        case .lightText: return Color(red: 0.929, green: 0.745, blue: 0.667)
        }
    }

    @ViewBuilder private func background(pressed: Bool) -> some View {
        switch kind {
        case .ink: RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pressed ? ink2 : ink)
        case .rust: RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pressed ? Color(red: 0.42, green: 0.15, blue: 0.06) : terracotta)
        case .cream: RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(red: 1, green: 0.953, blue: 0.902))
        case .glass: RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.14))
        case .outline: RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.clear)
        case .text, .lightText: Color.clear
        }
    }

    @ViewBuilder private var stroke: some View {
        switch kind {
        case .outline:
            RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(oatmeal, lineWidth: 1)
        case .glass:
            RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1)
        default:
            EmptyView()
        }
    }
}

struct StatusTag: View {
    let text: String
    var inverted = false

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(inverted ? warmPaperInk.opacity(0.7) : foreground).frame(width: 4, height: 4)
            Text(text).font(ui(9, .semibold)).tracking(0.4)
        }
        .foregroundStyle(inverted ? warmPaperInk.opacity(0.92) : foreground)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(inverted ? Color.white.opacity(0.14) : backgroundWash))
        .overlay(Capsule().stroke(inverted ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1))
    }

    static func palette(for text: String) -> (Color, Color) {
        switch text {
        case "待确认": return (butterInk, butter)
        case "待补充信息": return (plum, lilacWash)
        case "本轮结束": return (Color(red: 0.298, green: 0.400, blue: 0.298), sageWash)
        case "运行中": return (sage, sageWash)
        case "待完成": return (Color(red: 0.541, green: 0.278, blue: 0.114), peachWash)
        case "已中断": return (Color(red: 0.541, green: 0.278, blue: 0.114), peachWash)
        case "任务失败": return (Color(red: 0.62, green: 0.19, blue: 0.15), Color(red: 0.972, green: 0.894, blue: 0.878))
        case "已拦截": return (plum, lilacWash)
        case "已达上限": return (plum, lilacWash)
        default: return (quiet, oatmeal.opacity(0.55))
        }
    }
    static func ink(for text: String) -> Color { palette(for: text).0 }
    static func wash(for text: String) -> Color { palette(for: text).1 }

    private var palette: (Color, Color) { Self.palette(for: text) }
    private var foreground: Color { palette.0 }
    private var backgroundWash: Color { palette.1 }
}

struct SourceGlyph: View {
    let source: String
    var inverted = false

    var body: some View {
        Text(glyph)
            .font(numeral(10, .semibold))
            .foregroundStyle(inverted ? warmPaperInk : glyphInk)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(inverted ? Color.white.opacity(0.16) : glyphWash))
    }

    private var glyph: String {
        if source.hasPrefix("DSH") { return "D" }
        if source.contains("Codex") { return "C" }
        if source == "个人计划" { return "M" }
        return String(source.prefix(1))
    }
    private var glyphInk: Color {
        if source.hasPrefix("DSH") { return sage }
        if source.contains("Codex") { return Color(red: 0.416, green: 0.337, blue: 0.616) }
        if source == "个人计划" { return Color(red: 0.541, green: 0.278, blue: 0.114) }
        return quiet
    }
    private var glyphWash: Color {
        if source.hasPrefix("DSH") { return sageWash }
        if source.contains("Codex") { return Color(red: 0.918, green: 0.902, blue: 0.965) }
        if source == "个人计划" { return peachWash }
        return oatmeal.opacity(0.45)
    }
}

// MARK: - Hub 辅助

extension Hub {
    var todayPlans: [Plan] {
        let day = Calendar.current.component(.weekday, from: Date())
        return allPlans.filter { $0.enabled && ($0.weekdays.isEmpty || $0.weekdays.contains(day)) }
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }
    var running: [Entry] { data.entries.filter { !$0.done && $0.status == "运行中" } }
    func todayEntry(_ plan: Plan) -> Entry? {
        guard let occurrence = Schedule.due(plan, now: Date()) else { return nil }
        return data.entries.first { $0.id == occurrence.id }
    }
}

// MARK: - 主界面

struct HubView: View {
    @ObservedObject var hub: Hub
    @State var editing: Plan?
    @State var adding = false
    @State private var agendaTask: TaskSelection?
    @State private var completedOpen = true
    @State private var recordFilter: RecordFilter = .all
    @State private var expandedRounds: Set<String> = []
    @State private var seededHistory = false

    private var pending: [Entry] { hub.active.filter { $0.source != "个人计划" } }
    private var pendingCount: Int { pending.count }
    private var approvals: Int { pending.filter { $0.status == "待确认" && $0.token != nil }.count }

    var body: some View {
        VStack(spacing: 0) {
            masthead
            ruleRow
            if !hub.error.isEmpty {
                banner(hub.error, color: Color(red: 0.65, green: 0.20, blue: 0.15)) { hub.error = "" }
            }
            if !hub.notice.isEmpty {
                banner(hub.notice, color: ink2) { hub.notice = "" }
            }
            content
            footer
        }
        .background(cream)
        .foregroundStyle(ink)
        .frame(minWidth: 1120, minHeight: 700)
        .preferredColorScheme(.light)
        .tint(terracotta)
        .sheet(isPresented: $adding) { PlanEditor(hub: hub, plan: editing) }
        .sheet(item: $agendaTask) { selection in
            TaskEditor(hub: hub, taskID: selection.id)
        }
        .sheet(isPresented: $hub.showWatchEditor) {
            WebWatchEditor(hub: hub, watchID: hub.editingWatchID)
                .id(hub.editingWatchID ?? "new-web-watch")
        }
    }

    // MARK: 顶部

    private var masthead: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("mira").font(numeral(36)).foregroundStyle(ink)
                    Text(".").font(numeral(36)).foregroundStyle(terracotta)
                }
                Text("TODAY, SLOWLY")
                    .font(ui(9, .semibold)).tracking(3.2).foregroundStyle(faint)
            }
            Spacer()
            HStack(spacing: 24) {
                ForEach(["今日", "任务库", "监控", "计划", "记录"], id: \.self) { tab in
                    navItem(tab)
                }
                Rectangle().fill(oatmeal).frame(width: 1, height: 14).padding(.horizontal, 2)
                iconButton("gearshape") { hub.section = "设置" }
                    .help("连接与设置")
                    .accessibilityLabel("连接与设置")
            }
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 44)
        .padding(.top, 4)
    }

    private func navItem(_ tab: String) -> some View {
        Button { hub.section = tab } label: {
            VStack(spacing: 7) {
                Text(tab)
                    .font(ui(12.5, hub.section == tab ? .semibold : .regular))
                    .tracking(0.6)
                    .foregroundStyle(hub.section == tab ? ink : quiet)
                Rectangle()
                    .fill(hub.section == tab ? terracotta : Color.clear)
                    .frame(width: 20, height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换到\(tab)")
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(quiet)
                .frame(width: 28, height: 28)
                .background(Circle().fill(paper.opacity(0.65)))
                .overlay(Circle().stroke(oatmeal, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var ruleRow: some View {
        HStack(spacing: 14) {
            Text(dateLine).font(numeral(9.5)).tracking(2).foregroundStyle(faint)
            Rectangle().fill(oatmeal.opacity(0.75)).frame(height: 1)
            HStack(spacing: 6) {
                Circle().fill(connectionColor).frame(width: 5, height: 5)
                Text(connectionText).font(ui(9.5)).foregroundStyle(faint)
            }
        }
        .padding(.horizontal, 44)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private func banner(_ text: String, color: Color, close: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(text).font(ui(11)).foregroundStyle(color).lineLimit(2)
            Spacer()
            Button("关闭", action: close).buttonStyle(EditorialButtonStyle(kind: .text))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.16), lineWidth: 1))
        .padding(.horizontal, 44)
        .padding(.top, 4)
    }

    // MARK: 页面切换

    @ViewBuilder private var content: some View {
        switch hub.section {
        case "任务库": TaskLibraryPage(hub: hub)
        case "监控": WebWatchPage(hub: hub)
        case "计划": plansPage
        case "记录": historyPage
        case "设置": settingsPage
        default: todayPage
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                Text("让重要的事，找到你。").font(editorial(10.5)).foregroundStyle(faint)
                Text("— mira").font(numeral(10.5)).italic().foregroundStyle(quiet)
            }
            Spacer()
            Text("MIRA 0.2 · LOCAL FIRST")
                .font(numeral(8.5)).tracking(1.8).foregroundStyle(faint)
        }
        .padding(.horizontal, 44)
        .padding(.top, 10)
        .padding(.bottom, 13)
    }

    // MARK: 今日

    private var todayPage: some View {
        HStack(alignment: .top, spacing: 0) {
            dateRail.frame(width: 148).padding(.trailing, 22)
            columnLine
            todayFeed.padding(.leading, 26).padding(.trailing, 24).frame(maxWidth: .infinity)
            columnLine
            agendaRail.frame(width: 290).padding(.leading, 24)
        }
        .padding(.horizontal, 44)
        .padding(.top, 14)
        .frame(maxHeight: .infinity)
    }

    private var columnLine: some View {
        Rectangle().fill(oatmeal.opacity(0.7))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private var todayFeed: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(pendingCount == 0 ? sage : terracotta).frame(width: 5, height: 5)
                Text(kicker).font(ui(9, .semibold)).tracking(2.2).foregroundStyle(faint)
            }
            Text(greetingHeadline)
                .font(editorial(30))
                .lineSpacing(7)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
            Text(lede)
                .font(ui(11.5))
                .foregroundStyle(quiet)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if !hub.running.isEmpty {
                runningBand.padding(.top, 12)
            }
            sectionHeader.padding(.top, 14).padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Color.clear.frame(height: 1).id("feed-top")
                        feedContent
                    }
                    .padding(.bottom, 4)
                }
                .onAppear {
                    DispatchQueue.main.async { proxy.scrollTo("feed-top", anchor: .top) }
                }
                .onChange(of: pending.first?.id) { _ in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("feed-top", anchor: .top) }
                }
                .onChange(of: completedOpen) { open in
                    guard open else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("completed-section", anchor: .top)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [cream.opacity(0), cream], startPoint: .top, endPoint: .bottom)
                    .frame(height: 18)
                    .allowsHitTesting(false)
            }

            bottomLine
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("等你决定").font(editorial(15, .semibold)).tracking(1.4)
            Text(String(format: "%02d", pendingCount)).font(numeral(10)).foregroundStyle(terracotta)
            Spacer()
            Button { hub.section = "记录" } label: {
                HStack(spacing: 3) {
                    Text("全部记录")
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(EditorialButtonStyle(kind: .text))
        }
    }

    @ViewBuilder private var feedContent: some View {
        if pending.isEmpty {
            emptyFeed
        } else {
            ForEach(Array(pending.enumerated()), id: \.element.id) { index, entry in
                EntryCard(hub: hub, entry: entry,
                          highlighted: index == 0 && entry.status == "待确认" && entry.token != nil)
            }
        }
        if !completedToday.isEmpty {
            completedSection.padding(.top, 6)
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { completedOpen.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(faint)
                        .rotationEffect(.degrees(completedOpen ? 90 : 0))
                    Text("今日已完成").font(ui(9, .semibold)).tracking(2).foregroundStyle(faint)
                    Text("\(completedToday.count)").font(numeral(9)).foregroundStyle(faint)
                    Spacer()
                    Text(completedOpen ? "收起" : "展开").font(ui(9)).foregroundStyle(faint)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if completedOpen {
                VStack(spacing: 0) {
                    ForEach(Array(completedToday.prefix(7))) { entry in
                        CompletedRow(hub: hub, entry: entry)
                    }
                }
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(paper.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(oatmeal.opacity(0.55), lineWidth: 1))
                .padding(.top, 4)

                if completedToday.count > 7 {
                    Button { hub.section = "记录" } label: {
                        HStack(spacing: 4) {
                            Text("Show more")
                            Text("· 还有 \(completedToday.count - 7) 条").foregroundStyle(faint)
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        }
                        .font(ui(9.5, .medium))
                        .foregroundStyle(terracotta)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 9)
                    .padding(.leading, 2)
                }
            }
        }
        .id("completed-section")
    }

    private var runningBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(terracotta).frame(width: 5, height: 5)
                Text("正在进行").font(ui(9, .semibold)).tracking(2).foregroundStyle(faint)
                Text("\(hub.running.count)").font(numeral(9)).foregroundStyle(terracotta)
                Spacer()
            }
            ForEach(hub.running.prefix(3)) { entry in
                RunningStrip(hub: hub, entry: entry)
            }
            if hub.running.count > 3 {
                Text("还有 \(hub.running.count - 3) 项正在进行")
                    .font(ui(9)).foregroundStyle(faint).padding(.leading, 2)
            }
        }
    }

    private var emptyFeed: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("都处理完了。").font(editorial(21)).foregroundStyle(ink)
            Text("AI 需要你时，会先到这里。也可以在右侧安排今天的节奏。")
                .font(ui(11)).foregroundStyle(quiet).lineSpacing(4)
            if hub.data.lastEvent == nil {
                Button { hub.section = "设置" } label: {
                    HStack(spacing: 5) {
                        Text(hub.installed ? "查看连接状态" : "配置本机连接")
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(EditorialButtonStyle(kind: .ink))
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomLine: some View {
        VStack(spacing: 0) {
            Rectangle().fill(oatmeal.opacity(0.8)).frame(height: 1)
            HStack(spacing: 7) {
                Circle().fill(sage).frame(width: 5, height: 5)
                Text("今天已完成 \(completedToday.count) 件 · 还有 \(pendingCount) 件等你决定")
                    .font(ui(9.5)).foregroundStyle(faint)
                Spacer()
                Button { hub.section = "记录" } label: {
                    HStack(spacing: 3) {
                        Text("在记录里回看")
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                    }
                }
                .buttonStyle(EditorialButtonStyle(kind: .text))
            }
            .padding(.top, 8)
        }
        .padding(.top, 8)
    }

    // MARK: 左栏：日期

    private var dateRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dayString).font(editorial(74)).tracking(-2)
            Text(weekdayString).font(ui(10.5, .semibold)).tracking(3)
                .foregroundStyle(terracotta).padding(.top, 6)
            Text(monthString).font(numeral(9.5)).tracking(1.8)
                .foregroundStyle(faint).padding(.top, 4)

            dashedRule.padding(.vertical, 15)

            metric("TODAY", value: "\(agendaDone)", unit: " / \(agendaTotal)", ratio: agendaRatio)
            metric("回应", value: "\(pendingCount)", unit: " 件", ratio: nil)
                .padding(.top, 14)
            if approvals > 0 {
                metric("待批准", value: "\(approvals)", unit: " 次", ratio: nil)
                    .padding(.top, 14)
            }

            Spacer(minLength: 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var dashedRule: some View {
        Rectangle().fill(oatmeal.opacity(0.8)).frame(height: 1)
    }

    private func metric(_ label: String, value: String, unit: String, ratio: Double?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(ui(8.5, .semibold)).tracking(2).foregroundStyle(faint)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value).font(editorial(23)).foregroundStyle(ink)
                Text(unit).font(ui(9.5)).foregroundStyle(quiet)
            }
            .padding(.top, 2)
            if let ratio {
                ZStack(alignment: .leading) {
                    Capsule().fill(oatmeal.opacity(0.55)).frame(width: 92, height: 3)
                    Capsule().fill(terracotta).frame(width: max(0, min(92, 92 * ratio)), height: 3)
                }
                .padding(.top, 7)
            }
        }
    }


    // MARK: 右栏：安排

    private var agendaRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text("今日安排").font(editorial(15, .semibold)).tracking(1.4)
                Spacer()
                Text("\(agendaDone) / \(agendaTotal)")
                    .font(numeral(9)).foregroundStyle(faint)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(oatmeal, lineWidth: 1))
            }

            ringRow.padding(.top, 10)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 5) { agendaRows }
                    .padding(.top, 8)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            addPlanButton.padding(.top, 8)
            weekChart.padding(.top, 10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var ringRow: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(oatmeal.opacity(0.55), lineWidth: 5)
                Circle().trim(from: 0, to: max(0.001, agendaRatio))
                    .stroke(terracotta, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text("节奏").font(ui(8.5, .semibold)).tracking(2).foregroundStyle(faint)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int((agendaRatio * 100).rounded()))").font(editorial(22))
                    Text("%").font(ui(9)).foregroundStyle(quiet)
                }
                Text(agendaTotal == 0 ? "今天还没有安排" : "已完成 \(agendaDone) 项安排")
                    .font(ui(9)).foregroundStyle(quiet)
            }
        }
    }

    @ViewBuilder private var agendaRows: some View {
        if agendaTotal == 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("今天还没有安排。").font(editorial(17))
                Text("添加一件小事，到时间 MIRA 会提醒你。")
                    .font(ui(10.5)).foregroundStyle(quiet).lineSpacing(3)
                Button { editing = nil; adding = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 8, weight: .bold))
                        Text("添加一个安排")
                    }
                }
                .buttonStyle(EditorialButtonStyle(kind: .outline))
                .padding(.top, 6)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(pinnedTasks) { task in pinnedTaskRow(task) }
            ForEach(hub.todayPlans) { plan in planRow(plan) }
        }
    }

    private func pinnedTaskRow(_ task: TaskItem) -> some View {
        let done = task.status == .done
        return HStack(alignment: .top, spacing: 9) {
            Button { hub.completeTask(task.id) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(done ? sage : quiet)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(done)
            .accessibilityLabel("\(done ? "已完成" : "完成任务") \(task.title)")
            Button { agendaTask = TaskSelection(id: task.id) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(editorial(13.5))
                        .foregroundStyle(done ? faint : ink2)
                        .strikethrough(done)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let due = task.due, !done {
                        Text("截止 \(due.formatted(.dateTime.month().day()))")
                            .font(ui(9)).foregroundStyle(quiet)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.title)
            Image(systemName: "pin.fill")
                .font(.system(size: 9))
                .foregroundStyle(done ? faint : terracotta)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(paper.opacity(done ? 0.45 : 0.8), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func planRow(_ plan: Plan) -> some View {
        let entry = hub.todayEntry(plan)
        let done = entry?.done == true
        let isDue = entry != nil && !done
        HStack(alignment: .top, spacing: 9) {
            Text(String(format: "%02d:%02d", plan.hour, plan.minute))
                .font(numeral(10.5))
                .foregroundStyle(done ? faint : (isDue ? terracotta : quiet))
                .frame(width: 38, alignment: .leading)
                .padding(.top, 2)
            Circle()
                .fill(done ? sage : (isDue ? terracotta : Color.clear))
                .frame(width: 6, height: 6)
                .overlay(Circle().stroke(done || isDue ? Color.clear : faint.opacity(0.7), lineWidth: 1))
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.title)
                    .font(editorial(13.5))
                    .foregroundStyle(done ? faint : ink2)
                    .strikethrough(done, color: faint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if done {
                    Text("已完成").font(ui(9)).foregroundStyle(quiet)
                } else if let e = entry {
                    HStack(spacing: 6) {
                        Button("完成") { hub.finish(e.id) }
                            .buttonStyle(EditorialButtonStyle(kind: .ink))
                        Button("延后") { hub.snooze(e.id) }
                            .buttonStyle(EditorialButtonStyle(kind: .outline))
                    }
                    .padding(.top, 4)
                } else if plan.origin != nil {
                    Text("桌面同步 · 到时提醒").font(ui(9)).foregroundStyle(faint)
                } else {
                    Text("到时提醒").font(ui(9)).foregroundStyle(faint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDue ? paper : Color.clear)
        )
        .overlay {
            if isDue {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(oatmeal.opacity(0.9), lineWidth: 1)
            }
        }
    }

    private var addPlanButton: some View {
        VStack(spacing: 0) {
            Rectangle().fill(oatmeal.opacity(0.8)).frame(height: 1)
            Button { editing = nil; adding = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    Text("添加一个安排").font(ui(10.5, .medium))
                    Spacer()
                }
                .foregroundStyle(terracotta)
                .padding(.top, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("这一周").font(ui(8.5, .semibold)).tracking(2).foregroundStyle(faint)
                Spacer()
                Text("\(weekTotal) 件事").font(ui(9)).foregroundStyle(quiet)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    let count = weekCounts[index]
                    let height = weekMax == 0 ? 4 : 4 + 20 * CGFloat(count) / CGFloat(weekMax)
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == 6 ? terracotta : Color(red: 0.788, green: 0.718, blue: 0.635))
                            .frame(height: height)
                        Text(weekLetters[index])
                            .font(ui(8)).foregroundStyle(index == 6 ? terracotta : faint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 40, alignment: .bottom)
            .padding(.top, 9)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(red: 0.929, green: 0.894, blue: 0.839)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(oatmeal.opacity(0.55), lineWidth: 1))
    }

    // MARK: 计划

    private var plansPage: some View {
        HStack(alignment: .top, spacing: 0) {
            dateRail.frame(width: 148).padding(.trailing, 22)
            columnLine
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("计划").font(editorial(30))
                    Spacer()
                    Button { editing = nil; adding = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                            Text("新建计划")
                        }
                    }
                    .buttonStyle(EditorialButtonStyle(kind: .ink))
                }
                Text("每天或每周重复 · 当天错过补发 · 完成后不再打扰")
                    .font(ui(11)).foregroundStyle(quiet).padding(.top, 5)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) { planCards }
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }
            }
            .padding(.leading, 26).padding(.trailing, 24)
            .frame(maxWidth: .infinity)
            columnLine
            VStack(alignment: .leading, spacing: 12) {
                weekChart
                desktopCard
                Spacer(minLength: 0)
            }
            .frame(width: 262)
            .padding(.leading, 24)
        }
        .padding(.horizontal, 44)
        .padding(.top, 14)
        .frame(maxHeight: .infinity)
    }

    private var desktopCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(hub.scheduleLoaded ? sage : faint).frame(width: 5, height: 5)
                Text("桌面计划").font(editorial(13, .semibold))
            }
            Text(hub.scheduleStatus)
                .font(ui(9)).foregroundStyle(quiet).lineSpacing(3).lineLimit(3)
            Button("立即同步") { hub.syncSchedules(); hub.tick() }
                .buttonStyle(EditorialButtonStyle(kind: .outline))
            Text("读取本机 Codex automations；时间调整以来源应用为准。")
                .font(ui(8.5)).foregroundStyle(faint).lineSpacing(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(paper))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(oatmeal.opacity(0.6), lineWidth: 1))
    }

    @ViewBuilder private var planCards: some View {
        if hub.allPlans.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("还没有个人计划。").font(editorial(20))
                Text("从一件小事开始，比如晚饭后散步二十分钟。")
                    .font(ui(11)).foregroundStyle(quiet)
                Button("新建第一个计划") { editing = nil; adding = true }
                    .buttonStyle(EditorialButtonStyle(kind: .ink))
                    .padding(.top, 3)
            }
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(hub.allPlans) { plan in
                PlanCard(hub: hub, plan: plan) {
                    editing = plan
                    adding = true
                }
            }
        }
    }

    // MARK: 记录

    private var historyPage: some View {
        let snapshot = Date()
        let rounds = HistoryGrouping.rounds(
            from: hub.data.entries.filter { Schedule.inHistory($0, now: snapshot) })
        return HStack(alignment: .top, spacing: 0) {
            dateRail.frame(width: 148).padding(.trailing, 22)
            columnLine
            VStack(alignment: .leading, spacing: 0) {
                Text("记录").font(editorial(30))
                Text("每一步，都有迹可循；同一轮只写一行。")
                    .font(ui(10)).foregroundStyle(quiet).padding(.top, 6)
                historyFilterBar(rounds).padding(.top, 14)
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        historyContent(rounds)
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 26)
                }
            }
            .padding(.leading, 26)
            .frame(maxWidth: 860, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 44)
        .padding(.top, 14)
        .frame(maxHeight: .infinity)
        .onAppear { seedExpandedRound(rounds) }
    }

    private func seedExpandedRound(_ rounds: [HistoryRound]) {
        guard !seededHistory else { return }
        seededHistory = true
        if let newest = rounds.first { expandedRounds.insert(newest.id) }
    }

    private func toggleRound(_ round: HistoryRound) {
        if expandedRounds.contains(round.id) {
            expandedRounds.remove(round.id)
        } else {
            expandedRounds.insert(round.id)
        }
    }

    private func historyFilterBar(_ rounds: [HistoryRound]) -> some View {
        HStack(spacing: 6) {
            ForEach(RecordFilter.allCases) { filter in
                let count = rounds.filter(filter.matches).count
                let on = recordFilter == filter
                Button { recordFilter = filter } label: {
                    HStack(spacing: 5) {
                        Text(filter.title).font(ui(9.5, .semibold))
                        Text("\(count)").font(numeral(8.5))
                    }
                    .foregroundStyle(on ? warmPaperInk : quiet)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on ? ink : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(on ? Color.clear : oatmeal, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(filter.title)，\(count) 轮")
            }
            Spacer(minLength: 8)
            Text("共 \(rounds.count) 轮").font(numeral(8.5)).foregroundStyle(faint)
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(oatmeal.opacity(0.7)).frame(height: 1)
        }
    }

    @ViewBuilder private func historyContent(_ rounds: [HistoryRound]) -> some View {
        let filtered = rounds.filter(recordFilter.matches)
        if rounds.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("还没有历史记录。").font(editorial(20))
                Text("本轮结束、已处理与已过期的提醒会保存在这里。")
                    .font(ui(11)).foregroundStyle(quiet)
            }
            .padding(.top, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if filtered.isEmpty {
            Text("没有「\(recordFilter.title)」的记录。")
                .font(ui(11)).foregroundStyle(quiet)
                .padding(.top, 40)
        } else {
            ForEach(dayBuckets(filtered)) { bucket in
                historyDay(bucket)
            }
        }
    }

    private func dayBuckets(_ rounds: [HistoryRound]) -> [HistoryDay] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [HistoryRound]] = [:]
        for round in rounds {
            let day = calendar.startOfDay(for: round.end)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(round)
        }
        return order.map { HistoryDay(id: $0, rounds: buckets[$0] ?? []) }
    }

    private func historyDay(_ bucket: HistoryDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(RecordText.day(bucket.id)).font(editorial(11.5)).foregroundStyle(ink)
                Text(RecordText.dayNote(bucket.id)).font(ui(9)).foregroundStyle(faint)
                Rectangle().fill(oatmeal.opacity(0.55)).frame(height: 1)
                Text("\(bucket.rounds.count) 轮 · \(bucket.rounds.reduce(0) { $0 + $1.count }) 条")
                    .font(numeral(8.5)).foregroundStyle(faint)
            }
            .padding(.top, 16)
            .padding(.bottom, 4)

            ZStack(alignment: .topLeading) {
                Rectangle().fill(oatmeal.opacity(0.65))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
                    .offset(x: 56.5)
                VStack(spacing: 0) {
                    ForEach(bucket.rounds) { round in
                        HistoryRoundRow(hub: hub, round: round,
                                        expanded: expandedRounds.contains(round.id)) {
                            toggleRound(round)
                        }
                    }
                }
            }
        }
    }

    // MARK: 设置

    private var settingsPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("连接与设置").font(editorial(30))
                    Spacer()
                    Text("本地优先 · 无服务器").font(ui(9.5)).foregroundStyle(faint)
                }
                settings.padding(.top, 18)
            }
            .padding(.horizontal, 44)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: 1020, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 日期与状态

    private var now: Date { Date() }
    private var dayString: String { String(Calendar.current.component(.day, from: now)) }
    private var weekdayString: String {
        let index = Calendar.current.component(.weekday, from: now) - 1
        return ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][max(0, min(6, index))]
    }
    private var monthString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        return formatter.string(from: now).uppercased()
    }
    private var dateLine: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return String(format: "%02d — %02d — %d", parts.day ?? 1, parts.month ?? 1, parts.year ?? 2026)
    }

    private var connectionColor: Color {
        if hub.data.lastEvent != nil { return sage }
        return hub.installed || hub.dshInstalled ? Color(red: 0.75, green: 0.57, blue: 0.20) : faint
    }
    private var connectionText: String {
        if hub.data.lastEvent != nil { return "已收到事件 · 本地记录" }
        return hub.installed || hub.dshInstalled ? "已配置 · 等待第一条事件" : "尚未连接 · 本地可用"
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 5 { return "夜深了" }
        if hour < 12 { return "早上好" }
        if hour < 14 { return "中午好" }
        if hour < 19 { return "下午好" }
        return "晚上好"
    }

    private var greetingHeadline: String {
        switch pendingCount {
        case 0: return "\(greeting)，今天没有待回应的事。"
        case 1: return "\(greeting)，先把一件事回完。"
        default: return "\(greeting)，先把 \(pendingCount) 件事回完。"
        }
    }

    private var kicker: String {
        if pendingCount == 0 { return "ALL CLEAR · 今日已清空" }
        if pendingCount == 1 { return "1 THING AWAITS YOUR REPLY" }
        return "\(pendingCount) THINGS AWAIT YOUR REPLY"
    }

    private var lede: String {
        guard let first = pending.first else {
            return "AI 需要你的判断时，会把消息送到这里。右侧的安排会按时提醒，不急。"
        }
        let minutes = max(0, Int(now.timeIntervalSince(first.date) / 60))
        let waited = minutes < 1 ? "刚刚抵达" : "已等待 \(minutes) 分钟"
        var text = "最早一条来自 \(first.source)，\(waited)。"
        if let approval = pending.first(where: { $0.token != nil }), let expires = approval.expires {
            text += " 其中一次审批会在 \(expires.formatted(date: .omitted, time: .shortened)) 自动交还 DSH。"
        }
        return text
    }

    private var completedToday: [Entry] {
        hub.data.entries
            .filter { ($0.done || $0.automaticallyArchived) && Calendar.current.isDateInToday($0.date) }
            .sorted { $0.date > $1.date }
    }

    private var pinnedTasks: [TaskItem] {
        TaskLibrary.pinnedForToday(hub.data.tasks, now: now)
    }
    private var agendaTotal: Int { hub.todayPlans.count + pinnedTasks.count }
    private var agendaDone: Int {
        hub.todayPlans.filter { hub.todayEntry($0)?.done == true }.count
            + pinnedTasks.filter { $0.status == .done }.count
    }
    private var agendaRatio: Double {
        agendaTotal == 0 ? 0 : Double(agendaDone) / Double(agendaTotal)
    }

    private var weekDates: [Date] {
        (0..<7).reversed().compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: now)
        }
    }
    private var weekCounts: [Int] {
        weekDates.map { day in
            hub.data.entries.filter {
                ($0.done || $0.automaticallyArchived) && Calendar.current.isDate($0.date, inSameDayAs: day)
            }.count
        }
    }
    private var weekTotal: Int { weekCounts.reduce(0, +) }
    private var weekMax: Int { weekCounts.max() ?? 0 }
    private var weekLetters: [String] {
        weekDates.map { day in
            let index = Calendar.current.component(.weekday, from: day) - 1
            return ["日", "一", "二", "三", "四", "五", "六"][max(0, min(6, index))]
        }
    }
}

// MARK: - 消息卡片

struct EntryCard: View {
    @ObservedObject var hub: Hub
    let entry: Entry
    var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                SourceGlyph(source: entry.source, inverted: highlighted)
                Text(entry.source)
                    .font(ui(10, .semibold))
                    .foregroundStyle(highlighted ? warmPaperInk.opacity(0.82) : quiet)
                if let detail = detail {
                    Text(detail)
                        .font(ui(9))
                        .foregroundStyle(highlighted ? warmPaperInk.opacity(0.5) : faint)
                }
                Spacer(minLength: 6)
                StatusTag(text: entry.status, inverted: highlighted)
                Text(entry.date.formatted(date: .omitted, time: .shortened))
                    .font(numeral(9)).foregroundStyle(highlighted ? warmPaperInk.opacity(0.55) : faint)
            }

            Text(entry.displayTitle)
                .font(editorial(19))
                .lineSpacing(4)
                .foregroundStyle(highlighted ? warmPaperInk : ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(ui(11))
                    .lineSpacing(4)
                    .foregroundStyle(highlighted ? warmPaperInk.opacity(0.66) : quiet)
                    .lineLimit(2)
                    .padding(.top, 5)
            }

            actions.padding(.top, 11)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 13)
        .background {
            // Shadow the rounded background without compositing the text and controls.
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape.fill(highlighted ? AnyShapeStyle(rustGradient) : AnyShapeStyle(paper))
                .shadow(color: highlighted ? terracotta.opacity(0.22) : Color.black.opacity(0.035),
                        radius: highlighted ? 16 : 5, x: 0, y: highlighted ? 9 : 2)
                .overlay {
                    if !highlighted {
                        shape.strokeBorder(oatmeal.opacity(0.7), lineWidth: 1)
                    }
                }
        }
    }

    private var detail: String? {
        guard let thread = entry.thread, !thread.isEmpty else { return nil }
        return "会话 " + String(thread.prefix(10))
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 7) {
            if entry.codexID != nil {
                CodexApprovalControls(hub: hub, entry: entry)
            } else if entry.status == "待确认", entry.token != nil {
                Button("允许一次") { hub.decide(entry, "allow") }
                    .buttonStyle(EditorialButtonStyle(kind: highlighted ? .cream : .rust))
                Button("拒绝") { hub.decide(entry, "deny") }
                    .buttonStyle(EditorialButtonStyle(kind: highlighted ? .glass : .outline))
                Button("去 DSH 处理") { hub.decide(entry, "defer") }
                    .buttonStyle(EditorialButtonStyle(kind: highlighted ? .lightText : .text))
            } else {
                if !entry.link.isEmpty {
                    Button { hub.open(entry) } label: {
                        HStack(spacing: 4) {
                            Text("打开原任务")
                            Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .buttonStyle(EditorialButtonStyle(kind: .ink))
                }
                if entry.canSnooze {
                    Button("10 分钟后") { hub.snooze(entry.id) }
                        .buttonStyle(EditorialButtonStyle(kind: .outline))
                }
                if !entry.automaticallyArchived && !entry.courseUpdate {
                    Button(entry.source == "个人计划" ? "完成" : "标为已处理") { hub.finish(entry.id) }
                        .buttonStyle(EditorialButtonStyle(kind: .text))
                }
            }
            Spacer(minLength: 4)
            hint
        }
    }

    @ViewBuilder private var hint: some View {
        if entry.status == "待确认", entry.token != nil, let expires = entry.expires {
            CountdownHint(expires: expires, highlighted: highlighted)
        } else {
            Text(waitedText)
                .font(numeral(9))
                .foregroundStyle(highlighted ? warmPaperInk.opacity(0.5) : faint)
        }
    }

    private var waitedText: String {
        let minutes = max(0, Int(Date().timeIntervalSince(entry.date) / 60))
        if minutes < 1 { return "刚刚" }
        if minutes < 60 { return "已等待 \(minutes) 分钟" }
        return "已等待 \(minutes / 60) 小时"
    }
}

struct CountdownHint: View {
    let expires: Date
    var highlighted = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(expires.timeIntervalSince(context.date)))
            HStack(spacing: 5) {
                Image(systemName: "clock").font(.system(size: 8, weight: .medium))
                Text(remaining > 0 ? "\(remaining) 秒后交还" : "正在交还 DSH")
            }
        }
        .font(numeral(9))
        .foregroundStyle(highlighted ? warmPaperInk.opacity(0.55) : faint)
    }
}

struct RunningStrip: View {
    @ObservedObject var hub: Hub
    let entry: Entry

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(terracotta).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(editorial(14)).foregroundStyle(ink2).lineLimit(1)
                Text("\(entry.source) · 已运行 \(elapsed) 分钟")
                    .font(ui(9)).foregroundStyle(faint)
            }
            Spacer()
            if !entry.link.isEmpty {
                Button("打开") { hub.open(entry) }
                    .buttonStyle(EditorialButtonStyle(kind: .text))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(paper.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(oatmeal.opacity(0.6), lineWidth: 1))
    }

    private var elapsed: Int {
        max(0, Int(Date().timeIntervalSince(entry.date) / 60))
    }
}

struct CompletedRow: View {
    @ObservedObject var hub: Hub
    let entry: Entry

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(sage)
                .frame(width: 15, height: 15)
                .background(Circle().fill(sageWash))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayTitle)
                    .font(editorial(13.5))
                    .foregroundStyle(ink2)
                    .lineLimit(1)
                Text("\(entry.source) · \(entry.date.formatted(date: .omitted, time: .shortened)) · \(entry.historyStatus)")
                    .font(ui(8.5))
                    .foregroundStyle(faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if !entry.link.isEmpty {
                Button("打开") { hub.open(entry) }
                    .buttonStyle(EditorialButtonStyle(kind: .text))
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(oatmeal.opacity(0.4)).frame(height: 1)
        }
    }
}

// MARK: - 计划卡片

struct PlanCard: View {
    @ObservedObject var hub: Hub
    let plan: Plan
    var edit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%02d:%02d", plan.hour, plan.minute))
                    .font(numeral(22))
                    .foregroundStyle(plan.enabled ? terracotta : faint)
                Text(plan.origin == nil ? repeatText : "桌面同步")
                    .font(ui(8, .semibold)).tracking(0.8).foregroundStyle(faint)
            }
            .frame(width: 74, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(plan.title)
                    .font(editorial(18))
                    .foregroundStyle(plan.enabled ? ink : faint)
                    .fixedSize(horizontal: false, vertical: true)
                if !plan.notes.isEmpty {
                    Text(plan.notes)
                        .font(ui(10.5)).foregroundStyle(quiet).lineSpacing(3).lineLimit(2)
                }
                if let origin = plan.origin {
                    Text(origin + " · 在来源应用调整时间或暂停")
                        .font(ui(9)).foregroundStyle(faint)
                } else if let entry = hub.todayEntry(plan) {
                    Text(entry.done ? "今天已完成" : "今天已提醒")
                        .font(ui(9)).foregroundStyle(entry.done ? sage : faint)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                if plan.origin == nil {
                    Button { updateEnabled(!plan.enabled) } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(plan.enabled ? sage : faint)
                                .frame(width: 5, height: 5)
                            Text(plan.enabled ? "启用中" : "已暂停")
                                .font(ui(9, .semibold)).tracking(0.4)
                        }
                        .foregroundStyle(plan.enabled ? sage : quiet)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(plan.enabled ? sageWash : oatmeal.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                    .help(plan.enabled ? "暂停这个计划" : "启用这个计划")
                    HStack(spacing: 4) {
                        Button("编辑", action: edit)
                            .buttonStyle(EditorialButtonStyle(kind: .text))
                        Button("删除") { deletePlan() }
                            .buttonStyle(EditorialButtonStyle(kind: .text))
                    }
                } else {
                    Text("来源管理").font(ui(9)).foregroundStyle(faint).padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(paper))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(oatmeal.opacity(0.65), lineWidth: 1))
    }

    private var repeatText: String {
        if plan.weekdays.isEmpty { return "每天" }
        let names = ["", "日", "一", "二", "三", "四", "五", "六"]
        return "每周 " + plan.weekdays.sorted().map { names[$0] }.joined(separator: " · ")
    }

    private func updateEnabled(_ value: Bool) {
        if let index = hub.data.plans.firstIndex(where: { $0.id == plan.id }) {
            hub.data.plans[index].enabled = value
            _ = hub.save()
            hub.tick()
        }
    }

    private func deletePlan() {
        hub.data.plans.removeAll { $0.id == plan.id }
        hub.data.entries.removeAll { $0.id.hasPrefix("plan-\(plan.id)-") && !$0.done }
        _ = hub.save()
    }
}

// MARK: - 记录行

struct HistoryRoundRow: View {
    @ObservedObject var hub: Hub
    let round: HistoryRound
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(RecordText.time(round.end))
                .font(numeral(10)).foregroundStyle(quiet)
                .frame(width: 42, alignment: .trailing)
                .padding(.top, 2)

            node.frame(width: 12).padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                header
                Text(round.title)
                    .font(editorial(15.5)).foregroundStyle(ink2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                metaLine
                if expanded { steps.padding(.top, 6) }
            }
            .padding(.bottom, 10)
        }
        .padding(.top, 9)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .contain)
        .accessibilityHint(expanded ? "收起这一轮的经过" : "展开这一轮的经过")
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text(round.source).font(ui(9.5, .semibold)).foregroundStyle(quiet)
            RecordStatusDot(text: round.status)
            if round.count > 1, round.duration >= 30 {
                Text(RecordText.duration(round.duration))
                    .font(numeral(8.5)).foregroundStyle(faint)
            }
            Spacer(minLength: 8)
            if !round.link.isEmpty {
                Button { hub.open(round.last) } label: {
                    HStack(spacing: 3) {
                        Text("打开")
                        Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                    }
                    .font(ui(9.5, .medium))
                    .foregroundStyle(quiet)
                }
                .buttonStyle(.plain)
                .help("打开原会话")
            }
        }
    }

    private var metaLine: some View {
        HStack(spacing: 5) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(faint.opacity(0.9))
            Text(meta).font(ui(9)).foregroundStyle(faint).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var meta: String {
        var parts: [String] = []
        if round.count > 1 {
            parts.append("\(RecordText.time(round.start)) 开始")
            parts.append("\(round.count) 条事件")
        } else if !round.last.body.isEmpty {
            parts.append(round.last.body)
        }
        if let thread = round.thread, !thread.isEmpty {
            parts.append("会话 \(RecordText.session(thread))")
        }
        return parts.joined(separator: " · ")
    }

    private var node: some View {
        ZStack {
            Circle().fill(cream).frame(width: 14, height: 14)
            if hollow {
                Circle().stroke(nodeInk, lineWidth: 1.3).frame(width: 6.5, height: 6.5)
            } else {
                Circle().fill(nodeInk.opacity(0.16)).frame(width: 13, height: 13)
                Circle().fill(nodeInk).frame(width: 6.5, height: 6.5)
            }
        }
    }

    private var hollow: Bool {
        ["已处理", "已过期"].contains(round.status)
    }

    private var nodeInk: Color {
        StatusTag.palette(for: round.status).0
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(round.entries) { entry in
                HStack(spacing: 8) {
                    Text(RecordText.time(entry.date))
                        .font(numeral(8.5)).foregroundStyle(faint)
                        .frame(width: 30, alignment: .leading)
                    Text(RecordText.step(entry))
                        .font(ui(9)).foregroundStyle(quiet)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(RecordText.stepTag(entry))
                        .font(ui(8, .semibold)).foregroundStyle(faint)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(oatmeal.opacity(0.35)))
                }
            }
        }
        .padding(.leading, 10)
        .frame(maxWidth: 430, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(oatmeal.opacity(0.8)).frame(width: 1)
        }
    }
}

struct RecordStatusDot: View {
    let text: String

    var body: some View {
        let inkColor = StatusTag.palette(for: text).0
        return HStack(spacing: 4) {
            Circle().fill(inkColor).frame(width: 4, height: 4)
            Text(text).font(ui(9, .semibold)).tracking(0.3).foregroundStyle(inkColor)
        }
    }
}

enum RecordText {
    static func time(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// DSH 的 session id 形如 session-f9f9a80a-…；去掉前缀再截断才有辨识度。
    static func session(_ thread: String) -> String {
        var value = thread
        if value.hasPrefix("session-") { value.removeFirst("session-".count) }
        return String(value.prefix(8))
    }

    static func day(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0) 月 \(parts.day ?? 1) 日"
    }

    static func dayNote(_ date: Date) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let index = max(0, min(6, Calendar.current.component(.weekday, from: date) - 1))
        let name = names[index]
        if Calendar.current.isDateInToday(date) { return "\(name) · 今天" }
        if Calendar.current.isDateInYesterday(date) { return "\(name) · 昨天" }
        return name
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        if minutes == 0 { return "\(seconds) 秒" }
        if minutes < 60 {
            return seconds == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(seconds) 秒"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分"
    }

    static func step(_ entry: Entry) -> String {
        switch entry.status {
        case "运行中": return "开始处理这一轮"
        case "本轮结束": return "本轮结束，结果已收下"
        case "任务失败": return "本轮执行失败"
        case "已中断": return "本轮被中断"
        case "已拦截": return "提交阶段被拦截"
        case "已达上限": return "达到输出上限"
        case "待确认": return "请求你确认一次操作"
        case "待补充信息": return "需要你补充信息"
        default: return entry.body.isEmpty ? entry.displayTitle : entry.body
        }
    }

    static func stepTag(_ entry: Entry) -> String {
        entry.status == "运行中" ? "处理中" : entry.status
    }
}

// MARK: - 提醒弹窗

struct ReminderView: View {
    static let width: CGFloat = 470
    @ObservedObject var hub: Hub
    let entry: Entry
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text("M")
                    .font(numeral(13, .semibold))
                    .foregroundStyle(warmPaperInk)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(terracotta))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.source).font(ui(9, .semibold)).tracking(1).foregroundStyle(faint)
                    StatusTag(text: entry.status)
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(quiet)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(oatmeal.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭提醒")
                .help(entry.token != nil ? "关闭提醒，交还 DSH 原生对话框" : "关闭提醒，保留任务记录")
            }

            Text(entry.displayTitle)
                .font(editorial(18))
                .lineSpacing(4)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)

            if !entry.body.isEmpty {
                Text(entry.body)
                    .font(ui(11)).foregroundStyle(quiet).lineSpacing(4)
                    .lineLimit(3)
                    .padding(.top, 5)
            }

            if entry.codexID != nil {
                CodexApprovalControls(hub: hub, entry: entry, dismiss: dismiss).padding(.top, 14)
            } else {
                actions.padding(.top, 14)
            }

            if entry.token != nil, entry.status == "待确认" {
                Text("只对这一次请求生效；超时或关闭会交还 DSH 原生对话框。")
                    .font(ui(9)).foregroundStyle(faint)
                    .padding(.top, 9)
            }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(oatmeal, lineWidth: 1))
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            if entry.token != nil, entry.status == "待确认" {
                Button("允许一次") { if hub.decide(entry, "allow") { dismiss() } }
                    .buttonStyle(EditorialButtonStyle(kind: .rust))
                Button("拒绝") { if hub.decide(entry, "deny") { dismiss() } }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                Button("去 DSH 处理") { if hub.decide(entry, "defer") { dismiss() } }
                    .buttonStyle(EditorialButtonStyle(kind: .text))
                Spacer(minLength: 0)
                Button { hub.open(entry); dismiss() } label: {
                    HStack(spacing: 4) {
                        Text(entry.link.isEmpty ? "任务中心" : "打开")
                        Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                    }
                }
                .buttonStyle(EditorialButtonStyle(kind: .text))
            } else {
                if entry.canSnooze {
                    Button("10 分钟后") { hub.snooze(entry.id); dismiss() }
                        .buttonStyle(EditorialButtonStyle(kind: .outline))
                } else if !entry.automaticallyArchived && !entry.courseUpdate && hub.data.entries.contains(where: { $0.id == entry.id && !$0.done }) {
                    Button("标为已处理") {
                        if hub.finish(entry.id) { dismiss() } else { hub.showMain?(); dismiss() }
                    }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                }
                Spacer(minLength: 0)
                Button { hub.open(entry); dismiss() } label: {
                    HStack(spacing: 4) {
                        Text(entry.link.isEmpty ? "查看任务中心" : "打开原任务")
                        Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                    }
                }
                .buttonStyle(EditorialButtonStyle(kind: .ink))
            }
        }
    }

    private func close() {
        if let decision = ReminderClose.decision(for: entry) { _ = hub.decide(entry, decision) }
        dismiss()
    }
}
