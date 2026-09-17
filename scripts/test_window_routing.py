#!/usr/bin/env python3
"""Unit tests for window-specification routing in the specification driver."""

from __future__ import annotations

import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import run_specs
from run_specs import ROOT, Case, discover, report_window_failure, window_artifacts


class ApplicationBuildTests(unittest.TestCase):
    def test_application_backend_is_explicit_and_does_not_depend_on_app_name(self) -> None:
        for requested, expected in ((None, "dev"), ("speed", "speed")):
            with self.subTest(mode=requested), tempfile.TemporaryDirectory() as temporary:
                cases = discover(["examples/counter/specs/counting.scm"], Path(temporary))
                with patch.object(run_specs.subprocess, "run") as run:
                    if requested is None:
                        run_specs.build(cases, "selected-roc", True)
                    else:
                        run_specs.build(cases, "selected-roc", True, requested)
                compiler_calls = [call.args[0] for call in run.call_args_list
                                  if call.args[0][0] == "selected-roc"]
                self.assertEqual(len(compiler_calls), 1)
                self.assertIn(f"--opt={expected}", compiler_calls[0])

    def test_failed_diagnostic_build_does_not_retry_another_backend(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            cases = discover(["examples/counter/specs/counting.scm"], Path(temporary))
            failure = subprocess.CalledProcessError(1, ["selected-roc", "build"])
            with patch.object(run_specs.subprocess, "run", side_effect=[None, failure]) as run:
                with self.assertRaises(subprocess.CalledProcessError):
                    run_specs.build(cases, "selected-roc", True, "speed")
            self.assertEqual(run.call_count, 2)


class DiscoveryTests(unittest.TestCase):
    def test_one_directory_holds_both_kinds_of_spec(self) -> None:
        cases = discover(["examples/counter/specs/*.scm"], Path("/tmp/out"))
        stems = {case.spec.stem for case in cases}
        # A semantic case and window cases, discovered together.
        self.assertIn("counting", stems)
        self.assertIn("pointer", stems)
        for case in cases:
            self.assertEqual(case.spec.parent.name, "specs")

    def test_stems_are_unique_within_an_app(self) -> None:
        """Fixtures are keyed by stem under the app directory, so a duplicate
        stem would silently share another case's fixtures."""
        for app in sorted(ROOT.glob("examples/*/specs")):
            stems = [spec.stem for spec in app.glob("*.scm")]
            self.assertEqual(
                len(stems), len(set(stems)), f"duplicate spec stem in {app}"
            )

    def test_exclusions_apply_after_inclusions(self) -> None:
        cases = discover(
            ["examples/*/specs/gallery.scm"],
            Path("/tmp/out"),
            ["examples/image-library/specs/gallery.scm"],
        )
        paths = {case.spec.relative_to(ROOT).as_posix() for case in cases}
        self.assertNotIn("examples/image-library/specs/gallery.scm", paths)
        self.assertIn("examples/animation-studio/specs/gallery.scm", paths)


class ArtifactTests(unittest.TestCase):
    def case(self, output: Path) -> Case:
        return Case(
            spec=ROOT / "examples/counter/specs/pointer.scm",
            app=ROOT / "examples/counter/main.roc",
            executable=output / "bin" / "counter",
            capture=output / "examples/counter/specs/pointer.rgstats",
        )

    def test_window_artifacts_sit_beside_the_capture_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            case = self.case(Path(directory))
            artifacts = window_artifacts(case)
            self.assertEqual(artifacts.name, "pointer")
            self.assertEqual(artifacts.parent, case.capture.parent)

    def test_failure_record_has_only_relative_identity_and_bounded_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            case = self.case(Path(directory))
            captured = io.StringIO()
            with patch.object(run_specs.time, "monotonic", return_value=15.25):
                with contextlib.redirect_stdout(captured):
                    result = run_specs.finish_case(
                        case, 10.0, "window", "process_exit", "private diagnostic", -1073741819
                    )
            self.assertEqual(result, (case, "private diagnostic"))
            record = json.loads(run_specs.failure_record(case).read_text(encoding="utf-8"))
            self.assertEqual(record["spec"], "examples/counter/specs/pointer.scm")
            self.assertEqual(record["application"], "examples/counter/main.roc")
            self.assertEqual(record["elapsed_seconds"], 5.25)
            self.assertEqual(record["exit_status"], "0xC0000005")
            self.assertNotIn("private diagnostic", json.dumps(record))
            self.assertIn("elapsed=5.250s", captured.getvalue())

    def test_debugger_text_removes_runner_and_user_identity(self) -> None:
        private = (
            r"C:\Users\alice\project\app.exe "
            r"D:\a\roc-gui\roc-gui\source\main.roc "
            r"D:\a\_temp\native.exe "
            + str(ROOT / "platform/main.roc")
        )
        sanitized = run_specs.sanitize_debugger_output(private)
        self.assertNotIn("alice", sanitized)
        self.assertNotIn(str(ROOT), sanitized)
        self.assertNotIn(r"D:\a", sanitized)
        self.assertIn("C:/Users/user", sanitized)
        self.assertIn("/workspace/platform/main.roc", sanitized)


class ReportTests(unittest.TestCase):
    def test_failing_steps_and_screenshots_are_printed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            (artifacts / "report.json").write_text(
                json.dumps(
                    {
                        "outcome": "fail",
                        "steps": [
                            {"ordinal": 0, "kind": "settle", "status": "pass"},
                            {
                                "ordinal": 1,
                                "kind": "expect-on-screen",
                                "status": "fail",
                                "message": 'line 4: (text "x") is not on screen',
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )
            (artifacts / "00-initial.png").write_bytes(b"\x89PNG\r\n\x1a\n")
            captured = io.StringIO()
            with contextlib.redirect_stderr(captured):
                report_window_failure(artifacts)
            printed = captured.getvalue()
            self.assertIn("is not on screen", printed)
            self.assertIn("00-initial.png", printed)

    def test_an_unavailable_screenshot_is_surfaced(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            (artifacts / "report.json").write_text(
                json.dumps(
                    {
                        "outcome": "pass",
                        "steps": [
                            {
                                "ordinal": 0,
                                "kind": "screenshot",
                                "status": "unavailable",
                                "message": "screenshot unavailable (tool_missing)",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            captured = io.StringIO()
            with contextlib.redirect_stderr(captured):
                report_window_failure(artifacts)
            self.assertIn("tool_missing", captured.getvalue())

    def test_a_missing_report_is_reported_not_raised(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            captured = io.StringIO()
            with contextlib.redirect_stderr(captured):
                report_window_failure(Path(directory) / "absent")
            self.assertIn("no report written", captured.getvalue())


class DescriptionTests(unittest.TestCase):
    def test_description_requires_a_built_executable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            case = Case(
                spec=ROOT / "examples/counter/specs/counting.scm",
                app=ROOT / "examples/counter/main.roc",
                executable=Path(directory) / "bin" / "counter",
                capture=Path(directory) / "counting.rgstats",
            )
            with self.assertRaises(RuntimeError):
                run_specs.describe([case])


if __name__ == "__main__":
    unittest.main()
