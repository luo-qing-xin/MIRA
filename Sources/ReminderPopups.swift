import AppKit
import SwiftUI

@MainActor final class ReminderPopups: ObservableObject {
    @Published private(set) var entries: [Entry] = []
    private var panel: NSPanel?
    private var contentHeight: CGFloat = 190
    var insetChanged: ((CGFloat) -> Void)?

    var topInset: CGFloat { panel.map { $0.frame.height + 12 } ?? 0 }

    func show(_ entry: Entry, hub: Hub) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        if entry.token != nil || entry.codexID != nil {
            entries.insert(entry, at: 0)
        } else {
            entries.append(entry)
        }
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: ReminderView.width, height: contentHeight),
                styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false
            )
            panel.title = "MIRA · 提醒"
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: ReminderStackView(hub: hub, popups: self))
            self.panel = panel
        }
        layout()
        panel?.orderFrontRegardless()
    }

    func close(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index)
        if entries.isEmpty {
            panel?.close()
            panel = nil
            contentHeight = 190
            insetChanged?(0)
        }
    }

    func removeExpired(now: Date) {
        let expired = entries.filter { $0.expires.map { $0 <= now } ?? false }
        for entry in expired { close(entry.id) }
    }

    func fit(height: CGFloat) {
        guard !entries.isEmpty, height > 0 else { return }
        contentHeight = ceil(height)
        layout()
    }

    func layout() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let height = min(contentHeight, max(1, visible.height - 32))
        let frame = NSRect(x: visible.maxX - ReminderView.width - 24,
                           y: visible.maxY - height - 20,
                           width: ReminderView.width, height: height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
        insetChanged?(topInset)
    }
}

private struct ReminderStackView: View {
    let hub: Hub
    @ObservedObject var popups: ReminderPopups

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(popups.entries) { entry in
                        ReminderView(hub: hub, entry: entry) { popups.close(entry.id) }
                            .id(entry.id)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: ReminderStackHeight.self, value: geometry.size.height)
                    }
                }
            }
            .onChange(of: popups.entries.first?.id) { topID in
                if let topID { proxy.scrollTo(topID, anchor: .top) }
            }
        }
        .onPreferenceChange(ReminderStackHeight.self) { height in
            popups.fit(height: height)
        }
    }
}

private struct ReminderStackHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
