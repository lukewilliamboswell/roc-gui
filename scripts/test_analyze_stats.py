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
                CREATE TABLE runs(id INTEGER PRIMARY KEY, phase TEXT);
                CREATE TABLE cycles(run_id INTEGER, trigger TEXT, duration_ns INTEGER, measurement_phase TEXT);
                CREATE TABLE steps(run_id INTEGER, expected_count INTEGER, observed_count INTEGER);
                CREATE TABLE recorder_health(id INTEGER PRIMARY KEY, omitted_events INTEGER,
                                             writer_failed INTEGER, output_limited INTEGER);
                INSERT INTO recorder_health VALUES (1, 0, 0, 0);
                """
            )
            metadata = {"schema_version": "4", "clean_shutdown": "1", "final_state": "complete",
                        "spec_name": "case", "benchmark_scale": "100",
                        "benchmark_initial_size": "0", "benchmark_change_size": "100"}
            database.executemany("INSERT INTO metadata VALUES (?,?)", metadata.items())
            database.executemany("INSERT INTO measurement_status VALUES (?,?,?)", [
                ("host_cycles", "complete", "recorded"),
                ("scale_verification", "complete", "recorded"),
            ])
            for run_id, duration in enumerate(durations, 1):
                database.execute("INSERT INTO runs VALUES (?, 'sample')", (run_id,))
                database.execute("INSERT INTO cycles VALUES (?, 'click', ?, 'measured')", (run_id, duration))
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


if __name__ == "__main__":
    unittest.main()
