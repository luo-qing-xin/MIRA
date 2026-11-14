import SwiftUI

// MARK: - UniCourse

/// 在 MIRA 自己的窗口里走完 RUC 统一身份认证。密码只进 WebView，
/// MIRA 只取走 `.ruc.edu.cn` 的会话 Cookie，交给 Hub 存成 0600 文件。
struct UniCourseLoginSheet: View {
    @ObservedObject var hub: Hub

    var body: some View {
        WebLoginSheet(
            title: "登录 UniCourse",
            subtitle: "用学校账号登录；MIRA 只保存会话 Cookie，不保存密码。登录成功后窗口会自动关闭。",
            start: UniCourseFeed.home,
            cookieDomain: "ruc.edu.cn",
            isSignedIn: { url in
                url.host?.lowercased() == UniCourseFeed.host && !url.path.hasPrefix("/index/index/")
            },
            onSession: { hub.connectUniCourse(cookie: $0) })
    }
}

// MARK: - 学习通

/// 学习通（超星）的登录页在 passport2，登录成功后回到 i.chaoxing.com 或 mooc1。
struct ChaoxingLoginSheet: View {
    @ObservedObject var hub: Hub

    var body: some View {
        WebLoginSheet(
            title: "登录 学习通",
            subtitle: "用学习通账号登录（手机号或扫码）；MIRA 只保存会话 Cookie，不保存密码。",
            start: URL(string: "https://i.chaoxing.com/base")!,
            cookieDomain: "chaoxing.com",
            isSignedIn: { url in
                let host = url.host?.lowercased() ?? ""
                let text = url.absoluteString.lowercased()
                return host.hasSuffix("chaoxing.com")
                    && !text.contains("passport")
                    && !url.path.lowercased().contains("login")
            },
            onSession: { hub.connectChaoxing(cookie: $0) })
    }
}


// MARK: - 666 教学系统

/// 中国人民大学通用教学系统（666）：独立账号登录，登录后把会话 Cookie 交给 Hub。
struct TeachingLoginSheet: View {
    @ObservedObject var hub: Hub

    var body: some View {
        WebLoginSheet(
            title: "登录 教学系统（666）",
            subtitle: "用教学系统的账号登录；MIRA 只保存会话 Cookie，不保存密码。",
            start: TeachingFeed.loginPage,
            cookieDomain: "ruc.edu.cn",
            isSignedIn: { url in
                url.host?.lowercased() == TeachingFeed.host
                    && !url.path.hasPrefix("/user/login")
            },
            onSession: { hub.connectTeaching(cookie: $0) })
    }
}
