import Foundation

struct CodexPending: Codable, Identifiable {
    var id: String
    var session: String
    var requestId: String
    var turnId: String
    var owner: String
    var kind: String
    var fingerprint: String
    var details: String
    var title: String
    var actions: [String]
    var verified: Bool
    var message: String?

    var label: String { kind == "plan" ? "执行计划" : "允许一次" }

    var reminderBody: String {
        switch kind {
        case "plan":
            return "计划已生成，确认后开始执行。"
        case "computer-use":
            return details.isEmpty ? "Codex 正在等待 Computer Use 授权。"
                : "Codex 请求通过 Computer Use 使用「\(details)」。"
        default:
            return "请查看具体操作后选择允许或拒绝。"
        }
    }
}

/// The helper owns the Unix socket. Stdout is a private JSON-lines stream, and
/// terminating MIRA closes stdin so the helper also exits.
@MainActor final class CodexBridge {
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    var onMessage: (([String: Any]) -> Void)?

    func start() {
        guard process?.isRunning != true,
              let script = Bundle.main.url(forResource: "bridge", withExtension: "py") else { return }
        let task = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["-u", script.path]
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.receive(data) }
        }
        task.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.input = nil
                self?.onMessage?(["type": "connection", "connected": false, "message": "后台连接已停止，正在重连"])
            }
        }
        do {
            try task.run()
            process = task
            input = stdin.fileHandleForWriting
            buffer.removeAll()
        } catch {
            onMessage?(["type": "connection", "connected": false, "message": error.localizedDescription])
        }
    }

    func send(_ message: [String: Any]) throws {
        guard let input else { throw NSError(domain: "后台连接未启动", code: 1) }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end)
            buffer.removeSubrange(...end)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                onMessage?(object)
            }
        }
    }

    func stop() {
        try? input?.close()
        input = nil
        process?.terminate()
        process = nil
    }
}

extension Hub {
    func startCodexBridge() {
        codexBridge.onMessage = { [weak self] message in self?.receiveCodex(message) }
        codexBridge.start()
    }

    func watchCodex(checking approvalSessions: Set<String>, now: Date) {
        codexBridge.start()
        // Keep checking hook-only sessions briefly while Codex settles its
        // approval flow. Sessions with a live request are then watched by entry.
        codexApprovalChecks = codexApprovalChecks.filter { $0.value > now }
        for session in approvalSessions {
            codexApprovalChecks[session] = now.addingTimeInterval(60)
        }
        var sessions = Set(data.entries.filter {
            $0.source.hasPrefix("Codex") && (!$0.done || $0.date > now.addingTimeInterval(-86400))
        }.compactMap(\.thread))
        sessions.formUnion(codexApprovalChecks.keys)
        try? codexBridge.send(["type": "watch", "sessions": Array(sessions)])
    }

    func receiveCodex(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "connection":
            codexConnected = message["connected"] as? Bool ?? false
            codexConnectionStatus = message["message"] as? String ?? "后台连接不可用"
            if !codexConnected {
                codexAvailable.removeAll()
                for id in codexSubmitting { codexActionErrors[id] = "连接中断，正在核对确认结果" }
                codexSubmitting.removeAll()
            }
        case "unavailable":
            if let session = message["session"] as? String {
                codexAvailable.remove(session)
                codexSessionErrors[session] = message["message"] as? String
            }
        case "snapshot":
            guard let session = message["session"] as? String,
                  let objects = message["pending"] as? [[String: Any]],
                  let bytes = try? JSONSerialization.data(withJSONObject: objects),
                  let pending = try? JSONDecoder().decode([CodexPending].self, from: bytes) else { return }
            codexAvailable.insert(session)
            codexSnapshotDates[session] = Date()
            codexSessionErrors.removeValue(forKey: session)
            let ids = Set(pending.map(\.id))
            var entriesChanged = false
            if pending.contains(where: { $0.kind == "plan" }) {
                for index in data.entries.indices where data.entries[index].thread == session &&
                    data.entries[index].waitsForCodexPlan && !data.entries[index].notified && !data.entries[index].done {
                    data.entries[index].done = true
                    entriesChanged = true
                }
            }
            for index in data.entries.indices where data.entries[index].thread == session && data.entries[index].codexID != nil {
                let id = data.entries[index].id
                if !ids.contains(id) && !codexSubmitting.contains(id) {
                    if !data.entries[index].done {
                        data.entries[index].done = true
                        entriesChanged = true
                    }
                    closePopup?(id)
                    codexPending.removeValue(forKey: id)
                }
            }
            for request in pending {
                if let previous = codexPending[request.id], previous.fingerprint != request.fingerprint {
                    codexActionErrors[request.id] = "内容已更新，请查看后重新确认"
                }
                codexPending[request.id] = request
                let title = Titles.prompt(request.title)
                if let index = data.entries.firstIndex(where: { $0.id == request.id }) {
                    if data.entries[index].title != title {
                        data.entries[index].title = title
                        entriesChanged = true
                    }
                    if request.kind == "computer-use" && data.entries[index].body != request.reminderBody {
                        data.entries[index].body = request.reminderBody
                        entriesChanged = true
                    }
                    // A native pending request remains actionable until a response
                    // has been acknowledged or the live snapshot removes it.
                    if data.entries[index].done && !codexAccepted.contains(request.id) {
                        data.entries[index].done = false
                        entriesChanged = true
                    }
                } else {
                    if request.kind == "plan" {
                        for index in data.entries.indices where data.entries[index].thread == session &&
                            data.entries[index].codexID == nil && data.entries[index].status == "待确认" {
                            data.entries[index].done = true
                            closePopup?(data.entries[index].id)
                        }
                    }
                    var entry = Entry(id: request.id, title: title, body: request.reminderBody,
                                      source: "Codex", status: "待确认",
                                      link: "codex://threads/" + session, date: Date(), thread: session)
                    entry.codexID = request.id
                    entry.codexKind = request.kind
                    data.entries.insert(entry, at: 0)
                    entriesChanged = true
                }
            }
            if entriesChanged { _ = save() }
        case "result":
            guard let id = message["id"] as? String else { return }
            codexSubmitting.remove(id)
            if message["success"] as? Bool == true {
                codexAccepted.insert(id)
                codexActionErrors.removeValue(forKey: id)
                if let index = data.entries.firstIndex(where: { $0.id == id }) {
                    let isPlan = message["kind"] as? String == "plan"
                    data.entries[index].status = isPlan ? "运行中" : (message["action"] as? String == "allow" ? "已允许" : "已拒绝")
                    data.entries[index].done = !isPlan
                    if isPlan {
                        data.entries[index].codexID = nil
                        data.entries[index].codexKind = nil
                    }
                    _ = save()
                }
                closePopup?(id)
            } else {
                codexActionErrors[id] = message["message"] as? String ?? "确认未发送"
            }
        default: break
        }
    }

    func confirmCodex(_ request: CodexPending, action: String) {
        guard !codexSubmitting.contains(request.id), codexConnected,
              codexAvailable.contains(request.session), request.verified,
              request.actions.contains(action) else { return }
        do {
            let bytes = try JSONEncoder().encode(request)
            let object = try JSONSerialization.jsonObject(with: bytes)
            codexSubmitting.insert(request.id)
            codexActionErrors.removeValue(forKey: request.id)
            try codexBridge.send(["type": "decide", "item": object, "action": action])
        } catch {
            codexSubmitting.remove(request.id)
            codexActionErrors[request.id] = error.localizedDescription
        }
    }
}

import SwiftUI

struct CodexApprovalControls: View {
    @ObservedObject var hub: Hub
    let entry: Entry
    var dismiss: () -> Void = {}
    @State private var expanded = false

    private var request: CodexPending? { hub.codexPending[entry.id] }
    private var submitting: Bool { hub.codexSubmitting.contains(entry.id) }

    var body: some View {
        if entry.codexKind == "computer-use" {
            Button("打开原会话授权") { hub.open(entry); dismiss() }
                .buttonStyle(EditorialButtonStyle(kind: .ink))
        } else {
            approvalControls
        }
    }

    private var approvalControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let request {
                DisclosureGroup(request.kind == "plan" ? "查看完整计划" : "查看具体操作", isExpanded: $expanded) {
                    ScrollView {
                        Text(request.details)
                            .font(.system(size: 12, design: request.kind == "plan" ? .default : .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                    .frame(height: 210)
                }
                .font(.system(size: 12))
                HStack(spacing: 8) {
                    Button(submitting ? "正在提交…" : request.label) { hub.confirmCodex(request, action: "allow") }
                        .buttonStyle(EditorialButtonStyle(kind: .rust))
                        .disabled(!available(request, "allow"))
                    if request.kind != "plan" {
                        Button("拒绝") { hub.confirmCodex(request, action: "deny") }
                            .buttonStyle(EditorialButtonStyle(kind: .outline))
                            .disabled(!available(request, "deny"))
                    }
                    Button("稍后") { hub.snooze(entry.id); dismiss() }
                        .buttonStyle(EditorialButtonStyle(kind: .text))
                    Spacer(minLength: 0)
                }
                if let message = hub.codexActionErrors[entry.id] ?? request.message ??
                    hub.codexSessionErrors[request.session] {
                    Text(message).font(.system(size: 11)).foregroundStyle(terracotta)
                } else if !request.verified {
                    Text("此类请求尚未完成后台回传验证，可在原会话处理。")
                        .font(.system(size: 11)).foregroundStyle(quiet)
                } else if !hub.codexConnected {
                    Text(hub.codexConnectionStatus).font(.system(size: 11)).foregroundStyle(quiet)
                }
            } else {
                Text(hub.codexConnected ? "正在核对 Codex 的待确认状态…" : hub.codexConnectionStatus)
                    .font(.system(size: 12)).foregroundStyle(quiet)
            }
            Button("打开原会话") { hub.open(entry) }
                .buttonStyle(EditorialButtonStyle(kind: .text))
        }
        .foregroundStyle(ink)
    }

    private func available(_ request: CodexPending, _ action: String) -> Bool {
        !submitting && hub.codexConnected && hub.codexAvailable.contains(request.session) &&
        request.verified && request.actions.contains(action) && !hub.codexAccepted.contains(request.id)
    }
}
