#!/usr/bin/env python3

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import run_gpui_smoke


class SmokeEvidenceTests(unittest.TestCase):
    def test_failure_record_contains_bounded_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            record = Path(directory) / "failure.json"
            argv = ["run_gpui_smoke.py", "missing", "--failure-record", str(record)]
            completed = type("Completed", (), {"returncode": -1073741819})()
            with patch.object(sys, "argv", argv):
                with patch.object(run_gpui_smoke.subprocess, "run", return_value=completed):
                    self.assertEqual(run_gpui_smoke.main(), -1073741819)
            written = json.loads(record.read_text(encoding="utf-8"))
            self.assertEqual(written["case"], "native-gpui-smoke")
            self.assertEqual(written["outcome"], "process_exit")
            self.assertEqual(written["exit_status"], "0xC0000005")
            self.assertNotIn("executable", written)


if __name__ == "__main__":
    unittest.main()
