import EmailReaderCore
import Darwin
import Foundation

@main
struct EmailReaderWorker {
    static func main() async {
        let database = EmailReaderDatabase.shared
        do {
            try database.bootstrap(seedDemo: false)
            let trigger = value(after: "--trigger") ?? "scheduled"
            guard try database.loadAccount()?.authState == "connected" else {
                throw WorkerFailure("Gmail 尚未授权。")
            }
            let result = try await GmailSyncEngine(database: database).sync(trigger: trigger)
            FileHandle.standardOutput.write(Data("Gmail 同步完成：发现 \(result.discovered)，处理 \(result.analyzed)，失败 \(result.failed)。\n".utf8))
        } catch {
            _ = try? database.recordRun(trigger: "scheduled", status: "failed", discovered: 0, analyzed: 0, failed: 1, detail: error.localizedDescription)
            FileHandle.standardError.write(Data("Email Reader update failed: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func value(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }
}

private struct WorkerFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
