"""The Python and Node emitters must produce byte-equivalent contract JSON."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
EMITTER = ROOT / 'integrations/emit/mira_emit.py'
NODE = shutil.which('node')

spec = importlib.util.spec_from_file_location('mira_emit', EMITTER)
emitter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(emitter)

TIME = 1_764_000_000_123
EVENT = {
    'adapter': 'Demo',
    'name': 'Demo Tool',
    'kind': 'approval.asked',
    'session': 's-1',
    'turn': 2,
    'requiresPlanCheck': False,
    'cwd': '/Users/x/MIRA',
    'hint': '# 任务：整理记录\n\n第二段不出现',
    'reason': '需要写入',
    'link': 'dsh://open',
    'dedupeKey': 'approval:s-1:a1',
    'approval': {'token': 'abcd-1234', 'ttlMs': 60000, 'tool': 'bash', 'reason': '写文件'},
    'questions': [{'id': 'q1', 'question': '选哪个？', 'header': '选择'}],
    'ignored': 'dropped',
}

NODE_SCRIPT = """
const { emit } = require(process.argv[1]);
emit(process.argv[2], JSON.parse(process.argv[3]), Number(process.argv[4]));
"""


@unittest.skipUnless(NODE, 'node is required for cross-language parity')
class ParityTests(unittest.TestCase):
    def test_emitters_agree(self):
        with tempfile.TemporaryDirectory() as python_dir, tempfile.TemporaryDirectory() as node_dir:
            py_path = emitter.deliver(EVENT, python_dir, now_ms=TIME)
            run = subprocess.run([NODE, '-e', NODE_SCRIPT, str(ROOT / 'integrations/emit/emit.js'),
                                  node_dir, json.dumps(EVENT), str(TIME)],
                                 capture_output=True, text=True, timeout=30)
            self.assertEqual(run.returncode, 0, run.stderr)
            node_path = next((Path(node_dir) / 'inbox').glob('*.json'))
            py_payload = json.loads(py_path.read_text(encoding='utf-8'))
            node_payload = json.loads(node_path.read_text(encoding='utf-8'))
            self.assertEqual(py_payload, node_payload)

    def test_both_reject_incomplete_events(self):
        with tempfile.TemporaryDirectory() as node_dir:
            run = subprocess.run([NODE, '-e', NODE_SCRIPT, str(ROOT / 'integrations/emit/emit.js'),
                                  node_dir, json.dumps({'kind': 'turn.end'}), str(TIME)],
                                 capture_output=True, text=True, timeout=30)
            self.assertNotEqual(run.returncode, 0)
            self.assertIn('adapter', run.stderr)
        with self.assertRaises(ValueError):
            emitter.build({'kind': 'turn.end'}, TIME)


if __name__ == '__main__':
    unittest.main()
