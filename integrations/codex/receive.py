#!/usr/bin/python3
"""Observational hook. Never emit a permission/continuation decision."""
import hashlib
import json
import os
import re
import sqlite3
from pathlib import Path
import sys
import time
import uuid
from urllib.parse import quote


TITLE_LIMIT = 44
TITLE_HEAD = 28
TITLE_TAIL = 12


def prompt_title(prompt):
    """First prompt paragraph, head + tail when it is longer than one line."""
    text = '' if prompt is None else str(prompt)
    paragraphs = [part.strip() for part in re.split(r'\n\s*\n', text.strip())]
    first = next((part for part in paragraphs if part), '')
    text = re.sub(r'\s+', ' ', first).strip()
    for pattern in (r'^#{1,6}\s+', r'^(?:[-*+]\s+|>\s+)', r'^任务\s*[：:]\s*'):
        text = re.sub(pattern, '', text)
    text = text.strip()
    characters = list(text)
    if len(characters) <= TITLE_LIMIT:
        return ''.join(characters)
    start = ''.join(characters[:TITLE_HEAD]).rstrip()
    boundary = start.rfind(' ')
    if boundary >= TITLE_HEAD * 0.6:
        start = start[:boundary].rstrip()
    tail_start = max(0, len(characters) - TITLE_TAIL)
    if tail_start > 0 and characters[tail_start].isascii() and characters[tail_start].isalpha() \
            and characters[tail_start - 1].isascii() and characters[tail_start - 1].isalpha():
        while tail_start > 0 and characters[tail_start - 1].isascii() and characters[tail_start - 1].isalpha() \
                and len(characters) - tail_start < TITLE_TAIL + 16:
            tail_start -= 1
    end = ''.join(characters[tail_start:]).lstrip()
    first_space = end.find(' ')
    if 0 <= first_space <= TITLE_TAIL * 0.4:
        end = end[first_space + 1:].lstrip()
    end = re.sub(r'^[，。、；：,.;:!?！？\s]+', '', end).strip()
    start = re.sub(r'[…\.]+$', '', start).rstrip()
    if not end:
        return ''.join(characters[:TITLE_LIMIT]).rstrip() + '…'
    return start + '…' + end


def _title_path(root, session):
    digest = hashlib.sha256(session.encode('utf-8')).hexdigest()
    return Path(root) / 'titles' / (digest + '.json')


def remember_prompt(root, session, turn, prompt):
    """Persist only the clipped title, never the full prompt."""
    title = prompt_title(prompt)
    if not title:
        return None
    try:
        directory = Path(root) / 'titles'
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(directory, 0o700)
        temporary = directory / (uuid.uuid4().hex + '.tmp')
        with temporary.open('x') as output:
            os.chmod(temporary, 0o600)
            json.dump({'session': session, 'turn': turn, 'title': title, 'date': time.time()},
                      output, ensure_ascii=False)
        temporary.replace(_title_path(root, session))
    except Exception:
        return None
    return title


def remembered_title(root, session, turn, now, max_age=86400):
    try:
        record = json.loads(_title_path(root, session).read_text(encoding='utf-8'))
        title = record.get('title')
        if not isinstance(title, str) or not title.strip():
            return None
        stored_turn = record.get('turn')
        if turn and stored_turn and str(turn) != str(stored_turn):
            return None
        date = record.get('date')
        if isinstance(date, (int, float)) and now - date > max_age:
            return None
        return title.strip()
    except (OSError, ValueError):
        return None


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


def normalize(payload, now, codex_home=None, data_dir=None):
    event = payload.get('hook_event_name', '')
    statuses = {'Stop': '本轮结束', 'PermissionRequest': '待确认',
                'UserPromptSubmit': '运行中', 'Interrupt': '已中断', 'PreToolUse': '待补充信息'}
    if event not in statuses:
        return None
    tool_name = payload.get('tool_name')
    tool_name = tool_name if isinstance(tool_name, str) else ''
    if event == 'PreToolUse' and 'request_user_input' not in tool_name:
        return None
    session = payload.get('session_id')
    session = session.strip() if isinstance(session, str) else ''
    if not session:
        return None
    turn = str(payload.get('turn_id') or '')
    # Use tool input only in the hash; never store full commands or prompts.
    identity = json.dumps([session, turn, event, payload.get('tool_use_id'),
                           payload.get('tool_input') if event in ('PermissionRequest', 'PreToolUse') else None], sort_keys=True)
    key = hashlib.sha256(identity.encode()).hexdigest()
    cwd = payload.get('cwd')
    project = Path(cwd).name if isinstance(cwd, str) else ''
    # Root, missing, and non-string cwd must not produce an empty source label.
    missing_project = not project
    if missing_project:
        project = 'Codex'
    name = None
    if event == 'UserPromptSubmit':
        prompt = payload.get('prompt')
        if isinstance(prompt, str):
            name = prompt_title(prompt)
    if not name and data_dir is not None:
        name = remembered_title(data_dir, session, turn, now)
    if not name:
        name = task_title(session, codex_home) if codex_home is not None else None
    name = name or project + ' · 任务 ' + session[:8]
    bodies = {'Stop': 'Codex 本轮已结束，请打开原任务查看结果。',
              'PermissionRequest': 'Codex 即将请求执行权限，请返回原任务检查。此提醒不会批准操作。',
              'UserPromptSubmit': '已开始处理你的请求。',
              'Interrupt': '本轮已被中断，可返回任务继续。',
              'PreToolUse': 'Codex 需要补充信息，请返回原任务回答。'}
    return dict(id=key, title=name, body=bodies[event],
                source='Codex' if missing_project else 'Codex · ' + project,
                status=statuses[event],
                link='codex://threads/' + quote(session, safe=''), date=now,
                done=False, notified=False, thread=session)


def main():
    try:
        payload = json.load(sys.stdin)
        root = Path(os.environ.get('MIRA_DATA_DIR', str(Path.home() / 'Library/Application Support/MIRA')))
        entry = normalize(payload, time.time(),
                          os.environ.get('CODEX_HOME', str(Path.home() / '.codex')), root)
        if entry:
            if payload.get('hook_event_name') == 'UserPromptSubmit':
                event_session = payload.get('session_id')
                if isinstance(event_session, str) and event_session.strip():
                    prompt = payload.get('prompt')
                    if isinstance(prompt, str):
                        remember_prompt(root, event_session.strip(),
                                        str(payload.get('turn_id') or ''), prompt)
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
