import Foundation

// MARK: - Hub 通用网页监控

@MainActor
extension Hub {
    var webWatchStatus: String {
        guard !webWatches.isEmpty else { return "尚未添加" }
        if let id = webWatchBusyID, let watch = webWatches.first(where: { $0.id == id }) {
            return "正在检查《\(watch.name)》…"
        }
        if let failed = webWatches.first(where: { $0.enabled && $0.lastError != nil }) {
            return "需要处理 · \(failed.name)"
        }
        let enabled = webWatches.filter(\.enabled).count
        let listItems = webWatches.filter { $0.mode == .list }.reduce(0) { $0 + $1.itemCount }
        return "\(webWatches.count) 个监控 · \(enabled) 个自动检查 · \(listItems) 个条目"
    }

    func webWatch(_ id: String) -> WebWatch? {
        webWatches.first { $0.id == id }
    }

    @discardableResult
    func saveWebWatches() -> Bool {
        do {
            try WebWatchStore.save(webWatches, root: root, encoder: encoder)
            return true
        } catch {
            self.error = "网页监控配置保存失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 保存新监控或编辑后的监控。`resetBaseline` 表示地址、模式或识别的列表变了，
    /// 这时把当前页面当作新基线，不补发旧条目。
    func saveWebWatch(_ draft: WebWatch, baselineItems: [WebWatchItem], resetBaseline: Bool) {
        var watch = draft
        let existing = webWatches.first { $0.id == watch.id }
        if let existing {
            watch.createdAt = existing.createdAt
            if !resetBaseline {
                watch.baselineAt = existing.baselineAt
                watch.knownKeys = existing.knownKeys
                watch.fingerprint = existing.fingerprint
                watch.itemCount = existing.itemCount
                watch.textLength = existing.textLength
                watch.lastCheck = existing.lastCheck
                watch.lastError = existing.lastError
                watch.retryAt = existing.retryAt
            }
        }
        if watch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            watch.name = watch.host
        }
        if resetBaseline {
            let now = Date()
            watch.baselineAt = now
            watch.knownKeys = baselineItems.map(\.key)
            watch.itemCount = baselineItems.filter { $0.status != "已提交" }.count
            watch.lastCheck = now
            watch.lastError = nil
            watch.retryAt = nil
            if watch.mode == .page, watch.fingerprint == nil,
               let existingFingerprint = existing?.fingerprint {
                watch.fingerprint = existingFingerprint
            }
        }
        if let index = webWatches.firstIndex(where: { $0.id == watch.id }) {
            webWatches[index] = watch
        } else {
            webWatches.append(watch)
        }

        var imported = 0
        if resetBaseline, watch.mode == .list {
            let result = importWatchTasks(watch, items: baselineItems, now: Date())
            imported = result.added
            if result.added > 0 || result.completed > 0 || result.updated > 0 { _ = save() }
        }
        _ = saveWebWatches()
        if imported > 0 {
            notice = "已保存《\(watch.name)》，并导入 \(imported) 个当前条目到任务库。"
        } else {
            notice = "已保存网页监控《\(watch.name)》。之后发现新条目会提醒。"
        }
    }

    func resetWebWatchBaseline(_ id: String) {
        guard let index = webWatches.firstIndex(where: { $0.id == id }) else { return }
        webWatches[index].baselineAt = nil
        webWatches[index].lastCheck = nil
        webWatches[index].knownKeys = []
        _ = saveWebWatches()
    }

    func removeWebWatch(_ id: String) {
        guard let watch = webWatches.first(where: { $0.id == id }) else { return }
        webWatches.removeAll { $0.id == id }
        if webWatchBusyID == id { webWatchBusyID = nil }
        _ = saveWebWatches()
        notice = "已移除《\(watch.name)》。任务库中已导入的任务会保留。"
    }

    func setWebWatchEnabled(_ id: String, enabled: Bool) {
        guard let index = webWatches.firstIndex(where: { $0.id == id }) else { return }
        webWatches[index].enabled = enabled
        if enabled {
            webWatches[index].retryAt = nil
            webWatches[index].lastCheck = nil
        }
        _ = saveWebWatches()
        if enabled { checkWebWatch(id, force: true) }
    }

    func checkAllWebWatches() {
        guard !webWatches.isEmpty else { return }
        for index in webWatches.indices {
            webWatches[index].lastCheck = nil
            webWatches[index].retryAt = nil
        }
        _ = saveWebWatches()
        checkDueWebWatches()
    }

    /// 每次 tick 只启动一个页面检查；另一个检查会在下一次 tick 接上。
    func checkDueWebWatches(now: Date = Date()) {
        guard webWatchBusyID == nil else { return }
        guard let watch = webWatches.first(where: { candidate in
            guard candidate.enabled else { return false }
            return SyncInterval.isDue(lastCheck: candidate.lastCheck, retryAt: candidate.retryAt,
                                      interval: candidate.interval, now: now)
        }) else { return }
        checkWebWatch(watch.id)
    }

    func checkWebWatch(_ id: String, force: Bool = false) {
        guard webWatchBusyID == nil,
              let index = webWatches.firstIndex(where: { $0.id == id }) else { return }
        let watch = webWatches[index]
        if !force {
            guard watch.enabled else { return }
            guard SyncInterval.isDue(lastCheck: watch.lastCheck, retryAt: watch.retryAt,
                                     interval: watch.interval) else { return }
        }
        webWatchBusyID = id
        Task { [weak self] in
            let outcome = await WebWatchConnection.check(watch)
            self?.applyWebWatch(outcome, id: id, expected: watch)
        }
    }

    // MARK: - 应用一次检查

    private func applyWebWatch(_ rawOutcome: WebWatchOutcome, id: String, expected: WebWatch) {
        webWatchBusyID = nil
        guard let index = webWatches.firstIndex(where: { $0.id == id }) else { return }
        guard webWatches[index] == expected else { return }
        var watch = webWatches[index]
        var outcome = rawOutcome
        // Preserve existing identities when URL normalization learns new ID parameters.
        let prefix = "webwatch:\(watch.id):"
        outcome.items = outcome.items.map { item in
            guard !item.link.isEmpty else { return item }
            let matches = data.tasks.filter { task in
                task.externalKey?.hasPrefix(prefix) == true && task.links.contains { $0.url == item.link }
            }
            guard matches.count == 1, let external = matches[0].externalKey,
                  let known = watch.knownKeys.first(where: { prefix + WebWatchHash.stableID($0) == external }) else { return item }
            var migrated = item
            migrated.key = known
            return migrated
        }
        outcome.items = WebWatchPlanner.reconcile(outcome.items, knownKeys: watch.knownKeys)
        watch.coverage = outcome.coverage
        let now = outcome.checkedAt
        watch.lastCheck = now

        if let failure = outcome.error {
            watch.lastError = failure
            watch.retryAt = now.addingTimeInterval(300)
            webWatches[index] = watch
            _ = saveWebWatches()
            return
        }
        if outcome.signedOut {
            watch.lastError = "需要登录 · 点「编辑」在页面里登录后再检查"
            watch.retryAt = now.addingTimeInterval(6 * 3600)
            webWatches[index] = watch
            _ = saveWebWatches()
            return
        }
        guard let scan = outcome.scan else {
            watch.lastError = "页面没有返回可读取的内容"
            watch.retryAt = now.addingTimeInterval(300)
            webWatches[index] = watch
            _ = saveWebWatches()
            return
        }

        watch.lastError = nil
        watch.retryAt = nil
        let previous = data
        var added = 0
        var completed = 0
        var newCount = 0
        var stateChanged = false

        if watch.mode == .list {
            let firstSync = watch.baselineAt == nil
            let newItems = WebWatchPlanner.newItems(knownKeys: watch.knownKeys, current: outcome.items)
            let visibleNew = newItems.filter { $0.status != "已提交" }
            newCount = visibleNew.count
            // 每次都按当前页面完整对齐：新任务会被创建，已有任务更新，
            // 「已提交」会完成；这样删掉任务或稍后打开导入开关也能补回来。
            let result = importWatchTasks(watch, items: outcome.items, now: now)
            added = result.added
            completed = result.completed
            stateChanged = added > 0 || completed > 0 || result.updated > 0

            // Missing rows may mean pagination, a changed filter, or incomplete loading.
            // Only explicit source submission status can complete a task.
            if !firstSync, watch.notifyItems, !visibleNew.isEmpty {
                insertWatchEntries(watch, items: visibleNew, now: now)
                stateChanged = true
            }
            watch.knownKeys = WebWatchPlanner.mergedKeys(knownKeys: watch.knownKeys,
                                                         current: outcome.items)
            watch.itemCount = outcome.items.filter { $0.status != "已提交" }.count
            watch.baselineAt = watch.baselineAt ?? now
        } else {
            let firstSync = watch.fingerprint == nil
            let changed = !firstSync && watch.fingerprint != scan.fingerprint
            if changed, watch.notifyItems {
                let entry = WebWatchEntries.page(watch, from: watch.fingerprint,
                                                 to: scan.fingerprint, now: now)
                if !data.entries.contains(where: { $0.id == entry.id }) {
                    data.entries.insert(entry, at: 0)
                    stateChanged = true
                }
                newCount = 1
            }
            watch.fingerprint = scan.fingerprint
            watch.textLength = scan.textLength
            watch.baselineAt = watch.baselineAt ?? now
        }

        let saved = stateChanged ? save() : true
        if !saved {
            data = previous
            watch = webWatches[index]
            watch.lastError = "新条目已读到，但任务库保存失败；稍后重试"
            watch.retryAt = now.addingTimeInterval(300)
            webWatches[index] = watch
            _ = saveWebWatches()
            return
        }

        webWatches[index] = watch
        _ = saveWebWatches()

        if newCount > 0 {
            notice = "网页监控《\(watch.name)》发现 \(newCount) 条新内容。"
        } else if completed > 0 {
            notice = "网页监控《\(watch.name)》有 \(completed) 个条目已完成。"
        }
    }

    private func importWatchTasks(_ watch: WebWatch, items: [WebWatchItem],
                                  now: Date) -> (added: Int, completed: Int, updated: Int) {
        guard watch.mode == .list else { return (0, 0, 0) }
        let prefix = "webwatch:\(watch.id):"
        let category = TaskLibrary.categoryID(watch.categoryID, in: data.taskCategories)
        var added = 0
        var completed = 0
        var updated = 0

        for item in items {
            let title = WebWatchText.title(item)
            guard !title.isEmpty else { continue }
            let key = prefix + WebWatchHash.stableID(item.key)
            let existing = data.tasks.firstIndex { $0.externalKey == key }

            if item.status == "已提交" {
                if let index = existing,
                   ExternalTaskSync.complete(&data.tasks[index], checkedAt: now) {
                    completed += 1
                }
                continue
            }

            if let index = existing {
                var task = data.tasks[index]
                guard task.status != .done else { continue }
                let due = item.dueDate(now: now)
                var changed = false
                // An unreadable date is not evidence that the deadline was removed.
                if let due, task.due != due {
                    if let old = task.due, watch.notifyItems {
                        let entry = WebWatchEntries.deadline(watch, item: item, old: old, new: due, now: now)
                        if !data.entries.contains(where: { $0.id == entry.id }) {
                            data.entries.insert(entry, at: 0)
                        }
                    }
                    task.due = due
                    changed = true
                }
                if task.title != title { task.title = title; changed = true }
                if changed {
                    task.updatedAt = now
                    data.tasks[index] = task
                    updated += 1
                }
                continue
            }
            guard watch.importTasks else { continue }
            // 行内没有链接（onclick/SPA）时至少让任务能打开监控页。
            let taskLink = item.link.isEmpty ? watch.url : item.link
            var task = TaskItem(title: title,
                                notes: WebWatchText.notes(watchName: watch.name, item: item, now: now),
                                categoryID: category,
                                links: Links.validTaskLink(taskLink) ? [TaskLink(url: taskLink)] : [])
            task.due = item.dueDate(now: now)
            task.externalKey = key
            data.tasks.insert(task, at: 0)
            added += 1
        }
        return (added, completed, updated)
    }

    private func insertWatchEntries(_ watch: WebWatch, items: [WebWatchItem], now: Date) {
        guard !items.isEmpty else { return }
        if items.count <= 10 {
            for item in items {
                let entry = WebWatchEntries.item(watch, item: item, now: now)
                if !data.entries.contains(where: { $0.id == entry.id }) {
                    data.entries.insert(entry, at: 0)
                }
            }
        } else {
            let entry = WebWatchEntries.summary(watch, items: items, now: now)
            if !data.entries.contains(where: { $0.id == entry.id }) {
                data.entries.insert(entry, at: 0)
            }
        }
    }
}
