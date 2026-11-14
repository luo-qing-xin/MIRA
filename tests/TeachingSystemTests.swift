import Foundation

@main struct TeachingSystemTests {
    static func main() throws {
        // Next.js Server Action 的 RSC flight：每行 `<id>:<json>`。
        let classFlight = """
        0:{"a":"$@1","f":"","b":"build"}
        1:[{"id":"class-1","course":{"courseName":"数据结构与算法"}},{"id":"class-2","course":{"name":"离散数学"}}]
        """
        let classes = TeachingFeed.classes(fromFlight: classFlight)
        assert(classes.count == 2, "两门课：\(classes)")
        assert(classes[0].id == "class-1" && classes[0].courseName == "数据结构与算法")
        assert(classes[1].id == "class-2" && classes[1].courseName == "离散数学")

        let examFlight = """
        0:{"a":"$@1"}
        1:[{"id":"exam-1","examName":"期中  考试","startedAt":"2026-11-20T01:00:00.000Z","endedAt":"2030-11-20T03:00:00.000Z","status":"not_started","timeByMinute":120},
           {"id":"exam-2","examName":"实验测验","startedAt":"2020-01-01T01:00:00Z","endedAt":"2020-01-01T02:00:00Z","status":"ended"}]
        """
        let course = TeachingClass(id: "class-1", courseName: "数据结构与算法")
        let exams = TeachingFeed.exams(fromFlight: examFlight, of: course)
        assert(exams.count == 2, "两场考试：\(exams)")
        assert(exams[0].title == "期中 考试" && exams[0].courseName == "数据结构与算法")
        assert(exams[0].link == "https://666.ruc.edu.cn/exam/my/exam-1")
        assert(exams[0].end != nil && !exams[0].ended, "2030 年结束的考试不应判为已结束")
        assert(exams[1].ended, "2020 年结束的考试应判为已结束")

        // 纯 JSON 响应与数字时间戳也要能解析。
        let plain = """
        [{"id":"exam-3","examName":"数字逻辑","endedAt":1893456000000}]
        """
        let numeric = TeachingFeed.exams(fromFlight: plain, of: course)
        assert(numeric.count == 1 && numeric[0].end != nil, "毫秒时间戳：\(numeric)")
        assert(!numeric[0].ended, "2030 年时间戳不应判为结束")

        // 链接白名单：666 考试页可以直接打开，伪装域名不行。
        assert(Links.valid("https://666.ruc.edu.cn/exam/my/exam-1"))
        assert(!Links.valid("https://666.ruc.edu.cn.evil.example/exam/my"))

        // 配置落盘 0600。
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mira-teach-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = TeachingSettings()
        settings.cookie = "authjs.session-token=abc"
        settings.enabled = true
        settings.intervalMinutes = 720
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        try TeachingStore.save(settings, root: root, encoder: encoder)
        assert(TeachingStore.load(root: root, decoder: decoder) == settings)
        let attributes = try FileManager.default.attributesOfItem(atPath: TeachingStore.url(root: root).path)
        assert((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Cookie 文件必须是 0600")

        print("PASS: 666 教学系统课程/考试 flight 解析、时间戳、结束判定、链接白名单与配置落盘")
    }
}
