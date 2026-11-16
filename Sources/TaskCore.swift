import Foundation

// MARK: - 任务库模型

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo = "待办"
    case doing = "进行中"
    case done = "已完成"

    var id: String { rawValue }
}

enum TaskLinkKind: String, Codable, CaseIterable, Identifiable {
    case chatgpt, codex, github, web

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .codex: return "Codex"
        case .github: return "GitHub"
        case .web: return "网页"
        }
    }

    var badge: String {
        switch self {
        case .chatgpt: return "GPT"
        case .codex: return "CX"
        case .github: return "GH"
        case .web: return "WEB"
        }
    }
}

struct TaskCategory: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var builtin: Bool = false
    var created: Date = Date()

    static let uncategorizedID = "category-uncategorized"

    static let course = TaskCategory(id: "category-course", name: "课程", builtin: true,
                                    created: Date(timeIntervalSince1970: 0))
    static let research = TaskCategory(id: "category-research", name: "科研", builtin: true,
                                      created: Date(timeIntervalSince1970: 0))
    static let life = TaskCategory(id: "category-life", name: "生活", builtin: true,
                                  created: Date(timeIntervalSince1970: 0))
    static let uncategorized = TaskCategory(id: uncategorizedID, name: "未分类", builtin: true,
                                            created: Date(timeIntervalSince1970: 0))

    /// Default categories are always restored by the migration. 未分类 is last
    /// because it is the fallback rather than a meaningful bucket.
    static let defaults: [TaskCategory] = [course, research, life, uncategorized]
    static let defaultIDs = Set(defaults.map(\.id))

    static func defaultCategory(_ id: String) -> TaskCategory? {
        defaults.first { $0.id == id }
    }
}

struct TaskLink: Codable, Identifiable, Hashable {
    var id: String
    var kind: TaskLinkKind
    var url: String

    init(id: String = UUID().uuidString, url: String, kind: TaskLinkKind? = nil) {
        let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.url = cleaned
        self.kind = kind ?? Links.taskLinkKind(cleaned) ?? .web
    }
}

struct TaskItem: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var notes: String = ""
    var categoryID: String = TaskCategory.uncategorizedID
    var status: TaskStatus = .todo
    var due: Date?
    var important = false
    var pinned = false
    var pinnedAt: Date?
    var links: [TaskLink] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date?
    var archivedAt: Date?
    /// 外部来源的稳定键（如 `unicourse:<cno>:<hno>`）。可选，旧状态解码为 nil。
    var externalKey: String?
}

enum TaskView: String, CaseIterable, Identifiable {
    case active = "未完成"
    case completed = "已完成"
    case archived = "已归档"

    var id: String { rawValue }
}

enum TaskSort: String, CaseIterable, Identifiable {
    case due = "截止日期"
    case updated = "最近更新"
    case pinned = "手动置顶"

    var id: String { rawValue }
}

enum TaskDueFilter: String, CaseIterable, Identifiable {
    case all = "全部截止日期"
    case overdue = "已逾期"
    case today = "今天"
    case week = "未来 7 天"
    case hasDue = "有截止日期"
    case noDue = "无截止日期"

    var id: String { rawValue }
}

struct TaskFilter: Equatable {
    var query = ""
    var categoryID: String?
    var status: TaskStatus?
    var importantOnly = false
    var due: TaskDueFilter = .all
    var sort: TaskSort = .updated
}

// MARK: - 版本化迁移

enum TaskSchema {
    /// Version 1 was the pre-task-library state shape. Version 2 adds tasks,
    /// categories and a schema marker; future versions can extend this switch.
    static let currentVersion = 2

    /// Add missing default categories, repair dangling category references and
    /// normalize timestamps/link kinds. Existing plans, entries and seen keys
    /// are never rewritten. Returns true when the in-memory state changed.
    @discardableResult
    static func migrate(_ data: inout HubData, now: Date = Date()) -> Bool {
        var changed = data.schemaVersion != currentVersion

        var categories = TaskCategory.defaults
        var knownIDs = Set(categories.map(\.id))
        for category in data.taskCategories where !knownIDs.contains(category.id) {
            let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { changed = true; continue }
            var cleaned = category
            cleaned.name = name
            categories.append(cleaned)
            knownIDs.insert(cleaned.id)
        }
        if categories != data.taskCategories {
            data.taskCategories = categories
            changed = true
        }

        for index in data.tasks.indices {
            var task = data.tasks[index]
            if !knownIDs.contains(task.categoryID) {
                task.categoryID = TaskCategory.uncategorizedID
                changed = true
            }
            if task.updatedAt < task.createdAt {
                task.updatedAt = task.createdAt
                changed = true
            }
            if task.status == .done {
                if task.completedAt == nil {
                    task.completedAt = task.updatedAt
                    changed = true
                }
            } else if task.completedAt != nil {
                task.completedAt = nil
                changed = true
            }
            if task.pinned, task.pinnedAt == nil {
                task.pinnedAt = task.updatedAt
                changed = true
            } else if !task.pinned, task.pinnedAt != nil {
                task.pinnedAt = nil
                changed = true
            }
            for linkIndex in task.links.indices {
                if let detected = Links.taskLinkKind(task.links[linkIndex].url),
                   detected != task.links[linkIndex].kind {
                    task.links[linkIndex].kind = detected
                    changed = true
                }
            }
            data.tasks[index] = task
        }

        if data.schemaVersion != currentVersion {
            data.schemaVersion = currentVersion
            changed = true
        }
        return changed
    }
}

// MARK: - 链接安全

extension Links {
    /// Task links add GitHub and ordinary web pages on top of the existing
    /// ChatGPT/Codex allow-list. Opening still goes through URL + NSWorkspace;
    /// no custom scheme other than codex is accepted.
    static func taskLinkKind(_ value: String) -> TaskLinkKind? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URL(string: raw), url.user == nil, url.password == nil else { return nil }
        let scheme = url.scheme?.lowercased()
        if scheme == "codex", valid(raw) { return .codex }
        if scheme == "https", valid(raw) { return .chatgpt }
        if scheme == "https", let host = url.host?.lowercased(),
           host == "github.com" || host.hasSuffix(".github.com") { return .github }
        if let scheme, scheme == "https" || scheme == "http",
           let host = url.host, !host.isEmpty { return .web }
        return nil
    }

    static func validTaskLink(_ link: TaskLink) -> Bool {
        let raw = link.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detected = taskLinkKind(raw), detected == link.kind else { return false }
        switch link.kind {
        case .chatgpt:
            guard let url = URL(string: raw), url.scheme?.lowercased() == "https" else { return false }
            return valid(raw)
        case .codex:
            guard let url = URL(string: raw), url.scheme?.lowercased() == "codex" else { return false }
            return valid(raw)
        case .github:
            guard let url = URL(string: raw), url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased() else { return false }
            return host == "github.com" || host.hasSuffix(".github.com")
        case .web:
            guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil else { return false }
            return true
        }
    }

    static func validTaskLink(_ value: String) -> Bool {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = taskLinkKind(raw) else { return false }
        return validTaskLink(TaskLink(url: raw, kind: kind))
    }
}

// MARK: - 纯任务操作

enum TaskLibrary {
    static func categoryID(_ requested: String?, in categories: [TaskCategory]) -> String {
        guard let requested, categories.contains(where: { $0.id == requested }) else {
            return TaskCategory.uncategorizedID
        }
        return requested
    }

    static func categoryName(_ id: String, in categories: [TaskCategory]) -> String {
        categories.first(where: { $0.id == id })?.name ?? TaskCategory.uncategorized.name
    }

    @discardableResult
    static func add(_ data: inout HubData, title: String, categoryID: String? = nil,
                    now: Date = Date()) -> TaskItem? {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let task = TaskItem(title: cleaned,
                            categoryID: self.categoryID(categoryID, in: data.taskCategories),
                            createdAt: now, updatedAt: now)
        data.tasks.insert(task, at: 0)
        return task
    }

    @discardableResult
    static func update(_ data: inout HubData, task: TaskItem, now: Date = Date()) -> Bool {
        guard let index = data.tasks.firstIndex(where: { $0.id == task.id }) else { return false }
        let old = data.tasks[index]
        let cleaned = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        var next = task
        next.id = old.id
        next.title = cleaned
        next.categoryID = categoryID(task.categoryID, in: data.taskCategories)
        next.createdAt = old.createdAt
        next.archivedAt = old.archivedAt
        next.links = next.links.map { link in
            let raw = link.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind = Links.taskLinkKind(raw) ?? link.kind
            return TaskLink(id: link.id, url: raw, kind: kind)
        }
        guard next.links.allSatisfy({ Links.validTaskLink($0) }) else { return false }
        if next.pinned {
            next.pinnedAt = old.pinned ? (old.pinnedAt ?? now) : now
        } else {
            next.pinnedAt = nil
        }
        if next.status == .done {
            next.completedAt = old.status == .done ? (old.completedAt ?? now) : now
        } else {
            next.completedAt = nil
        }
        next.updatedAt = max(now, next.createdAt)
        data.tasks[index] = next
        return true
    }

    @discardableResult
    static func setStatus(_ data: inout HubData, id: String, status: TaskStatus,
                          now: Date = Date()) -> Bool {
        guard var task = data.tasks.first(where: { $0.id == id }) else { return false }
        task.status = status
        return update(&data, task: task, now: now)
    }

    @discardableResult
    static func complete(_ data: inout HubData, id: String, now: Date = Date()) -> Bool {
        setStatus(&data, id: id, status: .done, now: now)
    }

    /// Restore works for both completed and archived tasks. It always returns
    /// the task to 待办 so it is visible in the default view again.
    @discardableResult
    static func restore(_ data: inout HubData, id: String, now: Date = Date()) -> Bool {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return false }
        var task = data.tasks[index]
        task.status = .todo
        task.completedAt = nil
        task.archivedAt = nil
        task.updatedAt = max(now, task.createdAt)
        if task.pinned && task.pinnedAt == nil { task.pinnedAt = task.updatedAt }
        data.tasks[index] = task
        return true
    }

    @discardableResult
    static func archive(_ data: inout HubData, id: String, now: Date = Date()) -> Bool {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return false }
        data.tasks[index].archivedAt = now
        data.tasks[index].updatedAt = max(now, data.tasks[index].createdAt)
        return true
    }

    @discardableResult
    static func delete(_ data: inout HubData, id: String) -> Bool {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return false }
        data.tasks.remove(at: index)
        return true
    }

    @discardableResult
    static func togglePin(_ data: inout HubData, id: String, now: Date = Date()) -> Bool {
        guard var task = data.tasks.first(where: { $0.id == id }) else { return false }
        task.pinned.toggle()
        task.pinnedAt = task.pinned ? now : nil
        return update(&data, task: task, now: now)
    }

    @discardableResult
    static func toggleImportant(_ data: inout HubData, id: String, now: Date = Date()) -> Bool {
        guard var task = data.tasks.first(where: { $0.id == id }) else { return false }
        task.important.toggle()
        return update(&data, task: task, now: now)
    }

    // MARK: 分类

    @discardableResult
    static func addCategory(_ data: inout HubData, name: String, now: Date = Date()) -> TaskCategory? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 24,
              !data.taskCategories.contains(where: { $0.name.localizedCaseInsensitiveCompare(cleaned) == .orderedSame })
        else { return nil }
        let category = TaskCategory(id: "category-" + UUID().uuidString, name: cleaned,
                                    builtin: false, created: now)
        data.taskCategories.append(category)
        return category
    }

    @discardableResult
    static func renameCategory(_ data: inout HubData, id: String, to name: String) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 24,
              let index = data.taskCategories.firstIndex(where: { $0.id == id }),
              !data.taskCategories[index].builtin,
              !data.taskCategories.contains(where: {
                  $0.id != id && $0.name.localizedCaseInsensitiveCompare(cleaned) == .orderedSame
              }) else { return false }
        data.taskCategories[index].name = cleaned
        return true
    }

    /// Deleting a category never deletes its tasks: they fall back to 未分类.
    @discardableResult
    static func deleteCategory(_ data: inout HubData, id: String) -> Bool {
        guard let index = data.taskCategories.firstIndex(where: { $0.id == id }),
              !data.taskCategories[index].builtin else { return false }
        data.taskCategories.remove(at: index)
        for taskIndex in data.tasks.indices where data.tasks[taskIndex].categoryID == id {
            data.tasks[taskIndex].categoryID = TaskCategory.uncategorizedID
        }
        return true
    }

    static func taskCount(categoryID: String, in data: HubData) -> Int {
        data.tasks.filter { $0.categoryID == categoryID }.count
    }

    // MARK: 查询

    static func pinnedForToday(_ tasks: [TaskItem], now: Date,
                               calendar: Calendar = .current) -> [TaskItem] {
        let today = tasks.filter { task in
            guard task.pinned, task.archivedAt == nil else { return false }
            if task.status != .done { return true }
            return task.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        }
        return sort(today, by: .pinned)
    }

    static func visible(_ data: HubData, view: TaskView, filter: TaskFilter,
                        now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let today = calendar.startOfDay(for: now)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today)

        let matched = data.tasks.filter { task in
            guard inView(task, view: view) else { return false }
            if let categoryID = filter.categoryID, task.categoryID != categoryID { return false }
            if let status = filter.status, task.status != status { return false }
            if filter.importantOnly && !task.important { return false }
            switch filter.due {
            case .all:
                break
            case .overdue:
                guard let due = task.due, due < today else { return false }
            case .today:
                guard let due = task.due, calendar.isDate(due, inSameDayAs: now) else { return false }
            case .week:
                guard let due = task.due, due >= today, let weekEnd, due < weekEnd else { return false }
            case .hasDue:
                guard task.due != nil else { return false }
            case .noDue:
                guard task.due == nil else { return false }
            }
            if !query.isEmpty {
                let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
                let inTitle = task.title.range(of: query, options: options) != nil
                let inNotes = task.notes.range(of: query, options: options) != nil
                guard inTitle || inNotes else { return false }
            }
            return true
        }
        return sort(matched, by: filter.sort)
    }

    static func inView(_ task: TaskItem, view: TaskView) -> Bool {
        switch view {
        case .active: return task.archivedAt == nil && task.status != .done
        case .completed: return task.archivedAt == nil && task.status == .done
        case .archived: return task.archivedAt != nil
        }
    }

    static func sort(_ tasks: [TaskItem], by sort: TaskSort) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            if lhs.pinned && rhs.pinned {
                let lp = lhs.pinnedAt ?? .distantPast
                let rp = rhs.pinnedAt ?? .distantPast
                if lp != rp { return lp > rp }
            }
            switch sort {
            case .due:
                if let ld = lhs.due, let rd = rhs.due {
                    if ld != rd { return ld < rd }
                } else if lhs.due != nil {
                    return true
                } else if rhs.due != nil {
                    return false
                }
            case .updated, .pinned:
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id < rhs.id
        }
    }
}

/// 先认领旧任务，再处理提交状态；稳定键优先，避免同名任务串课。
enum ExternalTaskSync {
    static func existingIndex(in tasks: inout [TaskItem], key: String,
                              title: String, source: String, checkedAt: Date) -> Int? {
        if let index = tasks.firstIndex(where: { $0.externalKey == key }) { return index }
        let candidates = tasks.indices.filter {
            tasks[$0].externalKey == nil && tasks[$0].title == title
                && tasks[$0].notes.hasPrefix("来自 \(source) ·")
        }
        // 有歧义时不猜测，避免误完成另一项作业。
        guard candidates.count == 1, let index = candidates.first else { return nil }
        tasks[index].externalKey = key
        tasks[index].updatedAt = checkedAt
        return index
    }

    @discardableResult
    static func complete(_ task: inout TaskItem, checkedAt: Date) -> Bool {
        guard task.status != .done else { return false }
        task.status = .done
        task.completedAt = checkedAt
        task.updatedAt = checkedAt
        return true
    }
}
