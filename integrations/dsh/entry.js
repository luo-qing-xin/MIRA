// Pure mapping from a DSH `turn/end` session event to one MIRA inbox entry.
// No cordis, no filesystem: everything here is unit-testable with plain node.
import { createHash, randomUUID } from "node:crypto";
import { mkdirSync, renameSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";

/** Status/body copy per `TurnEndReason.kind`, mirroring the Codex hook wording. */
const REASONS = {
  completed: { status: "本轮结束", body: "DSH 本轮已结束，请打开原会话查看结果。" },
  error: { status: "任务失败", body: "DSH 本轮执行失败，可打开原会话查看原因。" },
  aborted: { status: "已中断", body: "DSH 本轮已被中断，可返回会话继续。" },
  blocked: { status: "已拦截", body: "本轮在提交阶段被拦截，没有执行。" },
  "max-tokens": { status: "已达上限", body: "本轮达到输出上限后结束，请检查结果是否完整。" },
  interrupted: { status: "已中断", body: "会话异常中断，可能是客户端退出或崩溃导致。" },
};
const FALLBACK = { status: "本轮结束", body: "DSH 本轮已结束，请打开原会话查看结果。" };

/** Resolve a DSH turn-end reason into MIRA status copy. Never throws. */
export function reasonInfo(reason) {
  const kind =
    reason !== null && typeof reason === "object" && typeof reason.kind === "string"
      ? reason.kind
      : "unknown";
  return { kind, ...(Object.hasOwn(REASONS, kind) ? REASONS[kind] : FALLBACK) };
}

/** Last path component of a working directory, or a neutral fallback. */
export function projectName(cwd) {
  if (typeof cwd !== "string" || cwd.length === 0) return "DSH";
  const name = basename(cwd.replace(/\/+$/, ""));
  return name.length > 0 ? name : "DSH";
}

/** Subagent children are not conversations the user is waiting on. */
export function isSubagent(session) {
  return session?.header?.origin === "subagent";
}

/** Stable dedupe id: one turn ends once, but a repeated delivery must collapse. */
export function entryId(sessionId, turn, kind) {
  return createHash("sha256")
    .update(JSON.stringify([String(sessionId), Number(turn), "turn/end", kind]))
    .digest("hex");
}

/** Id shared by one approval's reminder and its later dismissal. */
export function approvalEntryId(sessionId, approvalId) {
  return createHash("sha256")
    .update(JSON.stringify([String(sessionId), "approval", String(approvalId)]))
    .digest("hex");
}

/** Id shared by one pending question's reminder and its later dismissal. */
export function questionEntryId(sessionId, questionId) {
  return createHash("sha256")
    .update(JSON.stringify([String(sessionId), "user-question", String(questionId)]))
    .digest("hex");
}

function displayTitle(title, sessionId, cwd, turn) {
  const named = typeof title === "string" ? title.trim() : "";
  const round = Number.isSafeInteger(turn) && turn > 0 ? " · 第 " + turn + " 轮" : "";
  const fallback = projectName(cwd) + (round || " · 任务 " + String(sessionId).slice(0, 8));
  return (named || fallback).slice(0, 80);
}

function oneLine(value, limit = 120) {
  const text = typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
  return text.length > limit ? text.slice(0, limit - 1) + "…" : text;
}

/**
 * Build the reminder for a pending DSH tool approval.
 * @param {object} input - `approval/asked` data plus session metadata.
 */
export function buildApprovalEntry({
  sessionId,
  cwd,
  time,
  title,
  turn,
  toolName,
  reason,
  approvalId,
  link = "dsh://open",
}) {
  const tool = oneLine(toolName, 60) || "工具";
  const why = oneLine(reason);
  return {
    id: approvalEntryId(sessionId, approvalId),
    title: displayTitle(title, sessionId, cwd, turn),
    body: `DSH 需要你确认「${tool}」的操作${why ? "：" + why : "。"} 点击回到原会话处理。`,
    source: ("DSH · " + projectName(cwd)).slice(0, 80),
    status: "待确认",
    link,
    date: time / 1000,
    done: false,
    notified: false,
    thread: String(sessionId),
  };
}

/** Build one reminder covering a pending user-question request. */
export function buildQuestionEntry({ sessionId, cwd, time, title, turn, questions, link = "dsh://open" }) {
  const list = Array.isArray(questions) ? questions.filter((q) => q && typeof q === "object") : [];
  const first = oneLine(list[0]?.question);
  const more = list.length > 1 ? `（共 ${list.length} 个问题）` : "";
  return {
    id: questionEntryId(sessionId, list[0]?.id ?? "unknown"),
    title: displayTitle(title, sessionId, cwd, turn),
    body: `DSH 需要你补充信息${first ? "：" + first : "。"}${more} 点击回到原会话回答。`,
    source: ("DSH · " + projectName(cwd)).slice(0, 80),
    status: "待补充信息",
    link,
    date: time / 1000,
    done: false,
    notified: false,
    thread: String(sessionId),
  };
}

/**
 * A silent control entry: MIRA closes `targetId` and never shows this one.
 * Used when the approval was decided or the question was answered elsewhere.
 */
export function buildDismissal({ targetId, sessionId, time }) {
  return {
    id: "dismiss-" + targetId,
    title: "已处理",
    body: "",
    source: "DSH",
    status: "已处理",
    link: "",
    date: time / 1000,
    done: true,
    notified: true,
    thread: String(sessionId),
    dismiss: targetId,
  };
}

/**
 * Build the MIRA `Entry` JSON for one finished DSH turn.
 * @param {object} input
 * @param {string} input.sessionId
 * @param {string} [input.cwd]
 * @param {number} input.turn
 * @param {object} input.reason - `TurnEndReason`
 * @param {number} input.time - epoch milliseconds from the session event
 * @param {string} [input.title] - latest `session/title` text
 * @param {string} [input.link] - deep link opened on click
 */
export function buildEntry({ sessionId, cwd, turn, reason, time, title, link = "dsh://open" }) {
  const { kind, status, body } = reasonInfo(reason);
  const project = projectName(cwd);
  return {
    id: entryId(sessionId, turn, kind),
    title: displayTitle(title, sessionId, cwd, turn),
    body,
    source: ("DSH · " + project).slice(0, 80),
    status,
    link,
    date: time / 1000,
    done: false,
    notified: false,
    thread: String(sessionId),
  };
}

/**
 * Deliver one entry to MIRA's inbox directory. The temporary file keeps
 * readers from seeing a partially written JSON document.
 * @returns {string} final path
 */
export function writeEntry(dataDir, entry, { mode = 0o700 } = {}) {
  const inbox = join(dataDir, "inbox");
  mkdirSync(dataDir, { recursive: true, mode });
  mkdirSync(inbox, { recursive: true, mode });
  const stem = String(Math.floor(entry.date * 1e6)).padStart(20, "0") + "-" + entry.id;
  const target = join(inbox, stem + ".json");
  const temporary = join(inbox, "." + randomUUID() + ".tmp");
  writeFileSync(temporary, JSON.stringify(entry), { mode: 0o600 });
  renameSync(temporary, target);
  return target;
}
