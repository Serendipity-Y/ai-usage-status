import Darwin
import Foundation

enum GeminiQuotaSource: Equatable, Sendable {
    case command(String)
    case file(String)
    case none

    var displayDescription: String {
        switch self {
        case .command(let path): return "Local command: \(path)"
        case .file(let path): return "Local JSON file: \(path)"
        case .none: return "Not configured (optional JSON file at \(AppConfig.defaultGeminiQuotaFilePath))"
        }
    }
}

enum GeminiUsageFetcher {
    static func resolvedSource(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> GeminiQuotaSource {
        if let command = environment["GEMINI_QUOTA_COMMAND"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !command.isEmpty {
            return .command(expandTilde(command))
        }
        if let filePath = environment["GEMINI_QUOTA_FILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !filePath.isEmpty {
            return .file(expandTilde(filePath))
        }
        let defaultPath = AppConfig.defaultGeminiQuotaFilePath
        if fileManager.fileExists(atPath: defaultPath) {
            return .file(defaultPath)
        }
        let defaultCommand = AppConfig.defaultGeminiQuotaCommandPath
        if fileManager.isExecutableFile(atPath: defaultCommand) {
            return .command(defaultCommand)
        }
        return .none
    }

    static func fetch() async throws -> GeminiUsageSummary {
        try await Task.detached(priority: .utility) {
            try fetchSync()
        }.value
    }

    static func fetchSync(
        source: GeminiQuotaSource? = nil,
        timeout: DispatchTimeInterval = AppConfig.geminiFetchTimeout
    ) throws -> GeminiUsageSummary {
        let activeSource = source ?? resolvedSource()
        let data: Data
        switch activeSource {
        case .none:
            throw GeminiFetchError.notConfigured
        case .file(let path):
            data = try readFile(atPath: path)
        case .command(let path):
            data = try runCommand(atPath: path, timeout: timeout)
        }
        return try decodeSummary(from: data)
    }

    static func decodeSummary(from data: Data) throws -> GeminiUsageSummary {
        do {
            let payload = try JSONDecoder().decode(GeminiQuotaPayload.self, from: data)
            return try GeminiUsageSummary(payload: payload)
        } catch let error as GeminiFetchError {
            throw error
        } catch {
            throw GeminiFetchError.invalidOutput
        }
    }

    private static func readFile(atPath path: String) throws -> Data {
        guard FileManager.default.fileExists(atPath: path) else {
            throw GeminiFetchError.fileReadFailed
        }
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw GeminiFetchError.fileReadFailed
        }
    }

    private static func runCommand(atPath path: String, timeout: DispatchTimeInterval) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw GeminiFetchError.commandNotFound(path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        let collector = OutputCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                collector.append(chunk)
            }
        }
        // Drain and discard stderr so child output never deadlocks or leaks sensitive details.
        errors.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }

        defer {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            terminateProcess(process, finished: finished)
        }

        do {
            try process.run()
        } catch {
            throw GeminiFetchError.commandNotFound(path)
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            throw GeminiFetchError.timeout
        }

        // Flush any remaining buffered bytes after process exit.
        let tail = output.fileHandleForReading.readDataToEndOfFile()
        if !tail.isEmpty {
            collector.append(tail)
        }

        guard process.terminationStatus == 0 else {
            throw GeminiFetchError.commandFailed(process.terminationStatus)
        }
        return collector.snapshot()
    }

    private static func terminateProcess(_ process: Process, finished: DispatchSemaphore) {
        guard process.isRunning else { return }
        process.terminate()
        if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 1)
        }
    }

    private static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
