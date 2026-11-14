import Foundation

@main struct WebWatchTests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 9))!

        // 日期：完整日期、中文日期、无年份日期、时间、无效日期。
        func parts(_ text: String, now: Date = now) -> DateComponents? {
            guard let date = WebWatchParsing.dueDate(in: text, now: now, calendar: calendar) else { return nil }
            return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }
        let full = parts("截止 2026-11-24 23:55")
        assert(full?.year == 2026 && full?.month == 11 && full?.day == 24
               && full?.hour == 23 && full?.minute == 55, "完整日期：\(String(describing: full))")
        let chinese = parts("2026年3月5日")
        assert(chinese?.year == 2026 && chinese?.month == 3 && chinese?.day == 5
               && chinese?.hour == 23 && chinese?.minute == 59, "中文日期：\(String(describing: chinese))")
        let short = parts("11月24日 23:55")
        assert(short?.year == 2026 && short?.month == 11 && short?.day == 24
               && short?.hour == 23 && short?.minute == 55, "无年份日期：\(String(describing: short))")
        let nextYearNow = calendar.date(from: DateComponents(year: 2026, month: 12, day: 30))!
        assert(parts("1月5日", now: nextYearNow)?.year == 2027, "过去半年的无年份日期应滚到明年")
        assert(parts("2026-02-30") == nil, "2 月 30 日应判为无效")
        assert(webDate(in: "没有日期", calendar: calendar) == nil, "没有日期时应返回 nil")

        // ISO 时间带时区时不按本地 23:59 处理。
        let iso = WebWatchParsing.dueDate(in: "2026-11-24T15:55:00Z", now: now, calendar: calendar)
        assert(iso != nil, "ISO 日期应能解析")
        let isoParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: iso!)
        assert(isoParts.year == 2026 && isoParts.month == 11 && isoParts.day == 24
               && isoParts.hour == 23 && isoParts.minute == 55, "Z 时间按上海时区：\(isoParts)")

        // 状态。
        assert(WebWatchParsing.status(in: "状态：未提交") == "未提交")
        assert(WebWatchParsing.status(in: "已提交，待批阅") == "已提交")
        assert(WebWatchParsing.status(in: "已截止") == "已截止")
        assert(WebWatchParsing.status(in: "普通公告") == "")

        // 新条目去重，保持页面顺序。
        let items = [
            WebWatchItem(key: "a", title: "作业 A"),
            WebWatchItem(key: "b", title: "作业 B"),
            WebWatchItem(key: "a", title: "重复的 A")
        ]
        let new = WebWatchPlanner.newItems(knownKeys: ["b"], current: items)
        assert(new.map(\.key) == ["a"], "只保留未知且不重复的条目：\(new)")
        let merged = WebWatchPlanner.mergedKeys(knownKeys: ["old", "b"], current: items)
        assert(merged == ["a", "b", "old"], "新键在前、旧键在后：\(merged)")
        let capped = WebWatchPlanner.mergedKeys(knownKeys: ["x1", "x2"], current: [
            WebWatchItem(key: "n1", title: "1"), WebWatchItem(key: "n2", title: "2")
        ], limit: 3)
        assert(capped == ["n1", "n2", "x1"], "限制长度：\(capped)")

        // 扫描结果与条目抽取的 JSON 形态（与 JS 输出一致）。
        let scanJSON = """
        {"pageTitle":"作业中心","pageURL":"https://example.edu/hw","candidates":[
          {"selector":"#list","signature":{"tag":"section","id":"list","classes":["list"],"childTag":"article","childClasses":["row"]},"count":3,"score":24,"sampleTitles":["作业一","作业二"],"sampleDue":null,"label":"3 个条目"}
        ],"fingerprint":"abc123:42","textLength":42,"textSample":"作业中心","loginSuspected":false}
        """
        let scan = try JSONDecoder().decode(WebWatchScan.self, from: Data(scanJSON.utf8))
        assert(scan.candidates.count == 1 && scan.candidates[0].selector == "#list")
        assert(scan.candidates[0].sampleDue == nil && scan.fingerprint == "abc123:42")

        let extractJSON = """
        {"items":[{"key":"https://example.edu/hw/1","title":"作业一","link":"https://example.edu/hw/1","dueText":"2026-11-24 23:55","status":"未提交","subtitle":""}],"found":true}
        """
        let extraction = try JSONDecoder().decode(WebWatchExtraction.self, from: Data(extractJSON.utf8))
        assert(extraction.found && extraction.items.count == 1)
        assert(extraction.items[0].dueDate(now: now, calendar: calendar) != nil)

        // 地址校验：任意 http/https，拒绝脚本与其他 scheme。
        assert(WebWatchValidation.url("https://jwc.pku.edu.cn/hw") != nil)
        assert(WebWatchValidation.url("http://old.example.edu/notice") != nil)
        assert(WebWatchValidation.url("ftp://example.edu/file") == nil)
        assert(WebWatchValidation.url("javascript:alert(1)") == nil)
        assert(WebWatchValidation.url("https://user:pass@example.edu/") == nil)

        // 稳定哈希与提醒身份。
        assert(WebWatchHash.stableID("same") == WebWatchHash.stableID("same"))
        assert(WebWatchHash.stableID("same") != WebWatchHash.stableID("other"))
        let watch = WebWatch(id: "watch-1", name: "数据结构作业", url: "https://example.edu/hw",
                             selector: "#list", signature: WebWatchSignature(tag: "section"))
        let item = WebWatchItem(key: "https://example.edu/hw/1", title: "作业一",
                                link: "https://example.edu/hw/1", dueText: "2026-11-24 23:55",
                                status: "未提交")
        let first = WebWatchEntries.item(watch, item: item, now: now)
        let second = WebWatchEntries.item(watch, item: item, now: now)
        assert(first.id == second.id, "同一条目的提醒身份应稳定")
        assert(first.allowWebLink == true && first.courseUpdate, "网页监控提醒允许普通链接且只提醒一次")
        assert(WebWatchEntries.page(watch, from: "a", to: "b", now: now).id
               != WebWatchEntries.page(watch, from: "a", to: "c", now: now).id, "页面指纹变化应生成新提醒")
        assert(WebWatchText.notes(watchName: "数据结构作业", item: item, now: now)
            .contains("来自网页监控") && WebWatchText.notes(watchName: "数据结构作业", item: item, now: now)
            .contains("截止"))

        let deadline = WebWatchEntries.deadline(watch, item: item, old: now,
                                                 new: now.addingTimeInterval(86400), now: now)
        assert(deadline.title.contains("截止时间调整"))
        assert(deadline.body.contains("→") && deadline.allowWebLink == true && deadline.courseUpdate)

        let rescheduled = WebWatchItem(key: "title:作业|2026-12-20", title: "作业", dueText: "2026-12-20")
        assert(WebWatchPlanner.reconcile([rescheduled], knownKeys: ["title:作业|2026-12-10"])[0].key == "title:作业|2026-12-10")
        var scoped = rescheduled
        scoped.key = "https://example.edu/course/1::" + scoped.key
        assert(WebWatchPlanner.reconcile([scoped], knownKeys: ["https://example.edu/course/1::title:作业|2026-12-10"])[0].key.hasSuffix("2026-12-10"))
        assert(WebWatchPlanner.reconcile([rescheduled, rescheduled], knownKeys: ["title:作业|2026-12-10"])[0].key == rescheduled.key)
        var configured = watch
        configured.route = WebWatchRoute(courseURLs: ["https://example.edu/course/1"], nextSelector: "#next")
        let roundtrip = try JSONDecoder().decode(WebWatch.self, from: JSONEncoder().encode(configured))
        assert(roundtrip.route == configured.route)

        // 配置落盘 0600，旧/缺字段配置按默认值升级。
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mira-webwatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        var saved = watch
        saved.knownKeys = ["k1", "k2"]
        saved.lastCheck = now
        saved.createdAt = now
        try WebWatchStore.save([saved], root: root, encoder: encoder)
        let loaded = WebWatchStore.load(root: root, decoder: decoder)
        assert(loaded.count == 1 && loaded[0] == saved, "配置往返：\(loaded)")
        let attributes = try FileManager.default.attributesOfItem(atPath: WebWatchStore.url(root: root).path)
        assert((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "配置文件必须是 0600")

        let minimal = """
        {"schemaVersion":1,"watches":[{"id":"w-old","name":"旧配置","url":"https://example.edu/list"}]}
        """
        let upgraded = try decoder.decode(WebWatchStoreData.self, from: Data(minimal.utf8)).watches
        assert(upgraded.count == 1 && upgraded[0].mode == .list && upgraded[0].enabled)
        assert(upgraded[0].intervalMinutes == SyncInterval.defaultMinutes && upgraded[0].importTasks)

        print("PASS: 网页监控日期/状态/去重/扫描解析/地址校验/提醒身份/配置落盘")
    }

    private static func webDate(in text: String, calendar: Calendar) -> Date? {
        WebWatchParsing.dueDate(in: text, now: calendar.date(from: DateComponents(year: 2026, month: 11, day: 13))!,
                                calendar: calendar)
    }
}
