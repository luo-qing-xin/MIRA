import Foundation
import AppKit

// MARK: - Hub 任务库入口

extension Hub {
    /// Persist a task/category mutation as one atomic state write. On failure the
    /// previous in-memory state is restored, matching the reminder flows.
    @discardableResult
    private func mutateTasks(_ change: (inout HubData) -> Bool) -> Bool {
        let previous = data
        guard change(&data) else { return false }
        if save() { return true }
        data = previous
        return false
    }

    func task(_ id: String) -> TaskItem? {
        data.tasks.first { $0.id == id }
    }

    func taskCategoryName(_ id: String) -> String {
        TaskLibrary.categoryName(id, in: data.taskCategories)
    }

    @discardableResult
    func addTask(_ title: String) -> Bool {
        mutateTasks { data in TaskLibrary.add(&data, title: title) != nil }
    }

    @discardableResult
    func updateTask(_ task: TaskItem, archiving: Bool = false) -> Bool {
        mutateTasks { data in
            guard TaskLibrary.update(&data, task: task) else { return false }
            // The update above already confirmed that this task exists.
            if archiving { TaskLibrary.archive(&data, id: task.id) }
            return true
        }
    }

    @discardableResult
    func completeTask(_ id: String) -> Bool {
        mutateTasks { data in TaskLibrary.complete(&data, id: id) }
    }

    @discardableResult
    func restoreTask(_ id: String) -> Bool {
        mutateTasks { data in TaskLibrary.restore(&data, id: id) }
    }

    @discardableResult
    func deleteTask(_ id: String) -> Bool {
        mutateTasks { data in TaskLibrary.delete(&data, id: id) }
    }

    @discardableResult
    func toggleTaskPin(_ id: String) -> Bool {
        mutateTasks { data in TaskLibrary.togglePin(&data, id: id) }
    }

    @discardableResult
    func toggleTaskImportant(_ id: String) -> Bool {
        mutateTasks { data in TaskLibrary.toggleImportant(&data, id: id) }
    }

    @discardableResult
    func addTaskCategory(_ name: String) -> Bool {
        mutateTasks { data in TaskLibrary.addCategory(&data, name: name) != nil }
    }

    @discardableResult
    func renameTaskCategory(_ id: String, to name: String) -> Bool {
        mutateTasks { data in TaskLibrary.renameCategory(&data, id: id, to: name) }
    }

    @discardableResult
    func deleteTaskCategory(_ id: String) -> Bool {
        mutateTasks { data in TaskLibrary.deleteCategory(&data, id: id) }
    }

    /// Same safe-open policy as reminders: validate first, then hand the URL to
    /// NSWorkspace. Invalid links never reach the system opener.
    @discardableResult
    func openTaskLink(_ link: TaskLink) -> Bool {
        guard Links.validTaskLink(link), let url = URL(string: link.url) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
