import Foundation

@main struct TaskLibraryTests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func at(_ day: Int, _ hour: Int = 9) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        }
        let t0 = at(11, 9)
        let t1 = at(11, 10)
        let t2 = at(11, 11)
        let t3 = at(11, 12)
        let t4 = at(11, 13)
        let t5 = at(11, 14)
        let now = at(11, 10)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        // MARK: Legacy state migrates without touching reminders
        let legacyJSON = Data("""
        {"plans":[],"entries":[],"seen":[],"lastEvent":null}
        """.utf8)
        var legacy = try decoder.decode(HubData.self, from: legacyJSON)
        assert(legacy.schemaVersion == 1, "a pre-task state is version 1")
        assert(legacy.taskCategories.isEmpty && legacy.tasks.isEmpty)
        assert(TaskSchema.migrate(&legacy, now: t0))
        assert(legacy.schemaVersion == TaskSchema.currentVersion)
        assert(legacy.taskCategories.map(\.name) == ["课程", "科研", "生活", "未分类"])
        assert(legacy.taskCategories.allSatisfy(\.builtin))
        assert(!TaskSchema.migrate(&legacy, now: t0), "migration is idempotent")
        assert(legacy.entries.isEmpty && legacy.plans.isEmpty, "existing reminder data is untouched")

        let futureJSON = Data("""
        {"schemaVersion":\(TaskSchema.currentVersion + 1),"futureField":{"example":true}}
        """.utf8)
        do {
            _ = try decoder.decode(HubData.self, from: futureJSON)
            assertionFailure("a newer state must not be decoded and overwritten by an older app")
        } catch DecodingError.dataCorrupted(let context) {
            assert(context.codingPath.last?.stringValue == "schemaVersion")
        }

        // MARK: Quick add only needs a title
        var data = HubData()
        _ = TaskSchema.migrate(&data, now: t0)
        assert(data.taskCategories.map(\.id) == TaskCategory.defaults.map(\.id))
        assert(TaskLibrary.add(&data, title: "   ", now: t0) == nil, "blank title is rejected")
        let created = TaskLibrary.add(&data, title: "  准备组会  ", now: t0)!
        assert(created.title == "准备组会")
        assert(created.categoryID == TaskCategory.uncategorizedID)
        assert(created.status == .todo && created.due == nil && !created.important && !created.pinned)
        assert(created.createdAt == t0 && created.updatedAt == t0 && created.completedAt == nil && created.archivedAt == nil)
        assert(created.links.isEmpty)
        let unknownCategory = TaskLibrary.add(&data, title: "临时", categoryID: "missing", now: t0)!
        assert(unknownCategory.categoryID == TaskCategory.uncategorizedID, "unknown category falls back safely")
        _ = TaskLibrary.delete(&data, id: unknownCategory.id)

        // MARK: Edit, links and timestamps
        var draft = created
        draft.title = "准备组会 slides"
        draft.notes = "整理论文笔记"
        draft.categoryID = TaskCategory.research.id
        draft.important = true
        draft.due = at(13)
        draft.links = [
            TaskLink(url: "https://chatgpt.com/c/abc"),
            TaskLink(url: "https://github.com/openai/openai-python"),
            TaskLink(url: "https://example.com/paper"),
            TaskLink(url: "codex://threads/t1"),
        ]
        assert(draft.links.map(\.kind) == [.chatgpt, .github, .web, .codex])
        assert(TaskLibrary.update(&data, task: draft, now: t1))
        var saved = data.tasks.first(where: { $0.id == created.id })!
        assert(saved.title == "准备组会 slides" && saved.notes == "整理论文笔记")
        assert(saved.categoryID == TaskCategory.research.id)
        assert(saved.important && saved.due == at(13) && saved.links.count == 4)
        assert(saved.createdAt == t0, "created time is immutable")
        assert(saved.updatedAt == t1, "edit updates the updated time")

        // A malformed or mislabeled link can never be saved.
        var bad = saved
        bad.links = [TaskLink(url: "javascript:alert(1)", kind: .web)]
        assert(!TaskLibrary.update(&data, task: bad, now: t1.addingTimeInterval(1)))
        saved = data.tasks.first(where: { $0.id == created.id })!
        assert(saved.links.count == 4, "a rejected edit leaves the stored task unchanged")

        // MARK: Complete, restore, archive, delete
        assert(TaskLibrary.complete(&data, id: created.id, now: t2))
        saved = data.tasks.first(where: { $0.id == created.id })!
        assert(saved.status == .done && saved.completedAt == t2)
        assert(TaskLibrary.visible(data, view: .active, filter: TaskFilter(), now: now).isEmpty)
        assert(TaskLibrary.visible(data, view: .completed, filter: TaskFilter(), now: now).map(\.id) == [created.id])
        assert(TaskLibrary.restore(&data, id: created.id, now: t3))
        saved = data.tasks.first(where: { $0.id == created.id })!
        assert(saved.status == .todo && saved.completedAt == nil && saved.archivedAt == nil)
        assert(TaskLibrary.visible(data, view: .active, filter: TaskFilter(), now: now).map(\.id) == [created.id])

        _ = TaskLibrary.complete(&data, id: created.id, now: t3)
        assert(TaskLibrary.archive(&data, id: created.id, now: t4))
        assert(data.tasks.count == 1, "archiving never deletes the task")
        saved = data.tasks.first(where: { $0.id == created.id })!
        assert(saved.archivedAt == t4 && saved.status == .done && saved.links.count == 4)
        assert(TaskLibrary.visible(data, view: .completed, filter: TaskFilter(), now: now).isEmpty)
        assert(TaskLibrary.visible(data, view: .archived, filter: TaskFilter(), now: now).map(\.id) == [created.id])
        assert(TaskLibrary.restore(&data, id: created.id, now: t5))
        saved = data.tasks.first(where: { $0.id == created.id })!
        assert(saved.archivedAt == nil && saved.status == .todo && saved.completedAt == nil)
        assert(saved.title == "准备组会 slides" && saved.links.count == 4, "restore keeps the content")

        var deleted = data
        assert(TaskLibrary.delete(&deleted, id: created.id))
        assert(deleted.tasks.isEmpty)
        assert(TaskLibrary.delete(&deleted, id: created.id) == false, "deleting twice is a no-op")

        // MARK: Categories: fixed defaults, custom rename/delete, no task loss
        assert(!TaskLibrary.renameCategory(&data, id: TaskCategory.life.id, to: "家务"))
        assert(!TaskLibrary.deleteCategory(&data, id: TaskCategory.uncategorizedID))
        assert(data.tasks.count == 1, "refusing a default delete keeps its tasks")
        let custom = TaskLibrary.addCategory(&data, name: "  健身  ", now: t1)!
        assert(custom.name == "健身" && custom.builtin == false)
        assert(TaskLibrary.addCategory(&data, name: "健身", now: t1) == nil, "duplicate names are rejected")
        assert(TaskLibrary.addCategory(&data, name: "FIT", now: t1) != nil)
        assert(TaskLibrary.addCategory(&data, name: String(repeating: "字", count: 25), now: t1) == nil)
        assert(TaskLibrary.addCategory(&data, name: TaskCategory.course.name, now: t1) == nil)
        assert(TaskLibrary.renameCategory(&data, id: custom.id, to: "运动"))
        assert(TaskLibrary.addCategory(&data, name: "TRIM", now: t1) != nil)
        assert(TaskLibrary.renameCategory(&data, id: custom.id, to: "运动") == true, "renaming to itself is allowed")
        assert(!TaskLibrary.renameCategory(&data, id: custom.id, to: "TRIM"), "rename cannot collide case-insensitively")

        var categoryData = data
        var owned = categoryData.tasks[0]
        owned.categoryID = custom.id
        assert(TaskLibrary.update(&categoryData, task: owned, now: t2))
        assert(TaskLibrary.taskCount(categoryID: custom.id, in: categoryData) == 1)
        assert(TaskLibrary.deleteCategory(&categoryData, id: custom.id))
        assert(!categoryData.taskCategories.contains(where: { $0.id == custom.id }))
        assert(categoryData.tasks.count == 1, "category deletion never deletes tasks")
        assert(categoryData.tasks[0].categoryID == TaskCategory.uncategorizedID)
        assert(categoryData.tasks[0].title == owned.title && categoryData.tasks[0].links.count == owned.links.count)
        assert(!TaskLibrary.deleteCategory(&categoryData, id: "missing"))

        // MARK: Search, filters and sorting
        var queryData = HubData()
        _ = TaskSchema.migrate(&queryData, now: now)
        let course = TaskCategory.course.id
        let research = TaskCategory.research.id
        let life = TaskCategory.life.id

        var alpha = TaskLibrary.add(&queryData, title: "机器学习作业", now: at(9))!
        alpha.notes = "读论文 attention"
        alpha.categoryID = course
        alpha.important = true
        alpha.due = at(11)
        assert(TaskLibrary.update(&queryData, task: alpha, now: at(9, 10)))

        var beta = TaskLibrary.add(&queryData, title: "写投稿信", now: at(10))!
        beta.notes = "机器学习 项目"
        beta.categoryID = research
        beta.due = at(12)
        assert(TaskLibrary.update(&queryData, task: beta, now: at(10, 10)))
        let betaUpdated = queryData.tasks.first(where: { $0.id == beta.id })!.updatedAt

        var gamma = TaskLibrary.add(&queryData, title: "买牛奶", now: at(11))!
        gamma.notes = "生活采购"
        gamma.categoryID = life
        gamma.due = at(10)
        assert(TaskLibrary.update(&queryData, task: gamma, now: at(11, 10)))

        var delta = TaskLibrary.add(&queryData, title: "旧作业", now: at(8))!
        delta.categoryID = course
        assert(TaskLibrary.update(&queryData, task: delta, now: at(8, 10)))
        assert(TaskLibrary.complete(&queryData, id: delta.id, now: at(8, 30)))

        var epsilon = TaskLibrary.add(&queryData, title: "归档任务", now: at(7))!
        epsilon.categoryID = life
        assert(TaskLibrary.update(&queryData, task: epsilon, now: at(7, 10)))
        assert(TaskLibrary.archive(&queryData, id: epsilon.id, now: at(7, 20)))

        var zeta = TaskLibrary.add(&queryData, title: "ML Reading", now: at(6))!
        zeta.notes = "Papers"
        zeta.status = .doing
        zeta.categoryID = research
        assert(TaskLibrary.update(&queryData, task: zeta, now: at(6, 10)))

        var filter = TaskFilter()
        let active = TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar)
        assert(Set(active.map(\.id)) == [alpha.id, beta.id, gamma.id, zeta.id].reduce(into: Set<String>()) { $0.insert($1) })
        assert(!active.contains(where: { $0.id == delta.id || $0.id == epsilon.id }), "done and archived are not in the default view")
        let completed = TaskLibrary.visible(queryData, view: .completed, filter: filter, now: now, calendar: calendar)
        assert(completed.map(\.id) == [delta.id])
        let archived = TaskLibrary.visible(queryData, view: .archived, filter: filter, now: now, calendar: calendar)
        assert(archived.map(\.id) == [epsilon.id])

        filter.query = "机器学习"
        let searched = TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar)
        assert(Set(searched.map(\.id)) == [alpha.id, beta.id], "title and notes are both searched")
        filter.query = "ml"
        assert(TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar).map(\.id) == [zeta.id],
               "search is case-insensitive")
        filter.query = "  论文  "
        assert(TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar).map(\.id) == [alpha.id],
               "search trims whitespace and matches notes")
        filter.query = ""

        filter.categoryID = research
        assert(Set(TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar).map(\.id)) == [beta.id, zeta.id])
        filter.categoryID = nil
        filter.status = .doing
        assert(TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar).map(\.id) == [zeta.id])
        filter.status = nil
        filter.importantOnly = true
        assert(TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar).map(\.id) == [alpha.id])
        filter.importantOnly = false

        filter.due = .overdue
        assert(TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar).map(\.id) == [gamma.id])
        filter.due = .today
        assert(TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar).map(\.id) == [alpha.id])
        filter.due = .week
        assert(Set(TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar).map(\.id)) == [alpha.id, beta.id])
        filter.due = .noDue
        assert(TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar).map(\.id) == [zeta.id])
        filter.due = .all

        filter.sort = .due
        let byDue = TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar).map(\.id)
        assert(byDue == [gamma.id, alpha.id, beta.id, zeta.id], "due order puts dated tasks first and undated last")

        filter.sort = .updated
        let byUpdated = TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar).map(\.id)
        assert(byUpdated.first == gamma.id, "most recently updated first")
        assert(byUpdated.contains(beta.id) && byUpdated.contains(alpha.id))

        assert(TaskLibrary.togglePin(&queryData, id: gamma.id, now: at(11, 20)))
        filter.sort = .updated
        let pinnedFirst = TaskLibrary.visible(queryData, view: .active, filter: filter, now: now, calendar: calendar)
        assert(pinnedFirst.first?.id == gamma.id, "手动置顶 takes precedence over the chosen sort")
        assert(pinnedFirst.first?.pinned == true && pinnedFirst.first?.pinnedAt == at(11, 20))
        assert(TaskLibrary.togglePin(&queryData, id: gamma.id, now: at(11, 30)))
        assert(!queryData.tasks.first(where: { $0.id == gamma.id })!.pinned)

        assert(TaskLibrary.toggleImportant(&queryData, id: gamma.id, now: at(11, 40)))
        assert(queryData.tasks.first(where: { $0.id == gamma.id })!.important)

        // MARK: Safe links
        assert(Links.validTaskLink("https://chatgpt.com/c/test"))
        assert(Links.validTaskLink("https://chat.openai.com/c/test"))
        assert(Links.validTaskLink("codex://threads/test"))
        assert(Links.validTaskLink("https://github.com/openai/openai-python"))
        assert(Links.validTaskLink("https://www.github.com/openai"))
        assert(Links.validTaskLink("https://example.com/a?b=1#c"))
        assert(Links.validTaskLink("http://example.com"))
        assert(!Links.validTaskLink(""))
        assert(!Links.validTaskLink("file:///etc/passwd"))
        assert(!Links.validTaskLink("javascript:alert(1)"))
        assert(!Links.validTaskLink("dsh://open"))
        assert(Links.taskLinkKind("https://chatgpt.com.evil.example/c/test") == .web,
               "a lookalike ChatGPT host is only an ordinary web link")
        assert(Links.validTaskLink("https://chatgpt.com.evil.example/c/test"))
        assert(!Links.validTaskLink("https://user:pass@example.com/"))
        assert(Links.validTaskLink("https://github.com"))
        assert(!Links.validTaskLink(TaskLink(url: "https://chatgpt.com/c/test", kind: .web)),
               "a mislabeled link is refused")
        assert(!Links.validTaskLink(TaskLink(url: "https://example.com", kind: .github)))
        assert(Links.taskLinkKind("https://github.com/x") == .github)
        assert(Links.taskLinkKind("https://chatgpt.com/c/x") == .chatgpt)
        assert(Links.taskLinkKind("codex://threads/x") == .codex)
        assert(Links.taskLinkKind("https://example.com/x") == .web)
        assert(Links.taskLinkKind("https://github.com.evil.example/x") == .web, "lookalike hosts are ordinary web links")
        // The reminder/inbox URL policy stays exactly as strict as before.
        assert(Links.valid("https://chatgpt.com/c/test"))
        assert(!Links.valid("https://github.com/openai"))
        assert(!Links.valid("https://example.com"))

        // MARK: Reboot persistence
        let encoded = try encoder.encode(queryData)
        let restored = try decoder.decode(HubData.self, from: encoded)
        assert(restored.schemaVersion == TaskSchema.currentVersion)
        assert(restored.tasks.count == queryData.tasks.count)
        assert(restored.taskCategories.map(\.id) == queryData.taskCategories.map(\.id))
        let restoredAlpha = restored.tasks.first(where: { $0.id == alpha.id })!
        assert(restoredAlpha.title == "机器学习作业" && restoredAlpha.notes == "读论文 attention")
        assert(restoredAlpha.due == at(11) && restoredAlpha.important)
        assert(restored.tasks.first(where: { $0.id == epsilon.id })?.archivedAt == at(7, 20))
        assert(restored.tasks.first(where: { $0.id == delta.id })?.completedAt == at(8, 30))
        assert(restored.tasks.first(where: { $0.id == beta.id })?.updatedAt == betaUpdated)
        assert(TaskLibrary.visible(restored, view: .active, filter: TaskFilter(), now: now, calendar: calendar).count == 4)

        // A real file round-trip, close to an app restart.
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mira-task-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        try encoded.write(to: file, options: .atomic)
        let rebooted = try decoder.decode(HubData.self, from: Data(contentsOf: file))
        assert(rebooted.tasks.count == queryData.tasks.count)
        assert(rebooted.taskCategories.count == queryData.taskCategories.count)

        // MARK: Today's agenda follows the same pinned task through completion
        var agenda = HubData()
        let first = TaskLibrary.add(&agenda, title: "无截止日期", now: t0)!
        var second = TaskLibrary.add(&agenda, title: "未来截止日期", now: t0)!
        second.due = at(20)
        assert(TaskLibrary.update(&agenda, task: second, now: t0))
        let archivedTask = TaskLibrary.add(&agenda, title: "已归档", now: t0)!
        _ = TaskLibrary.add(&agenda, title: "未置顶", now: t0)!
        assert(TaskLibrary.pinnedForToday(agenda.tasks, now: t0, calendar: calendar).isEmpty)
        assert(TaskLibrary.togglePin(&agenda, id: first.id, now: t1))
        assert(TaskLibrary.togglePin(&agenda, id: second.id, now: t2))
        assert(TaskLibrary.togglePin(&agenda, id: archivedTask.id, now: t3))
        assert(TaskLibrary.archive(&agenda, id: archivedTask.id, now: t3))
        assert(TaskLibrary.pinnedForToday(agenda.tasks, now: t3, calendar: calendar).map(\.id) == [second.id, first.id])
        assert(TaskLibrary.complete(&agenda, id: second.id, now: t4))
        assert(TaskLibrary.pinnedForToday(agenda.tasks, now: t4, calendar: calendar).first?.status == .done)
        assert(TaskLibrary.pinnedForToday(agenda.tasks, now: at(12), calendar: calendar).map(\.id) == [first.id])
        assert(TaskLibrary.togglePin(&agenda, id: first.id, now: t5))
        assert(TaskLibrary.pinnedForToday(agenda.tasks, now: at(12), calendar: calendar).isEmpty)

        // MARK: Repair pass
        var repair = HubData()
        var broken = TaskLibrary.add(&repair, title: "坏引用", now: t0)!
        broken.categoryID = "gone"
        broken.updatedAt = t0.addingTimeInterval(-60)
        broken.pinned = true
        broken.links = [TaskLink(url: "https://chatgpt.com/c/x", kind: .web)]
        repair.tasks = [broken]
        repair.taskCategories = TaskCategory.defaults
        assert(TaskSchema.migrate(&repair, now: t1))
        assert(repair.tasks[0].categoryID == TaskCategory.uncategorizedID)
        assert(repair.tasks[0].updatedAt == repair.tasks[0].createdAt)
        assert(repair.tasks[0].pinnedAt == repair.tasks[0].updatedAt)
        assert(repair.tasks[0].links[0].kind == .chatgpt)

        print("PASS: task persistence + legacy migration, quick add, edit/timestamps, complete/restore, archive/restore, delete, category safety, search/filter/sort/pin, link safety, reboot round-trip")
    }
}
