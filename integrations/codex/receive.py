#!/usr/bin/python3
"""Codex hook adapter for MIRA.

This file only knows about Codex: which hook maps to which contract kind, which
payload field carries the prompt/turn/tool, and how to read Codex's local chat
name. Everything else (titles, status copy, de-duplication, links, delivery)
belongs to the shared emitter and MIRA's single receiver.

The hook is observe-only: it never emits a permission or continuation decision.
"""
import hashlib
import json
import os
import re
import sqlite3
import sys
import time
from pathlib import Path
from urllib.parse import quote

# Installed layout keeps mira_emit.py next to this file; the repository keeps it
# in integrations/emit/. Either location is accepted.
HERE = Path(__file__).resolve().parent
for candidate in (HERE, HERE.parent / "emit"):
    if (candidate / "mira_emit.py").is_file():
        sys.path.insert(0, str(candidate))
        break

try:
    import mira_emit  # noqa: E402  (path is prepared above)
except Exception:  # a broken SDK must never make the hook fail
    mira_emit = None

KINDS = {
    "Stop": ("turn.end", "completed"),
    "Interrupt": ("turn.end", "interrupted"),
    "PermissionRequest": ("approval.asked", None),
    "UserPromptSubmit": ("turn.start", None),
    "PreToolUse": ("question.asked", None),
}
EXECUTION_MODES = {'default', 'acceptEdits', 'dontAsk', 'bypassPermissions'}


def task_title(session, codex_home):
    """Best-effort local metadata adapter; never read messages or modify Codex DBs."""
    if codex_home is None:
        return None
    paths = sorted(Path(codex_home).glob('state_*.sqlite'),
                   key=lambda p: int(p.stem.split('_')[-1]) if p.stem.split('_')[-1].isdigit() else -1,
                   reverse=True)
    for path in paths[:3]:
        try:
            connection = sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True, timeout=0.1)
            try:
                columns = {row[1] for row in connection.execute('PRAGMA table_info(threads)')}
                # Current desktop stores its visible chat name in `name`; `title`
                # may contain the initial prompt. Never fetch that full prompt.
                expression = "COALESCE(NULLIF(TRIM(name), ''), SUBSTR(title, 1, 80))" if 'name' in columns else 'SUBSTR(title, 1, 80)'
                row = connection.execute('SELECT ' + expression + ' FROM threads WHERE id = ? LIMIT 1', (session,)).fetchone()
                if row and isinstance(row[0], str) and row[0].strip():
                    first_line = row[0].strip().splitlines()[0].strip()
                    return first_line[:60] + ('…' if len(first_line) > 60 else '')
            finally:
                connection.close()
        except (sqlite3.Error, OSError):
            continue
    return None


def _session(payload):
    session = payload.get('session_id')
    return session.strip() if isinstance(session, str) else ''


def _turn(payload):
    turn = payload.get('turn_id')
    if isinstance(turn, bool):
        return None
    if isinstance(turn, int):
        return turn if turn > 0 else None
    if isinstance(turn, str) and turn.strip().isdigit():
        return int(turn.strip())
    return None


def _request_text(prompt):
    """Skip Codex's attachment inventory before the emitter takes the first paragraph."""
    if not re.match(r'\s*# Files mentioned by the user:[ \t]*(?:\r?\n|$)', prompt):
        return prompt
    match = re.search(r'^#{1,6}[ \t]+My request:[ \t]*', prompt, re.MULTILINE)
    return prompt[match.end():].lstrip() if match else ''


def _key(prefix, session, payload):
    """Stable identity for repeated hook deliveries of the same event.

    Codex normally sends `tool_use_id`; when it does not, a short hash of the
    tool input keeps two different requests in one turn apart without storing
    the input itself.
    """
    turn = payload.get('turn_id')
    turn = '' if turn is None else str(turn)
    tool = payload.get('tool_use_id')
    tool = tool.strip() if isinstance(tool, str) else ''
    if not tool and payload.get('tool_input') is not None:
        material = json.dumps(payload.get('tool_input'), sort_keys=True, ensure_ascii=False)
        tool = hashlib.sha256(material.encode('utf-8')).hexdigest()[:12]
    return ':'.join(part for part in (prefix, session, turn, tool) if part)


def normalize(payload, now, codex_home=None):
    """Map one Codex hook payload onto a `mira.adapter/1` event, or None."""
    event = payload.get('hook_event_name', '')
    spec = KINDS.get(event)
    if spec is None:
        return None
    kind, reason = spec
    tool_name = payload.get('tool_name')
    tool_name = tool_name.strip() if isinstance(tool_name, str) else ''
    if event == 'PreToolUse' and 'request_user_input' not in tool_name:
        return None
    session = _session(payload)
    if not session:
        return None
    # Codex sends a null transcript path for in-memory sessions. Their events
    # have no chat history to open, including those from project suggestions.
    if 'transcript_path' in payload and payload['transcript_path'] is None:
        return None

    # Codex persists a proposed plan under the exact session and turn. Looking
    # only at this turn avoids treating an older plan as a new approval request.
    turn_id = str(payload.get('turn_id', ''))
    plan_pending = False
    if event == 'Stop' and codex_home is not None:
        if all(re.fullmatch(r'[A-Za-z0-9_-]+', part) for part in (session, turn_id)):
            plan_pending = (Path(codex_home) / 'plans' / session / turn_id / 'PLAN.md').is_file()
    if plan_pending:
        kind, reason = 'approval.asked', None

    contract = {
        'adapter': 'codex',
        'name': 'Codex',
        'kind': kind,
        'session': session,
        'time': int(now * 1000),
        'link': 'codex://threads/' + quote(session, safe=''),
        'dedupeKey': _key(kind, session, payload),
    }
    turn = _turn(payload)
    if turn is not None:
        contract['turn'] = turn
    cwd = payload.get('cwd')
    if isinstance(cwd, str) and cwd:
        contract['cwd'] = cwd
    if reason:
        contract['reason'] = reason
    # The desktop may write PLAN.md after Stop. Only an explicit execution
    # mode lets MIRA deliver a completion before checking live plan requests.
    mode = payload.get('permission_mode')
    if event == 'Stop' and not plan_pending and isinstance(mode, str) and mode in EXECUTION_MODES:
        contract['requiresPlanCheck'] = False

    prompt = payload.get('prompt')
    request = _request_text(prompt) if event == 'UserPromptSubmit' and isinstance(prompt, str) else ''
    if request:
        contract['hint'] = request
    else:
        # Only reached when this turn's prompt was never observed (MIRA was not
        # running). The emitter keeps the title short; MIRA clips it for display.
        title = task_title(session, codex_home)
        if title:
            contract['title'] = title

    if kind == 'approval.asked':
        contract['approval'] = ({'tool': '实施计划', 'reason': '计划已生成，等待你确认后执行'}
                                if plan_pending else {'tool': tool_name or '工具'})
    elif kind == 'question.asked':
        tool_use_id = payload.get('tool_use_id')
        if isinstance(tool_use_id, str) and tool_use_id:
            contract['questions'] = [{'id': tool_use_id}]
    return contract


def main():
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            raise ValueError('hook payload must be an object')
        root = Path(os.environ.get('MIRA_DATA_DIR', str(Path.home() / 'Library/Application Support/MIRA')))
        event = normalize(payload, time.time(), os.environ.get('CODEX_HOME', str(Path.home() / '.codex')))
        if event and mira_emit is not None:
            mira_emit.deliver(event, root)
    except Exception as exc:
        print('MIRA notification unavailable: ' + type(exc).__name__, file=sys.stderr)
    # Empty JSON is valid for Stop; no decision, no block, no permission override.
    print('{}')


if __name__ == '__main__':
    main()
