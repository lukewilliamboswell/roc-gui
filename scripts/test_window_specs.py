#!/usr/bin/env python3
"""Unit tests for the window specification driver."""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import run_window_specs
from run_window_specs import ROOT, WindowCase, command, discover


class DiscoveryTests(unittest.TestCase):
    def test_finds_window_specs_and_not_semantic_specs(self) -> None:
        cases = discover([], Path("/tmp/out"))
        self.assertTrue(cases, "expected at least one committed window spec")
        for case in cases:
            self.assertEqual(case.spec.parent.name, "window-specs")
            self.assertTrue(case.app.is_file())

    def test_semantic_specs_are_never_window_cases(self) -> None:
        discovered = {case.spec for case in discover([], Path("/tmp/out"))}
        semantic = set(ROOT.glob("examples/*/specs/*.scm"))
        self.assertFalse(discovered & semantic)

    def test_patterns_filter(self) -> None:
        cases = discover(["examples/counter/window-specs/*.scm"], Path("/tmp/out"))
        self.assertTrue(cases)
        for case in cases:
            self.assertEqual(case.app.parent.name, "counter")
        self.assertEqual(discover(["examples/nope/**"], Path("/tmp/out")), [])


class CommandTests(unittest.TestCase):
    def case(self, output: Path) -> WindowCase:
        return WindowCase(
            spec=ROOT / "examples/counter/window-specs/layout.scm",
            app=ROOT / "examples/counter/main.roc",
            executable=output / "bin" / "counter",
            output=output / "counter" / "layout",
        )

    def test_command_carries_the_window_flags(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            case = self.case(Path(directory))
            arguments = command(case, allow_missing_shots=False)
            self.assertIn("--host-run-window-spec", arguments)
            self.assertIn(f"--host-window-report={case.report}", arguments)
            self.assertIn(f"--host-window-shot-dir={case.output}", arguments)
            self.assertNotIn("--host-window-allow-missing-shots", arguments)

    def test_allow_missing_shots_is_opt_in(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            arguments = command(self.case(Path(directory)), allow_missing_shots=True)
            self.assertIn("--host-window-allow-missing-shots", arguments)


class ReportTests(unittest.TestCase):
    def test_failing_steps_and_screenshots_are_printed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            case = WindowCase(
                spec=ROOT / "examples/counter/window-specs/layout.scm",
                app=ROOT / "examples/counter/main.roc",
                executable=output / "bin" / "counter",
                output=output,
            )
            case.report.write_text(
                json.dumps(
                    {
                        "outcome": "fail",
                        "steps": [
                            {"ordinal": 0, "kind": "settle", "status": "pass"},
                            {
                                "ordinal": 1,
                                "kind": "expect-on-screen",
                                "status": "fail",
                                "message": "line 4: (text \"x\") is not on screen",
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )
            (output / "00-initial.png").write_bytes(b"\x89PNG\r\n\x1a\n")
            captured = io.StringIO()
            with contextlib.redirect_stdout(captured):
                run_window_specs.report_failure(case)
            joined = captured.getvalue()
            self.assertIn("is not on screen", joined)
            self.assertIn("00-initial.png", joined)

    def test_a_missing_report_is_reported_not_raised(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            case = WindowCase(
                spec=ROOT / "examples/counter/window-specs/layout.scm",
                app=ROOT / "examples/counter/main.roc",
                executable=output / "bin" / "counter",
                output=output / "missing",
            )
            captured = io.StringIO()
            with contextlib.redirect_stdout(captured):
                run_window_specs.report_failure(case)
            self.assertIn("no report written", captured.getvalue())


if __name__ == "__main__":
    unittest.main()
