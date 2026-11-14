// Contract tests for the DSH adapter. Run: node --test tests/test_dsh_bridge.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { fileURLToPath } from "node:url";

import { ADAPTER_VERSION, build, emit, hint } from "../integrations/emit/emit.js";
import {
  approvalAskedEvent,
  approvalClosedEvent,
  approvalKey,
  isSubagent,
  questionAskedEvent,
  questionClosedEvent,
  questionKey,
  reasonKind,
  turnEndEvent,
  turnKey,
  turnStartEvent,
} from "../integrations/dsh/entry.js";
import { apply } from "../integrations/dsh/index.js";

const TIME = 1_764_000_000_123;
const repoRoot = fileURLToPath(new URL("../", import.meta.url));

function events(root) {
  try {
    return readdirSync(join(root, "inbox"))
      .filter((file) => file.endsWith(".json"))
      .sort()
      .map((file) => JSON.parse(readFileSync(join(root, "inbox", file), "utf8")));
  } catch {
    return [];
  }
}

function alive(root) {
  writeFileSync(join(root, "heartbeat"), String(Date.now()));
}

function decide(root, token, decision) {
  mkdirSync(join(root, "decisions"), { recursive: true });
  writeFileSync(join(root, "decisions", token + ".json"), JSON.stringify({ token, decision }));
}

async function waitFor(predicate, timeoutMs = 2000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const value = predicate();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("condition not met in time");
}

function session(overrides = {}) {
  return { id: "session-1234-abcd", header: { cwd: "/Users/yunye/MIRA", ...overrides } };
}

function userMessage(text) {
  return { type: "user/message", data: { source: { kind: "user" }, content: [{ type: "text", text }] } };
}

function sessionWithEvents(list, overrides = {}) {
  return {
    id: "session-1234-abcd",
    seq: list.length,
    header: { cwd: "/Users/yunye/MIRA", ...overrides },
    eventAt: (index) => list[index],
  };
}

function harness(root, config = {}) {
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root, approvalTimeoutMs: 3000, pollMs: 10, ...config },
  );
  return handlers;
}

// MARK: - Emitter

test("the emitter stamps the envelope and bounds the title hint", () => {
  const event = build(
    {
      adapter: "Demo",
      name: "Demo Tool",
      kind: "turn.end",
      session: " s1 ",
      turn: 2.9,
      hint: "第一段\n\n第二段",
      unknown: "dropped",
    },
    TIME,
  );
  assert.equal(event.protocol, "mira.adapter/1");
  assert.equal(event.adapter.id, "demo");
  assert.equal(event.adapter.name, "Demo Tool");
  assert.equal(event.adapter.version, ADAPTER_VERSION);
  assert.equal(event.session, "s1");
  assert.equal(event.turn, 2);
  assert.equal(event.time, TIME);
  assert.equal(event.titleHint, "第一段");
  assert.equal(event.unknown, undefined);

  const long = build({ adapter: "x", kind: "turn.start", session: "s", hint: "长".repeat(400) }, TIME);
  assert.equal(Array.from(long.titleHint).length, 160);
});

test("the emitter rejects events without an adapter, kind or session", () => {
  assert.throws(() => build({ kind: "turn.end", session: "s" }, TIME), /adapter/);
  assert.throws(() => build({ adapter: "dsh", session: "s" }, TIME), /kind/);
  assert.throws(() => build({ adapter: "dsh", kind: "turn.end" }, TIME), /session/);
});

test("the emitter writes atomically with private permissions", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-emit-"));
  const path = emit(root, { adapter: "dsh", kind: "turn.end", session: "s", reason: "completed" }, TIME);
  const parsed = JSON.parse(readFileSync(path, "utf8"));
  assert.equal(parsed.protocol, "mira.adapter/1");
  assert.equal(statSync(path).mode & 0o777, 0o600);
  assert.equal(statSync(join(root, "inbox")).mode & 0o777, 0o700);
  assert.match(basename(path), /^\d{20}-[0-9a-f-]+\.json$/);
});

test("hints keep only the first paragraph", () => {
  assert.equal(hint("# 标题\n\n正文"), "# 标题");
  assert.equal(hint("   "), null);
  assert.equal(hint(undefined), null);
});

test("the JS emitter version matches the Swift receiver", () => {
  const source = readFileSync(join(repoRoot, "Sources/Core.swift"), "utf8");
  const match = source.match(/static let current = "([^"]+)"/);
  assert.ok(match, "Core.swift declares IntegrationVersion.current");
  assert.equal(ADAPTER_VERSION, match[1]);
});

// MARK: - DSH mapping

test("turn reasons map onto the contract vocabulary", () => {
  for (const kind of ["completed", "error", "aborted", "blocked", "max-tokens", "interrupted"]) {
    assert.equal(reasonKind({ kind }), kind);
  }
  assert.equal(reasonKind({ kind: "future-reason" }), "completed", "unknown reasons degrade like before");
  assert.equal(reasonKind(null), "completed");
  assert.equal(reasonKind({ kind: 42 }), "completed");
});

test("turn events carry stable dedupe keys and no reminder policy", () => {
  const start = turnStartEvent({ sessionId: "s1", cwd: "/x", turn: 2, time: TIME, hint: "整理记录" });
  assert.equal(start.kind, "turn.start");
  assert.equal(start.dedupeKey, turnKey("s1", 2, "start"));
  assert.equal(start.status, undefined, "the adapter does not decide reminder status");
  assert.equal(start.hint, "整理记录");
  assert.equal(start.cwd, "/x");
  assert.equal(start.turn, 2);

  const end = turnEndEvent({ sessionId: "s1", turn: 2, time: TIME, reason: { kind: "error" } });
  assert.equal(end.kind, "turn.end");
  assert.equal(end.reason, "error");
  assert.equal(
    turnEndEvent({ sessionId: "s1", turn: 2, time: TIME, reason: { kind: "error" } }).dedupeKey,
    end.dedupeKey,
    "a repeated delivery collapses",
  );
  assert.notEqual(
    turnEndEvent({ sessionId: "s1", turn: 3, time: TIME, reason: { kind: "error" } }).dedupeKey,
    end.dedupeKey,
  );
});

test("approval events share one key with their dismissal", () => {
  const asked = approvalAskedEvent({
    sessionId: "s1",
    cwd: "/x",
    turn: 1,
    time: TIME,
    hint: "整理记录",
    toolName: "bash",
    reason: "写入工作区之外的文件",
    approvalId: "a1",
    token: "abcd-1234",
    ttlMs: 60_000,
  });
  assert.equal(asked.kind, "approval.asked");
  assert.equal(asked.dedupeKey, approvalKey("s1", "a1"));
  assert.equal(asked.approval.tool, "bash");
  assert.equal(asked.approval.reason, "写入工作区之外的文件");
  assert.equal(asked.approval.token, "abcd-1234");
  assert.equal(asked.approval.ttlMs, 60_000);

  const closed = approvalClosedEvent({ sessionId: "s1", time: TIME + 1, approvalId: "a1" });
  assert.equal(closed.kind, "approval.closed");
  assert.equal(closed.closes, asked.dedupeKey);
  assert.equal(closed.closes, approvalKey("s1", "a1"));
  assert.equal(closed.hint, undefined);
});

test("question events use the first question as their identity", () => {
  const asked = questionAskedEvent({
    sessionId: "s1",
    time: TIME,
    questions: [
      { id: "q1", question: "选哪个方案？" },
      { id: "q2", question: "什么时候？" },
    ],
  });
  assert.equal(asked.kind, "question.asked");
  assert.equal(asked.dedupeKey, questionKey("s1", "q1"));
  assert.equal(asked.questions.length, 2);
  assert.equal(asked.questions[0].question, "选哪个方案？");
  const closed = questionClosedEvent({ sessionId: "s1", time: TIME + 1, questionId: "q1" });
  assert.equal(closed.closes, asked.dedupeKey);
});

test("detects subagent sessions", () => {
  assert.equal(isSubagent(sessionWithEvents([], { origin: "subagent" })), true);
  assert.equal(isSubagent(sessionWithEvents([])), false);
  assert.equal(isSubagent(undefined), false);
});

// MARK: - DSH plugin integration

test("turn start and end deliver contract events", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = harness(root);
  const s = sessionWithEvents([userMessage("把设置页的按钮改大一些")]);
  const fire = (event) => handlers.get("session/event")(s, event);

  fire({ type: "turn/start", time: TIME, data: { turn: 1 } });
  fire({ type: "turn/end", time: TIME + 1, data: { turn: 1, reason: { kind: "completed" } } });

  const [running, ended] = events(root);
  assert.equal(running.kind, "turn.start");
  assert.equal(running.adapter.id, "dsh");
  assert.equal(running.titleHint, "把设置页的按钮改大一些");
  assert.equal(running.link, "dsh://open");
  assert.equal(ended.kind, "turn.end");
  assert.equal(ended.reason, "completed");
  assert.equal(ended.time, TIME + 1);
});

test("a session title is used only when no prompt is readable", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = harness(root);
  const s = sessionWithEvents([]);
  handlers.get("session/event")(s, { type: "session/title", time: TIME, data: { title: "修复对比度", source: { kind: "provider" } } });
  handlers.get("session/event")(s, { type: "turn/end", time: TIME, data: { turn: 1, reason: { kind: "completed" } } });
  const [ended] = events(root);
  assert.equal(ended.title, "修复对比度");
  assert.equal(ended.titleHint, undefined);
});

test("a deterministic fallback title is not forwarded", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = harness(root);
  const s = sessionWithEvents([]);
  handlers.get("session/event")(s, { type: "session/title", time: TIME, data: { title: "# 任务：被截断", source: { kind: "fallback" } } });
  handlers.get("session/event")(s, { type: "turn/end", time: TIME, data: { turn: 2, reason: { kind: "completed" } } });
  const [ended] = events(root);
  assert.equal(ended.title, undefined, "MIRA derives a cleaner fallback from the project and turn");
  assert.equal(ended.turn, 2);
});

test("subagent sessions are skipped", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = harness(root);
  handlers.get("session/event")(
    sessionWithEvents([], { origin: "subagent" }),
    { type: "turn/end", time: TIME, data: { turn: 1, reason: { kind: "completed" } } },
  );
  assert.equal(events(root).length, 0);
});

test("a broken inbox never fails the turn", () => {
  const warnings = [];
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: (m) => warnings.push(m) } },
    { dataDir: "/dev/null/mira" },
  );
  assert.doesNotThrow(() => {
    handlers.get("session/event")(sessionWithEvents([]), {
      type: "turn/end",
      time: TIME,
      data: { turn: 1, reason: { kind: "completed" } },
    });
  });
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /mira-bridge: delivery failed/);
});

test("an allowed approval is delivered, answered once, and closed", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  alive(root);
  const handlers = harness(root);
  const pending = handlers.get("approval/request")(
    { agent: { session: session() }, toolName: "bash", reason: "需要写入" },
    async () => "unavailable",
  );
  const asked = await waitFor(() => events(root).find((item) => item.kind === "approval.asked"));
  assert.equal(asked.approval.tool, "bash");
  assert.equal(asked.approval.reason, "需要写入");
  assert.ok(asked.approval.token);
  decide(root, asked.approval.token, "allow");
  assert.equal(await pending, "allowed-once");
  const closed = await waitFor(() => events(root).find((item) => item.kind === "approval.closed"));
  assert.equal(closed.closes, asked.dedupeKey, "the dismissal targets the same reminder");
});

test("a denied approval is rejected and closed", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  alive(root);
  const handlers = harness(root);
  const pending = handlers.get("approval/request")(
    { agent: { session: session() }, toolName: "bash" },
    async () => "unavailable",
  );
  const asked = await waitFor(() => events(root).find((item) => item.kind === "approval.asked"));
  decide(root, asked.approval.token, "deny");
  assert.equal(await pending, "rejected");
  assert.ok(events(root).some((item) => item.kind === "approval.closed"));
});

test("deferring falls back to the desktop dialog", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  alive(root);
  const handlers = harness(root, { approvalTimeoutMs: 3000 });
  let delegated = false;
  const pending = handlers.get("approval/request")(
    { agent: { session: session() }, toolName: "bash" },
    async () => {
      delegated = true;
      return "ui-answer";
    },
  );
  const asked = await waitFor(() => events(root).find((item) => item.kind === "approval.asked"));
  decide(root, asked.approval.token, "defer");
  assert.equal(await pending, "ui-answer");
  assert.equal(delegated, true, "the desktop answerer decides when deferred");
  assert.ok(events(root).some((item) => item.kind === "approval.closed"));
});

test("an ignored approval times out to the desktop dialog", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  alive(root);
  const handlers = harness(root, { approvalTimeoutMs: 40 });
  const result = await handlers.get("approval/request")(
    { agent: { session: session() }, toolName: "bash" },
    async () => "ui-answer",
  );
  assert.equal(result, "ui-answer");
  const delivered = events(root);
  assert.ok(delivered.some((item) => item.kind === "approval.asked"), "the reminder was shown during the window");
  assert.ok(delivered.some((item) => item.kind === "approval.closed"), "the reminder is closed after the timeout");
});

test("a failed delivery falls back immediately instead of holding the approval", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  alive(root);
  chmodSync(root, 0o500);
  const warnings = [];
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: (m) => warnings.push(m) } },
    { dataDir: root, approvalTimeoutMs: 3000, pollMs: 10 },
  );
  const originalSetInterval = globalThis.setInterval;
  let polls = 0;
  globalThis.setInterval = (...args) => {
    polls += 1;
    return originalSetInterval(...args);
  };
  try {
    let delegated = false;
    const result = await handlers.get("approval/request")(
      { agent: { session: session() }, toolName: "bash" },
      async () => {
        delegated = true;
        return "ui-answer";
      },
    );
    assert.equal(result, "ui-answer");
    assert.equal(delegated, true, "desktop dialog handles the approval");
    assert.equal(polls, 0, "no decision polling starts when the reminder cannot be delivered");
    assert.match(warnings[0], /delivery failed/);
  } finally {
    globalThis.setInterval = originalSetInterval;
    chmodSync(root, 0o700);
  }
});

test("approvals are not claimed while MIRA is not running", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = harness(root, { approvalTimeoutMs: 40 });
  let delegated = false;
  const result = await handlers.get("approval/request")(
    { agent: { session: session() }, toolName: "bash" },
    async () => {
      delegated = true;
      return "ui-answer";
    },
  );
  assert.equal(result, "ui-answer");
  assert.equal(delegated, true);
  assert.equal(events(root).length, 0, "no reminder when MIRA cannot answer");
});

test("a pending question delegates and closes itself when answered", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = harness(root);
  const answer = { answers: [{ id: "q1", selected: ["A"] }] };
  const result = await handlers.get("user-questions/request")(
    { questions: [{ id: "q1", question: "选哪个？" }], agent: { session: session() } },
    async () => answer,
  );
  assert.deepEqual(result, answer, "the desktop answerer still owns the answer");
  const delivered = events(root);
  const asked = delivered.find((item) => item.kind === "question.asked");
  assert.ok(asked, "the question is observed");
  assert.equal(asked.questions[0].question, "选哪个？");
  const closed = delivered.find((item) => item.kind === "question.closed");
  assert.ok(closed, "the reminder closes after the answer");
  assert.equal(closed.closes, asked.dedupeKey);
});
