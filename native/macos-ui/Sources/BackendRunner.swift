import Foundation

enum BackendError: LocalizedError {
    case missingExecutable
    case failed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable: "应用包中缺少 QKKDecryptBackend。"
        case let .failed(code, message): "后端执行失败（\(code)）：\(message)"
        }
    }
}

@MainActor
final class BackendRunner {
    var onLine: ((String) -> Void)?
    var onFinish: ((Int32) -> Void)?
    private var process: Process?

    private func executableURL() throws -> URL {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("QKKDecryptBackend"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("dist/console/QKKDecrypt"),
        ].compactMap { $0 }
        guard let url = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw BackendError.missingExecutable
        }
        return url
    }

    func capture(arguments: [String], stdin: Data? = nil) async throws -> Data {
        let executable = try executableURL()
        return try await Task.detached {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = error
            if let stdin {
                let input = Pipe()
                process.standardInput = input
                try process.run()
                input.fileHandleForWriting.write(stdin)
                try input.fileHandleForWriting.close()
            } else {
                try process.run()
            }
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                throw BackendError.failed(process.terminationStatus, String(decoding: errorData, as: UTF8.self))
            }
            return data
        }.value
    }

    func start(arguments: [String]) {
        do {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = try executableURL()
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = error
            let consume: @Sendable (FileHandle) -> Void = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let text = String(decoding: data, as: UTF8.self)
                Task { @MainActor in
                    text.split(whereSeparator: \Character.isNewline).forEach { self?.onLine?(String($0)) }
                }
            }
            output.fileHandleForReading.readabilityHandler = consume
            error.fileHandleForReading.readabilityHandler = consume
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    self?.process = nil
                    self?.onFinish?(process.terminationStatus)
                }
            }
            try process.run()
            self.process = process
        } catch {
            onLine?(error.localizedDescription)
            onFinish?(-1)
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }
}
