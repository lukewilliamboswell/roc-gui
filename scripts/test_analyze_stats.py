import sqlite3
import tempfile
import unittest
from pathlib import Path

from scripts import analyze_stats


class ScalingAaBoundTests(unittest.TestCase):
    def capture(self, directory: Path, name: str, durations: tuple[int, ...]) -> Path:
        path = directory / name
        with sqlite3.connect(path) as database:
            database.executescript(
                """
                CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT);
                CREATE TABLE measurement_status(name TEXT PRIMARY KEY, status TEXT, reason TEXT);
                CREATE TABLE runs(id INTEGER PRIMARY KEY, phase TEXT, ended_ns INTEGER,
                  start_roc_alloc_requested_bytes INTEGER, end_roc_alloc_requested_bytes INTEGER);
                CREATE TABLE cycles(id INTEGER PRIMARY KEY, run_id INTEGER, trigger TEXT,
                  duration_ns INTEGER, roc_callback_ns INTEGER, validate_ns INTEGER,
                  graph_apply_ns INTEGER, measurement_phase TEXT);
                CREATE TABLE roc_work_spans(cycle_id INTEGER, allocated_bytes INTEGER);
                CREATE TABLE steps(run_id INTEGER, expected_count INTEGER, observed_count INTEGER);
                CREATE TABLE recorder_health(id INTEGER PRIMARY KEY, omitted_events INTEGER,
                                             writer_failed INTEGER, output_limited INTEGER);
                INSERT INTO recorder_health VALUES (1, 0, 0, 0);
                """
            )
            metadata = {"schema_version": "5", "clean_shutdown": "1", "final_state": "complete",
                        "spec_name": "case", "benchmark_scale": "100",
                        "benchmark_initial_size": "0", "benchmark_change_size": "100",
                        "app_name": "app", "executable_hash": "same-executable",
                        "backend": "semantic-headless", "target_profile": "release",
                        "host_os": "linux", "host_arch": "x86_64", "cpu_model": "test cpu",
                        "logical_cpu_count": "1", "requested_detail": "summary", "job_count": "1",
                        "timing_quality": "isolated"}
            database.executemany("INSERT INTO metadata VALUES (?,?)", metadata.items())
            database.executemany("INSERT INTO measurement_status VALUES (?,?,?)", [
                ("host_cycles", "complete", "recorded"),
                ("scale_verification", "complete", "recorded"),
                ("roc_work_spans", "complete", "recorded"),
                ("roc_allocations", "complete", "recorded"),
            ])
            for run_id, duration in enumerate(durations, 1):
                database.execute("INSERT INTO runs VALUES (?, 'sample', 1, 0, ?)", (run_id, duration * 10))
                database.execute(
                    "INSERT INTO cycles VALUES (?, ?, 'click', ?, ?, ?, ?, 'measured')",
                    (run_id, run_id, duration, duration * 2, duration * 3, duration * 4),
                )
                database.execute("INSERT INTO roc_work_spans VALUES (?, ?)", (run_id, duration * 5))
                database.execute("INSERT INTO steps VALUES (?, 100, 100)", (run_id,))
        return path

    def test_bound_is_unavailable_without_aa_capture(self):
        with tempfile.TemporaryDirectory() as temporary:
            capture = self.capture(Path(temporary), "capture.db", (10, 30))
            output = analyze_stats.perspective(capture, "scaling")
            self.assertIn("aa_bound_ns\tspread_exceeds_aa_bound", output)
            self.assertTrue(output.endswith("\tNULL\tNULL"))

    def test_scaling_flags_spread_above_validated_aa_bound(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            capture = self.capture(directory, "capture.db", (10, 40))
            aa = self.capture(directory, "aa.db", (10, 20))
            output = analyze_stats.perspective(capture, "scaling", aa)
            self.assertTrue(output.endswith("\t10\t1"))

    def test_cross_scale_reports_independent_component_and_allocation_ratios(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            base = self.capture(directory, "base.db", (10, 20))
            scaled = self.capture(directory, "scaled.db", (30, 60))
            with sqlite3.connect(scaled) as database:
                database.execute("UPDATE metadata SET value='300' WHERE key='benchmark_scale'")
            output = analyze_stats.scaling_compare(base, scaled)
            header, values = output.splitlines()[1:3]
            row = dict(zip(header.split("\t"), values.split("\t")))
            self.assertEqual(row["evidence_status"], "complete")
            self.assertEqual(row["callback_ratio"], "3.0")
            self.assertEqual(row["validation_ratio"], "3.0")
            self.assertEqual(row["graph_ratio"], "3.0")
            self.assertEqual(row["lifecycle_allocation_ratio"], "3.0")
            self.assertEqual(row["span_allocation_ratio"], "3.0")
            self.assertIn("complete sample lifecycle", row["lifecycle_allocation_scope"])
            self.assertIn("measured Roc work spans", row["span_allocation_scope"])

    def test_cross_scale_withholds_only_the_component_with_incomplete_evidence(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            base = self.capture(directory, "base.db", (10, 20))
            scaled = self.capture(directory, "scaled.db", (30, 60))
            with sqlite3.connect(scaled) as database:
                database.execute("UPDATE metadata SET value='300' WHERE key='benchmark_scale'")
                database.execute(
                    "UPDATE measurement_status SET status='partial',reason='span loss' "
                    "WHERE name='roc_work_spans'"
                )
            output = analyze_stats.scaling_compare(base, scaled)
            header, values = output.splitlines()[1:3]
            row = dict(zip(header.split("\t"), values.split("\t")))
            self.assertEqual(row["callback_ratio"], "3.0")
            self.assertEqual(row["validation_ratio"], "3.0")
            self.assertEqual(row["graph_ratio"], "3.0")
            self.assertEqual(row["lifecycle_allocation_ratio"], "3.0")
            self.assertEqual(row["span_allocation_ratio"], "NULL")
            self.assertEqual(row["scaled_span_status"], "partial")
            self.assertEqual(row["scaled_span_reason"], "span loss")

    def test_cross_scale_rejects_a_different_executable(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            base = self.capture(directory, "base.db", (10, 20))
            scaled = self.capture(directory, "scaled.db", (30, 60))
            with sqlite3.connect(scaled) as database:
                database.execute("UPDATE metadata SET value='300' WHERE key='benchmark_scale'")
                database.execute("UPDATE metadata SET value='other' WHERE key='executable_hash'")
            output = analyze_stats.scaling_compare(base, scaled)
            header, values = output.splitlines()[1:3]
            row = dict(zip(header.split("\t"), values.split("\t")))
            self.assertEqual(row["evidence_status"], "unavailable")
            self.assertEqual(row["callback_ratio"], "NULL")
            self.assertEqual(row["validation_ratio"], "NULL")
            self.assertEqual(row["graph_ratio"], "NULL")
            self.assertEqual(row["lifecycle_allocation_ratio"], "NULL")
            self.assertEqual(row["span_allocation_ratio"], "NULL")


if __name__ == "__main__":
    unittest.main()
