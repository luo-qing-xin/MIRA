#!/usr/bin/python3
"""Versioned, background-only adapter to the installed Codex desktop IPC.

JSON lines on stdin/stdout are private to the MIRA parent process. No socket is
exposed by MIRA. Full conversation snapshots stay in memory and are discarded.
"""
import asyncio
import copy
import hashlib
import json
import os
import re
import stat
import struct
import sys
import tempfile
import time
import uuid
from pathlib import Path

VERSIONS = {
    "initialize": 0, "thread-owner-discovery": 1,
    "thread-follower-start-turn": 2,
    "thread-follower-command-approval-decision": 1,
    "thread-follower-file-approval-decision": 1,
    "thread-follower-permissions-request-approval-response": 1,
}
METHODS = {
    "item/plan/requestImplementation": "plan",
    "item/commandExecution/requestApproval": "command",
    "item/fileChange/requestApproval": "file",
    "item/permissions/requestApproval": "permissions",
}
PLAN_PREFIX = "PLEASE IMPLEMENT THIS PLAN:\n"
ELICITATION_METHOD = "mcpServer/elicitation/request"


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def turns(state):
    history = state.get("turnHistory", {})
    if history.get("kind") == "canonical":
        return list(history.get("history", {}).get("entitiesByKey", {}).values())
    return state.get("turns", [])


def request_kind(request):
    method = request.get("method")
    if method != ELICITATION_METHOD:
        return METHODS.get(method)
    params = request.get("params") or {}
    metadata = params.get("_meta")
    if params.get("mode") != "form" or not isinstance(metadata, dict):
        return None
    connector = metadata.get("connector_id")
    if metadata.get("codex_approval_kind") != "mcp_tool_call" or not isinstance(connector, str):
        return None
    connector = "-".join(re.findall(r"[a-z0-9]+", connector.lower()))
    if connector == "computer-use" or connector.startswith("computer-use-"):
        return "computer-use"
    return None


def requests(state):
    # Codex tracks automatic review as a turn item. Only outstanding server
    # requests can be answered by a person.
    return [r for r in state.get("requests", [])
            if r.get("completed") is not True and request_kind(r) is not None]


def computer_use_app(params):
    metadata = params["_meta"]
    display = metadata.get("tool_params_display")
    if isinstance(display, list):
        for item in display:
            if isinstance(item, dict) and item.get("name") == "app":
                value = item.get("value")
                if isinstance(value, str) and value.strip():
                    return " ".join(value.split())[:80]
    arguments = metadata.get("tool_params")
    app = arguments.get("app") if isinstance(arguments, dict) else None
    return " ".join(app.split())[:80] if isinstance(app, str) else ""


def details(request, state):
    params = request.get("params", {})
    kind = METHODS[request["method"]]
    if kind == "plan":
        return params.get("planContent") or ""
    data = copy.deepcopy(params)
    for turn in turns(state):
        for item in turn.get("items", []):
            if item.get("id") == params.get("itemId"):
                data["operation"] = item
    return json.dumps(data, ensure_ascii=False, indent=2)


def proposal(request, state, owner):
    kind = request_kind(request)
    params = request.get("params", {})
    identity = [state["id"], request["id"], params.get("turnId"), kind]
    if kind == "computer-use":
        # This request stays on the native approval surface. Send only what
        # the reminder needs, without forwarding tool parameters or metadata.
        app = computer_use_app(params)
        return dict(id="codex-live-" + digest(identity)[:24], session=state["id"],
                    requestId=str(request["id"]), turnId=params.get("turnId") or "",
                    owner=owner, kind=kind, fingerprint=digest([identity, app]),
                    details=app, title=state.get("title") or "Codex", actions=[])
    content = details(request, state)
    model = state.get("latestCollaborationMode") or {}
    fingerprint = digest([identity, params, content, model])
    options = params.get("availableDecisions")
    allowed = ["allow", "deny"]
    if kind == "plan":
        allowed = ["allow"] if content else []
    elif options is not None:
        allowed = [action for action, value in (("allow", "accept"), ("deny", "decline")) if value in options]
    return dict(id="codex-live-" + digest(identity)[:24], session=state["id"],
                requestId=str(request["id"]), turnId=params.get("turnId") or "",
                owner=owner, kind=kind, fingerprint=fingerprint, details=content,
                title=state.get("title") or "Codex", actions=allowed)


def plan_start(state, content, message_id, mode="default"):
    collaboration = copy.deepcopy(state.get("latestCollaborationMode"))
    if not collaboration or not collaboration.get("settings", {}).get("model"):
        raise ValueError("无法读取当前模型设置")
    collaboration["mode"] = mode
    # Let Codex resolve the built-in instructions for the selected mode.
    collaboration["settings"]["developer_instructions"] = None
    return {
        "request": {
            "threadId": state["id"],
            "input": [{"type": "text", "text": content, "text_elements": []}],
            "clientUserMessageId": message_id,
            "collaborationMode": collaboration,
        },
        "context": {"inheritThreadSettings": True, "threadStartKind": "plan_implementation"},
    }


class IPC:
    def __init__(self, home):
        self.home = home
        self.writer = None
        self.pending = {}
        self.waiters = {}
        self.owners = {}
        self.locks = {}
        self.client_id = None
        self.reader_task = None
        self.on_disconnect = lambda: None

    @property
    def connected(self):
        return self.client_id is not None and self.writer is not None and not self.writer.is_closing()

    async def connect(self):
        if self.connected:
            return
        await self.close()
        path = self.home / "ipc/ipc.sock"
        info = path.stat()
        if info.st_uid != os.getuid() or not stat.S_ISSOCK(info.st_mode):
            raise ValueError("Codex IPC 路径不属于当前用户")
        reader, writer = await asyncio.open_unix_connection(str(path), limit=32 * 1024 * 1024)
        self.writer = writer
        self.reader_task = asyncio.create_task(self.read(reader, writer))
        try:
            reply = await self.request("initialize", {"clientType": "mira"})
            client_id = reply.get("result", {}).get("clientId")
            if not isinstance(client_id, str) or not client_id:
                raise ValueError("Codex 握手未返回客户端标识")
            if self.writer is not writer or writer.is_closing():
                raise ConnectionError("Codex 握手后连接已断开")
            self.client_id = client_id
        except (Exception, asyncio.CancelledError):
            await self.close()
            raise

    async def send(self, value):
        writer = self.writer
        if writer is None or writer.is_closing():
            raise ConnectionError("Codex 后台连接未建立")
        data = json.dumps(value, ensure_ascii=False).encode()
        try:
            writer.write(struct.pack("<I", len(data)) + data)
            await writer.drain()
        except OSError:
            self.disconnect(writer)
            raise

    async def request(self, method, params, owner=None, timeout=12):
        if method != "initialize" and not self.connected:
            raise ConnectionError("Codex 后台连接尚未完成握手")
        rid = str(uuid.uuid4())
        future = asyncio.get_running_loop().create_future()
        self.pending[rid] = future
        try:
            await self.send(dict(type="request", requestId=rid, sourceClientId=self.client_id,
                                 version=VERSIONS[method], method=method, params=params,
                                 targetClientId=owner, timeoutMs=int(timeout * 1000)))
            result = await asyncio.wait_for(future, timeout)
            if result.get("resultType") != "success":
                raise RuntimeError(result.get("error", "Codex 未接受请求"))
            return result
        finally:
            self.pending.pop(rid, None)
            if future.done() and not future.cancelled():
                future.exception()

    async def read(self, reader, writer):
        try:
            while True:
                size = struct.unpack("<I", await reader.readexactly(4))[0]
                if size > 32 * 1024 * 1024:
                    raise ValueError("Codex IPC 消息过大")
                message = json.loads(await reader.readexactly(size))
                if message.get("type") == "response":
                    future = self.pending.get(message.get("requestId"))
                    if future and not future.done():
                        future.set_result(message)
                elif message.get("type") == "client-discovery-request":
                    await self.send(dict(type="client-discovery-response",
                                         requestId=message["requestId"], response={"canHandle": False}))
                elif message.get("method") == "thread-stream-state-changed":
                    params = message.get("params", {})
                    thread = params.get("conversationId")
                    future = self.waiters.get(thread)
                    if future and not future.done() and message.get("sourceClientId") == self.owners.get(thread):
                        if message.get("version") != 11:
                            future.set_exception(ValueError("Codex 状态协议版本不兼容"))
                        elif params.get("change", {}).get("type") == "snapshot":
                            future.set_result(params["change"]["conversationState"])
        except (Exception, asyncio.CancelledError):
            self.disconnect(writer)

    def disconnect(self, writer):
        if self.writer is not writer:
            return
        initialized = self.client_id is not None
        self.writer = None
        self.client_id = None
        self.owners.clear()
        writer.transport.abort()
        for future in list(self.pending.values()) + list(self.waiters.values()):
            if not future.done():
                future.set_exception(ConnectionError("Codex 后台连接已断开"))
        if initialized:
            self.on_disconnect()

    async def snapshot(self, thread):
        lock = self.locks.setdefault(thread, asyncio.Lock())
        async with lock:
            writer = self.writer
            reply = await self.request("thread-owner-discovery", {"hostId": "local", "conversationId": thread})
            if self.writer is not writer or not self.connected:
                raise ConnectionError("Codex 会话查询期间连接已断开")
            owner = reply["handledByClientId"]
            self.owners[thread] = owner
            future = asyncio.get_running_loop().create_future()
            self.waiters[thread] = future
            try:
                await self.send(dict(type="broadcast", method="thread-stream-following-changed", version=1,
                                     sourceClientId=self.client_id, targetClientIds=[owner],
                                     params=dict(hostId="local", conversationId=thread, following=True)))
                state = await asyncio.wait_for(future, 10)
                if self.writer is not writer or not self.connected:
                    raise ConnectionError("Codex 会话查询期间连接已断开")
                if state.get("id") != thread:
                    raise ValueError("Codex 返回了不同会话")
                return state, owner
            finally:
                self.waiters.pop(thread, None)
                if future.done() and not future.cancelled():
                    future.exception()

    async def close(self):
        if self.writer:
            self.disconnect(self.writer)
        reader_task, self.reader_task = self.reader_task, None
        if reader_task:
            reader_task.cancel()
            await asyncio.gather(reader_task, return_exceptions=True)


def output(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


class Bridge:
    def __init__(self, home, root):
        self.ipc = IPC(home)
        self.ipc.on_disconnect = lambda: output({"type": "connection", "connected": False, "message": "Codex 后台连接已断开"})
        self.root = root
        self.watched = set()
        self.busy = set()
        self.journal_path = root / "codex-decisions.json"
        self.journal = json.loads(self.journal_path.read_text()) if self.journal_path.exists() else {}
        self.verified = set()
        verification = root / "codex-verified.json"
        if verification.exists():
            data = json.loads(verification.read_text())
            # Verification is tied to the exact installed client bundle.
            if data.get("build") == client_build():
                self.verified = set(data.get("kinds", []))

    def record_decision(self, key, record):
        updated = {**self.journal, key: record}
        self.root.mkdir(parents=True, exist_ok=True)
        handle = tempfile.NamedTemporaryFile(mode="w", dir=self.root, prefix=".codex-decisions-", delete=False)
        path = Path(handle.name)
        try:
            with handle:
                json.dump(updated, handle)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(path, self.journal_path)
        except Exception:
            path.unlink(missing_ok=True)
            raise
        self.journal = updated

    async def refresh(self, thread):
        try:
            state, owner = await self.ipc.snapshot(thread)
            pending = [proposal(r, state, owner) for r in requests(state)]
            for item in pending:
                item["verified"] = item["kind"] in METHODS.values() and item["kind"] in self.verified
                record = self.journal.get(item["id"])
                if record:
                    item["actions"] = []
                    item["message"] = "确认结果待核对，请在 Codex 查看" if record["status"] == "sending" else "确认已提交，等待 Codex 更新"
            output(dict(type="snapshot", session=thread, pending=pending))
        except Exception as exc:
            output(dict(type="unavailable", session=thread, message=str(exc)))

    async def decide(self, command):
        item = command["item"]
        key = item["id"]
        if key in self.busy:
            return
        self.busy.add(key)
        sent = False
        try:
            if item["kind"] not in METHODS.values() or item["kind"] not in self.verified:
                raise ValueError("此类确认尚未完成真实回传验证")
            if key in self.journal:
                raise ValueError("此请求已经提交，请等待状态核对")
            state, owner = await self.ipc.snapshot(item["session"])
            request = next((r for r in requests(state) if str(r["id"]) == item["requestId"]), None)
            if request is None:
                raise ValueError("请求已在 Codex 处理或失效")
            current = proposal(request, state, owner)
            if current["fingerprint"] != item["fingerprint"]:
                raise ValueError("内容已更新，请查看最新内容后重新确认")
            action = command["action"]
            if action not in current["actions"]:
                raise ValueError("当前请求不支持此操作")
            method, params = decision_request(request, state, action, str(uuid.uuid4()))
            record = {"status": "sending", "time": time.time(), "action": action}
            self.record_decision(key, record)
            sent = True
            await self.ipc.request(method, params, owner, timeout=30)
            try:
                self.record_decision(key, {**record, "status": "accepted"})
            except OSError:
                # Codex acknowledged the request. Keep the durable "sending"
                # record as a retry barrier even if recording the ack failed.
                pass
            output(dict(type="result", id=key, success=True, action=action, kind=item["kind"]))
        except Exception as exc:
            output(dict(type="result", id=key, success=False, message=str(exc), uncertain=sent))
        finally:
            self.busy.discard(key)
        await self.refresh(item["session"])

    async def poll(self):
        while True:
            try:
                if not self.ipc.connected:
                    await self.ipc.connect()
                    output(dict(type="connection", connected=True, message="后台已连接",
                                verified=sorted(self.verified)))
                # A small concurrency cap prevents a large inbox from flooding IPC.
                semaphore = asyncio.Semaphore(4)
                async def one(thread):
                    async with semaphore:
                        await self.refresh(thread)
                await asyncio.gather(*(one(t) for t in list(self.watched)))
            except Exception as exc:
                output(dict(type="connection", connected=False, message=str(exc)))
            await asyncio.sleep(3)

    async def run(self):
        polling = asyncio.create_task(self.poll())
        decisions = set()
        try:
            while True:
                line = await asyncio.get_running_loop().run_in_executor(None, sys.stdin.readline)
                if not line:
                    break
                try:
                    command = json.loads(line)
                    if command.get("type") == "watch":
                        new_sessions = set(command.get("sessions", []))
                        removed_sessions = self.watched - new_sessions
                        self.watched = new_sessions
                        for thread in removed_sessions:
                            owner = self.ipc.owners.pop(thread, None)
                            if owner and self.ipc.connected:
                                try:
                                    await self.ipc.send(dict(type="broadcast", method="thread-stream-following-changed",
                                        version=1, targetClientIds=[owner],
                                        params=dict(hostId="local", conversationId=thread, following=False)))
                                except OSError:
                                    break
                    elif command.get("type") == "decide":
                        task = asyncio.create_task(self.decide(command))
                        decisions.add(task)
                        task.add_done_callback(decisions.discard)
                except (ValueError, KeyError):
                    output(dict(type="connection", connected=False, message="MIRA 后台请求格式错误"))
        finally:
            polling.cancel()
            in_flight = tuple(decisions)
            for task in in_flight:
                task.cancel()
            await self.ipc.close()
            await asyncio.gather(polling, *in_flight, return_exceptions=True)


def decision_request(request, state, action, message_id):
    kind = METHODS[request["method"]]
    common = {"conversationId": state["id"], "requestId": request["id"]}
    if kind == "plan":
        if state.get("threadRuntimeStatus", {}).get("type") == "active":
            raise ValueError("会话已经在运行，请等待最新状态")
        return "thread-follower-start-turn", {
            "conversationId": state["id"],
            "turnStart": plan_start(state, PLAN_PREFIX + details(request, state), message_id),
        }
    if kind == "permissions":
        granted = request["params"].get("permissions", {}) if action == "allow" else {}
        return "thread-follower-permissions-request-approval-response", {
            **common, "response": {"permissions": granted, "scope": "turn"},
        }
    method = "thread-follower-" + ("command" if kind == "command" else "file") + "-approval-decision"
    return method, {**common, "decision": "accept" if action == "allow" else "decline"}


def client_build():
    path = Path("/Applications/ChatGPT.app/Contents/Info.plist")
    return digest(path.read_bytes().hex()) if path.exists() else ""


if __name__ == "__main__":
    home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
    root = Path(os.environ.get("MIRA_DATA_DIR", str(Path.home() / "Library/Application Support/MIRA")))
    asyncio.run(Bridge(home, root).run())
