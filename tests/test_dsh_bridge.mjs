// Unit checks for the DSH bridge. Run: node --test tests/test_dsh_bridge.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
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
  writeEntry,
} from "../integrations/dsh/entry.js";
import { apply } from "../integrations/dsh/index.js";

const TIME = 1_764_000_000_123;

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

test("falls back to project plus short id when no title exists", () => {
  const entry = buildEntry({
    sessionId: "session-1234-abcd",
    cwd: "/Users/yunye/项目",
    turn: 1,
    reason: { kind: "completed" },
    time: TIME,
  });
  assert.equal(entry.title, "项目 · 任务 session-");
  const blank = buildEntry({
    sessionId: "session-1234-abcd",
    cwd: "/Users/yunye/项目",
    turn: 1,
    reason: { kind: "completed" },
    time: TIME,
    title: "   ",
  });
  assert.equal(blank.title, entry.title);
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

test("approval asked and decided produce a reminder plus a dismissal", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root },
  );
  const emit = (event) => handlers.get("session/event")(session(), event);
  emit({ type: "approval/asked", time: TIME, data: { id: "approval-1", toolName: "bash" } });
  emit({ type: "approval/decided", time: TIME + 1000, data: { id: "approval-1", outcome: "allowed-once" } });

  const files = readdirSync(join(root, "inbox")).sort();
  assert.equal(files.length, 2);
  const asked = JSON.parse(readFileSync(join(root, "inbox", files[0]), "utf8"));
  const decided = JSON.parse(readFileSync(join(root, "inbox", files[1]), "utf8"));
  assert.equal(asked.status, "待确认");
  assert.equal(decided.dismiss, asked.id);
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

test("subagent approvals are not surfaced", () => {
  const root = mkdtempSync(join(tmpdir(), "mira-dsh-"));
  const handlers = new Map();
  apply(
    { on: (event, handler) => handlers.set(event, handler), logger: { warn: () => {} } },
    { dataDir: root },
  );
  handlers.get("session/event")(
    session({ origin: "subagent" }),
    { type: "approval/asked", time: TIME, data: { id: "a", toolName: "bash" } },
  );
  assert.equal(inboxCount(root), 0);
});
