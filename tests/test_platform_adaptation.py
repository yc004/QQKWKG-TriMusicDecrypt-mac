from __future__ import annotations

import pathlib
import tempfile
import unittest

from src.Infrastructure.kugou_decoder import _PortableAesCbcNoPadding
from src.Infrastructure.native_backend import NativeKudogBackend
from src.Infrastructure.transcoder import fast_detect_container, resolve_ffmpeg_path


class PlatformAdaptationTests(unittest.TestCase):
    def test_portable_aes_cbc_matches_nist_vector(self) -> None:
        # NIST SP 800-38A F.2.1, one block with no padding.
        key = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
        iv = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
        ciphertext = bytes.fromhex("7649abac8119b246cee98e9b12e9197d")
        plaintext = bytes.fromhex("6bc1bee22e409f96e93d7e117393172a")
        self.assertEqual(_PortableAesCbcNoPadding().decrypt(ciphertext, key, iv), plaintext)

    def test_native_library_exports_are_loadable(self) -> None:
        root = pathlib.Path(__file__).resolve().parents[1]
        library = root / "assets" / "libkudog_native.dylib"
        if not library.exists():
            self.skipTest("native macOS library has not been built")
        backend = NativeKudogBackend(library)
        self.assertTrue(backend.available, backend.reason)

    def test_fast_container_detection_is_platform_neutral(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sample = pathlib.Path(directory) / "sample.flac"
            sample.write_bytes(b"fLaC" + b"\0" * 64)
            self.assertEqual(fast_detect_container(sample), "flac")

    def test_ffmpeg_resolution_never_selects_windows_binary_on_macos(self) -> None:
        resolved = resolve_ffmpeg_path()
        self.assertIsNotNone(resolved)
        self.assertNotEqual(resolved.suffix.lower(), ".exe")

    def test_all_platform_adapters_import(self) -> None:
        from src.Infrastructure.platforms.registry import build_platform_adapter

        self.assertEqual(
            [build_platform_adapter(name).platform_id for name in ("qq", "kuwo", "kugou", "netease")],
            ["qq", "kuwo", "kugou", "netease"],
        )


if __name__ == "__main__":
    unittest.main()
