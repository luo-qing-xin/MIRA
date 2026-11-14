"use strict";
/**
 * Shared emitter for MIRA adapters speaking `mira.adapter/1`.
 *
 * Adapters only map their client's payload onto the contract fields; this
 * module owns the envelope, the version stamp, the 160-character title hint
 * budget and the atomic write into MIRA's inbox. Reminder policy lives in
 * MIRA (Swift), the single receiver.
 */
const { mkdirSync, renameSync, writeFileSync, chmodSync } = require("node:fs");
const { randomUUID } = require("node:crypto");
const { join } = require("node:path");
const { homedir } = require("node:os");

const PROTOCOL = "mira.adapter/1";
// Version of this adapter kit. MIRA compares it with its own expectation.
const ADAPTER_VERSION = "0.4.0";
// Only this much of a prompt ever leaves the client process.
const MAX_HINT = 160;
const MAX_TEXT = 500;

/** First paragraph, one line, bounded. The display clip happens in MIRA. */
function hint(value) {
  if (typeof value !== "string") return null;
  const first = value
    .replace(/\r\n/g, "\n")
    .split("\n\n")
    .map((part) => part.trim())
    .find(Boolean);
  const text = (first ?? "").split(/\s+/).filter(Boolean).join(" ");
  return text ? Array.from(text).slice(0, MAX_HINT).join("") : null;
}

function text(value, limit = MAX_TEXT) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? Array.from(trimmed).slice(0, limit).join("") : null;
}

function number(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function approval(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const result = {};
  const token = text(value.token, 64);
  if (token) result.token = token;
  const ttl = number(value.ttlMs);
  if (ttl !== null && ttl > 0) result.ttlMs = ttl;
  const tool = text(value.tool, 60);
  if (tool) result.tool = tool;
  const reason = text(value.reason, 200);
  if (reason) result.reason = reason;
  return Object.keys(result).length > 0 ? result : null;
}

function questions(value) {
  if (!Array.isArray(value)) return null;
  const result = [];
  for (const item of value.slice(0, 20)) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const question = {};
    for (const key of ["id", "question", "header"]) {
      const parsed = text(item[key], 300);
      if (parsed) question[key] = parsed;
    }
    if (Object.keys(question).length > 0) result.push(question);
  }
  return result.length > 0 ? result : null;
}

/** Validate one adapter event and return the contract envelope. */
function build(event, now = Date.now()) {
  if (!event || typeof event !== "object" || Array.isArray(event)) {
    throw new TypeError("adapter event must be an object");
  }
  const adapter = text(event.adapter, 40);
  if (!adapter) throw new TypeError("adapter id is required");
  const kind = text(event.kind, 40);
  if (!kind) throw new TypeError("kind is required");
  const session = text(event.session, 200);
  if (!session) throw new TypeError("session is required");

  const stamp = number(event.time);
  const payload = {
    protocol: PROTOCOL,
    adapter: {
      id: adapter.toLowerCase(),
      name: text(event.name, 40) ?? adapter,
      version: ADAPTER_VERSION,
    },
    kind,
    session,
    time: Math.round(stamp !== null && stamp > 0 ? stamp : now),
  };

  const turn = number(event.turn);
  if (turn !== null && Math.trunc(turn) > 0) payload.turn = Math.trunc(turn);
  if (typeof event.requiresPlanCheck === "boolean") payload.requiresPlanCheck = event.requiresPlanCheck;
  for (const [key, limit] of [
    ["cwd", 1024],
    ["title", 200],
    ["reason", 40],
    ["link", 1024],
    ["dedupeKey", 200],
    ["closes", 200],
  ]) {
    const parsed = text(event[key], limit);
    if (parsed) payload[key] = parsed;
  }
  const clipped = hint(event.hint);
  if (clipped) payload.titleHint = clipped;
  const pending = approval(event.approval);
  if (pending) payload.approval = pending;
  const asked = questions(event.questions);
  if (asked) payload.questions = asked;
  return payload;
}

function inboxDir(dataDir) {
  const root = dataDir || join(homedir(), "Library/Application Support/MIRA");
  return { root, inbox: join(root, "inbox") };
}

/** Write one contract event into the inbox atomically; returns its path. */
function emit(dataDir, event, now = Date.now()) {
  const payload = build(event, now);
  const { root, inbox } = inboxDir(dataDir);
  mkdirSync(root, { recursive: true, mode: 0o700 });
  mkdirSync(inbox, { recursive: true, mode: 0o700 });
  try {
    chmodSync(root, 0o700);
    chmodSync(inbox, 0o700);
  } catch {}
  const target = join(inbox, `${String(payload.time * 1000).padStart(20, "0")}-${randomUUID()}.json`);
  const temporary = join(inbox, `.${randomUUID()}.tmp`);
  writeFileSync(temporary, JSON.stringify(payload), { mode: 0o600 });
  renameSync(temporary, target);
  return target;
}

module.exports = { PROTOCOL, ADAPTER_VERSION, MAX_HINT, hint, build, emit };
