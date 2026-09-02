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

struct AutomaticDecryptItem: Identifiable, Equatable {
    let platform: MusicPlatform
    let path: String
    let fileCount: Int

    var id: String { "\(platform.rawValue)|\(path)" }
    var displayName: String { URL(fileURLWithPath: path).lastPathComponent }
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
    @Published var taskStatusDetail = ""
    @Published var hasStartedTask = false
    @Published var logs = ""
    @Published var lastError: String?
    @Published var automaticInputPath = ""
    @Published var automaticInputItems: [AutomaticDecryptItem] = []
    @Published var detectedPlatform: MusicPlatform?
    @Published var detectedFileCount = 0

    private var activeTaskKind: TaskKind?
    private var latestTaskLines: [String] = []
    private var pendingAutomaticJobs: [AutomaticDecryptItem] = []
    private var automaticJobTotal = 0
    private var automaticJobIndex = 0
    private var automaticFailedJobCount = 0
    private var automaticFailureReasons: [String] = []
    private var isAutomaticBatch = false
    private var ignoresNextFinish = false

    let backend = BackendRunner()
    let formats = ["auto", "flac", "m4a", "mp3", "wav"]
    let sampleRates = [0, 22050, 32000, 44100, 48000, 88200, 96000]
    let bitrates = [0, 96, 128, 160, 192, 256, 320]

    init() {
        backend.onLine = { [weak self] line in
            Task { @MainActor in self?.handleBackendLine(line) }
        }
        backend.onFinish = { [weak self] code in
            Task { @MainActor in
                guard let self else { return }
                if self.ignoresNextFinish {
                    self.ignoresNextFinish = false
                } else if self.isAutomaticBatch {
                    self.finishAutomaticJob(exitCode: code)
                } else {
                    self.finishTask(exitCode: code)
                }
            }
        }
        Task { await loadConfiguration() }
    }

    func appendLog(_ line: String) {
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        logs += "[\(stamp)] \(line)\n"
    }

    private func handleBackendLine(_ line: String) {
        latestTaskLines.append(line)
        if latestTaskLines.count > 80 { latestTaskLines.removeFirst(latestTaskLines.count - 80) }
        if isRunning { taskStatusDetail = line }
        appendLog(line)
    }

    private func finishTask(exitCode: Int32) {
        let operation = activeTaskKind == .transcode ? "转码" : "解密"
        isRunning = false
        if exitCode == 0 {
            statusText = "\(operation)完成"
            taskStatusDetail = "处理已完成，可以打开输出目录查看文件。"
        } else {
            statusText = "\(operation)失败"
            let reason = preferredFailureReason()
            taskStatusDetail = reason.isEmpty ? "后端进程退出，错误代码：\(exitCode)" : reason
            lastError = "\(operation)失败：\(taskStatusDetail)"
        }
        activeTaskKind = nil
    }

    private func preferredFailureReason() -> String {
        let preferred = latestTaskLines.last { line in
            let lower = line.lowercased()
            return lower.contains("failed:")
                || lower.contains("qq_decrypt_failed")
                || lower.contains("decrypt_failed")
                || lower.contains("解密失败")
        } ?? latestTaskLines.last { line in
            let lower = line.lowercased()
            return !lower.contains("[timing]")
                && (lower.contains("error") || lower.contains("失败") || lower.contains(" reason="))
        }
        guard let preferred else { return "" }
        if let marker = preferred.range(of: "| qkkdecrypt |") {
            return String(preferred[marker.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return preferred.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func chooseAutomaticInput() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "选择"
        panel.message = "选择一个或多个加密音乐文件或文件夹"
        if panel.runModal() == .OK {
            _ = acceptAutomaticInputs(panel.urls)
        }
    }

    @discardableResult
    func acceptAutomaticInput(_ url: URL) -> Bool {
        acceptAutomaticInputs([url])
    }

    @discardableResult
    func acceptAutomaticInputs(_ urls: [URL]) -> Bool {
        var additions: [AutomaticDecryptItem] = []
        var ignoredNames: [String] = []
        for url in urls {
            let normalizedURL = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: normalizedURL.path, isDirectory: &isDirectory) else {
                ignoredNames.append(normalizedURL.lastPathComponent)
                continue
            }
            let result = isDirectory.boolValue
                ? detectPlatforms(in: normalizedURL)
                : detectSingleFile(normalizedURL)
            guard !result.isEmpty else {
                ignoredNames.append(normalizedURL.lastPathComponent)
                continue
            }
            for (detected, count) in result {
                additions.append(AutomaticDecryptItem(platform: detected, path: normalizedURL.path, fileCount: count))
            }
        }

        let existingIDs = Set(automaticInputItems.map(\.id))
        additions = additions.filter { !existingIDs.contains($0.id) }
        guard !additions.isEmpty else {
            lastError = ignoredNames.isEmpty
                ? "这些文件已经在列表中。"
                : "未识别到支持的加密音乐格式。支持 QQ 音乐、酷我音乐、酷狗音乐和网易云音乐的加密文件。"
            return false
        }

        automaticInputItems.append(contentsOf: additions)
        refreshAutomaticInputSummary()
        hasStartedTask = false
        taskStatusDetail = ""
        statusText = "已添加 \(detectedFileCount) 个文件"
        for item in additions {
            appendLog("自动识别：\(item.displayName) → \(item.platform.title)，\(item.fileCount) 个文件。")
        }
        if !ignoredNames.isEmpty {
            appendLog("已忽略不支持的项目：\(ignoredNames.joined(separator: "、"))")
        }
        return true
    }

    func removeAutomaticInput(_ item: AutomaticDecryptItem) {
        guard !isRunning else { return }
        automaticInputItems.removeAll { $0.id == item.id }
        refreshAutomaticInputSummary()
        hasStartedTask = false
        taskStatusDetail = ""
        statusText = automaticInputItems.isEmpty ? "待命" : "已添加 \(detectedFileCount) 个文件"
    }

    var hasQQAutomaticInput: Bool {
        automaticInputItems.contains { $0.platform == .qq }
    }

    private func refreshAutomaticInputSummary() {
        automaticInputPath = automaticInputItems.first?.path ?? ""
        detectedPlatform = automaticInputItems.first?.platform
        detectedFileCount = automaticInputItems.reduce(0) { $0 + $1.fileCount }
        if let first = automaticInputItems.first {
            platform = first.platform
            inputPaths[first.platform] = first.path
        }
    }

    func clearAutomaticInput() {
        automaticInputPath = ""
        automaticInputItems = []
        detectedPlatform = nil
        detectedFileCount = 0
        hasStartedTask = false
        taskStatusDetail = ""
        statusText = "待命"
    }

    func startAutomaticDecrypt() {
        guard !isRunning, !automaticInputItems.isEmpty else {
            if automaticInputItems.isEmpty { lastError = "请先拖入支持的加密音乐文件或文件夹。" }
            return
        }
        isRunning = true
        hasStartedTask = true
        activeTaskKind = .decrypt
        latestTaskLines = []
        pendingAutomaticJobs = automaticInputItems
        automaticJobTotal = pendingAutomaticJobs.count
        automaticJobIndex = 0
        automaticFailedJobCount = 0
        automaticFailureReasons = []
        isAutomaticBatch = true
        statusText = "正在准备批量解密"
        taskStatusDetail = "正在保存配置并创建 \(automaticJobTotal) 个解密任务…"
        appendLog("开始批量解密，共 \(detectedFileCount) 个文件、\(automaticJobTotal) 个任务。")
        Task {
            await saveConfiguration()
            startNextAutomaticJob()
        }
    }

    private func startNextAutomaticJob() {
        guard isAutomaticBatch else { return }
        guard !pendingAutomaticJobs.isEmpty else {
            finishAutomaticBatch()
            return
        }

        let job = pendingAutomaticJobs.removeFirst()
        automaticJobIndex += 1
        platform = job.platform
        inputPaths[job.platform] = job.path
        latestTaskLines = []
        statusText = "正在解密 \(automaticJobIndex)/\(automaticJobTotal)"
        taskStatusDetail = "\(job.platform.title) · \(job.displayName) · \(job.fileCount) 个文件"
        appendLog("批量任务 [\(automaticJobIndex)/\(automaticJobTotal)]：\(job.platform.title) · \(job.displayName)")
        backend.start(arguments: decryptArguments(platform: job.platform, input: job.path))
    }

    private func finishAutomaticJob(exitCode: Int32) {
        if exitCode != 0 {
            automaticFailedJobCount += 1
            let reason = preferredFailureReason()
            automaticFailureReasons.append(
                reason.isEmpty ? "任务 \(automaticJobIndex) 失败（错误代码 \(exitCode)）" : reason
            )
        }
        startNextAutomaticJob()
    }

    private func finishAutomaticBatch() {
        isAutomaticBatch = false
        isRunning = false
        activeTaskKind = nil
        if automaticFailureReasons.isEmpty {
            statusText = "批量解密完成"
            taskStatusDetail = "已处理 \(detectedFileCount) 个文件，可以打开输出目录查看结果。"
            appendLog("批量解密完成。")
        } else {
            var seenReasons: Set<String> = []
            let uniqueReasons = automaticFailureReasons.filter { seenReasons.insert($0).inserted }
            statusText = automaticFailedJobCount == automaticJobTotal ? "批量解密失败" : "批量解密部分失败"
            taskStatusDetail = "\(automaticFailedJobCount) 个任务未完成，请查看错误提示。"
            lastError = "批量解密遇到错误：\n\n" + uniqueReasons.prefix(6).joined(separator: "\n")
            appendLog("批量解密结束，失败 \(automaticFailedJobCount) 个任务。")
        }
        pendingAutomaticJobs = []
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
        isRunning = true
        hasStartedTask = true
        activeTaskKind = .decrypt
        latestTaskLines = []
        statusText = "正在准备解密"
        taskStatusDetail = "正在保存配置并启动解密引擎…"
        appendLog("开始 \(platform.title) 解密任务。")
        Task {
            await saveConfiguration()
            statusText = "正在解密"
            taskStatusDetail = "解密引擎已启动，正在处理文件…"
            backend.start(arguments: decryptArguments(platform: platform, input: input))
        }
    }

    private func decryptArguments(platform: MusicPlatform, input: String) -> [String] {
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
        return arguments
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
        hasStartedTask = true
        activeTaskKind = .transcode
        latestTaskLines = []
        statusText = "正在转码"
        taskStatusDetail = "转码引擎已启动，正在处理文件…"
        appendLog("开始批量转码任务。")
        backend.start(arguments: arguments)
    }

    func stop() {
        ignoresNextFinish = isRunning
        isAutomaticBatch = false
        pendingAutomaticJobs = []
        backend.stop()
        isRunning = false
        statusText = "已停止"
        taskStatusDetail = "任务已由用户停止。"
        activeTaskKind = nil
        appendLog("用户已停止任务。")
    }

    private func detectSingleFile(_ url: URL) -> [MusicPlatform: Int] {
        guard let platform = platformForFileName(url.lastPathComponent) else { return [:] }
        return [platform: 1]
    }

    private func detectPlatforms(in directory: URL) -> [MusicPlatform: Int] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
        let options: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: options
        ) else { return [:] }

        var counts: [MusicPlatform: Int] = [:]
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: keys).isRegularFile) == true,
                  let platform = platformForFileName(fileURL.lastPathComponent) else { continue }
            counts[platform, default: 0] += 1
        }
        return counts
    }

    private func platformForFileName(_ fileName: String) -> MusicPlatform? {
        let name = fileName.lowercased()
        if [".mflac", ".mgg", ".mmp4"].contains(where: name.hasSuffix) { return .qq }
        if name.hasSuffix(".kwm") { return .kuwo }
        if [".kgm", ".kgma", ".kgg", ".vpr", ".kgm.flac", ".vpr.flac"].contains(where: name.hasSuffix) {
            return .kugou
        }
        if name.hasSuffix(".ncm") { return .netease }
        return nil
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
