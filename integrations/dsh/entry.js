// Pure mapping from DSH session events to MIRA adapter-contract events.
// No cordis, no filesystem: everything here is unit-testable with plain node.
// Titles, status copy, de-duplication and links are decided by MIRA.

/** Contract identity shared by one approval and its later dismissal. */
export function approvalKey(sessionId, approvalId) {
  return `approval:${String(sessionId)}:${String(approvalId)}`;
}

/** Contract identity shared by one question reminder and its dismissal. */
export function questionKey(sessionId, questionId) {
  return `question:${String(sessionId)}:${String(questionId ?? "unknown")}`;
}

/** Stable turn identity; repeated deliveries of one turn collapse in MIRA. */
export function turnKey(sessionId, turn, phase) {
  return `turn:${String(sessionId)}:${String(turn ?? "")}:${phase}`;
}

/** Subagent children are not conversations the user is waiting on. */
export function isSubagent(session) {
  return session?.header?.origin === "subagent";
}

/** Collapse a tool name or reason into one bounded line. */
function oneLine(value, limit = 120) {
  const text = typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
  return text.length > limit ? text.slice(0, limit - 1) + "…" : text;
}

/** Normalize a DSH turn-end reason into the contract vocabulary. */
export function reasonKind(reason) {
  const kind =
    reason !== null && typeof reason === "object" && typeof reason.kind === "string"
      ? reason.kind
      : "unknown";
  return ["completed", "error", "aborted", "blocked", "max-tokens", "interrupted"].includes(kind)
    ? kind
    : "completed";
}

function base({ sessionId, cwd, turn, time, hint, title, link }) {
  const event = {
    adapter: "dsh",
    name: "DSH",
    session: String(sessionId),
    time,
  };
  if (Number.isSafeInteger(turn) && turn > 0) event.turn = turn;
  if (typeof cwd === "string" && cwd.length > 0) event.cwd = cwd;
  // The prompt is the better task name; the session title is only a fallback
  // for turns where no prompt is readable. The emitter bounds the hint.
  if (typeof hint === "string" && hint.trim()) event.hint = hint;
  else if (typeof title === "string" && title.trim()) event.title = title.trim();
  if (typeof link === "string" && link.length > 0) event.link = link;
  return event;
}

export function turnStartEvent({ sessionId, cwd, turn, time, hint, title, link = "dsh://open" }) {
  return {
    ...base({ sessionId, cwd, turn, time, hint, title, link }),
    kind: "turn.start",
    dedupeKey: turnKey(sessionId, turn, "start"),
  };
}

export function turnEndEvent({ sessionId, cwd, turn, time, hint, title, reason, link = "dsh://open" }) {
  const kind = reasonKind(reason);
  return {
    ...base({ sessionId, cwd, turn, time, hint, title, link }),
    kind: "turn.end",
    reason: kind,
    dedupeKey: turnKey(sessionId, turn, `end:${kind}`),
  };
}

export function approvalAskedEvent({
  sessionId,
  cwd,
  turn,
  time,
  hint,
  title,
  toolName,
  reason,
  approvalId,
  token,
  ttlMs,
  link = "dsh://open",
}) {
  const event = {
    ...base({ sessionId, cwd, turn, time, hint, title, link }),
    kind: "approval.asked",
    dedupeKey: approvalKey(sessionId, approvalId),
    approval: { tool: oneLine(toolName, 60) || "工具" },
  };
  const why = oneLine(reason, 200);
  if (why) event.approval.reason = why;
  if (typeof token === "string" && token.length > 0) event.approval.token = token;
  if (Number.isFinite(ttlMs) && ttlMs > 0) event.approval.ttlMs = ttlMs;
  return event;
}

/** Silent control event: closes the approval reminder, never displays itself. */
export function approvalClosedEvent({ sessionId, time, approvalId }) {
  return {
    adapter: "dsh",
    name: "DSH",
    kind: "approval.closed",
    session: String(sessionId),
    time,
    closes: approvalKey(sessionId, approvalId),
  };
}

export function questionAskedEvent({
  sessionId,
  cwd,
  turn,
  time,
  hint,
  title,
  questions,
  link = "dsh://open",
}) {
  const list = Array.isArray(questions) ? questions.filter((q) => q && typeof q === "object") : [];
  const first = list[0]?.id ?? "unknown";
  const event = {
    ...base({ sessionId, cwd, turn, time, hint, title, link }),
    kind: "question.asked",
    dedupeKey: questionKey(sessionId, first),
  };
  const mapped = list
    .slice(0, 20)
    .map((q) => ({
      id: oneLine(q.id, 200),
      question: oneLine(q.question, 300),
      header: oneLine(q.header, 60),
    }))
    .map((q) => Object.fromEntries(Object.entries(q).filter(([, value]) => value)))
    .filter((q) => Object.keys(q).length > 0);
  if (mapped.length > 0) event.questions = mapped;
  return event;
}

/** Silent control event: closes the question reminder, never displays itself. */
export function questionClosedEvent({ sessionId, time, questionId }) {
  return {
    adapter: "dsh",
    name: "DSH",
    kind: "question.closed",
    session: String(sessionId),
    time,
    closes: questionKey(sessionId, questionId),
  };
}
