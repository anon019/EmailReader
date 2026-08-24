import AppKit
import Combine
import EmailReaderCore
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import SwiftUI

enum SidebarSelection: Hashable {
    case library(LibraryFilter)
    case category(MailCategory)
}

struct DailyCategoryCount: Identifiable {
    let category: MailCategory
    let count: Int
    var id: String { category.id }
}

struct DailyResearchTheme: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let signalLabel: String
    let threadIDs: [String]
    var count: Int { threadIDs.count }
}

struct DailyTickerCount: Identifiable {
    let ticker: String
    let count: Int
    let threadIDs: [String]
    let relevanceScore: Int
    var id: String { ticker }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: SidebarSelection = .library(.today)
    @Published var threads: [MailThread] = []
    @Published var selectedThreadID: String?
    @Published var selectedThread: MailThread?
    @Published var account: MailAccount?
    @Published var counts = FilterCounts()
    @Published var brief = DailyBrief.empty
    @Published var briefHistory: [DailyBrief] = []
    @Published var showingDailyBrief = true
    @Published var receipt: SyncReceipt?
    @Published var searchText = ""
    @Published var isSyncing = false
    @Published var syncPhase = ""
    @Published var errorMessage: String?
    @Published var showingSettings = false
    @Published var analysisAvailability = "检查中"
    @Published var isAuthorizing = false
    @Published var briefThreadStates: [String: ReadingState] = [:]
    @Published var briefProviderLabel = "本地整理"
    @Published var dailyUnreadThreads: [MailThread] = []
    @Published var dailyAlertThreads: [MailThread] = []
    @Published var dailyCategoryCounts: [DailyCategoryCount] = []
    @Published var dailyResearchThemes: [DailyResearchTheme] = []
    @Published var dailyTickerCounts: [DailyTickerCount] = []
    @Published var dailyInvestmentThesisCount = 0

    let database: EmailReaderDatabase
    private var briefMonitor: AnyCancellable?
    private var observedBriefTimestamp: String?

    init(database: EmailReaderDatabase = .shared) {
        self.database = database
        do {
            try database.bootstrap(seedDemo: false)
            reload(preserveSelection: false)
        } catch {
            errorMessage = error.localizedDescription
        }
        checkAnalysisAvailability()
        briefMonitor = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.reloadIfBriefChanged() }
            }
    }

    var currentFilterTitle: String {
        switch selection {
        case .library(let filter): filter.rawValue
        case .category(let category): category.rawValue
        }
    }

    var isDemoMode: Bool { account?.authState == "demo" || threads.contains(where: \.isDemo) }

    var briefGeneratedLabel: String {
        guard let date = ISO8601DateFormatter().date(from: brief.generatedAt) else { return "生成时间未知" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    var todayFocusTitle: String {
        if dailyAlertThreads.isEmpty {
            return brief.priority.isEmpty
                ? "今天没有必须处理的事项"
                : "今天的 \(brief.priority.count) 项警报已处理完成"
        }
        return "还有 \(dailyAlertThreads.count) 件事需要处理"
    }

    func reload(preserveSelection: Bool = true) {
        do {
            let filter: LibraryFilter
            let category: MailCategory?
            switch selection {
            case .library(let chosen):
                filter = chosen
                category = nil
            case .category(let chosen):
                filter = .all
                category = chosen
            }
            account = try database.loadAccount()
            counts = try database.loadCounts()
            brief = try database.loadDailyBrief()
            observedBriefTimestamp = try database.setting("last_brief_at")
            briefHistory = try database.loadBriefHistory()
            briefProviderLabel = Self.providerLabel(try database.setting("last_brief_provider"))
            receipt = try database.loadLatestReceipt()
            threads = try database.loadThreads(filter: filter, category: category, search: searchText)
            let allThreads = try database.loadThreads(filter: .all)
            let dailyCutoff = Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .distantPast
            let contextCutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
            let dailyThreads = allThreads.filter { !$0.isDemo && $0.receivedAt >= dailyCutoff }
            dailyUnreadThreads = dailyThreads.filter { $0.readingState == .unread }
            dailyAlertThreads = allThreads.filter {
                !$0.isDemo && $0.needsAttention && $0.readingState != .completed && $0.receivedAt >= contextCutoff
            }
            dailyCategoryCounts = MailCategory.allCases.compactMap { category in
                let count = dailyThreads.lazy.filter { $0.category == category }.count
                return count > 0 ? DailyCategoryCount(category: category, count: count) : nil
            }
            let investmentThreads = dailyThreads.filter { $0.category == .investment }
            dailyInvestmentThesisCount = investmentThreads.lazy.filter { $0.investmentThesis != nil }.count
            dailyResearchThemes = Self.researchThemes(from: investmentThreads)
            dailyTickerCounts = Self.tickerCounts(from: investmentThreads)
            let briefIDs = brief.priority.map(\.threadID) + brief.noteworthy.map(\.threadID) + brief.later.map(\.threadID)
            briefThreadStates = Dictionary(uniqueKeysWithValues: try briefIDs.compactMap { id in
                try database.loadThread(id: id).map { (id, $0.readingState) }
            })

            if case .library(.today) = selection, showingDailyBrief {
                selectedThreadID = nil
                selectedThread = nil
            } else if preserveSelection, let selectedThreadID, threads.contains(where: { $0.id == selectedThreadID }) {
                selectedThread = try database.loadThread(id: selectedThreadID)
            } else {
                selectedThreadID = threads.first?.id
                selectedThread = threads.first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadIfBriefChanged() {
        guard let latest = try? database.setting("last_brief_at"),
              latest != observedBriefTimestamp else { return }
        reload()
    }

    func changeSelection(_ value: SidebarSelection) {
        selection = value
        showingDailyBrief = value == .library(.today)
        withAnimation(.snappy(duration: 0.22)) { reload(preserveSelection: false) }
    }

    func openResearchTheme(_ theme: DailyResearchTheme) {
        openInvestmentThread(theme.threadIDs.first)
    }

    func openTicker(_ ticker: DailyTickerCount) {
        openInvestmentThread(ticker.threadIDs.first)
    }

    private func openInvestmentThread(_ threadID: String?) {
        selection = .category(.investment)
        showingDailyBrief = false
        reload(preserveSelection: false)
        guard let threadID else { return }
        selectedThreadID = threadID
        do {
            selectedThread = try database.loadThread(id: threadID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func researchThemes(from threads: [MailThread]) -> [DailyResearchTheme] {
        struct Definition {
            let id: String
            let title: String
            let subtitle: String
            let keywords: [String]
        }
        let definitions = [
            Definition(
                id: "ai-infrastructure", title: "AI 算力基础设施",
                subtitle: "数据中心、GPU、承购与推理经济性",
                keywords: ["算力", "spacex", "gpu", "数据中心", "nvda", "microsoft", "msft"]
            ),
            Definition(
                id: "cybersecurity", title: "Cloudflare / 网络安全",
                subtitle: "NET 经营改善与 AI 安全需求",
                keywords: ["cloudflare", "网络安全", "cybersecurity", "security", "net"]
            ),
            Definition(
                id: "gold", title: "黄金与贵金属",
                subtitle: "GOLD、GDX 与风险偏好变化",
                keywords: ["黄金", "gold", "gdx", "贵金属"]
            ),
            Definition(
                id: "macro-policy", title: "宏观与政策",
                subtitle: "利率、关税、监管与预测市场",
                keywords: ["宏观", "利率", "关税", "监管", "polymarket", "fed", "政策"]
            )
        ]
        return definitions.compactMap { definition in
            let matches = threads.filter { thread in
                let thesis = thread.investmentThesis
                let content = ([thread.subject, thread.summary, thesis?.thesis ?? ""] + (thesis?.tickers ?? []))
                    .joined(separator: " ")
                    .lowercased()
                return definition.keywords.contains { content.contains($0.lowercased()) }
            }
            guard !matches.isEmpty else { return nil }
            let signalLabel = matches.count >= 3 ? "强信号" : matches.count == 2 ? "交叉验证" : "观察"
            return DailyResearchTheme(
                id: definition.id,
                title: definition.title,
                subtitle: definition.subtitle,
                signalLabel: signalLabel,
                threadIDs: matches.map(\.id)
            )
        }
        .sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.title < rhs.title : lhs.count > rhs.count
        }
    }

    private static func tickerCounts(from threads: [MailThread]) -> [DailyTickerCount] {
        var threadIDsByTicker: [String: Set<String>] = [:]
        var scoreByTicker: [String: Int] = [:]
        for thread in threads {
            let rawTickers = thread.investmentThesis?.tickers ?? []
            let focusWeight = rawTickers.count <= 3 ? 5 : rawTickers.count <= 5 ? 2 : 1
            for rawTicker in rawTickers {
                let ticker = rawTicker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !ticker.isEmpty, ticker.count <= 8 else { continue }
                threadIDsByTicker[ticker, default: []].insert(thread.id)
                scoreByTicker[ticker, default: 0] += focusWeight
            }
        }
        let counts: [DailyTickerCount] = threadIDsByTicker.map { ticker, threadIDs in
            DailyTickerCount(
                ticker: ticker,
                count: threadIDs.count,
                threadIDs: Array(threadIDs),
                relevanceScore: scoreByTicker[ticker, default: 0]
            )
        }
        let sorted = counts.sorted { lhs, rhs in
            if lhs.relevanceScore != rhs.relevanceScore { return lhs.relevanceScore > rhs.relevanceScore }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.ticker < rhs.ticker
        }
        return Array(sorted.prefix(8))
    }

    func selectThread(_ id: String?) {
        showingDailyBrief = false
        selectedThreadID = id
        guard let id else { selectedThread = nil; return }
        do {
            try database.markOpened(threadID: id)
            selectedThread = try database.loadThread(id: id)
            counts = try database.loadCounts()
            if let index = threads.firstIndex(where: { $0.id == id }), let selectedThread {
                threads[index] = selectedThread
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showDailyBrief() {
        selection = .library(.today)
        showingDailyBrief = true
        selectedThreadID = nil
        selectedThread = nil
        reload(preserveSelection: false)
    }

    func setState(_ state: ReadingState) {
        guard let id = selectedThreadID else { return }
        setState(state, threadID: id)
    }

    func setState(_ state: ReadingState, threadID: String) {
        do {
            try database.updateReadingState(threadID: threadID, state: state)
            briefThreadStates[threadID] = state
            withAnimation(.snappy(duration: 0.25)) { reload() }
        } catch { errorMessage = error.localizedDescription }
    }

    func toggleAttention() {
        guard let id = selectedThreadID else { return }
        do {
            try database.toggleAttention(threadID: id)
            withAnimation(.snappy(duration: 0.2)) { reload() }
        } catch { errorMessage = error.localizedDescription }
    }

    func syncNow() {
        guard !isSyncing else { return }
        isSyncing = true
        syncPhase = "正在读取新增邮件"
        Task {
            defer {
                isSyncing = false
                syncPhase = ""
            }
            do {
                if account?.authState == "connected" {
                    try await WorkerSyncRunner.sync(database: database, trigger: "manual")
                    let temporaryDirectory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("EmailReader-Luna-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
                    let analysisInputURL = temporaryDirectory.appendingPathComponent("analysis-input.json")
                    let outputURL = temporaryDirectory.appendingPathComponent("luna-pipeline.json")
                    let inputManifest = try database.exportDailyLunaInput(to: analysisInputURL)

                    syncPhase = "Luna Medium 正在逐封分析并整理"
                    try await LunaBriefRunner.run(analysisInputURL: analysisInputURL, outputURL: outputURL)
                    let analyzedCount = try database.installLunaPipeline(from: outputURL, expectedInput: inputManifest)
                    try database.recordRun(
                        trigger: "manual_luna",
                        status: "complete",
                        discovered: inputManifest.count,
                        analyzed: analyzedCount,
                        failed: 0,
                        detail: "Luna Medium 已完成逐封分类、摘要、投资 thesis 与每日简报。"
                    )
                } else {
                    try await Task.sleep(for: .milliseconds(750))
                    try database.recordRun(trigger: "manual", status: "waiting_auth", discovered: 0, analyzed: 0, failed: 0, detail: "尚未连接 Gmail。")
                }
                reload()
            } catch {
                errorMessage = "更新未完成，已保留上一份有效简报。\n\n\(error.localizedDescription)"
                _ = try? database.recordRun(trigger: "manual", status: "failed", discovered: 0, analyzed: 0, failed: 1, detail: error.localizedDescription)
                reload()
            }
        }
    }

    func openInGmail() {
        guard let url = selectedThread?.gmailURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openInGmail(threadID: String) {
        guard let thread = try? database.loadThread(id: threadID), let url = thread.gmailURL else { return }
        NSWorkspace.shared.open(url)
    }

    private static func providerLabel(_ rawValue: String?) -> String {
        guard let rawValue else { return "分析引擎未知" }
        if rawValue.contains("gpt-5.6-luna-medium") { return "Luna Medium" }
        if rawValue.hasPrefix("ollama:") {
            return "本机 \(rawValue.replacingOccurrences(of: "ollama:", with: ""))"
        }
        return rawValue
    }

    func checkAnalysisAvailability() {
#if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            analysisAvailability = "Apple 端侧模型可用"
        case .unavailable(.appleIntelligenceNotEnabled):
            analysisAvailability = "Apple Intelligence 尚未启用"
        case .unavailable(.deviceNotEligible):
            analysisAvailability = "此设备不支持 Apple Intelligence"
        case .unavailable(.modelNotReady):
            analysisAvailability = "端侧模型正在准备"
        case .unavailable:
            analysisAvailability = "端侧模型暂不可用"
        }
#else
        analysisAvailability = "当前 SDK 不含 Apple 端侧模型；Luna 流程不受影响"
#endif
    }

    func connectGmail(oauthConfigurationURL: URL) async throws {
        isAuthorizing = true
        defer { isAuthorizing = false }
        try database.setAccountAuthState("authorizing")
        reload()
        do {
            try await GoogleOAuthCoordinator().authorize(
                configurationURL: oauthConfigurationURL,
                loginHint: account?.email.isEmpty == false ? account?.email : nil
            )
            try database.setAccountAuthState("connected")
            _ = try await GmailSyncEngine(database: database).sync(trigger: "first_authorization")
            reload(preserveSelection: false)
        } catch {
            try? database.setAccountAuthState("disconnected")
            reload()
            throw error
        }
    }
}
