import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import blueprint_admission as admission


class BlueprintAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.snapshot = {"name": "freetype", "system": "x86_64-linux", "nodes": []}
        self.record = {"schema_version": 1, "provider": "nix",
                       "build_identity": "/nix/store/" + "a" * 32 + "-freetype.drv",
                       "snapshot_digest": "sha256:" + "b" * 64, "snapshot": self.snapshot,
                       "artifact": {"name": "freetype-x64glibc.tar", "sha256": hashlib.sha256(b"archive").hexdigest(), "size": 7}}
        self.current = {"schema_version": 1, "name": "freetype", "system": "x86_64-linux",
                        "provider": "nix", "prepared": True,
                        "build_identity": self.record["build_identity"],
                        "snapshot_digest": self.record["snapshot_digest"], "snapshot": self.snapshot}

    def test_exact_admission_can_refresh_a_binding_only_when_build_is_identical(self):
        current = dict(self.current, snapshot_digest="sha256:" + "c" * 64,
                       snapshot=dict(self.snapshot, nodes=[{"changed": "selected declaration"}]))
        refreshed = admission.match_current(self.record, current, exact=True)
        self.assertEqual(refreshed["snapshot"], current["snapshot"])
        self.assertEqual(refreshed["artifact"], self.record["artifact"])
        with self.assertRaisesRegex(ValueError, "build identity differs"):
            admission.match_current(self.record, dict(current, build_identity="/nix/store/" + "d" * 32 + "-changed.drv"), exact=True)

    def test_structural_check_never_prepares_nix(self):
        with patch.object(admission.blueprint_link_inputs, "plan", return_value=dict(self.current, prepared=False, build_identity="")) as plan:
            admission.check_current(self.record)
        self.assertNotIn("prepare", plan.call_args.kwargs)

    def test_changed_digest_or_snapshot_cannot_reuse_admission(self):
        for current in (dict(self.current, snapshot_digest="sha256:" + "c" * 64),
                        dict(self.current, snapshot={"forged": True})):
            with self.assertRaisesRegex(ValueError, "stale"):
                admission.match_current(self.record, current, exact=False)

    def test_unprepared_and_malformed_records_cannot_establish_exact_equivalence(self):
        with self.assertRaisesRegex(ValueError, "provider preparation"):
            admission.match_current(self.record, dict(self.current, prepared=False), exact=True)
        for change in ({"provider": "another"}, {"build_identity": ""},
                       {"snapshot_digest": "b" * 64}, {"schema_version": 2}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                admission.match_current(dict(self.record, **change), self.current, exact=True)

    def test_archive_bytes_are_verified_before_preparing(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "freetype-x64glibc.tar"
            archive.write_bytes(b"archive")
            sidecar = archive.with_suffix(".tar.blueprint.json")
            sidecar.write_text(json.dumps(self.record))
            with patch.object(admission.blueprint_link_inputs, "plan", return_value=self.current) as plan:
                admission.admit(archive)
                self.assertTrue(plan.call_args.kwargs["prepare"])
            archive.write_bytes(b"changed")
            with patch.object(admission.blueprint_link_inputs, "plan") as plan:
                with self.assertRaisesRegex(ValueError, "admitted digest"):
                    admission.admit(archive)
                plan.assert_not_called()


if __name__ == "__main__":
    unittest.main()
