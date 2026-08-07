import Foundation

public enum WorkerSyncRunnerError: LocalizedError {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

public enum WorkerSyncRunner {
    public static var installedWorkerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EmailReader/EmailReaderWorker")
    }

    public static func sync(database: EmailReaderDatabase = .shared, trigger: String) async throws {
        guard FileManager.default.isExecutableFile(atPath: installedWorkerURL.path) else {
            _ = try await GmailSyncEngine(database: database).sync(trigger: trigger)
            return
        }
        try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = installedWorkerURL
            process.arguments = ["--trigger", trigger]
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw WorkerSyncRunnerError.failed(message.flatMap { $0.isEmpty ? nil : $0 } ?? "Gmail 同步助手失败。")
            }
        }.value
    }
}
