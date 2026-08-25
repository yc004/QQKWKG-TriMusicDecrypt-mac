import AppKit
import Foundation
import SwiftUI

enum Workspace: String, CaseIterable, Identifiable {
    case workbench, activity

    var id: String { rawValue }
    var title: String {
        switch self {
        case .workbench: "工作台"
        case .activity: "任务记录"
        }
    }
    var symbol: String {
        switch self {
        case .workbench: "wand.and.sparkles"
        case .activity: "clock.arrow.circlepath"
        }
    }
}

enum TaskKind: String, CaseIterable, Identifiable {
    case decrypt, transcode

    var id: String { rawValue }
    var title: String { self == .decrypt ? "平台解密" : "批量转码" }
    var symbol: String { self == .decrypt ? "lock.open" : "waveform.badge.plus" }
}

enum MusicPlatform: String, CaseIterable, Identifiable {
    case qq, kuwo, kugou, netease

    var id: String { rawValue }
    var title: String {
        switch self {
        case .qq: "QQ 音乐"
        case .kuwo: "酷我音乐"
        case .kugou: "酷狗音乐"
        case .netease: "网易云音乐"
        }
    }
    var symbol: String {
        switch self {
        case .qq: "music.note"
        case .kuwo: "waveform"
        case .kugou: "headphones"
        case .netease: "music.quarternote.3"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: Workspace? = .workbench
    @Published var taskKind: TaskKind = .decrypt
    @Published var platform: MusicPlatform = .qq
    @Published var inputPaths: [MusicPlatform: String] = [:]
    @Published var outputDirectory = ""
    @Published var recursive = true
    @Published var transcodeEnabled = true
    @Published var embedCover = true
    @Published var supplementAlbum = false
    @Published var outputMode = "shared"
    @Published var targetFormats: [MusicPlatform: String] = [
        .qq: "flac", .kuwo: "auto", .kugou: "auto", .netease: "auto",
    ]
    @Published var sampleRate = 0
    @Published var bitrate = 0
    @Published var transcodeInput = ""
    @Published var transcodeOutput = ""
    @Published var transcodeFormat = "m4a"
    @Published var workerCount = 2
    @Published var isRunning = false
    @Published var statusText = "待命"
    @Published var logs = ""
    @Published var lastError: String?

    let backend = BackendRunner()
    let formats = ["auto", "flac", "m4a", "mp3", "wav"]
    let sampleRates = [0, 22050, 32000, 44100, 48000, 88200, 96000]
    let bitrates = [0, 96, 128, 160, 192, 256, 320]

    init() {
        backend.onLine = { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        }
        backend.onFinish = { [weak self] code in
            Task { @MainActor in
                self?.isRunning = false
                self?.statusText = code == 0 ? "已完成" : "失败（退出码 \(code)）"
                if code != 0 { self?.selection = .activity }
            }
        }
        Task { await loadConfiguration() }
    }

    func appendLog(_ line: String) {
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        logs += "[\(stamp)] \(line)\n"
    }

    func chooseInput(for platform: MusicPlatform) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            inputPaths[platform] = url.path
        }
    }

    func chooseDirectory(_ assign: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { assign(url.path) }
    }

    func openOutputDirectory() {
        guard !outputDirectory.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: outputDirectory, isDirectory: true))
    }

    func loadConfiguration() async {
        do {
            let data = try await backend.capture(arguments: ["native-config", "get"])
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            apply(configuration: object)
            appendLog("已读取原生界面配置。")
        } catch {
            lastError = error.localizedDescription
            appendLog("配置读取失败：\(error.localizedDescription)")
        }
    }

    func saveConfiguration() async {
        do {
            let data = try JSONSerialization.data(withJSONObject: configurationPayload())
            _ = try await backend.capture(arguments: ["native-config", "set"], stdin: data)
            appendLog("配置已保存。")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startDecrypt() {
        guard !isRunning else { return }
        let input = inputPaths[platform, default: ""]
        guard !input.isEmpty else {
            lastError = "请先选择输入文件或目录。"
            return
        }
        Task {
            await saveConfiguration()
            var arguments = [platform.rawValue, "decrypt", "--input", input]
            if !outputDirectory.isEmpty { arguments += ["--output", outputDirectory] }
            if !recursive { arguments.append("--no-recursive") }
            arguments.append(transcodeEnabled ? "--transcode" : "--no-transcode")
            arguments.append(embedCover ? "--embed-cover" : "--no-embed-cover")
            arguments.append(supplementAlbum ? "--supplement-album" : "--no-supplement-album")
            let format = targetFormats[platform, default: "auto"]
            switch platform {
            case .qq:
                let resolved = format == "auto" ? "flac" : format
                arguments += ["--format-mflac", resolved, "--format-mgg", resolved, "--format-mmp4", resolved]
            case .kuwo: arguments += ["--format-kwm", format]
            case .kugou: arguments += ["--format-kgma", format, "--format-kgg", format]
            case .netease: arguments += ["--format-ncm", format]
            }
            isRunning = true
            statusText = "正在解密"
            appendLog("开始 \(platform.title) 解密任务。")
            backend.start(arguments: arguments)
        }
    }

    func startTranscode() {
        guard !isRunning, !transcodeInput.isEmpty else {
            if transcodeInput.isEmpty { lastError = "请先选择转码输入目录。" }
            return
        }
        var arguments = ["transcode-batch", "--input", transcodeInput]
        if !transcodeOutput.isEmpty { arguments += ["--output", transcodeOutput] }
        arguments += ["--max-workers", String(workerCount)]
        if !recursive { arguments.append("--no-recursive") }
        var rule = "全部:\(transcodeFormat)"
        if sampleRate > 0 || bitrate > 0 {
            rule += ":\(sampleRate > 0 ? String(sampleRate) : ""):\(bitrate > 0 ? String(bitrate) : "")"
        }
        arguments += ["--rule", rule]
        isRunning = true
        statusText = "正在转码"
        appendLog("开始批量转码任务。")
        backend.start(arguments: arguments)
    }

    func stop() {
        backend.stop()
        isRunning = false
        statusText = "已停止"
        appendLog("用户已停止任务。")
    }

    private func apply(configuration: [String: Any]) {
        if let shared = configuration["shared"] as? [String: Any] {
            outputDirectory = shared["output_dir"] as? String ?? outputDirectory
            outputMode = shared["output_mode"] as? String ?? outputMode
            recursive = shared["recursive"] as? Bool ?? recursive
            transcodeEnabled = shared["transcode_enabled"] as? Bool ?? transcodeEnabled
            embedCover = shared["embed_cover_art"] as? Bool ?? embedCover
            supplementAlbum = shared["supplement_album_metadata"] as? Bool ?? supplementAlbum
        }
        for item in MusicPlatform.allCases {
            guard let section = configuration[item.rawValue] as? [String: Any] else { continue }
            inputPaths[item] = section["input_dir"] as? String ?? ""
            let format: String?
            switch item {
            case .qq: format = (section["format_rules"] as? [String: Any])?["mflac"] as? String
            case .kuwo: format = section["format_kwm"] as? String
            case .kugou: format = section["target_format_kgma"] as? String
            case .netease: format = section["target_format_ncm"] as? String
            }
            if let format { targetFormats[item] = format }
        }
        if let batch = configuration["transcode_batch"] as? [String: Any] {
            transcodeInput = (batch["input_paths"] as? [String])?.first ?? ""
            transcodeOutput = batch["output_dir"] as? String ?? ""
            workerCount = batch["max_workers"] as? Int ?? workerCount
        }
    }

    private func configurationPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "shared": [
                "output_dir": outputDirectory,
                "output_mode": outputMode,
                "recursive": recursive,
                "transcode_enabled": transcodeEnabled,
                "embed_cover_art": embedCover,
                "supplement_album_metadata": supplementAlbum,
            ],
            "transcode_batch": [
                "input_paths": transcodeInput.isEmpty ? [] : [transcodeInput],
                "output_dir": transcodeOutput,
                "recursive": recursive,
                "max_workers": workerCount,
                "rules": [["source_format": "全部", "target_format": transcodeFormat]],
            ],
        ]
        for item in MusicPlatform.allCases {
            var section: [String: Any] = ["input_dir": inputPaths[item, default: ""]]
            let format = targetFormats[item, default: "auto"]
            switch item {
            case .qq: section["format_rules"] = ["mflac": format == "auto" ? "flac" : format, "mgg": format == "auto" ? "m4a" : format, "mmp4": format == "auto" ? "m4a" : format]
            case .kuwo: section["format_kwm"] = format
            case .kugou: section["target_format_kgma"] = format; section["target_format_kgg"] = format
            case .netease: section["target_format_ncm"] = format
            }
            payload[item.rawValue] = section
        }
        return payload
    }
}
