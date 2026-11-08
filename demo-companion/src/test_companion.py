"""Standard-library regression tests; no setup, restoration or sample launches."""
import copy
import json
import subprocess
import sys
import unittest

import check_site
import sources as S
import validate_content
from render import ROOT, code_block, new_ctx


class CompanionTests(unittest.TestCase):
    def test_complete_content_gate(self):
        self.assertEqual(validate_content.validate(require_all=True), [])

    def test_all_emitted_assets_links_and_sources(self):
        errors, not_run = check_site.check()
        self.assertEqual(errors, [])
        self.assertEqual(not_run, [])

    def test_named_source_registry_is_complete_and_unique(self):
        blocks = S.file_blocks()
        self.assertEqual(len(blocks), 40)
        self.assertEqual(len(S.prompts()[0]), 6)
        self.assertTrue(all(block["text"] and block["source"] for block in blocks.values()))

    def test_invalid_task_picker_is_rejected(self):
        binding = {"label": "Preflight", "inputs": {"httpsTimeoutSeconds": "99"}}
        with self.assertRaisesRegex(ValueError, "invalid picker"):
            S._task_text(binding, S.source_text(".vscode\\tasks.json"))

    def test_unused_task_override_is_rejected(self):
        binding = {"label": "Verify", "inputs": {"unknown-input": "value"}}
        with self.assertRaisesRegex(ValueError, "unused input"):
            S._task_text(binding, S.source_text(".vscode\\tasks.json"))

    def test_unsupported_switch_is_rejected(self):
        definition = copy.deepcopy(S.file_blocks()["verify-json"])
        definition["bound"]["switches"][0]["name"] = "UnsupportedSyntheticSwitch"
        with self.assertRaisesRegex(ValueError, "not declared"):
            S._bind(definition)

    def test_invented_source_line_is_rejected(self):
        definition = copy.deepcopy(S.file_blocks()["git-status"])
        definition["bound"]["text"] = "__synthetic_nonexistent_command__"
        with self.assertRaisesRegex(ValueError, "not found verbatim"):
            S._bind(definition)

    def test_duplicate_json_keys_fail_closed(self):
        class Text:
            def read_text(self, encoding):
                return '{"synthetic": 1, "synthetic": 2}'
        with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
            validate_content.read_json(Text())

    def test_paths_cannot_escape_source_root(self):
        for path in ("..\\outside", "C:\\outside", "\\absolute", "docs\\..\\outside"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                S.relative_path(path)

    def test_copyable_html_preserves_characters_and_line_breaks(self):
        text = 'synthetic <value> & "quoted"\nsecond line'
        output = code_block({"label": "Synthetic parser fixture", "lang": "text", "actor": "file", "text": text}, "index", new_ctx())
        page = check_site.Page()
        page.feed(output)
        self.assertEqual(page.codes, [text])

    def test_placeholder_stays_explicit_and_source_integrity_is_lossless(self):
        block = S.file_blocks()["deploy-dispatch"]
        output = code_block(block, "index", new_ctx())
        self.assertIn("&lt;reviewed-main-sha&gt;", output)
        page = check_site.Page()
        page.feed(output)
        self.assertEqual(page.codes, [block["text"]])
        self.assertEqual(block["placeholders"][0]["max_length"], 40)

    def test_dispatch_has_no_dated_sha_default(self):
        text = S.file_blocks()["deploy-dispatch"]["text"]
        self.assertIn("{{ph:reviewed-main-sha}}", text)
        self.assertNotIn(S.PIN, text)
        self.assertIn("-Confirm", text)

    def test_current_source_task_ports_are_exact(self):
        self.assertIn("-Port 8081", S.file_blocks()["run-java-local"]["text"])
        self.assertIn("-Port 8082", S.file_blocks()["run-go-local"]["text"])
        self.assertNotIn("RunContainer", S.file_blocks()["run-python-local"]["text"])

    def test_local_agent_kickoffs_are_source_bound_not_execution(self):
        for identifier, start in (
            ("prompt-workstation-start", "Start the local setup and demo journey."),
            ("prompt-workstation-resume", "Resume the local setup and demo journey."),
        ):
            block = S.file_blocks()[identifier]
            self.assertEqual(block["actor"], "copilot")
            self.assertTrue(block["text"].startswith(start))
            self.assertEqual(block["source"], [{"path": "docs\\SETUP.md"}])
        page = (ROOT / "pages" / "setup" / "setup-modules.html").read_text(encoding="utf-8")
        self.assertIn("Live VS Code selection/tool/native-confirmation acceptance is not yet proven", page)
        verify = (ROOT / "pages" / "setup" / "setup-verify.html").read_text(encoding="utf-8")
        for boundary in ("Missing/unusable", "every other default row positively PASS", "Malformed/unusable JSON", "Container=false"):
            self.assertIn(boundary, verify)

    def test_regeneration_is_byte_deterministic(self):
        files = sorted(ROOT.rglob("*.html")) + sorted((ROOT / "data").glob("*.js")) + [S.LOCK]
        before = {file: file.read_bytes() for file in files}
        result = subprocess.run([sys.executable, "-B", str(ROOT / "src" / "build.py"), "--strict"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual({file: file.read_bytes() for file in files}, before)

    def test_evidence_is_dated_underlying_revision_not_live_polling(self):
        evidence = json.loads((ROOT / "src" / "content" / "evidence.json").read_text(encoding="utf-8"))
        self.assertEqual({run["branch"] for run in evidence["runs"]}, {"main", "demo-complete"})
        self.assertTrue(all(run["observed_at"] and len(run["jobs"]) == 9 for run in evidence["runs"]))
        self.assertIn("not a continuously polled state", evidence["scope"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
