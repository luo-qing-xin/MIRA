import Foundation

/// 登录态 Cookie 的公共处理：服务端每次请求都可能轮换 Set-Cookie，
/// 只把变化并回存储的头，避免下一次带着已作废的旧值。
enum WebCookie {
    static func merged(_ cookie: String, response: HTTPURLResponse, url: URL) -> String? {
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String, let value = value as? String,
                  key.caseInsensitiveCompare("Set-Cookie") == .orderedSame else { continue }
            fields[key] = value
        }
        guard !fields.isEmpty else { return nil }
        let fresh = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard !fresh.isEmpty else { return nil }

        var pairs: [(name: String, value: String)] = []
        for piece in cookie.split(separator: ";") {
            let parts = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            pairs.append((name, String(parts[1]).trimmingCharacters(in: .whitespaces)))
        }
        for item in fresh {
            if let index = pairs.firstIndex(where: { $0.name == item.name }) {
                pairs[index].value = item.value
            } else {
                pairs.append((item.name, item.value))
            }
        }
        let merged = pairs.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        return merged == cookie ? nil : merged
    }
}
