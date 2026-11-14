import Foundation

@main struct UniCourseTests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 9))!

        // 首页「我的课程」：课程名 + data-id，另有一条 id=0 的「全部」。
        let home = """
        <div class="list-group" role="menu">
          <span class="hide">20269q4j9xl01crs</span>
          <a href="javascript:void(0);" title="数据科学导论-张绍磊" class="list-group-item courseitem"
              data-id="20269q4j9xl01crs" ng-click="changeCourse('20269q4j9xl01crs')"
              ng-class="{true:'cur'}[cno=='20269q4j9xl01crs']">
              数据科学导论-张绍磊 <span class="glyphicon glyphicon-chevron-right pull-right"></span>
          </a>
          <a href="javascript:void(0);" title="新《计算机系统基础I》-2026秋" class="list-group-item courseitem"
              data-id="2026swaa2akjdgne" ng-click="changeCourse('2026swaa2akjdgne')">
              新《计算机系统基础I》-2026秋
          </a>
          <a href="javascript:void(0);" class="list-group-item courseitem" data-id="0" ng-click="changeCourse('');">
              全部
          </a>
        </div>
        """
        let courses = UniCourseFeed.courses(fromHTML: home)
        assert(courses.count == 2, "两门课程，跳过「全部」：\(courses)")
        assert(courses[0].id == "20269q4j9xl01crs" && courses[0].name == "数据科学导论-张绍磊")
        assert(courses[1].id == "2026swaa2akjdgne" && courses[1].name == "新《计算机系统基础I》-2026秋")

        // 首页没有 courseitem 时，用任意作业页侧栏的「课程切换」链接兜底。
        let sidebar = """
        <a id="left-新《计算机系统基础I》-2026秋" class="list-group-item left-changecourse"
           href="/homework/index/cno/2026swaa2akjdgne" >新《计算机系统基础I》-2026秋</a>
        <a id="left-homework" class="list-group-item" href="/index/homework/index/cno/2026swaa2akjdgne.html">作业</a>
        """
        let fallback = UniCourseFeed.courses(fromHTML: sidebar)
        assert(fallback.count == 1 && fallback[0].id == "2026swaa2akjdgne", "\(fallback)")

        // 作业页：服务端渲染的 panel，未提交带 unfinished，已提交带 finished。
        let homework = """
        <div class="panel panel-default" id="panel-5805">
          <div class="panel-heading">
            <span class="hide">1</span>
            <span class="hide" htype="1">1</span>
            <a class="accordion-toggle title homework-title" data-toggle="collapse"
               href="#collapse-5805" id="hno-5805" >课后作业4</a>
            <span><small> &nbsp&nbsp普通作业</small></span>
            <span id="hw-check-5805" class="hw-check unfinished pull-right"></span>
            <span class="hide deadline">2026-11-24 23:55:00</span>
          </div>
          <div class="panel-body out collapse" id="collapse-5805">
            <div class="points"><span class="point_label label">（1-3）能力点</span></div>
          </div>
        </div>
        <div class="panel panel-success" id="panel-5790">
          <div class="panel-heading">
            <a class="accordion-toggle title homework-title" href="#collapse-5790" id="hno-5790" >期中考试成绩</a>
            <span><small> &nbsp&nbsp期中考试</small></span>
            <span id="hw-check-5790" class="hw-check finished pull-right"></span>
            <span class="hide deadline">2026-11-10 23:55:00</span>
          </div>
        </div>
        <div class="panel panel-default" id="panel-5700">
          <div class="panel-heading">
            <a class="accordion-toggle title homework-title" href="#collapse-5700" id="hno-5700" >DataLab 作业提交</a>
            <span><small> &nbsp&nbsp普通作业</small></span>
            <span id="hw-check-5700" class="hw-check unfinished pull-right"></span>
          </div>
        </div>
        """
        let course = UniCourseCourse(id: "2026swaa2akjdgne", name: "新《计算机系统基础I》-2026秋")
        let items = UniCourseFeed.assignments(fromHTML: homework, course: course, now: now)
        assert(items.count == 3, "三个作业块：\(items.count)")
        let first = items[0]
        assert(first.title == "课后作业4" && first.type == "普通作业", "\(first)")
        assert(!first.submitted, "unfinished 不能被当成 finished")
        assert(first.key == "2026swaa2akjdgne:5805")
        assert(first.link.hasSuffix("/index/homework/index/cno/2026swaa2akjdgne.html#panel-5805"))
        let due = first.due!
        assert(calendar.component(.day, from: due) == 24 && calendar.component(.hour, from: due) == 23
               && calendar.component(.minute, from: due) == 55, "截止时间：\(due)")

        let submitted = items[1]
        assert(submitted.submitted && submitted.title == "期中考试成绩" && submitted.type == "期中考试")

        let noDue = items[2]
        assert(noDue.due == nil && !noDue.submitted, "没有截止时间的未提交作业也要导入")

        // 公告 JSON：n_type 可能是字符串或数字；只取 2，忽略作业/课件事件。
        let news = """
        {"status":0,"data":[
          {"n_no":"18270","n_type":"2","n_cno":"2026swaa2akjdgne","n_cname":"新《计算机系统基础I》-2026秋",
           "n_sname":"方言诚","n_content":"第 4 章调课到周五","n_time":"2026-11-12 10:00:00",
           "n_curl":"/index/notice/index/cno/2026swaa2akjdgne.html"},
          {"n_no":"18271","n_type":2,"n_cno":"2026wgzx34ib06gl","n_cname":"2026数字逻辑",
           "n_sname":"陈文萍","n_content":"考试安排","n_time":"2026-11-13 08:00:00",
           "n_contenturl":"/index/notice/index/cno/2026wgzx34ib06gl.html"},
          {"n_no":"18272","n_type":"3","n_cno":"2026swaa2akjdgne","n_cname":"新《计算机系统基础I》-2026秋",
           "n_sname":"方言诚","n_content":"课后作业4","n_time":"2026-11-11 00:47:32",
           "n_curl":"/index/homework/index/cno/2026swaa2akjdgne.html"}
        ]}
        """
        var payload = Data([0xEF, 0xBB, 0xBF])
        payload.append(Data(news.utf8))
        let notices = UniCourseFeed.announcements(fromJSON: payload, now: now)
        assert(notices.count == 2, "两条公告：\(notices)")
        assert(notices[0].id == "news:18270" && notices[0].title == "第 4 章调课到周五")
        assert(notices[0].link.hasPrefix("https://unicourse.ruc.edu.cn/index/notice/"))
        assert(calendar.component(.day, from: notices[0].date) == 12)
        assert(notices[1].link.hasPrefix("https://unicourse.ruc.edu.cn/index/notice/"), "相对链接补齐域名")

        // 文本清理：`&nbsp&nbsp` 没有分号也要吃掉。
        assert(UniCourseFeed.cleanText("&nbsp&nbsp普通作业") == "普通作业")
        assert(UniCourseFeed.cleanText("A&amp;B") == "A&B")

        // 课程更新通知要能直接打开 UniCourse；同形域名仍然被拒绝。
        assert(Links.valid("https://unicourse.ruc.edu.cn/index/homework/index/cno/x.html#panel-1"))
        assert(!Links.valid("https://unicourse.ruc.edu.cn.evil.example/x"))

        // 新作业/公告通知只提醒一次即进入记录，不占用「待处理」。
        let note = Entry(id: "unicourse-1", title: "《课程》作业4", body: "", source: "UniCourse",
                         status: "新作业", link: "", date: now)
        assert(note.courseUpdate && !note.automaticallyArchived)
        assert(!Schedule.needsAttention(note, now: now) && Schedule.inHistory(note, now: now))
        assert(Notify.due([note], now: now) == [0])

        // 旧状态里的任务没有 externalKey，必须照常解码。
        let legacyTask = """
        {"id":"t1","title":"旧任务","notes":"","categoryID":"category-course","status":"待办",
         "important":false,"pinned":false,"links":[],"createdAt":0,"updatedAt":0}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let task = try decoder.decode(TaskItem.self, from: Data(legacyTask.utf8))
        assert(task.externalKey == nil && task.title == "旧任务")

        // 已提交的旧任务也先认领；完成后保留全部内容，重复同步不改完成时间。
        var old = task
        old.title = "《课程》作业4"
        old.notes = "来自 UniCourse · 普通作业"
        var synced = [old]
        let key = "unicourse:course:4"
        let matched = ExternalTaskSync.existingIndex(in: &synced, key: key,
                                                     title: old.title, source: "UniCourse", checkedAt: now)
        assert(matched == 0 && synced[0].externalKey == key)
        assert(ExternalTaskSync.complete(&synced[0], checkedAt: now))
        assert(synced.count == 1 && synced[0].status == .done && synced[0].notes == old.notes)
        assert(!ExternalTaskSync.complete(&synced[0], checkedAt: now.addingTimeInterval(60)))
        assert(synced[0].completedAt == now)
        assert(ExternalTaskSync.existingIndex(in: &synced, key: key,
                                              title: "改过的标题", source: "UniCourse", checkedAt: now) == 0)
        var manual = old
        manual.notes = "手动创建"
        var unrelated = [manual]
        assert(ExternalTaskSync.existingIndex(in: &unrelated, key: key,
                                              title: old.title, source: "UniCourse", checkedAt: now) == nil)
        var ambiguous = [old, old]
        assert(ExternalTaskSync.existingIndex(in: &ambiguous, key: key,
                                              title: old.title, source: "UniCourse", checkedAt: now) == nil)
        var other = old
        other.externalKey = "unicourse:other:4"
        var differentCourse = [other]
        assert(ExternalTaskSync.existingIndex(in: &differentCourse, key: key,
                                              title: old.title, source: "UniCourse", checkedAt: now) == nil)

        // 所有网站共用完成逻辑；保留归档位置、链接、备注及原任务 ID。
        for source in ["学习通", "教学系统", "网页监控"] {
            var imported = old
            imported.notes = "来自 \(source) · 作业"
            imported.archivedAt = now.addingTimeInterval(-60)
            imported.links = [TaskLink(url: "https://example.com/homework/4")]
            var tasks = [imported]
            assert(ExternalTaskSync.existingIndex(in: &tasks, key: source + ":4",
                title: imported.title, source: source, checkedAt: now) == 0)
            assert(ExternalTaskSync.complete(&tasks[0], checkedAt: now))
            assert(tasks[0].id == imported.id && tasks[0].archivedAt == imported.archivedAt)
            assert(tasks[0].links == imported.links && tasks[0].notes == imported.notes)
            assert(!ExternalTaskSync.complete(&tasks[0], checkedAt: now.addingTimeInterval(60)))
            assert(tasks[0].completedAt == now)
        }

        // 配置落盘：0600，且能读回。
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mira-unicourse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = UniCourseSettings()
        settings.cookie = "session=abc; uid=1"
        settings.enabled = true
        settings.importHomework = false
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        try UniCourseStore.save(settings, root: root, encoder: encoder)
        let loaded = UniCourseStore.load(root: root, decoder: decoder)
        assert(loaded == settings)
        let attributes = try FileManager.default.attributesOfItem(atPath: UniCourseStore.url(root: root).path)
        assert((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Cookie 文件必须是 0600")

        print("PASS: UniCourse 课程/作业/公告解析、截止时间、已提交状态、旧任务兼容与配置落盘")
    }
}
