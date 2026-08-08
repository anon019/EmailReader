import EmailReaderCore
import Darwin
import Foundation
import SwiftUI

@main
struct EmailReaderEntryPoint {
    static func main() {
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--codex-") }) {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                let succeeded = await CodexBriefCommandRunner.run(arguments: CommandLine.arguments)
                if !succeeded { exit(EXIT_FAILURE) }
                semaphore.signal()
            }
            while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
        } else {
            EmailReaderApplication.main()
        }
    }
}

private enum CodexBriefCommandRunner {
    static func run(arguments: [String]) async -> Bool {
        let database = EmailReaderDatabase.shared
        do {
            try database.bootstrap(seedDemo: false)
            if arguments.contains("--codex-run-luna") {
                guard try database.loadAccount()?.authState == "connected" else {
                    throw CodexCommandError("Gmail 尚未授权，无法运行 Luna 每日分析。")
                }
                try await WorkerSyncRunner.sync(database: database, trigger: "cli_luna")
                let temporaryDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("EmailReader-Luna-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
                let inputURL = temporaryDirectory.appendingPathComponent("analysis-input.json")
                let outputURL = temporaryDirectory.appendingPathComponent("luna-pipeline.json")
                let inputCount = try database.exportDailyLunaInput(to: inputURL)
                try await LunaBriefRunner.run(analysisInputURL: inputURL, outputURL: outputURL)
                let analyzedCount = try database.installLunaPipeline(from: outputURL)
                try database.recordRun(
                    trigger: "cli_luna", status: "complete", discovered: inputCount,
                    analyzed: analyzedCount, failed: 0,
                    detail: "Luna Medium 已完成逐封分类、摘要、投资 thesis 与每日简报。"
                )
                write("Luna 每日分析完成：\(analyzedCount)/\(inputCount) 封。\n")
            } else if let path = value(after: "--codex-authorize", in: arguments) {
                try database.setAccountAuthState("authorizing")
                try await GoogleOAuthCoordinator().authorize(
                    configurationURL: URL(fileURLWithPath: path),
                    loginHint: try database.loadAccount()?.email
                )
                try database.setAccountAuthState("connected")
                _ = try await GmailSyncEngine(database: database).sync(trigger: "credential_v3_migration")
                write("Gmail 单一凭证授权完成。\n")
            } else if let path = value(after: "--codex-prepare", in: arguments) {
                guard try database.loadAccount()?.authState == "connected" else {
                    throw CodexCommandError("Gmail 尚未授权，无法准备每日简报。")
                }
                try await WorkerSyncRunner.sync(database: database, trigger: "codex_automation")
                if try database.setting("analysis_rules_version") != "2" {
                    _ = try await GmailSyncEngine(database: database).reanalyzeStoredThreads()
                }
                try database.exportBriefInput(to: URL(fileURLWithPath: path), days: 7)
                write("已同步 Gmail，并导出过去 7 天简报输入：\(path)\n")
            } else if let path = value(after: "--codex-prepare-compact", in: arguments) {
                guard try database.loadAccount()?.authState == "connected" else {
                    throw CodexCommandError("Gmail 尚未授权，无法准备紧凑简报。")
                }
                try await WorkerSyncRunner.sync(database: database, trigger: "luna_compact_sync")
                if try database.setting("analysis_rules_version") != "2" {
                    _ = try await GmailSyncEngine(database: database).reanalyzeStoredThreads()
                }
                let localResult = try await LocalBriefEngine(database: database, model: "qwen3.5:4b").generate(publish: false)
                try database.exportCompactBriefInput(to: URL(fileURLWithPath: path), brief: localResult.brief)
                write("已完成本机筛选，并导出不含正文的 Luna 紧凑输入：\(path)\n")
            } else if let path = value(after: "--codex-prepare-luna", in: arguments) {
                guard try database.loadAccount()?.authState == "connected" else {
                    throw CodexCommandError("Gmail 尚未授权，无法准备 Luna 每日分析。")
                }
                try await WorkerSyncRunner.sync(database: database, trigger: "luna_daily_sync")
                let count = try database.exportDailyLunaInput(to: URL(fileURLWithPath: path))
                write("已同步 Gmail，并导出 \(count) 封待 Luna 逐封分析的邮件：\(path)\n")
            } else if let path = value(after: "--codex-export-compact-only", in: arguments) {
                try database.exportCompactBriefInput(to: URL(fileURLWithPath: path))
                write("已导出当前简报的不含正文紧凑输入：\(path)\n")
            } else if arguments.contains("--codex-local-brief") {
                guard try database.loadAccount()?.authState == "connected" else {
                    throw CodexCommandError("Gmail 尚未授权，无法生成本机简报。")
                }
                try await WorkerSyncRunner.sync(database: database, trigger: "local_brief_sync")
                if try database.setting("analysis_rules_version") != "2" {
                    _ = try await GmailSyncEngine(database: database).reanalyzeStoredThreads()
                }
                let result = try await LocalBriefEngine(database: database, model: "qwen3.5:4b").generate()
                write("本机简报完成：\(result.brief.headline)；成功 \(result.analyzed)，失败 \(result.failed)。\n")
            } else if arguments.contains("--codex-local-analyze-only") {
                let result = try await LocalBriefEngine(database: database, model: "qwen3.5:4b").generate()
                write("本机分析完成：\(result.brief.headline)；处理 \(result.analyzed)，失败 \(result.failed)。\n")
            } else if arguments.contains("--codex-reanalyze") {
                let count = try await GmailSyncEngine(database: database).reanalyzeStoredThreads()
                write("已重新整理 \(count) 封邮件。\n")
            } else if let path = value(after: "--codex-install-brief", in: arguments) {
                try database.installDailyBrief(from: URL(fileURLWithPath: path))
                let brief = try database.loadDailyBrief()
                write("已安装每日简报：\(brief.headline)\n")
            } else if let path = value(after: "--codex-install-luna-pipeline", in: arguments) {
                let count = try database.installLunaPipeline(from: URL(fileURLWithPath: path))
                let brief = try database.loadDailyBrief()
                write("已安装 Luna 逐封分析 \(count) 封及每日简报：\(brief.headline)\n")
            } else if arguments.contains("--codex-print-brief") {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                FileHandle.standardOutput.write(try encoder.encode(database.loadDailyBrief()))
                write("\n")
            } else {
                throw CodexCommandError("未知的 Codex 简报命令。")
            }
            return true
        } catch {
            FileHandle.standardError.write(Data("Email Reader: \(error.localizedDescription)\n".utf8))
            return false
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func write(_ value: String) {
        FileHandle.standardOutput.write(Data(value.utf8))
    }
}

private struct CodexCommandError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct EmailReaderApplication: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1060, minHeight: 680)
                .alert("Email Reader", isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )) {
                    Button("好") { model.errorMessage = nil }
                } message: {
                    Text(model.errorMessage ?? "未知错误")
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .newItem) {
                Button("立即更新") { model.syncNow() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("设置") { model.showingSettings = true }
                    .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
