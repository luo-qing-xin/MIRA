#!/usr/bin/python3
"""Shared emitter for MIRA adapters speaking `mira.adapter/1`.

Adapters only map their client's payload onto the contract fields; this module
owns the envelope, the version stamp, the 160-character title hint budget and
the atomic write into MIRA's inbox. Nothing here interprets reminders: MIRA
(Swift) is the single receiver that normalizes, titles, de-duplicates and
validates links.
"""
import json
import os
import time
import uuid
from pathlib import Path

PROTOCOL = "mira.adapter/1"
# Version of this adapter kit. MIRA compares it with its own expectation and
# shows "旧版 / 需要更新 / 重启后生效" in the settings cards.
ADAPTER_VERSION = "0.4.0"
# Only this much of a prompt ever leaves the client process.
MAX_HINT = 160
MAX_TEXT = 500


def hint(value):
    """First paragraph, one line, bounded. The display clip happens in MIRA."""
    if not isinstance(value, str):
        return None
    paragraph = value.replace("\r\n", "\n").split("\n\n")
    first = next((part.strip() for part in paragraph if part.strip()), "")
    text = " ".join(first.split())
    if not text:
        return None
    return "".join(list(text)[:MAX_HINT])


def _text(value, limit=MAX_TEXT):
    if not isinstance(value, str):
        return None
    text = value.strip()
    return "".join(list(text)[:limit]) if text else None


def _number(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def _approval(value):
    if not isinstance(value, dict):
        return None
    approval = {}
    token = _text(value.get("token"), 64)
    if token:
        approval["token"] = token
    ttl = _number(value.get("ttlMs"))
    if ttl is not None and ttl > 0:
        approval["ttlMs"] = ttl
    tool = _text(value.get("tool"), 60)
    if tool:
        approval["tool"] = tool
    reason = _text(value.get("reason"), 200)
    if reason:
        approval["reason"] = reason
    return approval or None


def _questions(value):
    if not isinstance(value, list):
        return None
    questions = []
    for item in value[:20]:
        if not isinstance(item, dict):
            continue
        question = {}
        for key in ("id", "question", "header"):
            text = _text(item.get(key), 300)
            if text:
                question[key] = text
        if question:
            questions.append(question)
    return questions or None


def build(event, now_ms=None):
    """Validate one adapter event and return the contract envelope."""
    if not isinstance(event, dict):
        raise ValueError("adapter event must be an object")
    adapter = event.get("adapter")
    if not isinstance(adapter, str) or not adapter.strip():
        raise ValueError("adapter id is required")
    kind = _text(event.get("kind"), 40)
    if not kind:
        raise ValueError("kind is required")
    session = _text(event.get("session"), 200)
    if not session:
        raise ValueError("session is required")

    stamp = _number(event.get("time"))
    payload = {
        "protocol": PROTOCOL,
        "adapter": {
            "id": adapter.strip().lower(),
            "name": _text(event.get("name"), 40) or adapter.strip(),
            "version": ADAPTER_VERSION,
        },
        "kind": kind,
        "session": session,
        "time": int(stamp if stamp and stamp > 0 else (now_ms if now_ms is not None else time.time() * 1000)),
    }

    turn = _number(event.get("turn"))
    if turn is not None and int(turn) > 0:
        payload["turn"] = int(turn)
    if isinstance(event.get("requiresPlanCheck"), bool):
        payload["requiresPlanCheck"] = event["requiresPlanCheck"]
    for key, limit in (("cwd", 1024), ("title", 200), ("reason", 40), ("link", 1024),
                       ("dedupeKey", 200), ("closes", 200)):
        text = _text(event.get(key), limit)
        if text:
            payload[key] = text
    clipped = hint(event.get("hint"))
    if clipped:
        payload["titleHint"] = clipped
    approval = _approval(event.get("approval"))
    if approval:
        payload["approval"] = approval
    questions = _questions(event.get("questions"))
    if questions:
        payload["questions"] = questions
    return payload


def inbox_dir(data_dir=None):
    if data_dir is not None:
        root = Path(data_dir)
    elif os.environ.get("MIRA_DATA_DIR"):
        root = Path(os.environ["MIRA_DATA_DIR"])
    else:
        root = Path.home() / "Library/Application Support/MIRA"
    return root, root / "inbox"


def deliver(event, data_dir=None, now_ms=None):
    """Write one contract event into the inbox atomically; returns its path."""
    payload = build(event, now_ms)
    root, inbox = inbox_dir(data_dir)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    inbox.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    os.chmod(inbox, 0o700)
    target = inbox / ("%020d-%s.json" % (payload["time"] * 1000, uuid.uuid4().hex))
    temporary = inbox / ("." + uuid.uuid4().hex + ".tmp")
    with temporary.open("x") as handle:
        os.chmod(temporary, 0o600)
        json.dump(payload, handle, ensure_ascii=False, sort_keys=True)
    temporary.replace(target)
    return target
