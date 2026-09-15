import unittest

from scripts.check_no_tracked_machine_code import machine_code_kind


class MachineCodeKindTests(unittest.TestCase):
    def test_rejects_compiled_formats(self):
        self.assertEqual(machine_code_kind(b"\x7fELF" + b"\0" * 60), "ELF")
        self.assertEqual(machine_code_kind(b"!<arch>\n"), "object archive")
        self.assertEqual(machine_code_kind(b"\x00asm\x01\0\0\0"), "WebAssembly")
        pe = bytearray(72)
        pe[:2] = b"MZ"
        pe[60:64] = (64).to_bytes(4, "little")
        pe[64:68] = b"PE\0\0"
        self.assertEqual(machine_code_kind(bytes(pe)), "PE/COFF")

    def test_permits_binary_application_data_and_text_linker_recipe(self):
        self.assertIsNone(machine_code_kind(b"RIFF" + b"\0" * 32 + b"WAVE"))
        self.assertIsNone(machine_code_kind(b"SQLite format 3\0" + b"\0" * 64))
        self.assertIsNone(machine_code_kind(b"INPUT(libasound.so.2)\n"))


if __name__ == "__main__":
    unittest.main()
