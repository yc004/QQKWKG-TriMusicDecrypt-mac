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
