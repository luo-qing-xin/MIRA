import asyncio
import importlib.util
import json
import socket
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

spec = importlib.util.spec_from_file_location("bridge", Path(__file__).resolve().parents[1] / "integrations/codex/bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

def state():
    return {"id": "thread", "title": "test", "requests": [],
            "latestCollaborationMode": {"mode": "plan", "settings": {
                "model": "original-model", "reasoning_effort": "high", "developer_instructions": "plan mode"}},
            "turns": []}

def request(kind="plan", rid="r1"):
    return {"id": rid, "method": next(k for k,v in bridge.METHODS.items() if v == kind),
            "params": {"turnId": "turn", "planContent": "original plan"}}

class ProtocolTests(unittest.TestCase):
    def test_only_outstanding_server_requests_are_approvals(self):
        s = state()
        s["turns"] = [{"items": [{"type": "automaticApprovalReview", "status": "inProgress"}]}]
        s["requests"] = [{**request("command", "completed"), "completed": True}]
        self.assertEqual(bridge.requests(s), [])

        manual = request("command", "manual")
        s["requests"].append(manual)
        self.assertEqual(bridge.requests(s), [manual])

    def test_only_pending_computer_use_app_requests_become_reminders(self):
        s = state()
        params = {
            "mode": "form", "serverName": "computer_use", "turnId": "turn",
            "_meta": {
                "codex_approval_kind": "mcp_tool_call", "connector_id": "computer-use",
                "tool_params": {"app": "com.example.app", "private_argument": "not for MIRA"},
                "tool_params_display": [{"name": "app", "value": "MIRA Validation"}],
                "persist": ["session", "always"],
            },
        }
        pending = dict(id=116, method="mcpServer/elicitation/request", params=params)
        other = dict(params, _meta=dict(params["_meta"], connector_id="browser-use"))
        auth = dict(params, mode="openai/userVerification")
        s["requests"] = [
            pending, dict(pending, id=117, completed=True),
            dict(pending, id=118, params=other), dict(pending, id=119, params=auth),
        ]
        self.assertEqual(bridge.requests(s), [pending])
        item = bridge.proposal(pending, s, "owner")
        self.assertEqual((item["kind"], item["details"], item["actions"]),
                         ("computer-use", "MIRA Validation", []))
        self.assertNotIn("not for MIRA", json.dumps(item))
        s["requests"] = [dict(pending, completed=True)]
        self.assertEqual(bridge.requests(s), [])

    def test_plan_preserves_model_and_changes_mode(self):
        s = state()
        method, params = bridge.decision_request(request(), s, "allow", "unique")
        self.assertEqual(method, "thread-follower-start-turn")
        mode = params["turnStart"]["request"]["collaborationMode"]
        self.assertEqual(mode["mode"], "default")
        self.assertEqual(mode["settings"]["model"], "original-model")
        self.assertEqual(mode["settings"]["reasoning_effort"], "high")
        self.assertEqual(s["latestCollaborationMode"]["mode"], "plan")

    def test_changed_plan_invalidates_confirmation(self):
        r, s = request(), state()
        first = bridge.proposal(r, s, "owner")
        r["params"]["planContent"] = "updated plan"
        second = bridge.proposal(r, s, "owner")
        self.assertEqual(first["id"], second["id"])
        self.assertNotEqual(first["fingerprint"], second["fingerprint"])

    def test_concurrent_requests_have_distinct_identity(self):
        self.assertNotEqual(bridge.proposal(request(rid="a"), state(), "o")["id"],
                            bridge.proposal(request(rid="b"), state(), "o")["id"])

    def test_command_decline_and_allowed_choices(self):
        r = request("command", 123)
        method, payload = bridge.decision_request(r, state(), "deny", "m")
        self.assertEqual(payload["requestId"], 123)
        self.assertEqual(payload["decision"], "decline")
        r["params"]["availableDecisions"] = ["decline"]
        self.assertEqual(bridge.proposal(r, state(), "o")["actions"], ["deny"])

    def test_permissions_grant_only_requested_for_turn(self):
        r = request("permissions")
        r["params"]["permissions"] = {"network": {"enabled": True}}
        _, p = bridge.decision_request(r, state(), "allow", "m")
        self.assertEqual(p["response"], {"permissions": r["params"]["permissions"], "scope": "turn"})
        _, p = bridge.decision_request(r, state(), "deny", "m")
        self.assertEqual(p["response"]["permissions"], {})


class IPCRecoveryTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory(dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        home = Path(self.temp.name)
        self.path = home / "ipc/ipc.sock"
        self.path.parent.mkdir()
        self.path.touch()
        self.ipc = bridge.IPC(home)
        self.connections = asyncio.Queue()
        self.peers = []
        self.addAsyncCleanup(self.cleanup_connections)
        # Use connected Unix sockets so the protocol runs through real stream
        # framing and EOF, even in environments that forbid binding a path.
        socket_check = patch.object(bridge.stat, "S_ISSOCK", return_value=True)
        opener = patch.object(bridge.asyncio, "open_unix_connection", side_effect=self.open_transport)
        socket_check.start()
        opener.start()
        self.addCleanup(socket_check.stop)
        self.addCleanup(opener.stop)

    async def open_transport(self, path, limit):
        self.assertEqual(path, str(self.path))
        local, remote = socket.socketpair()
        client = await asyncio.open_connection(sock=local, limit=limit)
        peer = await asyncio.open_connection(sock=remote)
        self.connections.put_nowait(peer)
        return client

    async def cleanup_connections(self):
        await self.ipc.close()
        while not self.connections.empty():
            self.peers.append(self.connections.get_nowait()[1])
        for peer in self.peers:
            peer.close()
            await peer.wait_closed()

    async def handshake(self, **response):
        task = asyncio.create_task(self.ipc.connect())
        reader, writer = await asyncio.wait_for(self.connections.get(), 1)
        self.peers.append(writer)
        message = await self.receive(reader)
        self.assertEqual(message["method"], "initialize")
        self.assertIsNone(message["sourceClientId"])
        reply = json.dumps(dict(type="response", requestId=message["requestId"], **response)).encode()
        writer.write(struct.pack("<I", len(reply)) + reply)
        await writer.drain()
        return task, reader, writer

    async def receive(self, reader):
        header = await asyncio.wait_for(reader.readexactly(4), 1)
        size = struct.unpack("<I", header)[0]
        return json.loads(await asyncio.wait_for(reader.readexactly(size), 1))

    async def test_failed_initialize_closes_transport_and_allows_new_handshake(self):
        first, reader, _ = await self.handshake(resultType="error", error="initialize rejected")
        with self.assertRaisesRegex(RuntimeError, "initialize rejected"):
            await first
        self.assertIsNone(self.ipc.writer)
        self.assertIsNone(self.ipc.reader_task)
        self.assertEqual(await asyncio.wait_for(reader.read(1), 1), b"")
        with self.assertRaises(ConnectionError):
            await self.ipc.request("thread-owner-discovery", {})
        second, _, _ = await self.handshake(resultType="success", result={"clientId": "new-client"})
        await second
        self.assertTrue(self.ipc.connected)
        self.assertEqual(self.ipc.client_id, "new-client")

    async def test_missing_client_id_does_not_mark_transport_ready(self):
        task, _, _ = await self.handshake(resultType="success", result={})
        with self.assertRaisesRegex(ValueError, "客户端标识"):
            await task
        self.assertFalse(self.ipc.connected)
        self.assertIsNone(self.ipc.writer)

    async def test_initialize_timeout_releases_the_connection(self):
        request = self.ipc.request

        async def with_short_timeout(method, params):
            return await request(method, params, timeout=0.05)

        with patch.object(self.ipc, "request", side_effect=with_short_timeout):
            task = asyncio.create_task(self.ipc.connect())
            reader, writer = await asyncio.wait_for(self.connections.get(), 1)
            self.peers.append(writer)
            self.assertEqual((await self.receive(reader))["method"], "initialize")
            with self.assertRaises(asyncio.TimeoutError):
                await task
        self.assertIsNone(self.ipc.writer)
        self.assertIsNone(self.ipc.reader_task)
        self.assertEqual(await asyncio.wait_for(reader.read(1), 1), b"")

    async def test_disconnect_rejects_pending_request_and_clears_old_owner(self):
        connected, reader, writer = await self.handshake(resultType="success", result={"clientId": "old-client"})
        await connected
        self.ipc.owners["thread"] = "old-owner"
        disconnected = asyncio.Event()
        self.ipc.on_disconnect = disconnected.set
        pending = asyncio.create_task(self.ipc.request("thread-owner-discovery", {"conversationId": "thread"}))
        message = await self.receive(reader)
        self.assertEqual(message["sourceClientId"], "old-client")
        writer.close()
        with self.assertRaises(ConnectionError):
            await asyncio.wait_for(pending, 1)
        await asyncio.wait_for(disconnected.wait(), 1)
        self.assertFalse(self.ipc.connected)
        self.assertEqual(self.ipc.owners, {})
        self.assertEqual(self.ipc.pending, {})
        reconnected, _, _ = await self.handshake(resultType="success", result={"clientId": "new-client"})
        await reconnected
        self.assertEqual(self.ipc.client_id, "new-client")


class DecisionTests(unittest.IsolatedAsyncioTestCase):
    async def test_unverified_cannot_submit(self):
        with tempfile.TemporaryDirectory() as tmp:
            b = bridge.Bridge(Path(tmp), Path(tmp))
            async def refresh(_): pass
            b.refresh = refresh
            item = bridge.proposal(request(), state(), "o")
            await b.decide({"item": item, "action": "allow"})
            self.assertEqual(b.journal, {})

    async def test_uncertain_submission_not_retried(self):
        with tempfile.TemporaryDirectory() as tmp:
            b = bridge.Bridge(Path(tmp), Path(tmp))
            b.verified = {"plan"}
            s = state()
            s["requests"] = [request()]
            class FakeIPC:
                count = 0
                async def snapshot(self, _): return s, "o"
                async def request(self, *args, **kwargs):
                    self.count += 1
                    raise TimeoutError("timeout")
            b.ipc = FakeIPC()
            async def refresh(_): pass
            b.refresh = refresh
            item = bridge.proposal(request(), s, "o")
            await b.decide({"item": item, "action": "allow"})
            await b.decide({"item": item, "action": "allow"})
            self.assertEqual(b.ipc.count, 1)
            self.assertEqual(b.journal[item["id"]]["status"], "sending")
            restarted = bridge.Bridge(Path(tmp), Path(tmp))
            restarted.verified = {"plan"}
            restarted.ipc = b.ipc
            restarted.refresh = AsyncMock()
            await restarted.decide({"item": item, "action": "allow"})
            self.assertEqual(b.ipc.count, 1)

    async def test_journal_failure_before_send_keeps_request_retryable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            b = bridge.Bridge(root, root)
            b.verified = {"plan"}
            s = state()
            s["requests"] = [request()]
            item = bridge.proposal(request(), s, "o")
            command = {"item": item, "action": "allow"}
            b.ipc.snapshot = AsyncMock(return_value=(s, "o"))
            b.ipc.request = AsyncMock()
            b.refresh = AsyncMock()
            with patch.object(bridge.os, "replace", side_effect=OSError("disk unavailable")), \
                 patch.object(bridge, "output") as result:
                await b.decide(command)
            b.ipc.request.assert_not_awaited()
            self.assertEqual(b.journal, {})
            self.assertEqual(list(root.iterdir()), [])
            self.assertFalse(result.call_args.args[0]["uncertain"])

            with patch.object(bridge, "output"):
                await b.decide(command)
            b.ipc.request.assert_awaited_once()
            self.assertEqual(b.journal[item["id"]]["status"], "accepted")
            self.assertEqual(b.journal_path.stat().st_mode & 0o777, 0o600)

    async def test_acknowledgement_write_failure_keeps_durable_retry_barrier(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            b = bridge.Bridge(root, root)
            b.verified = {"plan"}
            s = state()
            s["requests"] = [request()]
            item = bridge.proposal(request(), s, "o")
            command = {"item": item, "action": "allow"}
            b.ipc.snapshot = AsyncMock(return_value=(s, "o"))
            b.ipc.request = AsyncMock()
            b.refresh = AsyncMock()
            record_decision = b.record_decision

            def fail_after_ack(key, record):
                if record["status"] == "accepted":
                    raise OSError("disk unavailable")
                record_decision(key, record)

            with patch.object(b, "record_decision", side_effect=fail_after_ack), patch.object(bridge, "output") as result:
                await b.decide(command)
            self.assertTrue(result.call_args.args[0]["success"])
            self.assertEqual(b.journal[item["id"]]["status"], "sending")
            restarted = bridge.Bridge(root, root)
            restarted.verified = {"plan"}
            restarted.ipc = b.ipc
            restarted.refresh = AsyncMock()
            with patch.object(bridge, "output"):
                await restarted.decide(command)
            b.ipc.request.assert_awaited_once()

if __name__ == "__main__": unittest.main()
