"""Safety checks for the shell installer/remover used outside the MIRA UI."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / "scripts" / "install-dsh-bridge.sh"
UNINSTALL = ROOT / "scripts" / "uninstall-dsh-bridge.sh"

BLOCK = (
    "# MIRA bridge (added by scripts/install-dsh-bridge.sh)\n"
    "- insert:\n"
    "    - id: mira-bridge\n"
    "      name: './plugins/mira-bridge/index.js'\n"
)


class DshBridgeScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.profile = self.home / "profiles" / "desktop"
        self.profile.mkdir(parents=True)
        (self.profile / "package.json").write_text("{}", encoding="utf-8")
        self.patch = self.profile / "cordis.patch.yml"
        self.plugin = self.profile / "plugins" / "mira-bridge"
        self.env = {**os.environ, "DSH_HOME": str(self.home)}

    def tearDown(self):
        # A refused test may leave the patch unreadable; restore modes first.
        for path in [self.patch, *self.profile.rglob("*")]:
            try:
                os.chmod(path, 0o755 if path.is_dir() else 0o644)
            except OSError:
                pass
        self.temp.cleanup()

    def run_script(self, script):
        return subprocess.run(
            ["bash", str(script)],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_install_creates_missing_patch_like_the_app(self):
        self.assertFalse(self.patch.exists())
        result = self.run_script(INSTALL)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.patch.read_text(encoding="utf-8")
        self.assertIn("id: mira-bridge", text)
        self.assertTrue((self.plugin / "index.js").is_file())
        self.assertTrue((self.plugin / "entry.js").is_file())
        self.assertTrue((self.plugin / "emit.js").is_file(), "the shared emitter ships with the bridge")

        again = self.run_script(INSTALL)
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(
            self.patch.read_text(encoding="utf-8").count("- id: mira-bridge"),
            1,
            "installing twice must not duplicate the row",
        )

    def test_reinstall_refreshes_the_plugin_files(self):
        self.assertEqual(self.run_script(INSTALL).returncode, 0)
        target = self.plugin / "entry.js"
        target.write_text("// stale copy without a version marker\n", encoding="utf-8")
        again = self.run_script(INSTALL)
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(target.read_text(encoding="utf-8"),
                         (ROOT / "integrations" / "dsh" / "entry.js").read_text(encoding="utf-8"),
                         "re-running the installer refreshes an already installed plugin")
        self.assertIn("ADAPTER_VERSION", (self.plugin / "emit.js").read_text(encoding="utf-8"))
        self.assertEqual(
            self.patch.read_text(encoding="utf-8").count("- id: mira-bridge"),
            1,
            "refreshing files leaves the patch layer untouched",
        )

    def test_uninstall_round_trip_keeps_other_config(self):
        self.patch.write_text("prefs:\n  theme: light\n", encoding="utf-8")
        self.assertEqual(self.run_script(INSTALL).returncode, 0)
        result = self.run_script(UNINSTALL)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.plugin.exists())
        self.assertEqual(
            self.patch.read_text(encoding="utf-8").strip(),
            "prefs:\n  theme: light",
            "unrelated rows survive the round trip",
        )
        self.assertTrue(any(".mira-backup-" in path.name for path in self.profile.iterdir()))

    def test_uninstall_accepts_the_app_block(self):
        app_block = (
            "# MIRA bridge (added by MIRA)\n"
            "- insert:\n"
            "    - id: mira-bridge\n"
            "      name: './plugins/mira-bridge/index.js'\n"
        )
        self.patch.write_text(app_block, encoding="utf-8")
        self.plugin.mkdir(parents=True)
        (self.plugin / "index.js").write_text("// bridge", encoding="utf-8")
        result = self.run_script(UNINSTALL)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.plugin.exists())
        self.assertNotIn("mira-bridge", self.patch.read_text(encoding="utf-8"))

    @unittest.skipIf(os.geteuid() == 0, "root can read mode-000 files")
    def test_unreadable_patch_is_refused_without_deleting_the_plugin(self):
        self.patch.write_text(BLOCK, encoding="utf-8")
        self.plugin.mkdir(parents=True)
        (self.plugin / "index.js").write_text("// bridge", encoding="utf-8")
        os.chmod(self.patch, 0)

        result = self.run_script(UNINSTALL)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("无法读取", result.stderr)
        self.assertTrue((self.plugin / "index.js").is_file(), "unreadable patch must not cost the plugin")

        install = self.run_script(INSTALL)
        self.assertNotEqual(install.returncode, 0, "install must also refuse an unreadable patch")
        self.assertIn("无法读取", install.stderr)

    def test_leftover_quoted_row_is_refused_without_deleting_the_plugin(self):
        original = (
            BLOCK
            + "\ncustom:\n  - id: \"mira-bridge\"\n    name: './plugins/mira-bridge/index.js'\n"
        )
        self.patch.write_text(original, encoding="utf-8")
        self.plugin.mkdir(parents=True)
        (self.plugin / "index.js").write_text("// bridge", encoding="utf-8")

        result = self.run_script(UNINSTALL)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("残留", result.stderr)
        self.assertTrue((self.plugin / "index.js").is_file())
        self.assertEqual(
            self.patch.read_text(encoding="utf-8"),
            original,
            "a refused removal must leave the patch untouched",
        )

    def test_unknown_block_is_refused_without_deleting_the_plugin(self):
        original = "custom:\n  - id: mira-bridge\n    name: './plugins/mira-bridge/index.js'\n"
        self.patch.write_text(original, encoding="utf-8")
        self.plugin.mkdir(parents=True)
        (self.plugin / "index.js").write_text("// bridge", encoding="utf-8")

        result = self.run_script(UNINSTALL)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("不是已知格式", result.stderr)
        self.assertTrue((self.plugin / "index.js").is_file())
        self.assertEqual(self.patch.read_text(encoding="utf-8"), original)

    def test_quoted_id_with_comment_is_detected_without_rewriting_patch(self):
        original = b'- insert:\r\n    - id: "mira-bridge" # custom\r\n'
        self.patch.write_bytes(original)
        self.assertEqual(self.run_script(INSTALL).returncode, 0)
        self.assertEqual(self.patch.read_bytes(), original)
        self.assertNotEqual(self.run_script(UNINSTALL).returncode, 0)
        self.assertTrue(self.plugin.exists())

    def test_commented_out_row_is_not_a_connection(self):
        original = b"# - id: mira-bridge\r\n"
        self.patch.write_bytes(original)
        self.assertEqual(self.run_script(INSTALL).returncode, 0)
        self.assertIn(b"    - id: mira-bridge\r\n", self.patch.read_bytes())
        self.assertEqual(self.run_script(UNINSTALL).returncode, 0)
        self.assertEqual(self.patch.read_bytes(), original)

    def test_disabled_layer_keeps_its_comments_when_enabled(self):
        self.patch.write_bytes(b"---\r\n# keep\r\n[] # disabled\r\n")
        self.assertEqual(self.run_script(INSTALL).returncode, 0)
        self.assertTrue(self.patch.read_bytes().startswith(b"---\r\n# keep\r\n# disabled\r\n"))
        self.assertNotIn(b"[]", self.patch.read_bytes())

    def test_invalid_patch_does_not_modify_existing_plugin(self):
        self.plugin.mkdir(parents=True)
        index = self.plugin / "index.js"
        index.write_bytes(b"previous")
        self.patch.write_bytes(b"\xff")
        self.assertNotEqual(self.run_script(INSTALL).returncode, 0)
        self.assertEqual(index.read_bytes(), b"previous")
        self.assertEqual(self.patch.read_bytes(), b"\xff")

    @unittest.skipIf(os.geteuid() == 0, "root can write a read-only profile")
    def test_failed_patch_publication_restores_existing_plugin(self):
        self.plugin.mkdir(parents=True)
        index = self.plugin / "index.js"
        index.write_bytes(b"previous")
        self.profile.chmod(0o500)
        try:
            result = self.run_script(INSTALL)
        finally:
            self.profile.chmod(0o700)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.patch.exists())
        self.assertEqual(index.read_bytes(), b"previous")
        self.assertEqual(list(self.plugin.parent.iterdir()), [self.plugin])


if __name__ == "__main__":
    unittest.main()
