import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import os
import unittest
import sqlite3

SCRIPT = Path(__file__).resolve().parents[1] / 'integrations/codex/receive.py'
spec = importlib.util.spec_from_file_location('receive', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ReceiverTests(unittest.TestCase):
    def test_events(self):
        payload = dict(hook_event_name='PermissionRequest', session_id='thread-1', turn_id='turn-1', cwd='/project', tool_input={'command':'secret'})
        first = module.normalize(payload, 100)
        self.assertEqual(first['id'], module.normalize(payload, 101)['id'])
        self.assertNotIn('secret', json.dumps(first))
        self.assertEqual(first['status'], '待确认')
        payload['turn_id'] = 'turn-2'
        self.assertNotEqual(first['id'], module.normalize(payload, 102)['id'])
    def test_no_decisions(self):
        with tempfile.TemporaryDirectory() as tmp:
            for event in ['Stop', 'PermissionRequest', 'Interrupt', 'UserPromptSubmit']:
                run = subprocess.run(['/usr/bin/python3', str(SCRIPT)], input=json.dumps(dict(hook_event_name=event, session_id='abc', turn_id='t')), text=True, capture_output=True, env={**os.environ, 'MIRA_DATA_DIR':tmp})
                self.assertEqual(run.returncode, 0)
                self.assertEqual(json.loads(run.stdout), {})
            self.assertEqual(len(list((Path(tmp)/'inbox').glob('*.json'))), 4)
    def test_invalid_input_nonblocking(self):
        run = subprocess.run(['/usr/bin/python3', str(SCRIPT)], input='broken', text=True, capture_output=True)
        self.assertEqual(run.returncode, 0)
        self.assertEqual(json.loads(run.stdout), {})
    def test_unsupported(self):
        self.assertIsNone(module.normalize(dict(hook_event_name='Unrecognized', session_id='abc'), 1))

    def test_title_lookup_exact_session_read_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'state_5.sqlite'
            with sqlite3.connect(path) as db:
                db.execute('CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT)')
                db.execute('INSERT INTO threads VALUES (?, ?)', ('abc', '修复通知按钮对比度'))
                db.execute('INSERT INTO threads VALUES (?, ?)', ('other', '不相关任务'))
            original = path.read_bytes()
            payload = dict(hook_event_name='Stop', session_id='abc', cwd='/MIRA')
            self.assertEqual(module.normalize(payload, 100, tmp)['title'], '修复通知按钮对比度')
            self.assertEqual(path.read_bytes(), original)
            payload['session_id'] = "missing' OR 1=1 --"
            self.assertIn('MIRA · 任务 missing', module.normalize(payload, 100, tmp)['title'])

    def test_missing_or_incompatible_metadata_is_nonblocking(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(module.task_title('abc', tmp))
            (Path(tmp)/'state_99.sqlite').write_text('not sqlite')
            self.assertIsNone(module.task_title('abc', tmp))

    def test_visible_desktop_name_wins_over_initial_prompt(self):
        with tempfile.TemporaryDirectory() as tmp:
            with sqlite3.connect(Path(tmp)/'state_5.sqlite') as db:
                db.execute('CREATE TABLE threads (id TEXT, title TEXT, name TEXT)')
                db.execute('INSERT INTO threads VALUES (?, ?, ?)', ('abc', 'Long initial prompt ' * 200, '设计 AI 任务与提醒中心'))
            self.assertEqual(module.task_title('abc', tmp), '设计 AI 任务与提醒中心')

    def test_missing_session_is_ignored(self):
        self.assertIsNone(module.normalize(dict(hook_event_name='Stop', session_id=None, cwd='/x'), 1))
        self.assertIsNone(module.normalize(dict(hook_event_name='Stop', cwd='/x'), 1))
        self.assertIsNone(module.normalize(dict(hook_event_name='Stop', session_id='   ', cwd='/x'), 1))

    def test_root_or_missing_cwd_has_a_readable_label(self):
        cases = [
            {'hook_event_name': 'Stop', 'session_id': 'abcdefgh-1234'},
            {'hook_event_name': 'Stop', 'session_id': 'abcdefgh-1234', 'cwd': '/'},
            {'hook_event_name': 'Stop', 'session_id': 'abcdefgh-1234', 'cwd': ''},
            {'hook_event_name': 'Stop', 'session_id': 'abcdefgh-1234', 'cwd': None},
            {'hook_event_name': 'Stop', 'session_id': 'abcdefgh-1234', 'cwd': ['/tmp']},
        ]
        for payload in cases:
            entry = module.normalize(payload, 100)
            self.assertEqual(entry['source'], 'Codex', payload)
            self.assertEqual(entry['title'], 'Codex · 任务 abcdefgh', payload)
        named = module.normalize(dict(hook_event_name='Stop', session_id='s', cwd='/Users/x/Codex'), 1)
        self.assertEqual(named['source'], 'Codex · Codex', 'a real project named Codex keeps both labels')

    def test_null_tool_name_is_nonblocking(self):
        self.assertIsNone(module.normalize(dict(hook_event_name='PreToolUse', session_id='s', tool_name=None), 1))
        entry = module.normalize(dict(hook_event_name='PreToolUse', session_id='s', tool_name='request_user_input'), 1)
        self.assertEqual(entry['status'], '待补充信息')

    def test_null_session_writes_no_event(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = subprocess.run(
                ['/usr/bin/python3', str(SCRIPT)],
                input=json.dumps(dict(hook_event_name='Stop', session_id=None)),
                text=True, capture_output=True, env={**os.environ, 'MIRA_DATA_DIR': tmp},
            )
            self.assertEqual(run.returncode, 0)
            self.assertEqual(json.loads(run.stdout), {})
            self.assertEqual(list((Path(tmp)/'inbox').glob('*.json')), [])

if __name__ == '__main__': unittest.main()
