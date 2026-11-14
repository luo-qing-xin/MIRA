import Foundation

// MARK: - 模型

enum WebWatchMode: String, Codable, CaseIterable, Identifiable {
    case list
    case page

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: return "列表条目"
        case .page: return "整页变化"
        }
    }

    var hint: String {
        switch self {
        case .list: return "识别页面上的重复条目，新条目写入任务库。"
        case .page: return "页面正文有变化时提醒一次，不拆条目。"
        }
    }
}

/// 页面容器的轻量特征。保存它是为了在 CSS 路径因页面改版失效时，
/// 还能按标签、类名和子项结构找回列表，而不是立刻要求用户重新训练。
struct WebWatchSignature: Codable, Equatable {
    var tag: String = ""
    var id: String = ""
    var classes: [String] = []
    var childTag: String = ""
    var childClasses: [String] = []
}

struct WebWatchCandidate: Codable, Equatable, Identifiable {
    var selector: String
    var signature: WebWatchSignature
    var count: Int
    var score: Int
    var sampleTitles: [String]
    var sampleDue: String?
    var label: String

    var id: String { selector }
}

struct WebWatchItem: Codable, Equatable, Identifiable {
    var key: String
    var title: String
    var link: String
    var dueText: String
    var status: String
    var subtitle: String

    var id: String { key }

    init(key: String, title: String, link: String = "", dueText: String = "",
         status: String = "", subtitle: String = "") {
        self.key = key
        self.title = title
        self.link = link
        self.dueText = dueText
        self.status = status
        self.subtitle = subtitle
    }

    func dueDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        WebWatchParsing.dueDate(in: dueText, now: now, calendar: calendar)
    }
}

/// 页面扫描结果，字段与 `WebWatchScript` 的 JS 返回值一一对应。
struct WebWatchScan: Codable, Equatable {
    var pageTitle: String
    var pageURL: String
    var candidates: [WebWatchCandidate]
    var fingerprint: String
    var textLength: Int
    var textSample: String
    var loginSuspected: Bool

    init(pageTitle: String = "", pageURL: String = "", candidates: [WebWatchCandidate] = [],
         fingerprint: String = "", textLength: Int = 0, textSample: String = "",
         loginSuspected: Bool = false) {
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        self.candidates = candidates
        self.fingerprint = fingerprint
        self.textLength = textLength
        self.textSample = textSample
        self.loginSuspected = loginSuspected
    }
}

struct WebWatchExtraction: Codable, Equatable {
    var items: [WebWatchItem]
    var found: Bool

    init(items: [WebWatchItem] = [], found: Bool = false) {
        self.items = items
        self.found = found
    }
}

// MARK: - 本地配置

/// 一个监控只保存「看哪个页面、看哪一块、怎么提醒」，不保存 Cookie。
/// 登录态放在 MIRA 自己的 WKWebView 数据仓库里，由 WebKit 管理。
struct WebWatchRoute: Codable, Equatable {
    var courseURLs: [String] = []
    var entrySelector = ""
    var frameSelector = ""
    var titleSelector = ""
    var dueSelector = ""
    var statusSelector = ""
    var nextSelector = ""
    var maxPages = 20
}

struct WebWatch: Codable, Equatable, Identifiable {
    var route: WebWatchRoute?
    var coverage: String?
    var id: String
    var name: String
    var url: String
    var mode: WebWatchMode
    var selector: String
    var signature: WebWatchSignature?
    var intervalMinutes: Int
    var enabled: Bool
    var importTasks: Bool
    var autoComplete: Bool
    var notifyItems: Bool
    var categoryID: String
    var baselineAt: Date?
    var lastCheck: Date?
    var lastError: String?
    var retryAt: Date?
    /// 已见过的条目键，只保留最近一批，用于判断「新」。
    var knownKeys: [String]
    /// 整页模式的内容指纹；不保存正文。
    var fingerprint: String?
    var itemCount: Int
    var textLength: Int
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String = "", url: String = "",
         mode: WebWatchMode = .list, selector: String = "",
         signature: WebWatchSignature? = nil,
         intervalMinutes: Int = SyncInterval.defaultMinutes,
         enabled: Bool = true, importTasks: Bool = true, autoComplete: Bool = false,
         notifyItems: Bool = true, categoryID: String = TaskCategory.course.id,
         baselineAt: Date? = nil, lastCheck: Date? = nil, lastError: String? = nil,
         retryAt: Date? = nil, knownKeys: [String] = [], fingerprint: String? = nil,
         itemCount: Int = 0, textLength: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.url = url
        self.mode = mode
        self.selector = selector
        self.signature = signature
        self.intervalMinutes = intervalMinutes
        self.enabled = enabled
        self.importTasks = importTasks
        self.autoComplete = autoComplete
        self.notifyItems = notifyItems
        self.categoryID = categoryID
        self.baselineAt = baselineAt
        self.lastCheck = lastCheck
        self.lastError = lastError
        self.retryAt = retryAt
        self.knownKeys = knownKeys
        self.fingerprint = fingerprint
        self.itemCount = itemCount
        self.textLength = textLength
        self.createdAt = createdAt
    }

    var interval: TimeInterval { TimeInterval(max(5, intervalMinutes)) * 60 }
    var host: String { WebWatchValidation.url(url)?.host ?? url }

    enum CodingKeys: String, CodingKey {
        case id, name, url, mode, selector, signature, intervalMinutes
        case enabled, importTasks, autoComplete, notifyItems, categoryID
        case baselineAt, lastCheck, lastError, retryAt, knownKeys
        case fingerprint, itemCount, textLength, createdAt, route, coverage
    }

    /// 新字段一律用 decodeIfPresent 和默认值，旧配置升级时不会整份丢弃。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        route = try values.decodeIfPresent(WebWatchRoute.self, forKey: .route)
        coverage = try values.decodeIfPresent(String.self, forKey: .coverage)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
        mode = try values.decodeIfPresent(WebWatchMode.self, forKey: .mode) ?? .list
        selector = try values.decodeIfPresent(String.self, forKey: .selector) ?? ""
        signature = try values.decodeIfPresent(WebWatchSignature.self, forKey: .signature)
        intervalMinutes = SyncInterval.normalize(
            try values.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? SyncInterval.defaultMinutes)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        importTasks = try values.decodeIfPresent(Bool.self, forKey: .importTasks) ?? true
        autoComplete = try values.decodeIfPresent(Bool.self, forKey: .autoComplete) ?? false
        notifyItems = try values.decodeIfPresent(Bool.self, forKey: .notifyItems) ?? true
        categoryID = try values.decodeIfPresent(String.self, forKey: .categoryID) ?? TaskCategory.course.id
        baselineAt = try values.decodeIfPresent(Date.self, forKey: .baselineAt)
        lastCheck = try values.decodeIfPresent(Date.self, forKey: .lastCheck)
        lastError = try values.decodeIfPresent(String.self, forKey: .lastError)
        retryAt = try values.decodeIfPresent(Date.self, forKey: .retryAt)
        knownKeys = try values.decodeIfPresent([String].self, forKey: .knownKeys) ?? []
        fingerprint = try values.decodeIfPresent(String.self, forKey: .fingerprint)
        itemCount = try values.decodeIfPresent(Int.self, forKey: .itemCount) ?? 0
        textLength = try values.decodeIfPresent(Int.self, forKey: .textLength) ?? 0
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

struct WebWatchStoreData: Codable {
    var schemaVersion = 1
    var watches: [WebWatch] = []
}

enum WebWatchStore {
    static let fileName = "web-watches.json"
    static let limit = 40

    static func url(root: URL) -> URL { root.appendingPathComponent(fileName) }

    static func load(root: URL, decoder: JSONDecoder) -> [WebWatch] {
        guard let data = try? Data(contentsOf: url(root: root)),
              let payload = try? decoder.decode(WebWatchStoreData.self, from: data) else {
            return []
        }
        var seen = Set<String>()
        return Array(payload.watches.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    static func save(_ watches: [WebWatch], root: URL, encoder: JSONEncoder) throws {
        let target = url(root: root)
        let payload = WebWatchStoreData(watches: Array(watches.prefix(limit)))
        try encoder.encode(payload).write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
}

// MARK: - 校验与解析

enum WebWatchValidation {
    /// 监控目标允许任意 http/https 主机；这里只做结构校验。
    static func url(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func normalized(_ raw: String) -> String? {
        url(raw)?.absoluteString
    }
}

enum WebWatchParsing {
    private static let fullDate = try! NSRegularExpression(
        pattern: #"(20\d{2})\s*[年\-/.]\s*(\d{1,2})\s*[月\-/.]\s*(\d{1,2})\s*日?(?:[ T]*(\d{1,2})[:：](\d{2}))?"#)
    private static let shortDate = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})\s*[月\-/.]\s*(\d{1,2})\s*日?(?:[ T]*(\d{1,2})[:：](\d{2}))?"#)
    private static let isoPattern = try! NSRegularExpression(
        pattern: #"20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})"#)

    static func dueDate(in text: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)
        // 带时区的 ISO 时间优先按绝对时间解释，避免把 UTC 的 15:55 当成北京时间。
        if let match = isoPattern.firstMatch(in: trimmed, range: range),
           let iso = isoDate(ns.substring(with: match.range)) {
            return iso
        }
        if let match = fullDate.firstMatch(in: trimmed, range: range) {
            return date(match, ns: ns, yearIndex: 1, monthIndex: 2, dayIndex: 3,
                        hourIndex: 4, minuteIndex: 5, now: now, calendar: calendar)
        }
        if let match = shortDate.firstMatch(in: trimmed, range: range) {
            return date(match, ns: ns, yearIndex: nil, monthIndex: 1, dayIndex: 2,
                        hourIndex: 3, minuteIndex: 4, now: now, calendar: calendar)
        }
        return nil
    }

    private static func date(_ match: NSTextCheckingResult, ns: NSString, yearIndex: Int?,
                             monthIndex: Int, dayIndex: Int, hourIndex: Int, minuteIndex: Int,
                             now: Date, calendar: Calendar) -> Date? {
        func group(_ index: Int) -> String? {
            guard index < match.numberOfRanges else { return nil }
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return nil }
            return ns.substring(with: range)
        }
        guard let month = group(monthIndex).flatMap(Int.init),
              let day = group(dayIndex).flatMap(Int.init),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        let hasYear = yearIndex != nil
        let year = yearIndex.flatMap { group($0) }.flatMap(Int.init) ?? calendar.component(.year, from: now)
        let hour = group(hourIndex).flatMap(Int.init)
        let minute = group(minuteIndex).flatMap(Int.init)
        if let hour, !(0...23).contains(hour) { return nil }
        if let minute, !(0...59).contains(minute) { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour ?? 23
        components.minute = minute ?? 59
        components.second = 0
        guard let result = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: result)
        guard check.year == year, check.month == month, check.day == day else { return nil }

        // 没有年份的日期（如「11月24日」）若已过去半年，按下一年的日期理解。
        if !hasYear, result < now.addingTimeInterval(-180 * 86400) {
            components.year = year + 1
            return calendar.date(from: components)
        }
        return result
    }

    private static func isoDate(_ text: String) -> Date? {
        guard text.contains("T") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func status(in text: String) -> String {
        if text.range(of: #"未提交|未交|待完成|待办|未开始"#, options: .regularExpression) != nil {
            return "未提交"
        }
        if text.range(of: #"已截止|已过期|逾期|已结束"#, options: .regularExpression) != nil {
            return "已截止"
        }
        if text.range(of: #"待批阅|已批阅|已提交|已完成|已交"#, options: .regularExpression) != nil {
            return "已提交"
        }
        return ""
    }
}

// MARK: - 稳定键与去重

enum WebWatchHash {
    /// FNV-1a 64 位。只用于本地去重键和页面指纹，不做安全散列。
    static func stableID(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

enum WebWatchPlanner {
    /// 保持页面顺序，同时去掉重复键；首次同步时返回全部条目。
    static func newItems(knownKeys: [String], current: [WebWatchItem]) -> [WebWatchItem] {
        let known = Set(knownKeys)
        var seen = Set<String>()
        return current.filter { item in
            guard !known.contains(item.key), seen.insert(item.key).inserted else { return false }
            return true
        }
    }

    /// Dates are mutable. Reuse a unique historical title identity when no URL is available.
    /// Ambiguous duplicate titles are deliberately left unmatched.
    static func reconcile(_ items: [WebWatchItem], knownKeys: [String]) -> [WebWatchItem] {
        items.map { item in
            guard item.link.isEmpty, let marker = item.key.range(of: "title:", options: .backwards) else { return item }
            let scope = String(item.key[..<marker.lowerBound])
            let prefix = scope + "title:" + item.title
            let matches = knownKeys.filter { $0 == prefix || $0.hasPrefix(prefix + "|") }
            let current = items.filter { $0.link.isEmpty && $0.title == item.title && $0.key.hasPrefix(scope + "title:") }
            guard Set(matches).count == 1, current.count == 1 else { return item }
            var result = item
            result.key = matches[0]
            return result
        }
    }

    /// 把当前页面的键并入已见集合，新键在前，旧键在后，最多 800 个。
    static func mergedKeys(knownKeys: [String], current: [WebWatchItem], limit: Int = 800) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for key in current.map(\.key) + knownKeys where seen.insert(key).inserted {
            ordered.append(key)
        }
        return Array(ordered.prefix(limit))
    }
}

// MARK: - 任务与提醒文案

enum WebWatchText {
    static func title(_ item: WebWatchItem) -> String {
        let clean = item.title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(120))
    }

    static func dueLabel(_ due: Date?) -> String {
        guard let due else { return "未设置截止时间" }
        return "截止 " + due.formatted(date: .abbreviated, time: .shortened)
    }

    static func notes(watchName: String, item: WebWatchItem, now: Date = Date()) -> String {
        var parts = ["来自网页监控", watchName]
        if !item.status.isEmpty { parts.append(item.status) }
        parts.append(dueLabel(item.dueDate(now: now)))
        return parts.joined(separator: " · ")
    }

    static func pageSummary(_ watch: WebWatch, changedAt: Date) -> String {
        "《\(watch.name)》页面内容有变化 · " + changedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

enum WebWatchEntries {
    static func item(_ watch: WebWatch, item: WebWatchItem, now: Date = Date()) -> Entry {
        Entry(id: "webwatch-\(watch.id)-\(WebWatchHash.stableID(item.key))",
              title: String(WebWatchText.title(item).prefix(60)),
              body: "\(watch.name) · \(item.status.isEmpty ? "新条目" : item.status) · \(WebWatchText.dueLabel(item.dueDate(now: now)))",
              source: "网页监控", status: "新条目",
              link: item.link.isEmpty ? watch.url : item.link,
              date: now, allowWebLink: true)
    }

    static func deadline(_ watch: WebWatch, item: WebWatchItem, old: Date, new: Date,
                         now: Date = Date()) -> Entry {
        let identity = item.key + "|" + String(old.timeIntervalSince1970) + "|" + String(new.timeIntervalSince1970) + "|" + String(now.timeIntervalSince1970)
        return Entry(id: "webwatch-\(watch.id)-deadline-\(WebWatchHash.stableID(identity))",
                     title: String("截止时间调整 · \(WebWatchText.title(item))".prefix(60)),
                     body: "\(watch.name) · 原\(WebWatchText.dueLabel(old)) → \(WebWatchText.dueLabel(new))",
                     source: "网页监控", status: "网页更新",
                     link: item.link.isEmpty ? watch.url : item.link,
                     date: now, allowWebLink: true)
    }

    static func page(_ watch: WebWatch, from oldFingerprint: String?, to newFingerprint: String,
                     now: Date = Date()) -> Entry {
        let transition = (oldFingerprint ?? "") + "->" + newFingerprint
        return Entry(id: "webwatch-\(watch.id)-page-\(WebWatchHash.stableID(transition))",
                     title: String("《\(watch.name)》页面有更新".prefix(60)),
                     body: WebWatchText.pageSummary(watch, changedAt: now),
                     source: "网页监控", status: "网页更新",
                     link: watch.url, date: now, allowWebLink: true)
    }

    static func summary(_ watch: WebWatch, items: [WebWatchItem], now: Date = Date()) -> Entry {
        let names = items.prefix(3).map { WebWatchText.title($0) }.joined(separator: "、")
        let suffix = items.count > 3 ? " 等" : ""
        let identity = WebWatchHash.stableID(items.map(\.key).joined(separator: "|"))
        return Entry(id: "webwatch-\(watch.id)-summary-\(identity)",
                     title: String("《\(watch.name)》新增 \(items.count) 条".prefix(60)),
                     body: names + suffix,
                     source: "网页监控", status: "新条目",
                     link: watch.url, date: now, allowWebLink: true)
    }
}

// MARK: - 页面内检测脚本

/// 检测与抽取都在页面自己的 DOM 里做。MIRA 不把整页正文写入磁盘：
/// 列表模式只取标题、链接、日期文本；整页模式只存一个指纹。
enum WebWatchScript {
    static let source = #"""
    (function () {
      if (window.__miraWatch) { return; }
      var DATE_RE = /(?:20\d{2}\s*[年\-\/.]\s*\d{1,2}\s*[月\-\/.]\s*\d{1,2}\s*日?|\d{1,2}\s*[月\-\/.]\s*\d{1,2}\s*日?)(?:\s*(?:周[一二三四五六日天])?)?(?:\s*\d{1,2}[:：]\d{2})?/;
      var KEYWORD_RE = /(作业|考试|测验|截止|未提交|未交|待完成|待办|公告|通知|assignment|homework|exam|quiz|deadline|due|submit)/i;
      var LOGIN_RE = /(登录|登陆|login|sign in|统一身份认证|cas)/i;

      function textOf(el) {
        if (!el) { return ""; }
        var text = el.innerText || el.textContent || "";
        return String(text).replace(/\s+/g, " ").trim();
      }

      function cssEscape(value) {
        if (window.CSS && window.CSS.escape) { return window.CSS.escape(value); }
        return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
      }

      function classTokens(el) {
        return Array.prototype.slice.call(el.classList || []).filter(function (name) {
          return name.length >= 2 && name.length <= 40 && !/^\d/.test(name) && !/\d{3,}/.test(name);
        });
      }

      function selectorFor(el) {
        var parts = [];
        var node = el;
        var depth = 0;
        while (node && node.nodeType === 1 && depth < 5) {
          if (node.id && /^[A-Za-z][\w\-:.]*$/.test(node.id)) {
            parts.unshift("#" + cssEscape(node.id));
            break;
          }
          var part = node.tagName.toLowerCase();
          var classes = classTokens(node).slice(0, 2);
          if (classes.length) { part += "." + classes.map(cssEscape).join("."); }
          var parent = node.parentElement;
          if (parent) {
            var same = Array.prototype.filter.call(parent.children, function (child) {
              return child.tagName === node.tagName;
            });
            if (same.length > 1) { part += ":nth-of-type(" + (same.indexOf(node) + 1) + ")"; }
          }
          parts.unshift(part);
          node = parent;
          depth += 1;
        }
        return parts.join(" > ");
      }

      function signatureOf(el) {
        var first = el.children && el.children.length ? el.children[0] : null;
        return {
          tag: el.tagName.toLowerCase(),
          id: el.id || "",
          classes: classTokens(el).slice(0, 4),
          childTag: first ? first.tagName.toLowerCase() : "",
          childClasses: first ? classTokens(first).slice(0, 3) : []
        };
      }

      function stableKey(href, title, due) {
        if (href && !/^javascript:/i.test(href)) {
          try {
            var url = new URL(href, location.href);
            var hash = url.hash === "#" ? "" : url.hash;
            url.hash = "";
            var keep = [];
            url.searchParams.forEach(function (value, key) {
              if (/^(id|[a-z_]+id|no|num|work|task|exam|hw|homework|course|cno|hno|aid|assignment|paper|test)$/i.test(key)) {
                keep.push(key + "=" + value);
              }
            });
            keep.sort();
            return url.origin + url.pathname + (keep.length ? "?" + keep.join("&") : "") + hash;
          } catch (e) {}
        }
        if (!title) { return "untitled"; }
        return "title:" + title + (due ? "|" + due : "");
      }

      function itemInfo(child, fields) {
        fields = fields || {};
        var full = textOf(child);
        // Prefer labelled deadlines. Multiple unlabelled dates are ambiguous.
        var labelled = full.match(/(?:截止(?:时间|日期)?|提交期限|due(?:\s+date)?|deadline)\s*[:：]?\s*(.{0,60})/i);
        var allDates = full.match(new RegExp(DATE_RE.source, "g")) || [];
        var dueMatch = labelled ? labelled[1].match(DATE_RE) : (allDates.length === 1 ? [allDates[0]] : null);
        var due = dueMatch ? dueMatch[0].replace(/\s+/g, " ").trim() : "";
        var anchors = Array.prototype.slice.call(child.querySelectorAll("a[href]")).filter(function (a) {
          return textOf(a).length > 0;
        });
        anchors.sort(function (a, b) { return textOf(b).length - textOf(a).length; });
        var anchor = anchors[0] || child.querySelector("a[href]");
        var title = anchor ? textOf(anchor) : "";
        if (!title) {
          var lines = String(child.innerText || child.textContent || "").split(/\n+/).map(function (line) {
            return line.replace(/\s+/g, " ").trim();
          }).filter(function (line) { return line.length > 0; });
          title = lines.length ? lines[0] : full;
          if (due) { title = title.replace(due, " "); }
          title = title.replace(/未提交|未交|待完成|待办|未开始|已提交|已完成|已交|已批阅|待批阅|已截止|已过期|逾期|已结束/g, " ");
          title = title.replace(/截止|deadline|due/ig, " ");
          title = title.replace(/[|·\-—:：]\s*$/, "").replace(/\s+/g, " ").trim();
          if (!title) { title = full.slice(0, 80); }
        }
        if (due && title.length > due.length && title.slice(-due.length) === due) {
          title = title.slice(0, title.length - due.length).replace(/[|·\-—:：]\s*$/, "").trim();
        }
        title = title.replace(/\s+/g, " ").trim().slice(0, 160);
        var status = "";
        if (/未提交|未交|待完成|待办|未开始/.test(full)) { status = "未提交"; }
        else if (/已截止|已过期|逾期|已结束/.test(full)) { status = "已截止"; }
        else if (/待批阅|已批阅|已提交|已完成|已交/.test(full)) { status = "已提交"; }
        if (fields.titleSelector) { title = textOf(child.querySelector(fields.titleSelector)); }
        if (fields.dueSelector) { due = textOf(child.querySelector(fields.dueSelector)); }
        if (fields.statusSelector) {
          var state = textOf(child.querySelector(fields.statusSelector));
          status = /未提交|未交|待完成|not submitted|pending/i.test(state) ? "未提交" :
            (/已提交|已完成|待批阅|submitted|completed/i.test(state) ? "已提交" : "");
        }
        var href = anchor && anchor.href ? anchor.href : "";
        if (!/^https?:/i.test(href)) { href = ""; }
        return {
          key: stableKey(href, title, due),
          title: title,
          link: href,
          dueText: due,
          status: status,
          subtitle: ""
        };
      }

      function candidateFor(el) {
        var kids = Array.prototype.slice.call(el.children || []);
        if (kids.length < 1 || kids.length > 150) { return null; }
        var visible = kids.filter(function (kid) { return textOf(kid).length >= 2; });
        if (visible.length < 1) { return null; }
        var links = 0;
        var dates = 0;
        var keywords = 0;
        var sameTag = 0;
        var firstTag = visible[0].tagName;
        var sampleDue = "";
        var titles = [];
        for (var i = 0; i < visible.length; i++) {
          var kid = visible[i];
          var text = textOf(kid);
          if (kid.querySelector("a[href]")) { links += 1; }
          if (DATE_RE.test(text)) {
            dates += 1;
            if (!sampleDue) {
              var match = text.match(DATE_RE);
              if (match) { sampleDue = match[0].replace(/\s+/g, " ").trim(); }
            }
          }
          if (KEYWORD_RE.test(text)) { keywords += 1; }
          if (kid.tagName === firstTag) { sameTag += 1; }
        }
        if (links < 2 && !(dates >= 1 && keywords >= 1)) { return null; }
        var classes = classTokens(el).join(" ");
        var navish = /(^|\b)(nav|menu|header|footer|sidebar|breadcrumb|tab|pagination|pager|toolbar|login)(\b|$)/i.test((el.id || "") + " " + classes);
        var score = Math.min(links, 10) * 2 + Math.min(dates, 10) * 3 + Math.min(keywords, 6) * 2
          + (sameTag === visible.length ? 3 : 0) + Math.min(visible.length, 8);
        if (navish) { score -= 12; }
        if (keywords === 0 && dates === 0) { score -= 6; }
        if (score < 8) { return null; }
        for (var j = 0; j < Math.min(visible.length, 3); j++) {
          var info = itemInfo(visible[j]);
          if (info.title) { titles.push(info.title); }
        }
        var label = visible.length + " 个条目";
        if (dates) { label += " · " + dates + " 个含日期"; }
        if (keywords) { label += " · " + keywords + " 个含关键词"; }
        return {
          selector: selectorFor(el),
          signature: signatureOf(el),
          count: visible.length,
          score: score,
          sampleTitles: titles,
          sampleDue: sampleDue || null,
          label: label
        };
      }

      function scan() {
        var candidates = [];
        var elements = document.body ? document.body.querySelectorAll("*") : [];
        for (var i = 0; i < elements.length; i++) {
          var el = elements[i];
          if (el.children.length < 1) { continue; }
          if (/^(html|body|head|script|style|nav|header|footer|select)$/i.test(el.tagName)) { continue; }
          var candidate = candidateFor(el);
          if (candidate) { candidates.push(candidate); }
        }
        candidates.sort(function (a, b) { return b.score - a.score; });
        var chosen = [];
        var seen = {};
        for (var j = 0; j < candidates.length && chosen.length < 6; j++) {
          if (seen[candidates[j].selector]) { continue; }
          seen[candidates[j].selector] = true;
          chosen.push(candidates[j]);
        }
        var body = document.body ? (document.body.innerText || document.body.textContent || "") : "";
        var normalized = body.replace(/\s+/g, " ").trim();
        var main = document.querySelector("main, [role=main], #content, #main, .content, .main") || document.body;
        var mainText = main ? (main.innerText || main.textContent || "") : "";
        var fingerprintText = (mainText || normalized).replace(/\s+/g, " ").trim();
        var hash = 2166136261;
        for (var k = 0; k < fingerprintText.length; k++) {
          hash ^= fingerprintText.charCodeAt(k);
          hash = Math.imul(hash, 16777619);
        }
        var loginSuspected = false;
        if (chosen.length === 0) {
          var hasPassword = !!document.querySelector("input[type=password]");
          var loginURL = /(^|\/)(login|signin|sign-in|sso|cas|auth)(\/|$)/i.test(location.pathname);
          if (hasPassword || (loginURL && LOGIN_RE.test((document.title || "") + " " + normalized.slice(0, 500)))) {
            loginSuspected = true;
          }
        }
        return JSON.stringify({
          pageTitle: document.title || "",
          pageURL: location.href,
          candidates: chosen,
          fingerprint: (hash >>> 0).toString(16) + ":" + fingerprintText.length,
          textLength: fingerprintText.length,
          textSample: normalized.slice(0, 800),
          loginSuspected: loginSuspected
        });
      }

      function classOverlap(el, expected) {
        var classes = classTokens(el);
        var hits = 0;
        (expected || []).forEach(function (name) { if (classes.indexOf(name) >= 0) { hits += 1; } });
        return hits;
      }

      function findContainer(selector, signature, doc) {
        doc = doc || document;
        if (selector) {
          try {
            var found = doc.querySelector(selector);
            if (found) { return found; }
          } catch (e) {}
        }
        if (!signature) { return null; }
        var all = doc.body ? doc.body.querySelectorAll(signature.tag || "*") : [];
        var best = null;
        var bestScore = 0;
        for (var i = 0; i < all.length; i++) {
          var el = all[i];
          var kids = el.children || [];
          if (kids.length < 1) { continue; }
          var score = 0;
          if (signature.id && el.id === signature.id) { score += 5; }
          score += classOverlap(el, signature.classes) * 2;
          var first = kids[0];
          if (first && signature.childTag && first.tagName.toLowerCase() === signature.childTag) { score += 2; }
          if (first) { score += classOverlap(first, signature.childClasses); }
          if (score > bestScore) { bestScore = score; best = el; }
        }
        return bestScore >= 6 ? best : null;
      }

      function extract(args) {
        var doc = document;
        if (args.frameSelector) {
          var frame = document.querySelector(args.frameSelector);
          try { doc = frame && frame.contentDocument; } catch(e) { doc = null; }
          if (!doc) { throw new Error("无法读取 iframe：仅支持同源框架，请直接打开框架网址"); }
        }
        var el = findContainer(args.selector, args.signature, doc);
        if (!el) { return JSON.stringify({ items: [], found: false }); }
        var kids = Array.prototype.slice.call(el.children || []).filter(function (kid) {
          return textOf(kid).length >= 2;
        });
        var items = [];
        var seen = {};
        for (var i = 0; i < kids.length && items.length < 300; i++) {
          var info = itemInfo(kids[i], args);
          if (!info.title) { continue; }
          if (seen[info.key] !== undefined) {
            seen[info.key] += 1;
            info.key += "#" + seen[info.key];
          } else {
            seen[info.key] = 0;
          }
          items.push(info);
        }
        return JSON.stringify({ items: items, found: true });
      }

      window.__miraWatch = { scan: scan, extract: extract, version: "1" };
    })();
    """#

    static let scanCall = "window.__miraWatch.scan()"

    static func extractCall(selector: String, signature: WebWatchSignature?, route: WebWatchRoute? = nil) -> String {
        let signaturePayload: [String: Any] = [
            "tag": signature?.tag ?? "",
            "id": signature?.id ?? "",
            "classes": signature?.classes ?? [],
            "childTag": signature?.childTag ?? "",
            "childClasses": signature?.childClasses ?? []
        ]
        let payload: [String: Any] = ["selector": selector, "signature": signaturePayload,
            "frameSelector": route?.frameSelector ?? "", "titleSelector": route?.titleSelector ?? "",
            "dueSelector": route?.dueSelector ?? "", "statusSelector": route?.statusSelector ?? ""]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return "window.__miraWatch.extract({selector:'', signature:null})"
        }
        return "window.__miraWatch.extract(" + json + ")"
    }
}
