"""A refused Windows shader-tool pair is named by every identity examined."""

from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import windows_gnu_build as build

MICROSOFT = "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US"


class ShaderToolAdmissionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.sdk = Path(temporary.name)
        self.fxc, self.dll = self.sdk / "fxc.exe", self.sdk / "d3dcompiler_47.dll"
        self.fxc.write_bytes(b"fxc")
        self.dll.write_bytes(b"dll")

    def inventory(self, fxc=build.FXC_SHA, dll=build.COMPILER_SHA):
        return {"fxc.exe": {"sha256": fxc, "size": 3}, "d3dcompiler_47.dll": {"sha256": dll, "size": 3}}

    def signatures(self, thumbprint=build.SIGNER, subject=MICROSOFT, status=0):
        return [{"Path": str(path), "Status": status, "Thumbprint": thumbprint, "Subject": subject}
                for path in (self.fxc, self.dll)]

    def admit(self, inventory, signatures, pinned):
        build.admit_shader_tools(self.sdk, self.fxc, self.dll, inventory, signatures, pinned)

    def test_the_reviewed_pair_is_admitted_pinned_and_unpinned(self):
        for pinned in (True, False):
            self.admit(self.inventory(), self.signatures(), pinned)

    def test_a_serviced_pair_is_admitted_only_unpinned(self):
        serviced = self.inventory(fxc="1" * 64, dll="2" * 64)
        signatures = self.signatures(thumbprint="A" * 40)
        self.admit(serviced, signatures, False)
        with self.assertRaises(ValueError) as refused:
            self.admit(serviced, signatures, True)
        message = str(refused.exception)
        self.assertIn("matching the reviewed pins", message)
        for identity in ("1" * 64, "2" * 64, "A" * 40, build.SIGNER, build.FXC_SHA, build.COMPILER_SHA):
            self.assertIn(identity, message)
        self.assertIn("fxc.exe sha256=", message)
        self.assertIn("d3dcompiler_47.dll sha256=", message)

    def test_a_reviewed_signer_with_other_bytes_is_refused_pinned(self):
        with self.assertRaisesRegex(ValueError, "reviewed pins"):
            self.admit(self.inventory(fxc="3" * 64), self.signatures(), True)

    def test_a_signature_that_is_not_microsofts_is_refused_even_unpinned(self):
        for signatures in (self.signatures(subject="O=Example"), self.signatures(status=1),
                           self.signatures()[:1], []):
            with self.assertRaisesRegex(ValueError, "Authenticode"):
                self.admit(self.inventory(), signatures, False)

    def test_a_refusal_names_an_unreported_signature(self):
        with self.assertRaisesRegex(ValueError, "d3dcompiler_47.dll .* signature=unreported"):
            self.admit(self.inventory(), self.signatures()[:1], False)


if __name__ == "__main__":
    unittest.main()
