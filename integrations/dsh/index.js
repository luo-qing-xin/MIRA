// DSH (DeepSeek Harness) bridge: turns session events into MIRA inbox entries.
// Mounted as an ordinary cordis plugin row; it never answers approvals.
import { homedir } from "node:os";
import { join } from "node:path";
import {
  approvalEntryId,
  buildApprovalEntry,
  buildDismissal,
  buildEntry,
  buildQuestionEntry,
  isSubagent,
  questionEntryId,
  summarize,
  writeEntry,
} from "./entry.js";

export const name = "dsh-mira-bridge";

const DEFAULT_DATA_DIR = join(homedir(), "Library/Application Support/MIRA");

function settings(config) {
  const raw = config !== null && typeof config === "object" ? config : {};
  const dataDir =
    typeof raw.dataDir === "string" && raw.dataDir.startsWith("/") ? raw.dataDir : DEFAULT_DATA_DIR;
  const link = typeof raw.link === "string" && raw.link.length > 0 ? raw.link : "dsh://open";
  return { dataDir, link, skipSubagents: raw.skipSubagents !== false };
}

/**
 * Register the observer. All failures stay inside this plugin: a broken inbox
 * must never fail a DSH turn or block a pending decision.
 */
export function apply(ctx, config) {
  const { dataDir, link, skipSubagents } = settings(config);
  const titles = new Map();
  const turns = new Map();

  function deliver(entry) {
    try {
      writeEntry(dataDir, entry);
    } catch (error) {
      ctx.logger?.warn?.(`mira-bridge: delivery failed: ${error?.message ?? error}`);
    }
  }

  function skip(session) {
    return skipSubagents && isSubagent(session);
  }

  function firstPrompt(session) {
    if (typeof session.eventAt !== "function" || !Number.isSafeInteger(session.seq)) return undefined;
    const limit = Math.min(session.seq, 5000);
    for (let seq = 0; seq < limit; seq += 1) {
      const event = session.eventAt(seq);
      if (event?.type !== "user/message" || event.data?.source?.kind !== "user") continue;
      const blocks = Array.isArray(event.data.content) ? event.data.content : [];
      const text = blocks.filter((block) => block?.type === "text").map((block) => block.text ?? "").join(" ");
      if (text.trim()) return text;
    }
    return undefined;
  }

  function titleOf(session) {
    const cached = titles.get(session.id);
    if (cached) return cached;
    try {
      // Do not declare an inject dependency: the bridge must keep working in
      // profiles without the title service, and cordis' object form maps
      // service names, not required/optional lists.
      const service = ctx.sessionTitle ?? ctx.get?.("sessionTitle");
      const snapshot = service?.get?.(session);
      const title = typeof snapshot?.title === "string" ? snapshot.title.trim() : "";
      if (title) {
        titles.set(session.id, title);
        return title;
      }
    } catch (error) {
      ctx.logger?.warn?.(`mira-bridge: title lookup failed: ${error?.message ?? error}`);
    }
    // Titles are generated asynchronously; before that, the first user message
    // is the best human-readable name for the task.
    try {
      const prompt = firstPrompt(session);
      const summary = prompt ? summarize(prompt) : "";
      if (summary) {
        titles.set(session.id, summary);
        return summary;
      }
    } catch (error) {
      ctx.logger?.warn?.(`mira-bridge: prompt summary failed: ${error?.message ?? error}`);
    }
    return undefined;
  }

  ctx.on("session/event", (session, event) => {
    try {
      if (event.type === "session/title") {
        if (typeof event.data?.title === "string" && event.data.title.trim()) {
          titles.set(session.id, event.data.title);
        }
        return;
      }
      if (skip(session)) return;
      if (event.type === "turn/start" || event.type === "turn/end") {
        if (Number.isSafeInteger(event.data?.turn)) turns.set(session.id, event.data.turn);
      }
      switch (event.type) {
        case "turn/end":
          deliver(
            buildEntry({
              sessionId: session.id,
              cwd: session.header?.cwd,
              turn: event.data?.turn,
              reason: event.data?.reason,
              time: event.time,
              title: titleOf(session),
              link,
            }),
          );
          break;
        case "approval/asked":
          deliver(
            buildApprovalEntry({
              sessionId: session.id,
              cwd: session.header?.cwd,
              time: event.time,
              title: titleOf(session),
              turn: turns.get(session.id),
              toolName: event.data?.toolName,
              reason: event.data?.reason,
              approvalId: event.data?.id,
              link,
            }),
          );
          break;
        case "approval/decided":
          deliver(
            buildDismissal({
              targetId: approvalEntryId(session.id, event.data?.id),
              sessionId: session.id,
              time: event.time,
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

  // A pending question is a waterfall, not a session event: observe it, then
  // delegate the actual answer to the desktop client.
  ctx.on("user-questions/request", async (request, next) => {
    let pending = [];
    let pendingSession = "";
    try {
      const session = request?.agent?.session;
      const questions = Array.isArray(request?.questions) ? request.questions : [];
      if (session && !skip(session) && questions.length > 0) {
        pendingSession = session.id;
        pending = questions.map((question) => questionEntryId(session.id, question?.id ?? "unknown"));
        deliver(
          buildQuestionEntry({
            sessionId: session.id,
            cwd: session.header?.cwd,
            time: Date.now(),
            title: titles.get(session.id),
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
      for (const targetId of pending) {
        deliver(buildDismissal({ targetId, sessionId: pendingSession, time: Date.now() }));
      }
    }
  });

  ctx.on("session/disposed", (session) => {
    titles.delete(session.id);
    turns.delete(session.id);
  });
}
