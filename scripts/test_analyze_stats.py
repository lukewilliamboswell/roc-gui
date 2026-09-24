import sqlite3
import tempfile
import unittest
from pathlib import Path

from scripts import analyze_stats, run_specs, summarize_suite


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
            metadata = {"schema_version": "25", "clean_shutdown": "1", "final_state": "complete",
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

    def comparison_capture(self, directory: Path, name: str, durations: tuple[int, ...]) -> Path:
        path = self.capture(directory, name, durations)
        with sqlite3.connect(path) as database:
            database.executemany("INSERT INTO metadata VALUES (?,?)", [
                ("spec_hash", "same-spec"), ("benchmark_samples", "1"),
                ("benchmark_iterations", "1"), ("buffer_mib", "16"),
            ])
        return path

    def test_legacy_callback_and_native_work_schemas_are_rejected(self):
        for legacy_version in ("11", "12", "13", "14", "15", "16", "17", "18"):
            with self.subTest(schema=legacy_version), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                current = self.comparison_capture(directory, "current.db", (1_000_000,))
                legacy = self.comparison_capture(directory, "legacy.db", (200_000_000,))
                with sqlite3.connect(legacy) as database:
                    database.execute("UPDATE metadata SET value=? WHERE key='schema_version'", (legacy_version,))
                with self.assertRaisesRegex(RuntimeError, "unsupported schema version"):
                    analyze_stats.summary(legacy)
                with self.assertRaisesRegex(RuntimeError, "unsupported schema version"):
                    analyze_stats.perspective(legacy, "native_work")
                with self.assertRaisesRegex(RuntimeError, "unsupported schema"):
                    summarize_suite.summarize(legacy)
                with self.assertRaisesRegex(RuntimeError, "unsupported or missing schema"):
                    run_specs.validate_capture(legacy)
                with sqlite3.connect(current) as database:
                    database.execute("INSERT INTO metadata VALUES ('application_outcome','success')")
                    database.execute("ALTER TABLE runs ADD COLUMN outcome TEXT DEFAULT 'pass'")
                run_specs.validate_capture(current)
                output = analyze_stats.compare(current, legacy)
                self.assertIn("evidence_status=incomparable", output)
                self.assertIn("schema version differs or is unsupported", output)
                self.assertNotIn("median_ratio", output)
                self.assertIn("evidence_status=complete", analyze_stats.compare(current, current))

    def test_comparison_without_measured_cycles_reports_unavailable(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            before = self.comparison_capture(directory, "before.db", ())
            after = self.comparison_capture(directory, "after.db", ())
            output = analyze_stats.compare(before, after)
            self.assertIn("evidence_status=unavailable", output)
            self.assertIn("no measured samples in before and after capture", output)
            self.assertIn("before samples=0 min=unavailable median=unavailable spread=unavailable", output)
            self.assertIn("after samples=0 min=unavailable median=unavailable spread=unavailable", output)
            self.assertIn("median_delta=unavailable median_ratio=unavailable", output)
            self.assertNotIn("0.000ms", output)

    def test_comparison_preserves_available_side_when_other_has_no_samples(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            measured = self.comparison_capture(directory, "measured.db", (1_000_000,))
            absent = self.comparison_capture(directory, "absent.db", ())
            for before, after, side in [(absent, measured, "before"), (measured, absent, "after")]:
                with self.subTest(side=side):
                    output = analyze_stats.compare(before, after)
                    self.assertIn(f"evidence_status=unavailable evidence_reason=no measured samples in {side} capture", output)
                    self.assertIn("samples=1 min=1.000ms median=1.000ms spread=0.000ms", output)
                    self.assertIn("median_delta=unavailable median_ratio=unavailable", output)

    def test_zero_baseline_has_measured_timing_but_no_defined_ratio(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            before = self.comparison_capture(directory, "before.db", (0,))
            after = self.comparison_capture(directory, "after.db", (1_000_000,))
            output = analyze_stats.compare(before, after)
            self.assertIn("evidence_status=complete", output)
            self.assertIn("before samples=1 min=0.000ms median=0.000ms spread=0.000ms", output)
            self.assertIn("median_delta=+1.000ms median_ratio=unavailable", output)

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


class NativeWorkReportTests(unittest.TestCase):
    def capture(self, directory: Path, *, status: str = "complete", frames: int = 2,
                observations: tuple[tuple[int, int, int, int], ...] = ()) -> Path:
        path = directory / "native.rgstats"
        with sqlite3.connect(path) as database:
            database.executescript("""
                CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT);
                CREATE TABLE measurement_status(name TEXT PRIMARY KEY, status TEXT, reason TEXT);
                CREATE TABLE gpui_frames(id INTEGER PRIMARY KEY);
                CREATE TABLE gpui_native_work(
                    frame_id INTEGER NOT NULL REFERENCES gpui_frames(id),
                    metric INTEGER NOT NULL CHECK(metric BETWEEN 0 AND 1),
                    kind INTEGER NOT NULL CHECK(kind BETWEEN 0 AND 19),
                    count INTEGER NOT NULL CHECK(count>0),
                    PRIMARY KEY(frame_id,metric,kind));
                INSERT INTO metadata VALUES ('schema_version','25');
            """)
            database.execute("INSERT INTO measurement_status VALUES ('gpui_native_work',?,?)",
                             (status, "native owner observation"))
            database.executemany("INSERT INTO gpui_frames VALUES (?)",
                                 ((frame,) for frame in range(1, frames + 1)))
            database.executemany("INSERT INTO gpui_native_work VALUES (?,?,?,?)", observations)
        return path

    def rows(self, path: Path) -> list[dict[str, str]]:
        output = analyze_stats.perspective(path, "native_work").splitlines()
        return [dict(zip(output[1].split("\t"), row.split("\t"))) for row in output[2:]]

    def test_native_operations_are_reported_separately_over_all_completed_frames(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = self.capture(Path(temporary), observations=(
                (1, 0, 1, 7), (2, 0, 1, 3),
                (1, 1, 1, 20), (2, 1, 1, 5),
                (1, 0, 5, 1),
            ))
            rows = self.rows(path)
            self.assertEqual(len(rows), 40)
            by_kind = {(row["metric"], row["kind"]): row for row in rows}
            rendered = by_kind["node_view_renders", "button"]
            self.assertEqual(rendered["evidence_status"], "complete")
            self.assertEqual(rendered["recorded_frames"], "2")
            self.assertEqual(rendered["total_count"], "10")
            self.assertEqual(rendered["max_per_frame"], "7")
            self.assertEqual(rendered["mean_per_frame"], "5.0")
            elements = by_kind["view_elements_created", "button"]
            self.assertEqual(elements["total_count"], "25")
            self.assertEqual(elements["mean_per_frame"], "12.5")
            self.assertEqual(by_kind["node_view_renders", "column"]["mean_per_frame"], "0.5")
            self.assertEqual(by_kind["node_view_renders", "image"]["total_count"], "0")

    def test_recorded_frame_with_no_native_work_has_measured_zeros(self):
        with tempfile.TemporaryDirectory() as temporary:
            rows = self.rows(self.capture(Path(temporary), frames=1))
            self.assertTrue(all(row["evidence_status"] == "complete" for row in rows))
            self.assertTrue(all(row["recorded_frames"] == "1" for row in rows))
            self.assertTrue(all(row["total_count"] == "0" and row["max_per_frame"] == "0"
                                and row["mean_per_frame"] == "0.0" for row in rows))

    def test_no_completed_frame_reports_unavailable_not_zero_work(self):
        with tempfile.TemporaryDirectory() as temporary:
            rows = self.rows(self.capture(Path(temporary), frames=0))
            self.assertTrue(all(row["evidence_status"] == "unavailable" for row in rows))
            self.assertTrue(all("no completed GPUI frame" in row["evidence_reason"] for row in rows))
            self.assertTrue(all(row["total_count"] == "NULL" and row["max_per_frame"] == "NULL"
                                and row["mean_per_frame"] == "NULL" for row in rows))

    def test_headless_and_incomplete_observations_do_not_publish_work_totals(self):
        for status in ("not_recorded", "partial", "unavailable", "unfinalized"):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as temporary:
                path = self.capture(Path(temporary), status=status, observations=((1, 0, 1, 7),))
                rows = self.rows(path)
                self.assertTrue(all(row["evidence_status"] == status for row in rows))
                self.assertTrue(all(row["evidence_reason"] == "native owner observation" for row in rows))
                self.assertTrue(all(row["total_count"] == "NULL" and row["max_per_frame"] == "NULL"
                                    and row["mean_per_frame"] == "NULL" for row in rows))

    def test_missing_observation_status_is_unavailable_even_with_native_rows(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = self.capture(Path(temporary), observations=((1, 0, 1, 7),))
            with sqlite3.connect(path) as database:
                database.execute("DELETE FROM measurement_status")
            rows = self.rows(path)
            self.assertTrue(all(row["evidence_status"] == "unavailable" for row in rows))
            self.assertTrue(all(row["total_count"] == "NULL" for row in rows))


class GpuiFrameWorkReportTests(unittest.TestCase):
    def test_replayed_and_fresh_work_are_separate_owner_counts(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "gpui-frame-work.rgstats"
            with sqlite3.connect(path) as database:
                database.executescript("""
                    CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT);
                    CREATE TABLE measurement_status(name TEXT PRIMARY KEY, status TEXT, reason TEXT);
                    CREATE TABLE gpui_frames(id INTEGER PRIMARY KEY);
                    CREATE TABLE gpui_frame_work(frame_id INTEGER, metric INTEGER, count INTEGER,
                                                 PRIMARY KEY(frame_id,metric));
                    INSERT INTO metadata VALUES ('schema_version','25');
                    INSERT INTO measurement_status VALUES
                        ('gpui_frame_work','complete','GPUI owner observation');
                    INSERT INTO gpui_frames VALUES (1),(2);
                    INSERT INTO gpui_frame_work VALUES (1,6,10000),(2,6,9999);
                    INSERT INTO gpui_frame_work VALUES (1,12,4),(2,12,3);
                """)
            output = analyze_stats.perspective(path, "gpui_frame_work").splitlines()
            rows = {
                row["metric"]: row
                for row in (
                    dict(zip(output[1].split("\t"), line.split("\t")))
                    for line in output[2:]
                )
            }
            self.assertEqual(rows["replayed_scene_operations"]["total_count"], "19999")
            self.assertEqual(rows["fresh_hitboxes"]["max_per_frame"], "4")


class TimelineReportTests(unittest.TestCase):
    def capture(self, directory: Path, frame_status: str) -> Path:
        path = directory / "timeline.rgstats"
        with sqlite3.connect(path) as database:
            database.executescript("""
                CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT);
                CREATE TABLE measurement_status(name TEXT PRIMARY KEY, status TEXT, reason TEXT);
                CREATE TABLE cycles(id INTEGER PRIMARY KEY, start_ns INTEGER, end_ns INTEGER);
                CREATE TABLE gpui_frames(id INTEGER PRIMARY KEY, start_ns INTEGER, end_ns INTEGER);
                CREATE TABLE gpui_frame_cycles(frame_id INTEGER, cycle_id INTEGER);
                CREATE TABLE virtual_list_frames(id INTEGER PRIMARY KEY, start_ns INTEGER,
                    end_ns INTEGER, origin TEXT, frame_id INTEGER, cycle_id INTEGER);
                INSERT INTO metadata VALUES ('schema_version','25');
                INSERT INTO measurement_status VALUES
                    ('virtual_list_linkage','complete','every list pass records its origin');
                INSERT INTO cycles VALUES (1,10,20),(2,30,40);
                INSERT INTO gpui_frames VALUES (1,50,60),(2,70,80),(3,90,95);
                INSERT INTO gpui_frame_cycles VALUES (1,1),(1,2);
                INSERT INTO virtual_list_frames VALUES (1,35,39,'patch',NULL,2),
                    (2,61,62,'paint',1,NULL),(3,96,99,'patch',NULL,NULL);
            """)
            database.execute("INSERT INTO measurement_status VALUES ('frame_cycle_linkage',?,?)",
                             (frame_status, "frame owner linkage"))
        return path

    def row(self, path: Path) -> dict[str, str]:
        output = analyze_stats.perspective(path, "timeline").splitlines()
        return dict(zip(output[1].split("\t"), output[2].split("\t")))

    def test_coalesced_cycles_and_list_origins_are_counted_from_recorded_keys(self):
        with tempfile.TemporaryDirectory() as temporary:
            row = self.row(self.capture(Path(temporary), "complete"))
            self.assertEqual(row["frames"], "3")
            self.assertEqual(row["frames_with_cycles"], "1")
            self.assertEqual(row["frames_without_new_cycle"], "2")
            self.assertEqual(row["frame_cycle_links"], "2")
            self.assertEqual(row["paint_passes_linked"], "1")
            self.assertEqual(row["patch_passes"], "2")
            self.assertEqual(row["patch_passes_of_cycles"], "1")
            self.assertEqual((row["first_ns"], row["last_ns"]), ("10", "99"))

    def test_headless_linkage_is_not_recorded_rather_than_zero(self):
        with tempfile.TemporaryDirectory() as temporary:
            row = self.row(self.capture(Path(temporary), "not_recorded"))
            self.assertEqual(row["evidence_status"], "not_recorded")
            self.assertEqual(row["frames_with_cycles"], "NULL")
            self.assertEqual(row["frame_cycle_links"], "NULL")


if __name__ == "__main__":
    unittest.main()
