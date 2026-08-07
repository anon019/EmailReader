import AppKit
import Combine
import EmailReaderCore
import Foundation
import FoundationModels
import SwiftUI

enum SidebarSelection: Hashable {
    case library(LibraryFilter)
    case category(MailCategory)
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
        brief.priority.isEmpty ? "今天没有必须处理的事项" : "今天只需要处理 \(brief.priority.count) 件事"
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
                    syncPhase = "正在本机提炼与重新排序"
                    _ = try await LocalBriefEngine(database: database, model: "qwen3.5:4b").generate()
                } else {
                    try await Task.sleep(for: .milliseconds(750))
                    try database.recordRun(trigger: "manual", status: "waiting_auth", discovered: 0, analyzed: 0, failed: 0, detail: "尚未连接 Gmail。")
                }
                reload()
            } catch {
                errorMessage = error.localizedDescription
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
