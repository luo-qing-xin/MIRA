// DSH (DeepSeek Harness) bridge: turns session events into MIRA adapter
// contract events. The bridge owns only DSH knowledge — which session event
// means what, how to read the current prompt, and how to wait for an approval
// answer. MIRA normalizes, titles, de-duplicates and validates links.
import { randomUUID } from "node:crypto";
import { existsSync, readFileSync, unlinkSync } from "node:fs";
import { createRequire } from "node:module";
import { homedir } from "node:os";
import { join } from "node:path";
import {
  approvalAskedEvent,
  approvalClosedEvent,
  isSubagent,
  questionAskedEvent,
  questionClosedEvent,
  turnEndEvent,
  turnStartEvent,
} from "./entry.js";

// Installed layout copies emit.js next to this file; the repository keeps it in
// integrations/emit/. resolve synchronously so the plugin can stay declarative.
const require = createRequire(import.meta.url);
const emitter = (() => {
  for (const candidate of ["./emit.js", "../emit/emit.js"]) {
    try {
      return require(candidate);
    } catch {}
  }
  throw new Error("mira-bridge: emitter is missing (reinstall the bridge)");
})();

export const name = "dsh-mira-bridge";

const DEFAULT_DATA_DIR = join(homedir(), "Library/Application Support/MIRA");

function settings(config) {
  const raw = config !== null && typeof config === "object" ? config : {};
  const dataDir =
    typeof raw.dataDir === "string" && raw.dataDir.startsWith("/") ? raw.dataDir : DEFAULT_DATA_DIR;
  const link = typeof raw.link === "string" && raw.link.length > 0 ? raw.link : "dsh://open";
  const approvalTimeoutMs = Number.isFinite(raw.approvalTimeoutMs) ? Math.max(1000, raw.approvalTimeoutMs) : 60_000;
  const pollMs = Number.isFinite(raw.pollMs) ? Math.max(5, raw.pollMs) : 250;
  const heartbeatMs = Number.isFinite(raw.heartbeatMs) ? Math.max(1000, raw.heartbeatMs) : 15_000;
  return { dataDir, link, skipSubagents: raw.skipSubagents !== false, approvalTimeoutMs, pollMs, heartbeatMs };
}

/**
 * Register the observer. All failures stay inside this plugin: a broken inbox
 * must never fail a DSH turn or block a pending decision.
 */
export function apply(ctx, config) {
  const { dataDir, link, skipSubagents, approvalTimeoutMs, pollMs, heartbeatMs } = settings(config);
  const titles = new Map();
  const turns = new Map();

  function miraAlive() {
    try {
      const stamp = Number(readFileSync(join(dataDir, "heartbeat"), "utf8").trim());
      return Number.isFinite(stamp) && Date.now() - stamp <= heartbeatMs;
    } catch {
      return false;
    }
  }

  function waitForDecision(token, signal) {
    const file = join(dataDir, "decisions", token + ".json");
    return new Promise((resolve) => {
      const started = Date.now();
      let settled = false;
      let timer;
      const finish = (value) => {
        if (settled) return;
        settled = true;
        clearInterval(timer);
        signal?.removeEventListener?.("abort", onAbort);
        resolve(value);
      };
      const onAbort = () => finish("defer");
      const poll = () => {
        try {
          if (existsSync(file)) {
            const raw = readFileSync(file, "utf8");
            try { unlinkSync(file); } catch {}
            const parsed = JSON.parse(raw);
            if (parsed?.token === token && ["allow", "deny", "defer"].includes(parsed.decision)) {
              finish(parsed.decision);
              return;
            }
          }
        } catch {}
        if (Date.now() - started >= approvalTimeoutMs) finish("timeout");
      };
      if (signal?.aborted) return finish("defer");
      signal?.addEventListener?.("abort", onAbort, { once: true });
      timer = setInterval(poll, pollMs);
    });
  }

  function deliver(event) {
    try {
      emitter.emit(dataDir, event);
      return true;
    } catch (error) {
      ctx.logger?.warn?.(`mira-bridge: delivery failed: ${error?.message ?? error}`);
      return false;
    }
  }

  function skip(session) {
    return skipSubagents && isSubagent(session);
  }

  function scanPrompt(session, newestFirst) {
    if (typeof session.eventAt !== "function" || !Number.isSafeInteger(session.seq)) return undefined;
    const limit = Math.min(session.seq, 5000);
    for (let offset = 0; offset < limit; offset += 1) {
      const seq = newestFirst ? limit - 1 - offset : offset;
      const event = session.eventAt(seq);
      if (event?.type !== "user/message" || event.data?.source?.kind !== "user") continue;
      const blocks = Array.isArray(event.data.content) ? event.data.content : [];
      const text = blocks.filter((block) => block?.type === "text").map((block) => block.text ?? "").join(" ");
      if (text.trim()) return text;
    }
    return undefined;
  }

  /** The most recent prompt authored by the user, regardless of turn boundaries. */
  function latestPrompt(session) {
    return scanPrompt(session, true);
  }

  /** Non-fallback session title; a fallback is just the prompt clipped by DSH. */
  function sessionTitleOf(session) {
    const cached = titles.get(session.id);
    if (cached) return cached;
    try {
      // Do not declare an inject dependency: the bridge must keep working in
      // profiles without the title service, and cordis' object form maps
      // service names, not required/optional lists.
      const service = ctx.sessionTitle ?? ctx.get?.("sessionTitle");
      const snapshot = service?.get?.(session);
      const title = typeof snapshot?.title === "string" ? snapshot.title.trim() : "";
      if (title && snapshot?.source?.kind !== "fallback") {
        titles.set(session.id, title);
        return title;
      }
    } catch (error) {
      ctx.logger?.warn?.(`mira-bridge: title lookup failed: ${error?.message ?? error}`);
    }
    return undefined;
  }

  /** Prompt first (best task name), then the visible session title. */
  function titleFor(session) {
    try {
      const prompt = latestPrompt(session);
      if (prompt) return { hint: prompt };
    } catch (error) {
      ctx.logger?.warn?.(`mira-bridge: prompt lookup failed: ${error?.message ?? error}`);
    }
    const title = sessionTitleOf(session);
    return title ? { title } : {};
  }

  ctx.on("session/event", (session, event) => {
    try {
      if (event.type === "session/title") {
        const title = typeof event.data?.title === "string" ? event.data.title.trim() : "";
        // A deterministic fallback is only the first prompt clipped by DSH's
        // byte budget; the full prompt is a better name, so it is not pinned.
        if (title && event.data?.source?.kind !== "fallback") {
          titles.set(session.id, title);
        }
        return;
      }
      if (skip(session)) return;
      if (event.type === "turn/start" || event.type === "turn/end") {
        if (Number.isSafeInteger(event.data?.turn)) turns.set(session.id, event.data.turn);
      }
      const time = typeof event.time === "number" ? event.time : Date.now();
      switch (event.type) {
        case "turn/start":
          deliver(
            turnStartEvent({
              sessionId: session.id,
              cwd: session.header?.cwd,
              turn: event.data?.turn,
              time,
              ...titleFor(session),
              link,
            }),
          );
          break;
        case "turn/end":
          deliver(
            turnEndEvent({
              sessionId: session.id,
              cwd: session.header?.cwd,
              turn: event.data?.turn,
              reason: event.data?.reason,
              time,
              ...titleFor(session),
              link,
            }),
          );
          break;
        default:
          break;
      }
    } catch (error) {
      ctx.logger?.warn?.(`mira-bridge: event handling failed: ${error?.message ?? error}`);
    }
  });

  // An approval is a waterfall: claim it only while MIRA is alive, show an
  // actionable reminder, and fall back to the desktop dialog on timeout,
  // deferral, or dismissal.
  ctx.on("approval/request", async (request, next) => {
    const session = request?.agent?.session;
    if (!session || skip(session) || !miraAlive()) return next();
    const token = randomUUID();
    const askedAt = Date.now();
    const event = approvalAskedEvent({
      sessionId: session.id,
      cwd: session.header?.cwd,
      time: askedAt,
      turn: turns.get(session.id),
      ...titleFor(session),
      toolName: request.toolName,
      reason: request.reason,
      approvalId: token,
      token,
      ttlMs: approvalTimeoutMs,
      link,
    });
    // If MIRA cannot receive the request, do not sit on the approval: hand it
    // straight back to the desktop dialog instead of waiting for a reply.
    if (!deliver(event)) return next();
    let decision = "defer";
    try {
      decision = await waitForDecision(token, request.signal);
    } catch (error) {
      ctx.logger?.warn?.(`mira-bridge: approval wait failed: ${error?.message ?? error}`);
    }
    deliver(approvalClosedEvent({ sessionId: session.id, time: Math.max(Date.now(), askedAt + 1), approvalId: token }));
    if (decision === "allow") return "allowed-once";
    if (decision === "deny") return "rejected";
    return next();
  }, { prepend: true });

  // A pending question is a waterfall, not a session event: observe it, then
  // delegate the actual answer to the desktop client.
  ctx.on("user-questions/request", async (request, next) => {
    let pendingSession = "";
    let pendingQuestion = null;
    try {
      const session = request?.agent?.session;
      const questions = Array.isArray(request?.questions) ? request.questions : [];
      if (session && !skip(session) && questions.length > 0) {
        pendingSession = session.id;
        pendingQuestion = questions[0]?.id ?? "unknown";
        deliver(
          questionAskedEvent({
            sessionId: session.id,
            cwd: session.header?.cwd,
            time: Date.now(),
            turn: turns.get(session.id),
            ...titleFor(session),
            questions,
            link,
          }),
        );
      }
    } catch (error) {
      ctx.logger?.warn?.(`mira-bridge: question handling failed: ${error?.message ?? error}`);
    }
    try {
      return await next();
    } finally {
      if (pendingSession) {
        deliver(questionClosedEvent({ sessionId: pendingSession, time: Date.now(), questionId: pendingQuestion }));
      }
    }
  });

  ctx.on("session/disposed", (session) => {
    titles.delete(session.id);
    turns.delete(session.id);
  });
}
