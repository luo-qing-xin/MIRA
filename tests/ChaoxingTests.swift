import Foundation

@main struct ChaoxingTests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

        // backclazzdata：班级为 content，课程在 content.course.data[]；content 可能是字符串。
        let courseJSON = """
        {"result":1,"msg":"","channelList":[
          {"key":"class-1","cpi":"u1","content":"{\\"id\\":\\"class-1\\",\\"name\\":\\"2026秋 1 班\\",\\"course\\":{\\"data\\":[{\\"id\\":\\"course-1\\",\\"name\\":\\"计算机系统基础\\"}]}}"},
          {"key":"class-2","content":{"id":"class-2","name":"2 班","course":{"data":[{"id":"course-2","name":"数字逻辑"}]}}},
          {"key":"class-2","content":{"id":"class-2","name":"2 班","course":{"data":[{"id":"course-2","name":"数字逻辑"}]}}}
        ]}
        """
        let courses = ChaoxingFeed.courses(fromJSON: Data(courseJSON.utf8))
        assert(courses.count == 2, "两门课并去重：\(courses)")
        assert(courses[0].courseID == "course-1" && courses[0].classID == "class-1"
               && courses[0].name == "计算机系统基础", "\(courses[0])")
        assert(courses[1].courseID == "course-2" && courses[1].name == "数字逻辑")

        // 旧版 course-centric 结构。
        let legacyJSON = """
        {"result":1,"channelList":[{"content":{"id":"course-9","name":"离散数学","clazz":[{"id":"class-9","name":"9 班"}]}}]}
        """
        let legacy = ChaoxingFeed.courses(fromJSON: Data(legacyJSON.utf8))
        assert(legacy.count == 1 && legacy[0].courseID == "course-9" && legacy[0].classID == "class-9", "\(legacy)")

        let course = courses[0]
        let workHTML = """
        <dl class="work-list">
          <dt data="/work/doHomeWorkNew?courseId=course-1&classId=class-1&workId=1001" status="0">
            <h3>第一次作业</h3>
            <p>2026-11-10 10:00 发布</p>
            <p>截止时间：2026-11-20 23:59</p>
            <b>做作业</b>
          </dt>
          <dt data="/work/doHomeWorkNew?courseId=course-1&classId=class-1&workId=1002" status="4">
            <h3>第二次作业</h3><p>2026-10-15 95.0</p>
          </dt>
          <dt data="/work/doHomeWorkNew?courseId=course-1&classId=class-1&workId=1003" status="2">
            <h3>过期作业</h3><p>2026-10-01</p><b>已过期</b>
          </dt>
          <dt data="/work/doHomeWorkNew?courseId=course-1&classId=class-1&workId=1004" status="1">
            <h3>没有截止时间的作业</h3><p>2026-11-12</p><b>做作业</b>
          </dt>
          <dt data="/work/doHomeWorkNew?courseId=course-1&classId=class-1&workId=1005" status="4">
            <h3>只有分数没有动作文字的作业</h3><p>2026-10-01 100.0</p>
          </dt>
        </dl>
        """
        let works = ChaoxingFeed.tasks(fromWorkListHTML: workHTML, course: course)
        assert(works.count == 5, "五条作业：\(works.count)")
        let first = works[0]
        assert(first.title == "第一次作业" && first.state == .pending)
        assert(first.key == "work:course-1:1001", "用 workId 做稳定键：\(first.key)")
        assert(first.link.hasPrefix("https://mooc1-api.chaoxing.com/work/doHomeWorkNew"), "\(first.link)")
        let due = first.due!
        assert(calendar.component(.day, from: due) == 20 && calendar.component(.hour, from: due) == 23
               && calendar.component(.minute, from: due) == 59, "截止时间：\(due)")
        assert(works[1].state == .submitted && works[1].title == "第二次作业", "status=4 是已完成，即使没有动作文字")
        assert(works[2].state == .pending && works[2].overdue, "status=2 是已过期但仍未交")
        assert(works[3].due == nil && works[3].state == .pending && !works[3].overdue)
        assert(works[4].state == .submitted && works[4].title == "只有分数没有动作文字的作业")

        let examHTML = """
        <table>
          <tr><th>标题</th><th>分数</th><th>状态</th></tr>
          <tr data="//mooc1.chaoxing.com/exam/test?courseId=course-1&classId=class-1&examId=9001" title="期中考试" status="0">
            <td>期中考试</td><td>--</td><td>做考试</td>
          </tr>
        </table>
        """
        let exams = ChaoxingFeed.tasks(fromExamListHTML: examHTML, course: course)
        assert(exams.count == 1 && exams[0].kind == .exam && exams[0].state == .pending, "\(exams)")
        assert(exams[0].key == "exam:course-1:9001" && exams[0].link.hasPrefix("https://mooc1.chaoxing.com/exam/test"))

        // 没有 workId 时用标题 + 链接哈希，跨次抓取稳定。
        let anonymous = """
        <dt data="/work/doHomeWorkNew?courseId=course-1&classId=class-1" status="0">
          <h3>匿名作业</h3><b>做作业</b>
        </dt>
        """
        let a = ChaoxingFeed.tasks(fromWorkListHTML: anonymous, course: course)
        let b = ChaoxingFeed.tasks(fromWorkListHTML: anonymous, course: course)
        assert(a.count == 1 && a[0].key == b[0].key && a[0].key.hasPrefix("work:course-1:h:"))

        // 链接白名单：学习通作业页可以直接打开，伪装域名不行。
        assert(Links.valid("https://mooc1.chaoxing.com/work/doHomeWorkNew?workId=1"))
        assert(Links.valid("https://i.chaoxing.com/base"))
        assert(!Links.valid("https://chaoxing.com.evil.example/work"))

        // 两个连接器共用同一组抓取间隔。
        assert(ChaoxingSettings.intervalChoices == SyncInterval.choices)
        assert(SyncInterval.label(1440) == "1 天")

        // 配置落盘 0600。
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mira-cx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = ChaoxingSettings()
        settings.cookie = "_uid=1; fid=2"
        settings.enabled = true
        settings.includeExams = false
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        try ChaoxingStore.save(settings, root: root, encoder: encoder)
        assert(ChaoxingStore.load(root: root, decoder: decoder) == settings)
        let attributes = try FileManager.default.attributesOfItem(atPath: ChaoxingStore.url(root: root).path)
        assert((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Cookie 文件必须是 0600")

        print("PASS: 学习通课程/作业/考试解析、workId 键、截止时间、状态与链接白名单")
    }
}
