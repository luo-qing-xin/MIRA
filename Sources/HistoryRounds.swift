import Foundation

/// 记录页的展示模型：同一轮的事件（运行中 → 本轮结束）合成一行。
/// 只影响展示，state.json 仍然保存原始事件。
struct HistoryRound: Identifiable {
    static let terminalStatuses: Set<String> = ["本轮结束", "任务失败", "已中断", "已拦截", "已达上限"]
    static let awaitingStatuses: Set<String> = ["待确认", "待补充信息"]
    static let failedStatuses: Set<String> = ["任务失败", "已中断", "已拦截", "已达上限"]

    private(set) var entries: [Entry]
    let id: String

    init(_ entry: Entry) {
        self.entries = [entry]
        self.id = entry.id
    }

    var first: Entry { entries[0] }
    var last: Entry { entries[entries.count - 1] }
    var title: String { last.displayTitle }
    var source: String { last.source }
    var link: String {
        entries.reversed().first { !$0.link.isEmpty }?.link ?? ""
    }
    var thread: String? {
        entries.reversed().compactMap(\.thread).first
    }
    var start: Date { first.date }
    var end: Date { last.date }
    var count: Int { entries.count }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var status: String { last.historyStatus }
    var rawStatus: String { last.status }
    var isTerminal: Bool { Self.terminalStatuses.contains(last.status) }

    mutating func append(_ entry: Entry) {
        entries.append(entry)
    }
}

enum RecordFilter: String, CaseIterable, Identifiable {
    case all, finished, awaiting, failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .finished: return "本轮结束"
        case .awaiting: return "待回应"
        case .failed: return "失败"
        }
    }

    func matches(_ round: HistoryRound) -> Bool {
        switch self {
        case .all: return true
        case .finished: return round.rawStatus == "本轮结束"
        case .awaiting: return HistoryRound.awaitingStatuses.contains(round.rawStatus)
        case .failed: return HistoryRound.failedStatuses.contains(round.rawStatus)
        }
    }
}

enum HistoryGrouping {
    /// 升序扫描，按 session 维护「还没结束的那一轮」。同一 session 的事件可能
    /// 和别的会话交错到达（Codex 和 DSH 同时跑），所以不能只看上一条。
    /// 结束态出现后立即封口，下一次进入同一 session 的事件会开新的一轮。
    static func rounds(from entries: [Entry], limit: Int = 160) -> [HistoryRound] {
        let ordered = entries.sorted { $0.date < $1.date }
        var rounds: [HistoryRound] = []
        var openByThread: [String: Int] = [:]

        for entry in ordered {
            let thread = entry.thread.flatMap { $0.isEmpty ? nil : $0 }
            if let thread, let index = openByThread[thread], rounds.indices.contains(index),
               canJoin(rounds[index], entry) {
                rounds[index].append(entry)
                if rounds[index].isTerminal { openByThread[thread] = nil }
            } else {
                rounds.append(HistoryRound(entry))
                if let thread, !rounds[rounds.count - 1].isTerminal {
                    // 同一会话里又开了一轮而没有结束标记：旧的一轮保持原样，
                    // 后续事件归到新的一轮。
                    openByThread[thread] = rounds.count - 1
                }
            }
        }
        return rounds.sorted { $0.end > $1.end }.prefix(limit).map { $0 }
    }

    private static func canJoin(_ round: HistoryRound, _ entry: Entry) -> Bool {
        guard !round.isTerminal else { return false }
        // 两个「运行中」相邻说明上一轮没有收到结束事件；不要吞进同一行。
        if entry.status == "运行中", round.last.status == "运行中" { return false }
        // 同一轮的状态事件相隔很短；超过六小时视为新的一轮。
        return entry.date.timeIntervalSince(round.end) < 6 * 3600
    }
}

/// 记录页里的一天。
struct HistoryDay: Identifiable {
    let id: Date
    let rounds: [HistoryRound]
}
