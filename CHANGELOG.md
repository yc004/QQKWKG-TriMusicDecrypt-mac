# [1.5.0](https://github.com/yc004/QQKWKG-TriMusicDecrypt-mac/compare/v1.4.4...v1.5.0) (2026-08-25)


### Features

* **macOS:** add native SwiftUI interface and DMG release ([acb2770](https://github.com/yc004/QQKWKG-TriMusicDecrypt-mac/commit/acb277087b2121b66cf9a5253543cb597ec8ea5d))

# Changelog

All notable changes to this project will be documented in this file.

## [1.6.0] - 2026-09-02

### Added

- Added a compact multi-file drag-and-drop workflow that automatically identifies QQ Music, Kuwo, Kugou and NetEase formats.
- Added sequential mixed-platform batch decryption with current/total task progress and aggregated native error alerts.
- Added a native Full Disk Access onboarding flow using PermissionFlow and FullDiskAccess for QQ Music login data.

### Changed

- Redesigned the macOS main window as a lightweight single-screen application using native SwiftUI, AppKit and Liquid Glass components.
- Moved live preparation, decryption, completion and failure states onto the main screen and removed the separate batch entry point.
- Updated macOS packaging to resolve Swift Package dependencies and include their resource bundles.

### Validation

- Verified mixed QQ Music and NetEase tasks progress from `1/2` to `2/2` in the real macOS interface.
- Verified native error dialogs aggregate per-file backend failure reasons.
- Passed 9 automated platform/decryption tests and strict bundle signature verification.

## [1.5.0] - 2026-08-25

### Added

- Added a fully native SwiftUI and AppKit macOS interface while retaining the existing Python application and infrastructure layers.
- Added native macOS navigation, toolbar, settings, alerts, file panels, system switches, tab pickers and Liquid Glass presentation.
- Added a reusable DMG packaging step with an Applications shortcut.

### Changed

- Redesigned the macOS workflow around platform decryption, batch transcoding, task history and persistent configuration.
- Replaced simulated macOS controls with Apple system components and native accessibility semantics.
- Updated the application icon and macOS packaging pipeline for the current SDK.

### Validation

- Verified the native application workflow in a real macOS window.
- Passed 9 automated platform/decryption tests and strict bundle signature verification.
- Verified the frontend executable is built with macOS SDK 27.0 and targets macOS 15.0 or later.

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
