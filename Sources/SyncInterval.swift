import Foundation

/// 课程来源的抓取间隔。两个连接器共用同一组档位，避免设置页出现两套不同的时间。
enum SyncInterval {
    /// A scheduled retry replaces the normal interval, including longer backoffs.
    static func isDue(lastCheck: Date?, retryAt: Date?, interval: TimeInterval, now: Date = Date()) -> Bool {
        if let retryAt { return now >= retryAt }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    static let choices = [30, 60, 120, 720, 1440, 10080]
    static let defaultMinutes = 30

    static func label(_ minutes: Int) -> String {
        switch minutes {
        case 60: return "1 小时"
        case 120: return "2 小时"
        case 720: return "12 小时"
        case 1440: return "1 天"
        case 10080: return "7 天"
        default:
            if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
            return "\(minutes) 分钟"
        }
    }

    /// 旧配置里的 15 分钟等档位不在新列表里，读取时收敛到默认值，避免 Picker 空白。
    static func normalize(_ minutes: Int) -> Int {
        choices.contains(minutes) ? minutes : defaultMinutes
    }
}
