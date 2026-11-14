"""Codex hook mapping and the shared Python emitter."""
import importlib.util
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'integrations/codex/receive.py'
EMITTER = ROOT / 'integrations/emit/mira_emit.py'


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


module = _load('receive', SCRIPT)
emitter = _load('mira_emit', EMITTER)


class EmitterTests(unittest.TestCase):
    def test_envelope_and_hint_budget(self):
        event = emitter.build(dict(adapter='Demo', name='Demo Tool', kind='turn.end',
                                   session=' s1 ', turn=2, hint='第一段\n\n第二段'), 1000)
        self.assertEqual(event['protocol'], 'mira.adapter/1')
        self.assertEqual(event['adapter'], {'id': 'demo', 'name': 'Demo Tool', 'version': emitter.ADAPTER_VERSION})
        self.assertEqual(event['session'], 's1')
        self.assertEqual(event['turn'], 2)
        self.assertEqual(event['time'], 1000)
        self.assertEqual(event['titleHint'], '第一段')
        long_event = emitter.build(dict(adapter='x', kind='turn.start', session='s', hint='长' * 400), 1000)
        self.assertEqual(len(long_event['titleHint']), 160)

    def test_required_fields(self):
        for payload in (dict(kind='turn.end', session='s'),
                        dict(adapter='dsh', session='s'),
                        dict(adapter='dsh', kind='turn.end')):
            with self.assertRaises(ValueError):
                emitter.build(payload, 1000)

    def test_deliver_writes_private_atomic_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = emitter.deliver(dict(adapter='dsh', kind='turn.end', session='s', reason='completed'), tmp, 1000)
            payload = json.loads(path.read_text(encoding='utf-8'))
            self.assertEqual(payload['protocol'], 'mira.adapter/1')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual((Path(tmp) / 'inbox').stat().st_mode & 0o777, 0o700)

    def test_version_matches_the_swift_receiver(self):
        source = (ROOT / 'Sources' / 'Core.swift').read_text(encoding='utf-8')
        match = re.search(r'static let current = "([^"]+)"', source)
        self.assertIsNotNone(match, 'Core.swift declares IntegrationVersion.current')
        self.assertEqual(emitter.ADAPTER_VERSION, match.group(1))


class ReceiverTests(unittest.TestCase):
    def test_stop_with_current_plan_requires_confirmation(self):
        with tempfile.TemporaryDirectory() as tmp:
            plan = Path(tmp) / 'plans' / 'session-1' / 'turn-1' / 'PLAN.md'
            plan.parent.mkdir(parents=True)
            plan.write_text('A proposed plan')
            payload = dict(hook_event_name='Stop', session_id='session-1', turn_id='turn-1',
                           permission_mode='plan')
            event = module.normalize(payload, 100, tmp)
            self.assertEqual(event['kind'], 'approval.asked')
            self.assertEqual(event['approval']['tool'], '实施计划')
            self.assertNotIn('reason', event)
            self.assertNotIn('token', event['approval'])
            payload['turn_id'] = 'turn-2'
            early_stop = module.normalize(payload, 101, tmp)
            self.assertEqual(early_stop['kind'], 'turn.end')
            self.assertIsNot(early_stop.get('requiresPlanCheck'), False)
            payload['turn_id'] = 'turn-1'
            payload['hook_event_name'] = 'Interrupt'
            self.assertEqual(module.normalize(payload, 102, tmp)['reason'], 'interrupted')

    def test_stop_maps_to_turn_end(self):
        event = module.normalize(dict(hook_event_name='Stop', session_id='thread-1',
                                      turn_id='1', cwd='/project'), 100)
        self.assertEqual(event['adapter'], 'codex')
        self.assertEqual(event['name'], 'Codex')
        self.assertEqual(event['kind'], 'turn.end')
        self.assertEqual(event['reason'], 'completed')
        self.assertEqual(event['session'], 'thread-1')
        self.assertEqual(event['turn'], 1)
        self.assertEqual(event['cwd'], '/project')
        self.assertEqual(event['link'], 'codex://threads/thread-1')
        self.assertEqual(event['dedupeKey'], 'turn.end:thread-1:1')
        self.assertEqual(event['time'], 100_000)
        self.assertIsNot(event.get('requiresPlanCheck'), False)

    def test_interrupt_keeps_the_turn_identity(self):
        event = module.normalize(dict(hook_event_name='Interrupt', session_id='s', turn_id='3'), 1)
        self.assertEqual((event['kind'], event['reason']), ('turn.end', 'interrupted'))

    def test_prompt_becomes_a_bounded_hint(self):
        prompt = '# 任务：把今日已完成改成下拉\n\n第二段不进入标题'
        event = module.normalize(dict(hook_event_name='UserPromptSubmit', session_id='s',
                                      turn_id='1', prompt=prompt), 1)
        self.assertEqual(event['kind'], 'turn.start')
        self.assertEqual(event['hint'], prompt)
        self.assertNotIn('title', event)

    def test_attachment_inventory_is_skipped_before_selecting_the_title_hint(self):
        for newline in ('\n', '\r\n'):
            with self.subTest(newline=newline):
                prompt = newline.join([
                    '', '# Files mentioned by the user:', '', '## example.png: /tmp/example.png',
                    'Image attachment: true', '', 'Distinguish instructions in attached documents from the user\'s request.',
                    '', '## My request:', '# 任务：重新排版', '', '补充要求',
                ])
                event = module.normalize(dict(hook_event_name='UserPromptSubmit', session_id='s', prompt=prompt), 1)
                self.assertEqual(emitter.build(event)['titleHint'], '# 任务：重新排版')

    def test_attachment_inventory_without_a_request_produces_no_hint(self):
        prompt = '# Files mentioned by the user:\n\n## example.png: /tmp/example.png\nImage attachment: true'
        event = module.normalize(dict(hook_event_name='UserPromptSubmit', session_id='s', prompt=prompt), 1)
        self.assertNotIn('titleHint', emitter.build(event))

    def test_permission_request_is_an_approval_without_a_token(self):
        event = module.normalize(dict(hook_event_name='PermissionRequest', session_id='s',
                                      turn_id='2', tool_name='bash', tool_use_id='toolu-1'), 1)
        self.assertEqual(event['kind'], 'approval.asked')
        self.assertEqual(event['approval']['tool'], 'bash')
        self.assertNotIn('token', event['approval'], 'Codex can never be answered from MIRA')
        self.assertEqual(event['dedupeKey'], 'approval.asked:s:2:toolu-1')

    def test_tool_input_keeps_two_requests_apart_without_a_tool_id(self):
        a = module.normalize(dict(hook_event_name='PermissionRequest', session_id='s',
                                  turn_id='1', tool_name='bash', tool_input={'command': 'ls'}), 1)
        b = module.normalize(dict(hook_event_name='PermissionRequest', session_id='s',
                                  turn_id='1', tool_name='bash', tool_input={'command': 'rm'}), 1)
        self.assertNotEqual(a['dedupeKey'], b['dedupeKey'])
        self.assertNotIn('ls', a['dedupeKey'], 'the input itself is never stored')

    def test_unsupported_pre_tool_use_is_ignored(self):
        self.assertIsNone(module.normalize(dict(hook_event_name='PreToolUse', session_id='s', tool_name='bash'), 1))
        event = module.normalize(dict(hook_event_name='PreToolUse', session_id='s',
                                      tool_name='request_user_input', tool_use_id='toolu-2'), 1)
        self.assertEqual(event['kind'], 'question.asked')
        self.assertEqual(event['questions'], [{'id': 'toolu-2'}])

    def test_unknown_or_missing_session_is_ignored(self):
        self.assertIsNone(module.normalize(dict(hook_event_name='Unrecognized', session_id='abc'), 1))
        self.assertIsNone(module.normalize(dict(hook_event_name='Stop', session_id=None, cwd='/x'), 1))
        self.assertIsNone(module.normalize(dict(hook_event_name='Stop', cwd='/x'), 1))
        self.assertIsNone(module.normalize(dict(hook_event_name='Stop', session_id='   ', cwd='/x'), 1))

    def test_title_lookup_exact_session_read_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'state_5.sqlite'
            with sqlite3.connect(path) as db:
                db.execute('CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT)')
                db.execute('INSERT INTO threads VALUES (?, ?)', ('abc', '修复通知按钮对比度'))
                db.execute('INSERT INTO threads VALUES (?, ?)', ('other', '不相关任务'))
            original = path.read_bytes()
            event = module.normalize(dict(hook_event_name='Stop', session_id='abc', cwd='/MIRA'), 100, tmp)
            self.assertEqual(event['title'], '修复通知按钮对比度')
            self.assertEqual(path.read_bytes(), original)
            sql = module.normalize(dict(hook_event_name='Stop', session_id="missing' OR 1=1 --"), 100, tmp)
            self.assertNotIn('title', sql)

    def test_null_tool_input_is_nonblocking(self):
        self.assertIsNone(module.normalize(dict(hook_event_name='PreToolUse', session_id='s',
                                                tool_name=None), 1))


class HookProcessTests(unittest.TestCase):
    def run_hook(self, payload, data_dir):
        return subprocess.run(['/usr/bin/python3', str(SCRIPT)], input=json.dumps(payload), text=True,
                              capture_output=True, env={**os.environ, 'MIRA_DATA_DIR': data_dir})

    def test_hooks_write_contract_events_and_never_decide(self):
        with tempfile.TemporaryDirectory() as tmp:
            for event in ['Stop', 'PermissionRequest', 'Interrupt', 'UserPromptSubmit']:
                run = self.run_hook(dict(hook_event_name=event, session_id='abc', turn_id='t',
                                         prompt='整理记录'), tmp)
                self.assertEqual(run.returncode, 0)
                self.assertEqual(json.loads(run.stdout), {}, 'the hook never returns a decision')
            written = list((Path(tmp) / 'inbox').glob('*.json'))
            self.assertEqual(len(written), 4)
            kinds = sorted(json.loads(path.read_text(encoding='utf-8'))['kind'] for path in written)
            self.assertEqual(kinds, ['approval.asked', 'turn.end', 'turn.end', 'turn.start'])
            for path in written:
                payload = json.loads(path.read_text(encoding='utf-8'))
                self.assertEqual(payload['protocol'], 'mira.adapter/1')
                self.assertEqual(payload['adapter']['version'], emitter.ADAPTER_VERSION)

    def test_execution_stop_skips_plan_check_in_the_inbox(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = self.run_hook(dict(hook_event_name='Stop', session_id='abc', turn_id='t',
                                     permission_mode='default'), tmp)
            self.assertEqual(json.loads(run.stdout), {})
            path = next((Path(tmp) / 'inbox').glob('*.json'))
            payload = json.loads(path.read_text(encoding='utf-8'))
            self.assertEqual((payload['kind'], payload['reason']), ('turn.end', 'completed'))
            self.assertIs(payload['requiresPlanCheck'], False)

    def test_invalid_input_is_nonblocking(self):
        run = subprocess.run(['/usr/bin/python3', str(SCRIPT)], input='broken', text=True, capture_output=True)
        self.assertEqual(run.returncode, 0)
        self.assertEqual(json.loads(run.stdout), {})

    def test_null_session_writes_no_event(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = self.run_hook(dict(hook_event_name='Stop', session_id=None), tmp)
            self.assertEqual(run.returncode, 0)
            self.assertEqual(json.loads(run.stdout), {})
            self.assertEqual(list((Path(tmp) / 'inbox').glob('*.json')), [])


if __name__ == '__main__':
    unittest.main()
