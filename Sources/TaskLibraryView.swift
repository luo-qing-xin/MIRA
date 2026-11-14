import SwiftUI
import AppKit

private let taskPeach = Color(red: 0.976, green: 0.906, blue: 0.855)

// MARK: - 任务库主页面

struct TaskLibraryPage: View {
    @ObservedObject var hub: Hub
    @State private var view: TaskView = .active
    @State private var filter = TaskFilter()
    @State private var quickTitle = ""
    @State private var editingTask: TaskSelection?
    @State private var showingCategories = false
    @FocusState private var quickFocused: Bool

    private var now: Date { Date() }
    private var filtered: [TaskItem] {
        TaskLibrary.visible(hub.data, view: view, filter: filter)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            taskRail.frame(width: 124).padding(.trailing, 16)
            Rectangle().fill(oatmeal.opacity(0.7)).frame(width: 1)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                header
                if view != .archived { quickAdd }
                viewSwitch.padding(.top, 8)
                filterBar.padding(.top, 6)
                taskList.padding(.top, 4)
            }
            .padding(.leading, 18)
            .padding(.trailing, 24)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 44)
        .padding(.top, 2)
        .frame(maxHeight: .infinity)
        .sheet(item: $editingTask) { selection in
            TaskEditor(hub: hub, taskID: selection.id)
        }
        .sheet(isPresented: $showingCategories) {
            TaskCategoryManager(hub: hub)
        }
        .onChange(of: view) { newView in
            if newView != .active { filter.status = nil }
        }
        .onChange(of: hub.data.taskCategories) { categories in
            if let id = filter.categoryID, !categories.contains(where: { $0.id == id }) {
                filter.categoryID = nil
            }
        }
    }

    // MARK: 左栏

    private var taskRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TASKS").font(ui(8.5, .semibold)).tracking(2.4).foregroundStyle(faint)
            Text("\(activeCount)").font(editorial(54)).tracking(-2).foregroundStyle(ink)
                .padding(.top, 2)
            Text("件未完成").font(ui(10.5, .semibold)).tracking(1).foregroundStyle(terracotta)

            Rectangle().fill(oatmeal.opacity(0.8)).frame(height: 1)
                .padding(.vertical, 10)

            railMetric("进行中", count: doingCount) {
                view = .active; filter.due = .all; filter.status = .doing
            }
            railMetric("已逾期", count: overdueCount, alert: overdueCount > 0) {
                view = .active; filter.status = nil; filter.due = .overdue
            }.padding(.top, 9)
            railMetric("今日到期", count: todayDueCount) {
                view = .active; filter.status = nil; filter.due = .today
            }.padding(.top, 9)
            railMetric("已完成", count: completedCount) {
                view = .completed; filter.status = nil; filter.due = .all
            }.padding(.top, 9)
            railMetric("已归档", count: archivedCount) {
                view = .archived; filter.status = nil; filter.due = .all
            }.padding(.top, 9)

            Rectangle().fill(oatmeal.opacity(0.8)).frame(height: 1)
                .padding(.vertical, 10)

            Text("只记录，不催促。").font(editorial(10.5)).foregroundStyle(quiet)
            Text("点击任务编辑，勾选圆圈完成。").font(ui(9)).foregroundStyle(faint)
                .lineSpacing(3).padding(.top, 4)

            Spacer(minLength: 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func railMetric(_ label: String, count: Int, alert: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(ui(8.5, .semibold)).tracking(1.6).foregroundStyle(faint)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(count)").font(editorial(22))
                        .foregroundStyle(alert ? terracotta : ink)
                    Text("项").font(ui(9)).foregroundStyle(quiet)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("查看\(label)任务")
    }

    // MARK: 标题与快速添加

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("任务库").font(editorial(24))
                Text("课程、科研与生活里的事，记下来再慢慢做。")
                    .font(ui(9.5)).foregroundStyle(quiet)
            }
            Spacer()
            Button { showingCategories = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 9, weight: .semibold))
                    Text("管理分类")
                }
            }
            .buttonStyle(EditorialButtonStyle(kind: .outline))
            .help("新增、重命名或删除自定义分类")
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(terracotta)
                .frame(width: 24, height: 24)
                .background(Circle().fill(taskPeach))
            TextField("记下一件事，按回车创建 · 只需标题", text: $quickTitle)
                .textFieldStyle(.plain)
                .font(ui(12))
                .foregroundStyle(ink)
                .focused($quickFocused)
                .onSubmit(addQuick)
            if !quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("添加") { addQuick() }
                    .buttonStyle(EditorialButtonStyle(kind: .ink))
            } else {
                Text("可稍后补充分类、截止日期和链接")
                    .font(ui(8.5)).foregroundStyle(faint).lineLimit(1)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(paper))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(oatmeal.opacity(0.8), lineWidth: 1))
        .padding(.top, 8)
    }

    private func addQuick() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { quickFocused = true; return }
        if hub.addTask(title) {
            quickTitle = ""
            view = .active
            clearFilters()
            quickFocused = true
        }
    }

    // MARK: 视图切换

    private var viewSwitch: some View {
        HStack(spacing: 7) {
            ForEach(TaskView.allCases) { item in
                let selected = view == item
                Button { view = item } label: {
                    HStack(spacing: 5) {
                        Text(item.rawValue).font(ui(10.5, selected ? .semibold : .regular))
                        Text("\(count(item))").font(numeral(9))
                            .foregroundStyle(selected ? warmPaperInk.opacity(0.7) : faint)
                    }
                    .foregroundStyle(selected ? warmPaperInk : quiet)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Capsule().fill(selected ? ink : paper.opacity(0.55)))
                    .overlay(Capsule().stroke(selected ? Color.clear : oatmeal.opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(item.rawValue)任务")
            }
            Spacer()
            Text("\(filtered.count) 项结果")
                .font(numeral(9)).foregroundStyle(faint)
        }
    }

    // MARK: 搜索与筛选

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(faint)
                    TextField("搜索标题与描述", text: $filter.query)
                        .textFieldStyle(.plain)
                        .font(ui(10.5))
                        .foregroundStyle(ink)
                    if !filter.query.isEmpty {
                        Button { filter.query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10)).foregroundStyle(faint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(paper))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(oatmeal.opacity(0.8), lineWidth: 1))

                categoryMenu
                dueMenu
                sortMenu
            }

            HStack(spacing: 6) {
                if view != .completed {
                    statusChip("全部状态", status: nil)
                    statusChip("待办", status: .todo)
                    statusChip("进行中", status: .doing)
                    if view == .archived { statusChip("已完成", status: .done) }
                }
                Button { filter.importantOnly.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: filter.importantOnly ? "star.fill" : "star")
                            .font(.system(size: 8, weight: .semibold))
                        Text("仅重点").font(ui(9.5, filter.importantOnly ? .semibold : .regular))
                    }
                    .foregroundStyle(filter.importantOnly ? butterInk : quiet)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(filter.importantOnly ? butter : Color.clear))
                    .overlay(Capsule().stroke(filter.importantOnly ? Color.clear : oatmeal.opacity(0.7), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("只显示重点任务")

                if hasFilters {
                    Button("清除筛选") { clearFilters() }
                        .buttonStyle(EditorialButtonStyle(kind: .text))
                }
                Spacer()
                Text(filter.sort.rawValue + "优先")
                    .font(ui(8.5)).foregroundStyle(faint)
            }
        }
    }

    private var categoryMenu: some View {
        Menu {
            Button(filter.categoryID == nil ? "✓ 全部分类" : "全部分类") {
                filter.categoryID = nil
            }
            Divider()
            ForEach(hub.data.taskCategories) { category in
                Button(filter.categoryID == category.id ? "✓ \(category.name)" : category.name) {
                    filter.categoryID = category.id
                }
            }
        } label: {
            filterLabel(filter.categoryID.map { hub.taskCategoryName($0) } ?? "全部分类",
                        active: filter.categoryID != nil)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("按分类筛选")
    }

    private var dueMenu: some View {
        Menu {
            ForEach(TaskDueFilter.allCases) { option in
                Button(filter.due == option ? "✓ \(option.rawValue)" : option.rawValue) {
                    filter.due = option
                }
            }
        } label: {
            filterLabel(filter.due == .all ? "截止日期" : filter.due.rawValue,
                        active: filter.due != .all)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("按截止日期筛选")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(TaskSort.allCases) { option in
                Button(filter.sort == option ? "✓ \(option.rawValue)" : option.rawValue) {
                    filter.sort = option
                }
            }
        } label: {
            filterLabel("排序 · " + filter.sort.rawValue, active: filter.sort != .updated)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("切换排序方式")
    }

    private func filterLabel(_ text: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Text(text).font(ui(10, active ? .semibold : .regular)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
        }
        .foregroundStyle(active ? terracotta : quiet)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(active ? Color(red: 0.984, green: 0.933, blue: 0.886) : paper))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(active ? terracotta.opacity(0.35) : oatmeal.opacity(0.8), lineWidth: 1))
    }

    private func statusChip(_ label: String, status: TaskStatus?) -> some View {
        let selected = filter.status == status
        return Button { filter.status = status } label: {
            Text(label).font(ui(9.5, selected ? .semibold : .regular))
                .foregroundStyle(selected ? ink : quiet)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(selected ? oatmeal.opacity(0.75) : Color.clear))
                .overlay(Capsule().stroke(selected ? Color.clear : oatmeal.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var hasFilters: Bool {
        !filter.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || filter.categoryID != nil || filter.status != nil
            || filter.importantOnly || filter.due != .all
    }

    private func clearFilters() {
        filter.query = ""
        filter.categoryID = nil
        filter.status = nil
        filter.importantOnly = false
        filter.due = .all
    }

    // MARK: 列表

    private var taskList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 6) {
                if filtered.isEmpty {
                    emptyState.padding(.vertical, 34)
                } else {
                    ForEach(filtered) { task in
                        TaskRow(hub: hub, task: task) {
                            editingTask = TaskSelection(id: task.id)
                        }
                    }
                }
                Color.clear.frame(height: 2)
            }
            .padding(.bottom, 6)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(emptyHeadline).font(editorial(21)).foregroundStyle(ink)
            Text(emptyLede).font(ui(10.5)).foregroundStyle(quiet).lineSpacing(4)
            if hasFilters {
                Button("清除筛选") { clearFilters() }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                    .padding(.top, 2)
            } else if view == .active {
                Button("在上面的输入框写下第一件事") { quickFocused = true }
                    .buttonStyle(EditorialButtonStyle(kind: .ink))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyHeadline: String {
        if hasFilters { return "没有匹配的任务。" }
        switch view {
        case .active: return "任务库还是空的。"
        case .completed: return "还没有完成的任务。"
        case .archived: return "没有归档的任务。"
        }
    }

    private var emptyLede: String {
        if hasFilters { return "换一个关键词，或清除分类、状态和截止日期筛选。" }
        switch view {
        case .active: return "只写标题就能创建；分类、截止日期与链接都可以之后再补。"
        case .completed: return "完成的任务会留在这里，可以随时恢复为待办。"
        case .archived: return "归档只会移出日常列表，不会删除任务，也不会删除关联链接。"
        }
    }

    // MARK: 计数

    private var activeCount: Int { count(.active) }
    private var completedCount: Int { count(.completed) }
    private var archivedCount: Int { count(.archived) }
    private var doingCount: Int {
        hub.data.tasks.filter { TaskLibrary.inView($0, view: .active) && $0.status == .doing }.count
    }
    private var overdueCount: Int {
        let today = Calendar.current.startOfDay(for: now)
        return hub.data.tasks.filter {
            TaskLibrary.inView($0, view: .active) && ($0.due.map { $0 < today } ?? false)
        }.count
    }
    private var todayDueCount: Int {
        hub.data.tasks.filter {
            TaskLibrary.inView($0, view: .active) && ($0.due.map { Calendar.current.isDateInToday($0) } ?? false)
        }.count
    }

    private func count(_ target: TaskView) -> Int {
        hub.data.tasks.filter { TaskLibrary.inView($0, view: target) }.count
    }
}

struct TaskSelection: Identifiable {
    let id: String
}

// MARK: - 任务行

struct TaskRow: View {
    @ObservedObject var hub: Hub
    let task: TaskItem
    let open: () -> Void

    private var categoryName: String { hub.taskCategoryName(task.categoryID) }
    private var isOverdue: Bool {
        guard task.status != .done, let due = task.due else { return false }
        return Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: Date())
    }
    private var isDueToday: Bool {
        task.due.map { Calendar.current.isDateInToday($0) } ?? false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            completionControl.padding(.top, 2)

            Button(action: open) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(task.title)
                            .font(editorial(16))
                            .foregroundStyle(task.status == .done ? faint : ink)
                            .strikethrough(task.status == .done, color: faint)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if task.important {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(butterInk)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 6) {
                        categoryTag
                        statusTag
                        if let due = task.due {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar").font(.system(size: 7, weight: .medium))
                                Text(due.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                                    .font(numeral(8.5))
                            }
                            .foregroundStyle(isOverdue ? terracotta : (isDueToday ? butterInk : quiet))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(isOverdue ? Color(red: 0.972, green: 0.894, blue: 0.878)
                                                        : (isDueToday ? butter : oatmeal.opacity(0.35))))
                            .help(isOverdue ? "已逾期" : (isDueToday ? "今天截止" : "截止日期"))
                        }
                        if !task.links.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "link").font(.system(size: 7, weight: .medium))
                                Text("\(task.links.count)").font(numeral(8.5))
                            }
                            .foregroundStyle(quiet)
                        }
                        Text("更新 " + task.updatedAt.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                            .font(ui(8)).foregroundStyle(faint)
                    }

                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(ui(9.5)).foregroundStyle(quiet)
                            .lineLimit(1).padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑任务 \(task.title)")

            HStack(spacing: 6) {
                Button { hub.toggleTaskPin(task.id) } label: {
                    Image(systemName: task.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(task.pinned ? terracotta : faint)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(task.pinned ? taskPeach : Color.clear))
                }
                .buttonStyle(.plain)
                .help(task.pinned ? "取消置顶" : "置顶任务")
                .accessibilityLabel(task.pinned ? "取消置顶" : "置顶任务")

                if task.archivedAt != nil {
                    Button("恢复") { hub.restoreTask(task.id) }
                        .buttonStyle(EditorialButtonStyle(kind: .text))
                } else if task.status == .done {
                    Button("恢复") { hub.restoreTask(task.id) }
                        .buttonStyle(EditorialButtonStyle(kind: .text))
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(paper))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(oatmeal.opacity(0.65), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.025), radius: 3, x: 0, y: 1)
    }

    @ViewBuilder private var completionControl: some View {
        if task.archivedAt != nil {
            ZStack {
                Circle().stroke(faint.opacity(0.6), lineWidth: 1.2)
                if task.status == .done {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(sage)
                }
            }
            .frame(width: 18, height: 18)
            .help("已归档")
        } else {
            Button {
                if task.status == .done {
                    hub.restoreTask(task.id)
                } else {
                    hub.completeTask(task.id)
                }
            } label: {
                ZStack {
                    Circle().stroke(task.status == .done ? sage : (task.status == .doing ? terracotta : faint.opacity(0.7)),
                                    lineWidth: 1.2)
                    if task.status == .done {
                        Circle().fill(sageWash)
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(sage)
                    } else if task.status == .doing {
                        Circle().fill(terracotta).frame(width: 7, height: 7)
                    }
                }
                .frame(width: 18, height: 18)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(task.status == .done ? "恢复为待办" : "标记完成")
            .accessibilityLabel(task.status == .done ? "恢复任务" : "完成任务")
        }
    }

    private var categoryTag: some View {
        Text(categoryName)
            .font(ui(8.5, .medium))
            .foregroundStyle(quiet)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(oatmeal.opacity(0.35)))
    }

    private var statusTag: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(task.status == .done ? sage : (task.status == .doing ? terracotta : faint))
                .frame(width: 4, height: 4)
            Text(task.status.rawValue).font(ui(8.5, .semibold))
        }
        .foregroundStyle(task.status == .done ? sage : (task.status == .doing ? terracotta : quiet))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(task.status == .done ? sageWash
                                    : (task.status == .doing ? taskPeach : oatmeal.opacity(0.3))))
    }
}

// MARK: - 详情编辑

struct TaskEditor: View {
    @ObservedObject var hub: Hub
    let taskID: String
    @Environment(\.dismiss) private var dismiss

    @State private var draft = TaskItem(title: "")
    @State private var loaded = false
    @State private var dueEnabled = false
    @State private var dueDate = Date()
    @State private var linkDraft = ""
    @State private var linkError = ""
    @State private var saveError = ""
    @State private var confirmDelete = false

    private var current: TaskItem? { hub.data.tasks.first { $0.id == taskID } }
    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.links.allSatisfy { Links.validTaskLink($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            Rectangle().fill(oatmeal.opacity(0.7)).frame(height: 1)

            TextField("任务标题", text: $draft.title)
                .textFieldStyle(.plain)
                .font(editorial(21))
                .foregroundStyle(ink)
                .padding(.horizontal, 11).padding(.vertical, 9)
                .background(inputBackground)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    label("分类")
                    Picker("", selection: $draft.categoryID) {
                        ForEach(hub.data.taskCategories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(ui(11))
                    .frame(width: 150, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 6) {
                    label("状态")
                    Picker("", selection: $draft.status) {
                        ForEach(TaskStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(ui(11))
                    .frame(width: 120, alignment: .leading)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    label("标记")
                    HStack(spacing: 12) {
                        Toggle("重点", isOn: $draft.important)
                            .toggleStyle(.checkbox)
                            .font(ui(10))
                            .tint(terracotta)
                        Toggle("置顶", isOn: $draft.pinned)
                            .toggleStyle(.checkbox)
                            .font(ui(10))
                            .tint(terracotta)
                    }
                }
            }

            HStack(spacing: 10) {
                Toggle("截止日期", isOn: $dueEnabled)
                    .toggleStyle(.checkbox)
                    .font(ui(10.5))
                    .tint(terracotta)
                if dueEnabled {
                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .font(ui(11))
                }
                Spacer()
                Text(dueEnabled ? "只记录真实日期，不用来生成每日目标。" : "可选；不设置也能保存。")
                    .font(ui(8.5)).foregroundStyle(faint)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("描述 · 可选")
                TextEditor(text: $draft.notes)
                    .font(ui(11))
                    .foregroundStyle(ink)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(height: 80)
                    .background(inputBackground)
            }

            linksSection

            if !saveError.isEmpty {
                Text(saveError)
                    .font(ui(9)).foregroundStyle(Color(red: 0.65, green: 0.20, blue: 0.15))
                    .lineLimit(2)
            }

            timestamps

            HStack(spacing: 8) {
                Button("删除") { confirmDelete = true }
                    .buttonStyle(EditorialButtonStyle(kind: .text))
                    .foregroundStyle(Color(red: 0.65, green: 0.20, blue: 0.15))
                if draft.archivedAt != nil || draft.status == .done {
                    Button("恢复为待办") {
                        if hub.restoreTask(taskID) { dismiss() }
                    }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                }
                if draft.archivedAt == nil {
                    Button("归档") {
                        if saveDraft(archiving: true) { dismiss() }
                    }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(EditorialButtonStyle(kind: .text))
                if draft.status != .done, draft.archivedAt == nil {
                    Button("完成") {
                        draft.status = .done
                        if saveDraft() { dismiss() }
                    }
                    .buttonStyle(EditorialButtonStyle(kind: .cream))
                }
                Button("保存") { if saveDraft() { dismiss() } }
                    .buttonStyle(EditorialButtonStyle(kind: .rust))
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.42)
            }
            .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 590)
        .background(cream)
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .tint(terracotta)
        .onAppear(perform: load)
        .alert("删除这个任务？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                if hub.deleteTask(taskID) { dismiss() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复，关联链接也会一起移除。归档则可以在「已归档」中找回。")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("任务详情").font(editorial(24))
            Spacer()
            Text(draft.archivedAt != nil ? "ARCHIVED" : "TASK DETAIL")
                .font(ui(8.5, .semibold)).tracking(2).foregroundStyle(faint)
        }
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            label("关联链接 · 可选")
            if draft.links.isEmpty {
                Text("还没有链接。可以添加 ChatGPT、Codex、GitHub 或普通网页。")
                    .font(ui(9)).foregroundStyle(faint)
            } else {
                VStack(spacing: 5) {
                    ForEach(draft.links) { link in
                        HStack(spacing: 7) {
                            Text(link.kind.badge)
                                .font(numeral(8, .semibold))
                                .foregroundStyle(terracotta)
                                .frame(width: 27, height: 20)
                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(taskPeach))
                            Text(link.url)
                                .font(ui(9.5))
                                .foregroundStyle(Links.validTaskLink(link) ? ink2 : Color(red: 0.65, green: 0.20, blue: 0.15))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            if Links.validTaskLink(link) {
                                Button("打开") { openLink(link) }
                                    .buttonStyle(EditorialButtonStyle(kind: .text))
                            } else {
                                Text("无效").font(ui(8.5, .semibold))
                                    .foregroundStyle(Color(red: 0.65, green: 0.20, blue: 0.15))
                            }
                            Button { draft.links.removeAll { $0.id == link.id } } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(faint)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("移除链接")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(paper))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(oatmeal.opacity(0.55), lineWidth: 1))
                    }
                }
            }
            HStack(spacing: 7) {
                TextField("粘贴完整链接，例如 https://chatgpt.com/c/…", text: $linkDraft)
                    .textFieldStyle(.plain)
                    .font(ui(9.5))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(inputBackground)
                    .onSubmit(addLink)
                if let detected = Links.taskLinkKind(linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Text(detected.label).font(ui(8, .semibold))
                        .foregroundStyle(terracotta)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(taskPeach))
                }
                Button("添加") { addLink() }
                    .buttonStyle(EditorialButtonStyle(kind: .outline))
                    .disabled(Links.taskLinkKind(linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                    .opacity(Links.taskLinkKind(linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)) == nil ? 0.42 : 1)
            }
            if !linkError.isEmpty {
                Text(linkError).font(ui(8.5)).foregroundStyle(Color(red: 0.65, green: 0.20, blue: 0.15))
            }
            Text("ChatGPT、GitHub 和网页使用完整 http(s) 链接；Codex 使用 codex://threads/…。仅允许安全协议。")
                .font(ui(8.5)).foregroundStyle(faint).lineSpacing(2)
        }
    }

    private var timestamps: some View {
        HStack(spacing: 14) {
            timestamp("创建", draft.createdAt)
            timestamp("更新", draft.updatedAt)
            if let completed = draft.completedAt { timestamp("完成", completed) }
            if let archived = draft.archivedAt { timestamp("归档", archived) }
            Spacer()
        }
    }

    private func timestamp(_ label: String, _ date: Date) -> some View {
        HStack(spacing: 3) {
            Text(label).font(ui(8)).foregroundStyle(faint)
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(numeral(8)).foregroundStyle(faint)
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(paper)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(oatmeal.opacity(0.75), lineWidth: 1))
    }

    private func label(_ text: String) -> some View {
        Text(text).font(ui(8.5, .semibold)).tracking(1.4).foregroundStyle(faint)
    }

    private func load() {
        guard !loaded, let task = current else { return }
        draft = task
        dueEnabled = task.due != nil
        dueDate = task.due ?? Calendar.current.startOfDay(for: Date())
        loaded = true
    }

    private func openLink(_ link: TaskLink) {
        if hub.openTaskLink(link) {
            linkError = ""
        } else {
            linkError = "链接无效或无法打开。"
        }
    }

    private func addLink() {
        let raw = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = Links.taskLinkKind(raw) else {
            linkError = "链接无效。请填写完整的 ChatGPT / GitHub / 网页链接，或 codex://threads/…。"
            return
        }
        let link = TaskLink(url: raw, kind: kind)
        guard Links.validTaskLink(link) else {
            linkError = "链接没有通过安全校验。" ; return
        }
        guard !draft.links.contains(where: { $0.url == link.url }) else {
            linkError = "这个链接已经添加过了。"; return
        }
        draft.links.append(link)
        linkDraft = ""
        linkError = ""
    }

    @discardableResult
    private func saveDraft(archiving: Bool = false) -> Bool {
        saveError = ""
        guard canSave else {
            saveError = "标题不能为空；无效链接需要先修正或移除。"
            return false
        }
        draft.due = dueEnabled ? Calendar.current.startOfDay(for: dueDate) : nil
        guard hub.updateTask(draft, archiving: archiving) else {
            saveError = hub.error.isEmpty ? "保存失败，请检查标题或链接。" : hub.error
            return false
        }
        if let latest = hub.data.tasks.first(where: { $0.id == taskID }) { draft = latest }
        return true
    }
}

// MARK: - 分类管理

struct TaskCategoryManager: View {
    @ObservedObject var hub: Hub
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var editingID: String?
    @State private var editName = ""
    @State private var error = ""
    @State private var deleteTarget: TaskCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("管理分类").font(editorial(24))
                Spacer()
                Text("CATEGORIES").font(ui(8.5, .semibold)).tracking(2).foregroundStyle(faint)
            }
            Rectangle().fill(oatmeal.opacity(0.7)).frame(height: 1)

            HStack(spacing: 8) {
                TextField("新分类名称，例如：申请", text: $newName)
                    .textFieldStyle(.plain)
                    .font(ui(11))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(inputBackground)
                    .onSubmit(addCategory)
                Button("新增分类") { addCategory() }
                    .buttonStyle(EditorialButtonStyle(kind: .ink))
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
            }

            if !error.isEmpty {
                Text(error).font(ui(9)).foregroundStyle(Color(red: 0.65, green: 0.20, blue: 0.15))
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(hub.data.taskCategories) { category in
                        categoryRow(category)
                        Rectangle().fill(oatmeal.opacity(0.45)).frame(height: 1)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Text("默认分类不能删除或改名。删除自定义分类时，其下任务会移到「未分类」，任务本身和链接都会保留。")
                .font(ui(8.5)).foregroundStyle(faint).lineSpacing(3)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(EditorialButtonStyle(kind: .rust))
            }
        }
        .padding(24)
        .frame(width: 560, height: 540)
        .background(cream)
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .tint(terracotta)
        .alert("删除这个分类？", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), presenting: deleteTarget) { category in
            Button("删除", role: .destructive) {
                if hub.deleteTaskCategory(category.id) {
                    deleteTarget = nil
                } else {
                    error = "删除失败，请重试。"
                }
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { category in
            Text("「\(category.name)」下的 \(TaskLibrary.taskCount(categoryID: category.id, in: hub.data)) 个任务会移到「未分类」，不会被删除。")
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: TaskCategory) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(category.builtin ? faint.opacity(0.45) : terracotta.opacity(0.65))
                .frame(width: 3, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.name).font(editorial(14, .semibold)).foregroundStyle(ink2)
                    if category.builtin {
                        Text("默认").font(ui(7.5, .semibold))
                            .foregroundStyle(faint)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(oatmeal.opacity(0.45)))
                    }
                }
                Text("\(TaskLibrary.taskCount(categoryID: category.id, in: hub.data)) 个任务")
                    .font(ui(8.5)).foregroundStyle(faint)
            }
            Spacer()
            if editingID == category.id {
                TextField("分类名称", text: $editName)
                    .textFieldStyle(.plain)
                    .font(ui(10))
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .frame(width: 130)
                    .background(inputBackground)
                    .onSubmit { saveRename(category) }
                Button("保存") { saveRename(category) }
                    .buttonStyle(EditorialButtonStyle(kind: .ink))
                Button("取消") { editingID = nil; error = "" }
                    .buttonStyle(EditorialButtonStyle(kind: .text))
            } else if category.builtin {
                Text("固定").font(ui(9)).foregroundStyle(faint).padding(.trailing, 4)
            } else {
                Button("重命名") {
                    editingID = category.id
                    editName = category.name
                    error = ""
                }
                .buttonStyle(EditorialButtonStyle(kind: .text))
                Button("删除") { deleteTarget = category }
                    .buttonStyle(EditorialButtonStyle(kind: .text))
                    .foregroundStyle(Color(red: 0.65, green: 0.20, blue: 0.15))
            }
        }
        .padding(.vertical, 9)
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(paper)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(oatmeal.opacity(0.75), lineWidth: 1))
    }

    private func addCategory() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard hub.addTaskCategory(name) else {
            error = "无法新增：名称需为 1–24 个字且不能与已有分类重复。"
            return
        }
        newName = ""
        error = ""
    }

    private func saveRename(_ category: TaskCategory) {
        guard hub.renameTaskCategory(category.id, to: editName) else {
            error = "无法重命名：名称需为 1–24 个字且不能与其他分类重复。"
            return
        }
        editingID = nil
        error = ""
    }
}
