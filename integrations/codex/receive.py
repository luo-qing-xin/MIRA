#!/usr/bin/python3
"""Observational hook. Never emit a permission/continuation decision."""
import hashlib
import json
import os
import sqlite3
from pathlib import Path
import sys
import time
import uuid
from urllib.parse import quote


def task_title(session, codex_home):
    """Best-effort local metadata adapter; never read messages or modify Codex DBs."""
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


def normalize(payload, now, codex_home=None):
    event = payload.get('hook_event_name', '')
    statuses = {'Stop': '本轮结束', 'PermissionRequest': '待确认',
                'UserPromptSubmit': '运行中', 'Interrupt': '已中断', 'PreToolUse': '待补充信息'}
    if event not in statuses:
        return None
    if event == 'PreToolUse' and 'request_user_input' not in payload.get('tool_name', ''):
        return None
    session = str(payload.get('session_id', ''))
    if not session:
        return None
    turn = str(payload.get('turn_id', ''))
    # Use tool input only in the hash; never store full commands or prompts.
    identity = json.dumps([session, turn, event, payload.get('tool_use_id'),
                           payload.get('tool_input') if event in ('PermissionRequest', 'PreToolUse') else None], sort_keys=True)
    key = hashlib.sha256(identity.encode()).hexdigest()
    project = Path(payload.get('cwd') or 'Codex').name
    name = task_title(session, codex_home) if codex_home is not None else None
    name = name or project + ' · 任务 ' + session[:8]
    bodies = {'Stop': 'Codex 本轮已结束，请打开原任务查看结果。',
              'PermissionRequest': 'Codex 即将请求执行权限，请返回原任务检查。此提醒不会批准操作。',
              'UserPromptSubmit': '已开始处理你的请求。',
              'Interrupt': '本轮已被中断，可返回任务继续。',
              'PreToolUse': 'Codex 需要补充信息，请返回原任务回答。'}
    return dict(id=key, title=name, body=bodies[event],
                source='Codex · ' + project, status=statuses[event],
                link='codex://threads/' + quote(session, safe=''), date=now,
                done=False, notified=False, thread=session)


def main():
    try:
        payload = json.load(sys.stdin)
        entry = normalize(payload, time.time(), os.environ.get('CODEX_HOME', str(Path.home() / '.codex')))
        if entry:
            root = Path(os.environ.get('MIRA_DATA_DIR', str(Path.home() / 'Library/Application Support/MIRA')))
            inbox = root / 'inbox'
            inbox.mkdir(parents=True, exist_ok=True, mode=0o700)
            os.chmod(root, 0o700)
            destination = inbox / ('%020d-' % (entry['date'] * 1000000) + entry['id'] + '.json')
            temporary = inbox / (str(uuid.uuid4()) + '.tmp')
            with temporary.open('x') as output:
                os.chmod(temporary, 0o600)
                json.dump(entry, output, ensure_ascii=False)
            temporary.replace(destination)
    except Exception as exc:
        print('MIRA notification unavailable: ' + type(exc).__name__, file=sys.stderr)
    # Empty JSON is valid for Stop; no decision, no block, no permission override.
    print('{}')


if __name__ == '__main__':
    main()
