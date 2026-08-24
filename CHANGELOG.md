# 1.0.0 (2026-08-24)


### Bug Fixes

* 优化QQ音乐进程检测，解决缓慢或假死问题 ([1e69b7e](https://github.com/yc004/QQKWKG-TriMusicDecrypt-mac/commit/1e69b7ef56ca6ff81cfd38fe9a9f7151f7d136dd))


### Features

* add verified macOS UI support ([aaa5a0f](https://github.com/yc004/QQKWKG-TriMusicDecrypt-mac/commit/aaa5a0f5c40058a87914f7cd4cd95e7571677b56))

# Changelog

All notable changes to this project will be documented in this file.

## [1.4.4] - 2026-08-24

### Added

- Added the original PySide6 UI to the macOS distribution.
- Added native Apple Silicon packaging for both UI and console editions.
- Added macOS QMC2 offline decryption for QQ Music QTag/V1 files and musicex EKey retrieval.
- Added macOS runtime paths, process detection, FFmpeg discovery, native `.dylib` loading and portable AES support.

### Fixed

- Fixed QQ Music files incorrectly entering the Windows-only Frida decrypt path on macOS.
- Fixed mojibake in QQ Music failure messages and improved bilingual error reporting.
- Fixed macOS window sizing, dark navigation styling, startup scroll position and Qt frozen-app dependencies.

### Validation

- Verified successful decryption in the packaged macOS UI application.
- Passed 9 automated platform/decryption tests and strict bundle signature verification.
