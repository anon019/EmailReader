import Foundation

public enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case today = "今日简报"
    case unread = "未读原件"
    case later = "稍后阅读"
    case attention = "风险预警"
    case completed = "已完成"
    case history = "历史简报"
    case all = "邮件来源"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .today: "sun.horizon"
        case .unread: "circle.fill"
        case .later: "bookmark"
        case .attention: "exclamationmark.circle"
        case .completed: "checkmark.circle"
        case .history: "clock.arrow.circlepath"
        case .all: "tray.full"
        }
    }
}

public enum ReadingState: String, CaseIterable, Codable, Sendable {
    case unread
    case read
    case later
    case completed

    public var label: String {
        switch self {
        case .unread: "未读"
        case .read: "已读"
        case .later: "待看"
        case .completed: "已处理"
        }
    }
}

public enum MailCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case action = "行动事项"
    case security = "账户与安全"
    case finance = "账单与财务"
    case investment = "投资研究"
    case project = "工作与项目"
    case reading = "资讯与阅读"
    case personal = "个人往来"
    case notification = "一般通知"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .action: "bolt"
        case .security: "lock.shield"
        case .finance: "creditcard"
        case .investment: "chart.line.uptrend.xyaxis"
        case .project: "folder"
        case .reading: "newspaper"
        case .personal: "person.2"
        case .notification: "bell"
        }
    }
}

public struct MailAccount: Identifiable, Hashable, Sendable {
    public let id: String
    public let email: String
    public let provider: String
    public let displayName: String
    public let authState: String
    public let lastSyncAt: Date?

    public init(id: String, email: String, provider: String, displayName: String, authState: String, lastSyncAt: Date?) {
        self.id = id
        self.email = email
        self.provider = provider
        self.displayName = displayName
        self.authState = authState
        self.lastSyncAt = lastSyncAt
    }
}

public struct MailThread: Identifiable, Hashable, Sendable {
    public let id: String
    public let accountID: String
    public let providerThreadID: String
    public let subject: String
    public let senderName: String
    public let senderEmail: String
    public let receivedAt: Date
    public let snippet: String
    public let bodyPlain: String
    public let category: MailCategory
    public let readingState: ReadingState
    public let gmailUnread: Bool
    public let needsAttention: Bool
    public let predictedAttention: Bool
    public let userAttention: Bool
    public let importance: Int
    public let summary: String
    public let investmentThesis: InvestmentThesis?
    public let whyImportant: String
    public let actionItems: [String]
    public let deadline: String?
    public let confidence: Double
    public let messageCount: Int
    public let hasAttachments: Bool
    public let gmailURL: URL?
    public let isDemo: Bool

    public init(
        id: String,
        accountID: String,
        providerThreadID: String,
        subject: String,
        senderName: String,
        senderEmail: String,
        receivedAt: Date,
        snippet: String,
        bodyPlain: String,
        category: MailCategory,
        readingState: ReadingState,
        gmailUnread: Bool,
        needsAttention: Bool,
        predictedAttention: Bool? = nil,
        userAttention: Bool = false,
        importance: Int,
        summary: String,
        investmentThesis: InvestmentThesis? = nil,
        whyImportant: String,
        actionItems: [String],
        deadline: String?,
        confidence: Double,
        messageCount: Int,
        hasAttachments: Bool,
        gmailURL: URL?,
        isDemo: Bool
    ) {
        self.id = id
        self.accountID = accountID
        self.providerThreadID = providerThreadID
        self.subject = subject
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.receivedAt = receivedAt
        self.snippet = snippet
        self.bodyPlain = bodyPlain
        self.category = category
        self.readingState = readingState
        self.gmailUnread = gmailUnread
        let predictedAttention = predictedAttention ?? needsAttention
        self.predictedAttention = predictedAttention
        self.userAttention = userAttention
        self.needsAttention = predictedAttention || userAttention
        self.importance = importance
        self.summary = summary
        self.investmentThesis = investmentThesis
        self.whyImportant = whyImportant
        self.actionItems = actionItems
        self.deadline = deadline
        self.confidence = confidence
        self.messageCount = messageCount
        self.hasAttachments = hasAttachments
        self.gmailURL = gmailURL
        self.isDemo = isDemo
    }
}

public struct InvestmentThesis: Codable, Hashable, Sendable {
    public let thesis: String
    public let evidence: [String]
    public let catalysts: [String]
    public let risks: [String]
    public let tickers: [String]
    public let horizon: String?

    public init(
        thesis: String,
        evidence: [String],
        catalysts: [String],
        risks: [String],
        tickers: [String],
        horizon: String?
    ) {
        self.thesis = thesis
        self.evidence = evidence
        self.catalysts = catalysts
        self.risks = risks
        self.tickers = tickers
        self.horizon = horizon
    }
}

public struct FilterCounts: Sendable, Equatable {
    public var today = 0
    public var unread = 0
    public var later = 0
    public var attention = 0
    public var completed = 0
    public var history = 0
    public var all = 0

    public init() {}

    public subscript(filter: LibraryFilter) -> Int {
        switch filter {
        case .today: today
        case .unread: unread
        case .later: later
        case .attention: attention
        case .completed: completed
        case .history: history
        case .all: all
        }
    }
}

public struct SyncReceipt: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let trigger: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let status: String
    public let discoveredCount: Int
    public let analyzedCount: Int
    public let failedCount: Int
    public let detail: String

    public init(id: Int64, trigger: String, startedAt: Date, finishedAt: Date?, status: String, discoveredCount: Int, analyzedCount: Int, failedCount: Int, detail: String) {
        self.id = id
        self.trigger = trigger
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.discoveredCount = discoveredCount
        self.analyzedCount = analyzedCount
        self.failedCount = failedCount
        self.detail = detail
    }
}

public struct DailyBriefItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let threadID: String
    public let title: String
    public let sender: String
    public let summary: String
    public let investmentThesis: InvestmentThesis?
    public let whyItMatters: String
    public let suggestedAction: String?
    public let category: MailCategory

    public init(
        id: String,
        threadID: String,
        title: String,
        sender: String,
        summary: String,
        investmentThesis: InvestmentThesis? = nil,
        whyItMatters: String,
        suggestedAction: String?,
        category: MailCategory
    ) {
        self.id = id
        self.threadID = threadID
        self.title = title
        self.sender = sender
        self.summary = summary
        self.investmentThesis = investmentThesis
        self.whyItMatters = whyItMatters
        self.suggestedAction = suggestedAction
        self.category = category
    }
}

public struct DailyBrief: Codable, Sendable, Equatable {
    public let date: String
    public let generatedAt: String
    public let periodLabel: String
    public let headline: String
    public let overview: String
    public let total: Int
    public let priority: [DailyBriefItem]
    public let noteworthy: [DailyBriefItem]
    public let later: [DailyBriefItem]
    public let lowPriorityCount: Int

    public var urgent: Int { priority.count }
    public var actionable: Int { priority.filter { $0.suggestedAction != nil }.count }
    public var reading: Int { noteworthy.count + later.count }

    public init(
        date: String,
        generatedAt: String,
        periodLabel: String,
        headline: String,
        overview: String,
        total: Int,
        priority: [DailyBriefItem],
        noteworthy: [DailyBriefItem],
        later: [DailyBriefItem],
        lowPriorityCount: Int
    ) {
        self.date = date
        self.generatedAt = generatedAt
        self.periodLabel = periodLabel
        self.headline = headline
        self.overview = overview
        self.total = total
        self.priority = priority
        self.noteworthy = noteworthy
        self.later = later
        self.lowPriorityCount = lowPriorityCount
    }

    public static var empty: DailyBrief {
        DailyBrief(
            date: "",
            generatedAt: "",
            periodLabel: "今日",
            headline: "今天还没有需要整理的新邮件",
            overview: "Codex 完成下一次整理后，重点、行动项与延伸阅读会出现在这里。",
            total: 0,
            priority: [],
            noteworthy: [],
            later: [],
            lowPriorityCount: 0
        )
    }
}

public struct BriefInputMail: Codable, Sendable {
    public let id: String
    public let senderName: String
    public let senderEmail: String
    public let subject: String
    public let receivedAt: String
    public let snippet: String
    public let bodyPlain: String
    public let hasAttachments: Bool
}

public struct BriefInputEnvelope: Codable, Sendable {
    public let generatedAt: String
    public let scope: String
    public let mails: [BriefInputMail]
}

public struct CompactBriefInputMail: Codable, Sendable {
    public let id: String
    public let sender: String
    public let subject: String
    public let receivedAt: String
    public let category: MailCategory
    public let summary: String
    public let investmentThesis: InvestmentThesis?
    public let whyImportant: String
    public let suggestedAction: String?
    public let importance: Int
    public let needsAttention: Bool
}

public struct CompactBriefInputEnvelope: Codable, Sendable {
    public let generatedAt: String
    public let scope: String
    public let total: Int
    public let lowPriorityCount: Int
    public let mails: [CompactBriefInputMail]
}
