// Unit checks for the DSH bridge. Run: node --test tests/test_dsh_bridge.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  approvalEntryId,
  buildApprovalEntry,
  buildDismissal,
  buildEntry,
  buildQuestionEntry,
  entryId,
  isSubagent,
  projectName,
  questionEntryId,
  reasonInfo,
  summarize,
  writeEntry,
} from "../integrations/dsh/entry.js";
import { apply } from "../integrations/dsh/index.js";

const TIME = 1_764_000_000_123;

function alive(root) {
  writeFileSync(join(root, "heartbeat"), String(Date.now()));
}

function inboxEntries(root) {
  try {
    return readdirSync(join(root, "inbox"))
      .filter((file) => file.endsWith(".json"))
      .sort()
      .map((file) => JSON.parse(readFileSync(join(root, "inbox", file), "utf8")));
  } catch {
    return [];
  }
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

function decide(root, token, decision) {
  mkdirSync(join(root, "decisions"), { recursive: true });
  writeFileSync(join(root, "decisions", token + ".json"), JSON.stringify({ token, decision }));
}

function inboxCount(root) {
  try {
    return readdirSync(join(root, "inbox")).length;
  } catch {
    return 0;
  }
}

function session(overrides = {}) {
  return {
    id: "session-1234-abcd",
    header: { cwd: "/Users/yunye/MIRA", ...overrides },
  };
}

test("maps every documented turn-end reason", () => {
  assert.deepEqual(reasonInfo({ kind: "completed" }), {
    kind: "completed",
    status: "本轮结束",
    body: "DSH 本轮已结束，请打开原会话查看结果。",
  });
  assert.equal(reasonInfo({ kind: "error", error: { code: "UNKNOWN" } }).status, "任务失败");
  assert.equal(reasonInfo({ kind: "aborted", reason: {} }).status, "已中断");
  assert.equal(reasonInfo({ kind: "blocked" }).status, "已拦截");
  assert.equal(reasonInfo({ kind: "max-tokens" }).status, "已达上限");
  assert.equal(reasonInfo({ kind: "interrupted" }).status, "已中断");
});

test("degrades on unknown or malformed reasons instead of throwing", () => {
  assert.deepEqual(reasonInfo({ kind: "future-reason" }), {
    kind: "future-reason",
    status: "本轮结束",
    body: "DSH 本轮已结束，请打开原会话查看结果。",
  });
  assert.equal(reasonInfo(null).kind, "unknown");
  assert.equal(reasonInfo(undefined).status, "本轮结束");
  assert.equal(reasonInfo({ kind: 42 }).kind, "unknown");
});

test("reads the project name from the working directory", () => {
  assert.equal(projectName("/Users/yunye/MIRA"), "MIRA");
  assert.equal(projectName("/Users/yunye/MIRA/"), "MIRA");
  assert.equal(projectName(""), "DSH");
  assert.equal(projectName(undefined), "DSH");
});

test("detects subagent sessions", () => {
  assert.equal(isSubagent(session({ origin: "subagent" })), true);
  assert.equal(isSubagent(session()), false);
  assert.equal(isSubagent(undefined), false);
});

test("builds one inbox entry per finished turn", () => {
  const entry = buildEntry({
    sessionId: "session-1234-abcd",
    cwd: "/Users/yunye/MIRA",
    turn: 3,
    reason: { kind: "completed" },
    time: TIME,
    title: "设计 AI 任务与提醒中心",
  });
  assert.equal(entry.id, entryId("session-1234-abcd", 3, "completed"));
  assert.equal(entry.title, "设计 AI 任务与提醒中心");
  assert.equal(entry.source, "DSH · MIRA");
  assert.equal(entry.status, "本轮结束");
  assert.equal(entry.link, "dsh://open");
  assert.equal(entry.thread, "session-1234-abcd");
  assert.equal(entry.date, TIME / 1000);
  assert.equal(entry.done, false);
  assert.equal(entry.notified, false);
});

test("keeps ids stable for one turn and distinct across turns", () => {
  const base = { sessionId: "s", cwd: "/x", reason: { kind: "completed" }, time: TIME };
  assert.equal(buildEntry({ ...base, turn: 1 }).id, buildEntry({ ...base, turn: 1 }).id);
  assert.notEqual(buildEntry({ ...base, turn: 1 }).id, buildEntry({ ...base, turn: 2 }).id);
  assert.notEqual(
    buildEntry({ ...base, turn: 1 }).id,
    buildEntry({ ...base, turn: 1, reason: { kind: "error" } }).id,
  );
});

test("falls back to project plus round when no title exists", () => {
  const entry = buildEntry({
    sessionId: "session-1234-abcd",
    cwd: "/Users/yunye/项目",
    turn: 1,
    reason: { kind: "completed" },
    time: TIME,
  });
  assert.equal(entry.title, "项目 · 第 1 轮");
  const blank = buildEntry({
    sessionId: "session-1234-abcd",
    cwd: "/Users/yunye/项目",
    turn: 1,
    reason: { kind: "completed" },
    time: TIME,
    title: "   ",
  });
  assert.equal(blank.title, entry.title);
  assert.equal(buildEntry({
    sessionId: "session-1234-abcd",
    cwd: "/Users/yunye/项目",
    turn: 4,
    reason: { kind: "completed" },
    time: TIME,
  }).title, "项目 · 第 4 轮", "each turn keeps its own round label");
});

test("writes a private, atomically renamed JSON file", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const entry = buildEntry({
    sessionId: "session-1234-abcd",
    cwd: "/Users/yunye/MIRA",
    turn: 2,
    reason: { kind: "completed" },
    time: TIME,
  });
  const path = writeEntry(root, entry);
  assert.equal(statSync(root).mode & 0o777, 0o700);
  assert.equal(statSync(path).mode & 0o777, 0o600);
  assert.deepEqual(JSON.parse(readFileSync(path, "utf8")), entry);
  assert.deepEqual(
    readdirSync(join(root, "inbox")),
    [path.split("/").pop()],
    "no temporary file survives delivery",
  );
  assert.match(path.split("/").pop(), /^\d{20}-[0-9a-f]{64}\.json$/);
});

test("repeated delivery of the same turn collapses to one file", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const entry = buildEntry({
    sessionId: "s",
    cwd: "/x",
    turn: 1,
    reason: { kind: "completed" },
    time: TIME,
  });
  writeEntry(root, entry);
  writeEntry(root, entry);
  assert.equal(inboxCount(root), 1);
});

test("observes session events and delivers only real turn ends", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  const ctx = {
    on: (event, handler) => handlers.set(event, handler),
    logger: { warn: () => {}, debug: () => {} },
  };
  apply(ctx, { dataDir: root });

  const emit = (session, event) => handlers.get("session/event")(session, event);
  emit(session(), { type: "session/title", time: TIME, data: { title: "真实任务" } });
  emit(session(), { type: "turn/start", time: TIME, data: { turn: 1 } });
  assert.equal(inboxCount(root), 0, "turn start is not a reminder");

  emit(session(), { type: "turn/end", time: TIME, data: { turn: 1, reason: { kind: "completed" } } });
  const [file] = readdirSync(join(root, "inbox"));
  const entry = JSON.parse(readFileSync(join(root, "inbox", file), "utf8"));
  assert.equal(entry.title, "真实任务");
  assert.equal(entry.status, "本轮结束");
});

test("skips subagent children", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root },
  );
  handlers.get("session/event")(
    session({ origin: "subagent" }),
    { type: "turn/end", time: TIME, data: { turn: 1, reason: { kind: "completed" } } },
  );
  assert.equal(inboxCount(root), 0);
});

test("a broken inbox never fails the turn", () => {
  const warnings = [];
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: (m) => warnings.push(m) } },
    { dataDir: "/dev/null/mira" },
  );
  assert.doesNotThrow(() => {
    handlers.get("session/event")(session(), {
      type: "turn/end",
      time: TIME,
      data: { turn: 1, reason: { kind: "completed" } },
    });
  });
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /mira-bridge: delivery failed/);
});

test("builds a confirmation reminder for a pending approval", () => {
  const entry = buildApprovalEntry({
    sessionId: "session-9",
    cwd: "/Users/yunye/MIRA",
    time: TIME,
    title: "真实任务",
    toolName: "bash",
    reason: "写入工作区之外的文件",
    approvalId: "approval-1",
  });
  assert.equal(entry.status, "待确认");
  assert.equal(entry.id, approvalEntryId("session-9", "approval-1"));
  assert.match(entry.body, /「bash」/);
  assert.match(entry.body, /写入工作区之外的文件/);
  assert.equal(entry.thread, "session-9");
  assert.equal(entry.link, "dsh://open");
});

test("builds a question reminder that counts multiple questions", () => {
  const entry = buildQuestionEntry({
    sessionId: "session-9",
    cwd: "/Users/yunye/MIRA",
    time: TIME,
    questions: [
      { id: "q1", question: "先做哪一块？" },
      { id: "q2", question: "要不要现在重启？" },
    ],
  });
  assert.equal(entry.status, "待补充信息");
  assert.equal(entry.id, questionEntryId("session-9", "q1"));
  assert.match(entry.body, /先做哪一块/);
  assert.match(entry.body, /共 2 个问题/);
});

test("dismissal closes its target and is never shown", () => {
  const target = approvalEntryId("session-9", "approval-1");
  const dismissal = buildDismissal({ targetId: target, sessionId: "session-9", time: TIME });
  assert.equal(dismissal.id, "dismiss-" + target);
  assert.equal(dismissal.dismiss, target);
  assert.equal(dismissal.done, true);
});

test("an approval is claimable from MIRA and closes itself", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  alive(root);
  const handlers = new Map();
  apply(
    { on: (event, handler, options) => handlers.set(event, { handler, options }), logger: { warn: () => {} } },
    { dataDir: root, approvalTimeoutMs: 3000, pollMs: 10 },
  );
  const registration = handlers.get("approval/request");
  assert.equal(registration.options?.prepend, true, "approval answerer runs before the desktop dialog");
  const pending = registration.handler(
    { agent: { session: session() }, toolName: "bash", reason: "写入工作区之外的文件" },
    async () => "unavailable",
  );
  const entry = await waitFor(() => inboxEntries(root).find((item) => item.status === "待确认"));
  assert.ok(entry.token, "reminder carries a one-shot token");
  assert.ok(entry.expires > entry.date, "reminder expires with the approval window");
  assert.match(entry.body, /bash/);

  decide(root, entry.token, "allow");
  assert.equal(await pending, "allowed-once");
  const closed = await waitFor(() => inboxEntries(root).find((item) => item.dismiss === entry.id));
  assert.ok(closed, "answered approval is dismissed");
});

test("a denied approval returns rejected and closes the reminder", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  alive(root);
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root, approvalTimeoutMs: 3000, pollMs: 10 },
  );
  const pending = handlers.get("approval/request")(
    { agent: { session: session() }, toolName: "bash" },
    async () => "unavailable",
  );
  const entry = await waitFor(() => inboxEntries(root).find((item) => item.status === "待确认"));
  decide(root, entry.token, "deny");
  assert.equal(await pending, "rejected");
});

test("deferring falls back to the desktop dialog", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  alive(root);
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root, approvalTimeoutMs: 3000, pollMs: 10 },
  );
  let delegated = false;
  const pending = handlers.get("approval/request")(
    { agent: { session: session() }, toolName: "bash" },
    async () => {
      delegated = true;
      return "ui-answer";
    },
  );
  const entry = await waitFor(() => inboxEntries(root).find((item) => item.status === "待确认"));
  decide(root, entry.token, "defer");
  assert.equal(await pending, "ui-answer");
  assert.equal(delegated, true, "desktop answerer decides when deferred");
});

test("an ignored approval times out to the desktop dialog", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  alive(root);
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root, approvalTimeoutMs: 40, pollMs: 10 },
  );
  const result = await handlers.get("approval/request")(
    { agent: { session: session() }, toolName: "bash" },
    async () => "ui-answer",
  );
  assert.equal(result, "ui-answer");
  const entries = inboxEntries(root).sort((a, b) => a.date - b.date);
  assert.ok(entries.some((item) => item.status === "待确认"), "reminder was shown during the window");
  assert.ok(entries.some((item) => item.dismiss), "reminder is closed after timeout");
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
  assert.equal(inboxCount(root), 0);
});

test("approvals are not claimed while MIRA is not running", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root, approvalTimeoutMs: 40, pollMs: 10 },
  );
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
  assert.equal(inboxCount(root), 0, "no reminder when MIRA cannot answer");
});

test("a pending question delegates and closes itself when answered", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root },
  );
  const answer = { answers: [{ id: "q1", selected: ["A"] }] };
  const result = await handlers.get("user-questions/request")(
    { questions: [{ id: "q1", question: "选哪个？" }], agent: { session: session() } },
    async () => answer,
  );
  assert.deepEqual(result, answer, "the desktop answerer still owns the answer");
  const files = readdirSync(join(root, "inbox")).sort();
  assert.equal(files.length, 2);
  const asked = JSON.parse(readFileSync(join(root, "inbox", files[0]), "utf8"));
  const closed = JSON.parse(readFileSync(join(root, "inbox", files[1]), "utf8"));
  assert.equal(asked.status, "待补充信息");
  assert.equal(closed.dismiss, asked.id);
});

test("a cancelled question still closes its reminder", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root },
  );
  await assert.rejects(
    handlers.get("user-questions/request")(
      { questions: [{ id: "q1", question: "选哪个？" }], agent: { session: session() } },
      async () => {
        throw new Error("aborted");
      },
    ),
    /aborted/,
  );
  const files = readdirSync(join(root, "inbox")).sort();
  assert.equal(files.length, 2, "reminder plus dismissal");
});

test("subagent approvals are not claimed", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  alive(root);
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root, approvalTimeoutMs: 40, pollMs: 10 },
  );
  const result = await handlers.get("approval/request")(
    { agent: { session: session({ origin: "subagent" }) }, toolName: "bash" },
    async () => "ui-answer",
  );
  assert.equal(result, "ui-answer");
  assert.equal(inboxCount(root), 0);
});

test("reads the folded session title when the title event was missed", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    {
      on: (event, handler) => handlers.set(event, handler),
      logger: { warn: () => {} },
      sessionTitle: { get: () => ({ title: "设计 AI 任务与提醒中心" }) },
    },
    { dataDir: root },
  );
  handlers.get("session/event")(session(), {
    type: "turn/end",
    time: TIME,
    data: { turn: 2, reason: { kind: "completed" } },
  });
  const [file] = readdirSync(join(root, "inbox"));
  const entry = JSON.parse(readFileSync(join(root, "inbox", file), "utf8"));
  assert.equal(entry.title, "设计 AI 任务与提醒中心");
});

test("a failing title service still delivers with a round fallback", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    {
      on: (event, handler) => handlers.set(event, handler),
      logger: { warn: () => {} },
      sessionTitle: { get: () => { throw new Error("not live"); } },
    },
    { dataDir: root },
  );
  handlers.get("session/event")(session(), {
    type: "turn/end",
    time: TIME,
    data: { turn: 2, reason: { kind: "completed" } },
  });
  const [file] = readdirSync(join(root, "inbox"));
  const entry = JSON.parse(readFileSync(join(root, "inbox", file), "utf8"));
  assert.equal(entry.title, "MIRA · 第 2 轮");
});

test("approval reminders inherit the current round", async () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  alive(root);
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root, approvalTimeoutMs: 40, pollMs: 10 },
  );
  handlers.get("session/event")(session(), { type: "turn/start", time: TIME, data: { turn: 3 } });
  const pending = handlers.get("approval/request")(
    { agent: { session: session() }, toolName: "bash" },
    async () => "ui-answer",
  );
  const entry = await waitFor(() => inboxEntries(root).find((item) => item.status === "待确认"));
  assert.equal(entry.title, "MIRA · 第 3 轮");
  await pending;
});

function sessionWithEvents(events) {
  return {
    id: "session-1234-abcd",
    header: { cwd: "/Users/yunye/MIRA" },
    seq: events.length,
    eventAt: (index) => events[index],
  };
}

test("uses the first user message as the task name when no title exists", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root },
  );
  const session = sessionWithEvents([
    { type: "user/message", data: { source: { kind: "runtime-context" }, content: [{ type: "text", text: "Current runtime context." }] } },
    { type: "user/message", data: { source: { kind: "user" }, content: [{ type: "text", text: "我想做一个软件，就是说如果我的 codex 任务完成了，或者需要我确定了" }] } },
  ]);
  handlers.get("session/event")(session, {
    type: "turn/end",
    time: TIME,
    data: { turn: 1, reason: { kind: "completed" } },
  });
  const [file] = readdirSync(join(root, "inbox"));
  const entry = JSON.parse(readFileSync(join(root, "inbox", file), "utf8"));
  assert.equal(entry.title, summarize("我想做一个软件，就是说如果我的 codex 任务完成了，或者需要我确定了"));
  assert.ok(entry.title.endsWith("…"), "long prompt is truncated");
});

test("synthetic context messages are not used as task names", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root },
  );
  const session = sessionWithEvents([
    { type: "user/message", data: { source: { kind: "runtime-context" }, content: [{ type: "text", text: "Current runtime context." }] } },
  ]);
  handlers.get("session/event")(session, {
    type: "turn/end",
    time: TIME,
    data: { turn: 2, reason: { kind: "completed" } },
  });
  const [file] = readdirSync(join(root, "inbox"));
  const entry = JSON.parse(readFileSync(join(root, "inbox", file), "utf8"));
  assert.equal(entry.title, "MIRA · 第 2 轮");
});

test("summarize cleans prompt markup and prefers the first paragraph", () => {
  assert.equal(
    summarize("# 任务：对当前项目进行长期自主迭代优化\n\n你是一名资深软件架构师。"),
    "对当前项目进行长期自主迭代优化",
  );
  assert.equal(
    summarize("任务：修复登录\n第二行说明\n\n后面的段落不进入标题"),
    "修复登录 第二行说明",
  );
  assert.equal(summarize("## 每周回顾"), "每周回顾");
  assert.equal(summarize("Short task"), "Short task");
  assert.equal(summarize(""), "");
  assert.equal(
    summarize("这是一个明显超过十个字符的任务说明文字", 10),
    "这是一个明显超过十个…",
  );
  assert.equal(
    summarize("Fix the login button contrast issue today", 20),
    "Fix the login…",
    "a Latin title cuts on a word boundary",
  );
});

test("cleans a raw prompt heading passed as a title", () => {
  const entry = buildEntry({
    sessionId: "session-1234-abcd",
    cwd: "/Users/yunye/MIRA",
    turn: 2,
    reason: { kind: "completed" },
    time: TIME,
    title: "# 任务：对当前项目进行长期",
  });
  assert.equal(entry.title, "对当前项目进行长期");
});

test("prefers the full prompt over a DSH fallback title", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    {
      on: (event, handler) => handlers.set(event, handler),
      logger: { warn: () => {} },
      sessionTitle: { get: () => ({ title: "# 任务：对当前项目进行长期", source: { kind: "fallback" } }) },
    },
    { dataDir: root },
  );
  const session = sessionWithEvents([
    {
      type: "user/message",
      data: {
        source: { kind: "user" },
        content: [{ type: "text", text: "# 任务：对当前项目进行长期自主迭代优化\n\n你是一名资深软件架构师。" }],
      },
    },
  ]);
  handlers.get("session/event")(session, {
    type: "turn/end",
    time: TIME,
    data: { turn: 1, reason: { kind: "completed" } },
  });
  const [file] = readdirSync(join(root, "inbox"));
  const entry = JSON.parse(readFileSync(join(root, "inbox", file), "utf8"));
  assert.equal(entry.title, "对当前项目进行长期自主迭代优化");
});

test("uses a generated title instead of the prompt", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    {
      on: (event, handler) => handlers.set(event, handler),
      logger: { warn: () => {} },
      sessionTitle: { get: () => ({ title: "设计 AI 任务与提醒中心", source: { kind: "provider" } }) },
    },
    { dataDir: root },
  );
  const session = sessionWithEvents([
    { type: "user/message", data: { source: { kind: "user" }, content: [{ type: "text", text: "请帮我重构登录页" }] } },
  ]);
  handlers.get("session/event")(session, {
    type: "turn/end",
    time: TIME,
    data: { turn: 1, reason: { kind: "completed" } },
  });
  const [file] = readdirSync(join(root, "inbox"));
  const entry = JSON.parse(readFileSync(join(root, "inbox", file), "utf8"));
  assert.equal(entry.title, "设计 AI 任务与提醒中心");
});

test("cleans a fallback title when no prompt is readable", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    {
      on: (event, handler) => handlers.set(event, handler),
      logger: { warn: () => {} },
      sessionTitle: { get: () => ({ title: "# 任务：对当前项目进行长期", source: { kind: "fallback" } }) },
    },
    { dataDir: root },
  );
  handlers.get("session/event")(session(), {
    type: "turn/end",
    time: TIME,
    data: { turn: 1, reason: { kind: "completed" } },
  });
  const [file] = readdirSync(join(root, "inbox"));
  const entry = JSON.parse(readFileSync(join(root, "inbox", file), "utf8"));
  assert.equal(entry.title, "对当前项目进行长期");
});

test("a fallback title event does not pin the truncated name", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root },
  );
  const session = sessionWithEvents([
    {
      type: "user/message",
      data: {
        source: { kind: "user" },
        content: [{ type: "text", text: "# 任务：对当前项目进行长期自主迭代优化\n\n你是一名资深软件架构师。" }],
      },
    },
  ]);
  handlers.get("session/event")(session, {
    type: "session/title",
    time: TIME,
    data: { title: "# 任务：对当前项目进行长期", source: { kind: "fallback" } },
  });
  handlers.get("session/event")(session, {
    type: "turn/end",
    time: TIME,
    data: { turn: 1, reason: { kind: "completed" } },
  });
  const first = JSON.parse(readFileSync(join(root, "inbox", readdirSync(join(root, "inbox"))[0]), "utf8"));
  assert.equal(first.title, "对当前项目进行长期自主迭代优化");

  handlers.get("session/event")(session, {
    type: "session/title",
    time: TIME,
    data: { title: "长期迭代优化任务", source: { kind: "provider" } },
  });
  handlers.get("session/event")(session, {
    type: "turn/end",
    time: TIME,
    data: { turn: 2, reason: { kind: "completed" } },
  });
  const titles = readdirSync(join(root, "inbox"))
    .sort()
    .map((file) => JSON.parse(readFileSync(join(root, "inbox", file), "utf8")).title);
  assert.ok(titles.includes("长期迭代优化任务"), "a provider title replaces the prompt summary");
});
