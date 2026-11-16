import Foundation

@main struct HubReliabilityTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mira-hub-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        for interval: TimeInterval in [1800, 86400, 604800] {
            assert(!SyncInterval.isDue(lastCheck: now, retryAt: nil, interval: interval, now: now.addingTimeInterval(300)))
            assert(!SyncInterval.isDue(lastCheck: now, retryAt: now.addingTimeInterval(300), interval: interval, now: now.addingTimeInterval(299)))
            assert(SyncInterval.isDue(lastCheck: now, retryAt: now.addingTimeInterval(300), interval: interval, now: now.addingTimeInterval(300)))
            assert(SyncInterval.isDue(lastCheck: now, retryAt: nil, interval: interval, now: now.addingTimeInterval(interval)))
        }
        assert(!SyncInterval.isDue(lastCheck: nil, retryAt: now.addingTimeInterval(21600), interval: 1800, now: now))
        assert(SyncInterval.isDue(lastCheck: nil, retryAt: nil, interval: 1800, now: now))
        let hub = Hub(root: root)
        assert(hub.save())
        let uni = hub.uniSession, cx = hub.cxSession, teach = hub.teachSession
        hub.disconnectUniCourse()
        hub.disconnectChaoxing()
        hub.disconnectTeaching()
        let state = try Data(contentsOf: hub.file)
        hub.apply(UniCourseConnection.Outcome(updatedCookie: "stale"), session: uni)
        hub.applyChaoxing(ChaoxingConnection.Outcome(updatedCookie: "stale"), session: cx)
        hub.applyTeaching(TeachingConnection.Outcome(updatedCookie: "stale"), session: teach)
        assert(!hub.unicourse.signedIn && !hub.chaoxing.signedIn && !hub.teaching.signedIn)
        for file in ["unicourse.json", "chaoxing.json", "teaching.json"] {
            assert(!FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path))
        }
        let unchanged = try Data(contentsOf: hub.file)
        assert(unchanged == state)

        // An old response must not clear the new session's in-flight state.
        hub.uniBusy = true; hub.cxBusy = true; hub.teachBusy = true
        hub.apply(UniCourseConnection.Outcome(error: "old failure"), session: uni)
        hub.applyChaoxing(ChaoxingConnection.Outcome(error: "old failure"), session: cx)
        hub.applyTeaching(TeachingConnection.Outcome(error: "old failure"), session: teach)
        assert(hub.uniBusy && hub.cxBusy && hub.teachBusy)
        hub.apply(UniCourseConnection.Outcome(updatedCookie: "current"), session: hub.uniSession)
        hub.applyChaoxing(ChaoxingConnection.Outcome(updatedCookie: "current"), session: hub.cxSession)
        hub.applyTeaching(TeachingConnection.Outcome(updatedCookie: "current"), session: hub.teachSession)
        assert(!hub.uniBusy && !hub.cxBusy && !hub.teachBusy)
        assert(hub.unicourse.cookie == "current" && hub.chaoxing.cookie == "current" && hub.teaching.cookie == "current")

        var shown: [String] = []
        hub.showPopup = { shown.append($0.id) }
        let entry = Entry(id: "notification", title: "Reminder", body: "", source: "个人计划", status: "待完成", link: "", date: Date())
        hub.data.entries = [entry]
        hub.notificationFailed(entry, message: "injected failure")
        assert(shown == [entry.id])
        hub.data.entries[0].done = true
        hub.notificationFailed(entry, message: "late failure")
        hub.data.entries[0].done = false
        hub.data.entries[0].snooze = Date().addingTimeInterval(600)
        hub.notificationFailed(entry, message: "late failure")
        hub.data.entries[0].snooze = nil
        hub.data.entries[0].expires = Date().addingTimeInterval(-1)
        hub.notificationFailed(entry, message: "late failure")
        hub.data.entries = []
        hub.notificationFailed(entry, message: "late failure")
        assert(shown == [entry.id], "Late failures must not resurrect dismissed reminders")
        print("PASS: stale course responses, current responses, notification failure fallback and late callbacks")
    }
}
