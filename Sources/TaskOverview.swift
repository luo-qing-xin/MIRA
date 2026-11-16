import SwiftUI
import AppKit

// MARK: - 登录待办浮窗

@MainActor final class TaskOverviewController {
    private let hub: Hub
    private var panel: NSPanel?
    private var topInset: CGFloat = 0

    init(hub: Hub) { self.hub = hub }

    var isVisible: Bool { panel?.isVisible == true }

    func show(topInset: CGFloat = 0) {
        self.topInset = max(0, topInset)
        if panel != nil {
            scheduleResize()
            return
        }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 300),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.title = "MIRA · 待办"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let content = NSHostingView(rootView: TaskOverviewView(
            hub: hub,
            close: { [weak self] in self?.close() },
            openTasks: { [weak self] in
                self?.close()
                self?.hub.section = "任务库"
                self?.hub.showMain?()
            },
            changed: { [weak self] in self?.scheduleResize() }
        ))
        panel.contentView = content
        self.panel = panel
        resize(panel: panel, content: content)
    }

    /// Keep the task card below the reminder stack when there is room.
    func setTopInset(_ value: CGFloat) {
        topInset = max(0, value)
        guard let panel, let content = panel.contentView else { return }
        resize(panel: panel, content: content)
    }

    func close() {
        panel?.close()
        panel = nil
    }

    private func scheduleResize() {
        // Let SwiftUI apply the task mutation before asking for a new fitting size.
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, let content = panel.contentView else { return }
            self.resize(panel: panel, content: content)
        }
    }

    private func resize(panel: NSPanel, content: NSView) {
        content.layoutSubtreeIfNeeded()
        let width: CGFloat = 470
        let height = max(180, content.fittingSize.height)
        panel.setContentSize(NSSize(width: width, height: height))
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let y = visible.maxY - 20 - topInset - height
        if topInset > 0, y < visible.minY + 12 {
            panel.orderOut(nil)
            return
        }
        panel.setFrameOrigin(NSPoint(x: visible.maxX - width - 24, y: max(visible.minY + 12, y)))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}

struct TaskOverviewView: View {
    @ObservedObject var hub: Hub
    let close: () -> Void
    let openTasks: () -> Void
    let changed: () -> Void

    private var tasks: [TaskItem] {
        TaskLibrary.sort(
            hub.data.tasks.filter { TaskLibrary.inView($0, view: .active) },
            by: .due
        )
    }

    private var displayed: [TaskItem] { Array(tasks.prefix(5)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(oatmeal.opacity(0.8)).frame(height: 1).padding(.top, 12)
            if tasks.isEmpty {
                emptyState
            } else {
                taskRows
            }
            footer.padding(.top, 12)
        }
        .padding(20)
        .frame(width: 470, alignment: .leading)
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(oatmeal, lineWidth: 1))
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .onChange(of: tasks.count) { _ in changed() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("M")
                .font(numeral(13, .semibold))
                .foregroundStyle(warmPaperInk)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(terracotta))
            VStack(alignment: .leading, spacing: 3) {
                Text("待办")
                    .font(editorial(20))
                Text(tasks.isEmpty ? "现在没有未完成的事" : "\(tasks.count) 项未完成 · 点击圆圈完成")
                    .font(ui(9))
                    .foregroundStyle(faint)
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
            .accessibilityLabel("关闭待办浮窗")
            .help("关闭待办浮窗")
        }
    }

    private var taskRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(displayed.enumerated()), id: \.element.id) { index, task in
                row(task)
                if index < displayed.count - 1 {
                    Rectangle().fill(oatmeal.opacity(0.45)).frame(height: 1)
                }
            }
            if tasks.count > displayed.count {
                HStack {
                    Text("还有 \(tasks.count - displayed.count) 项未显示")
                        .font(ui(8.5))
                        .foregroundStyle(faint)
                    Spacer()
                    Button("查看全部") { openTasks() }
                        .buttonStyle(EditorialButtonStyle(kind: .text))
                }
                .padding(.top, 7)
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Button { complete(task) } label: {
                Circle()
                    .stroke(terracotta.opacity(0.6), lineWidth: 1.2)
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .help("标记完成")
            .accessibilityLabel("完成任务 \(task.title)")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(task.title)
                        .font(editorial(14))
                        .foregroundStyle(ink2)
                        .lineLimit(1)
                    if task.important {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(butterInk)
                    }
                    Spacer(minLength: 2)
                    if task.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(terracotta)
                    }
                }
                HStack(spacing: 5) {
                    Text(hub.taskCategoryName(task.categoryID))
                        .font(ui(8))
                        .foregroundStyle(quiet)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(oatmeal.opacity(0.35)))
                    if task.status == .doing {
                        Text("进行中")
                            .font(ui(8, .semibold))
                            .foregroundStyle(terracotta)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(terracotta.opacity(0.09)))
                    }
                    if let due = task.due {
                        dueTag(due)
                    }
                    if !task.links.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "link").font(.system(size: 6, weight: .medium))
                            Text("\(task.links.count)").font(numeral(7.5))
                        }
                        .foregroundStyle(faint)
                    }
                }
            }
        }
        .padding(.vertical, 7)
    }

    private func dueTag(_ due: Date) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        let overdue = due < today
        let isToday = Calendar.current.isDateInToday(due)
        let text = overdue ? "已逾期" : (isToday ? "今天截止" : "截止 " + due.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
        let color = overdue ? terracotta : (isToday ? butterInk : quiet)
        return HStack(spacing: 2) {
            Image(systemName: "calendar").font(.system(size: 6, weight: .medium))
            Text(text).font(numeral(7.5))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(Capsule().fill(overdue ? Color(red: 0.972, green: 0.894, blue: 0.878)
                                    : (isToday ? butter : oatmeal.opacity(0.35))))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("现在没有待办。").font(editorial(17)).foregroundStyle(ink2)
            Text("在任务库里记下一件事，下次登录会在这里出现。")
                .font(ui(9.5)).foregroundStyle(quiet).lineSpacing(3)
        }
        .padding(.vertical, 20)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { openTasks() } label: {
                HStack(spacing: 5) {
                    Text("打开任务库")
                    Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(EditorialButtonStyle(kind: .ink))
            Button("关闭", action: close)
                .buttonStyle(EditorialButtonStyle(kind: .text))
            Spacer()
            Text("MIRA · 登录待办")
                .font(numeral(8))
                .tracking(1.4)
                .foregroundStyle(faint)
        }
    }

    private func complete(_ task: TaskItem) {
        _ = hub.completeTask(task.id)
    }
}
