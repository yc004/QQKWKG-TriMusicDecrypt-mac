from __future__ import annotations

import base64
import pathlib
import struct
import tempfile
import unittest
from unittest import mock

from src.Infrastructure.kugou_decoder import _new_qmc_cipher_from_ekey
from src.Infrastructure.platforms.qq.adapter import QQPlatformAdapter
from src.Infrastructure.platforms.qq.offline_decoder import decode_file, inspect_footer


TEST_EKEY = "VGhpcyBpcyBHFWEh4cjZ1Vi7rJ56XeoPlqGM1sxBGPg7mt89umKclFBr9iqfmFdS"


def _encrypted_flac() -> bytes:
    plain = bytearray(b"fLaC" + bytes(range(256)) * 8)
    _new_qmc_cipher_from_ekey(TEST_EKEY, use_native=False).decrypt(plain, 0)
    return bytes(plain)


class QQOfflineDecoderTests(unittest.TestCase):
    def test_qtag_mflac_is_decrypted_without_qqmusic_process(self) -> None:
        metadata = f"{TEST_EKEY},12345,2".encode("ascii")
        payload = _encrypted_flac() + metadata + struct.pack(">I", len(metadata)) + b"QTag"
        with tempfile.TemporaryDirectory() as tmp:
            source = pathlib.Path(tmp) / "song.mflac"
            output = pathlib.Path(tmp) / "song.flac"
            source.write_bytes(payload)
            result = decode_file(source, output)
            self.assertEqual(result["detected_container"], "flac")
            self.assertEqual(result["backend"], "qmc2-offline:qtag")
            self.assertTrue(output.read_bytes().startswith(b"fLaC"))

    def test_v1_mflac_embedded_key_is_decrypted(self) -> None:
        raw_ekey = base64.b64decode(TEST_EKEY)
        payload = _encrypted_flac() + raw_ekey + struct.pack("<I", len(raw_ekey))
        with tempfile.TemporaryDirectory() as tmp:
            source = pathlib.Path(tmp) / "song.mflac"
            output = pathlib.Path(tmp) / "song.flac"
            source.write_bytes(payload)
            self.assertEqual(inspect_footer(source).kind, "v1")
            decode_file(source, output)
            self.assertTrue(output.read_bytes().startswith(b"fLaC"))

    def test_musicex_footer_metadata_is_parsed(self) -> None:
        metadata = bytearray(160)
        struct.pack_into("<I", metadata, 0, 9876)
        mid = "003TESTMID".encode("utf-16-le") + b"\x00\x00"
        name = "F000TEST.mflac".encode("utf-16-le") + b"\x00\x00"
        metadata[0x0C:0x0C + len(mid)] = mid
        metadata[0x48:0x48 + len(name)] = name
        footer_size = len(metadata) + 16
        with tempfile.TemporaryDirectory() as tmp:
            source = pathlib.Path(tmp) / "song.mflac"
            source.write_bytes(b"encrypted" * 32 + metadata + struct.pack("<II", footer_size, 1) + b"musicex\x00")
            footer = inspect_footer(source)
            self.assertEqual(footer.kind, "musicex")
            self.assertEqual(footer.song_id, 9876)
            self.assertEqual(footer.media_mid, "003TESTMID")
            self.assertEqual(footer.filename, "F000TEST.mflac")

    @mock.patch("src.Infrastructure.platforms.qq.adapter.platform.system", return_value="Darwin")
    def test_macos_does_not_require_windows_qqmusic_process(self, _system: mock.Mock) -> None:
        adapter = QQPlatformAdapter()
        self.assertFalse(adapter.requires_running_process())
        self.assertEqual(adapter.validate_runtime({}), (True, None))


if __name__ == "__main__":
    unittest.main()
