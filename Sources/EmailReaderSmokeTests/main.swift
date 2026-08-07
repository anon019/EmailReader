import EmailReaderCore
import Foundation

@main
struct EmailReaderSmokeTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EmailReaderSmoke-\(UUID().uuidString)")
        let database = EmailReaderDatabase(path: directory.appendingPathComponent("test.sqlite3"))
        defer { try? FileManager.default.removeItem(at: directory) }

        try database.bootstrap(seedDemo: true)
        let initial = try database.loadCounts()
        guard initial.all == 8, initial.unread > 0 else {
            throw SmokeFailure("demo bootstrap counts are invalid: \(initial)")
        }

        try database.updateReadingState(threadID: "demo-security", state: .completed)
        guard try database.loadThread(id: "demo-security")?.readingState == .completed else {
            throw SmokeFailure("reading state did not persist")
        }

        guard try database.loadThreads(filter: .all, category: .security).count == 1 else {
            throw SmokeFailure("category filter failed")
        }
        guard try database.loadThreads(filter: .all, search: "Stripe").count == 1 else {
            throw SmokeFailure("search failed")
        }

        try database.toggleAttention(threadID: "demo-newsletter")
        try database.updateAnalysis(
            threadID: "demo-newsletter",
            result: MailAnalysisResult(
                category: .reading, summary: "重新分析", whyImportant: "测试用户关注不被覆盖",
                actionItems: [], deadline: nil, importance: 60, needsAttention: false, confidence: 0.9
            )
        )
        guard let manuallyFocused = try database.loadThread(id: "demo-newsletter"),
              manuallyFocused.userAttention,
              !manuallyFocused.predictedAttention,
              manuallyFocused.needsAttention else {
            throw SmokeFailure("user attention was overwritten by model analysis")
        }
        let repeatedNewsletter = MailThread(
            id: manuallyFocused.id,
            accountID: manuallyFocused.accountID,
            providerThreadID: manuallyFocused.providerThreadID,
            subject: manuallyFocused.subject,
            senderName: manuallyFocused.senderName,
            senderEmail: manuallyFocused.senderEmail,
            receivedAt: manuallyFocused.receivedAt,
            snippet: manuallyFocused.snippet,
            bodyPlain: manuallyFocused.bodyPlain,
            category: manuallyFocused.category,
            readingState: manuallyFocused.readingState,
            gmailUnread: manuallyFocused.gmailUnread,
            needsAttention: false,
            importance: manuallyFocused.importance,
            summary: "浅层规则摘要不应覆盖深度摘要",
            whyImportant: manuallyFocused.whyImportant,
            actionItems: manuallyFocused.actionItems,
            deadline: manuallyFocused.deadline,
            confidence: manuallyFocused.confidence,
            messageCount: manuallyFocused.messageCount,
            hasAttachments: manuallyFocused.hasAttachments,
            gmailURL: manuallyFocused.gmailURL,
            isDemo: false
        )
        try database.upsertThread(repeatedNewsletter)
        guard try database.loadThread(id: manuallyFocused.id)?.summary == "重新分析" else {
            throw SmokeFailure("unchanged Gmail sync overwrote a cached deep summary")
        }

        let repeatedHeaders = GmailHeaderNormalizer.normalize([
            ("Received", "first-hop"),
            ("Subject", "A real message"),
            ("received", "last-hop")
        ])
        guard repeatedHeaders["received"] == "last-hop",
              repeatedHeaders["subject"] == "A real message" else {
            throw SmokeFailure("repeated Gmail headers were not normalized safely")
        }

        let analyzer = MailAnalyzer()
        let login = await analyzer.analyzeFallback(
            subject: "新设备登录提醒",
            sender: "security@broker.example",
            body: "您的账户刚刚通过一台新设备登录。"
        )
        guard login.category == .security, login.needsAttention else {
            throw SmokeFailure("real login security event was not prioritized")
        }
        let securityArticle = await analyzer.analyzeFallback(
            subject: "Research: Security is the next cloud growth driver",
            sender: "newsletter@substack.com",
            body: "View this post on the web. Unsubscribe. This is industry research."
        )
        guard securityArticle.category == .reading, !securityArticle.needsAttention else {
            throw SmokeFailure("security-themed newsletter was mistaken for an account event")
        }
        let portfolio = await analyzer.analyzeFallback(
            subject: "FYI：分析师评级变化",
            sender: "ibkr@interactivebrokers.com",
            body: "CRCL 买入评级减少一个。"
        )
        guard portfolio.category == .finance, portfolio.importance >= 60, !portfolio.needsAttention else {
            throw SmokeFailure("portfolio signal classification failed")
        }

        let brief = DailyBriefBuilder.build(from: try database.loadThreads(filter: .all))
        let briefIDs = brief.priority.map(\.threadID) + brief.noteworthy.map(\.threadID) + brief.later.map(\.threadID)
        guard Set(briefIDs).count == briefIDs.count else {
            throw SmokeFailure("daily brief contains duplicate thread mappings")
        }
        guard !briefIDs.contains("demo-security") else {
            throw SmokeFailure("completed attention item returned to the daily brief")
        }
        try database.saveDailyBrief(brief, provider: "test")
        let compactURL = directory.appendingPathComponent("compact-input.json")
        try database.exportCompactBriefInput(to: compactURL)
        let compact = try JSONDecoder().decode(
            CompactBriefInputEnvelope.self,
            from: Data(contentsOf: compactURL)
        )
        guard let compactText = String(data: try Data(contentsOf: compactURL), encoding: .utf8),
              compact.mails.count == briefIDs.count,
              !compactText.contains("bodyPlain") else {
            throw SmokeFailure("compact Luna input was incomplete or included raw bodies")
        }

        let alerts = (0..<5).map { index in
            MailThread(
                id: "alert-\(index)", accountID: "gmail-primary", providerThreadID: "alert-\(index)",
                subject: "账户风险 \(index)", senderName: "Security", senderEmail: "security@example.com",
                receivedAt: .now.addingTimeInterval(TimeInterval(-index * 60)), snippet: "风险提醒", bodyPlain: "风险提醒",
                category: .security, readingState: .unread, gmailUnread: true, needsAttention: true,
                importance: 95, summary: "检测到风险", whyImportant: "需要核实", actionItems: ["核实"],
                deadline: nil, confidence: 0.95, messageCount: 1, hasAttachments: false,
                gmailURL: nil, isDemo: false
            )
        }
        let alertBrief = DailyBriefBuilder.build(from: alerts)
        guard alertBrief.priority.count == 5, alertBrief.lowPriorityCount == 0 else {
            throw SmokeFailure("unresolved alerts were hidden by a presentation cap")
        }

        let catchupNow = Date()
        let missedWindowThread = MailThread(
            id: "missed-window", accountID: "gmail-primary", providerThreadID: "missed-window",
            subject: "停机期间的重要研究", senderName: "Research", senderEmail: "research@example.com",
            receivedAt: catchupNow.addingTimeInterval(-40 * 60 * 60), snippet: "重要变化", bodyPlain: "重要变化",
            category: .reading, readingState: .unread, gmailUnread: true, needsAttention: false,
            importance: 70, summary: "停机期间收到的重要研究", whyImportant: "需要补入下一份简报", actionItems: [],
            deadline: nil, confidence: 0.9, messageCount: 1, hasAttachments: false,
            gmailURL: nil, isDemo: false
        )
        let defaultWindowBrief = DailyBriefBuilder.build(from: [missedWindowThread], now: catchupNow)
        let catchupBrief = DailyBriefBuilder.build(
            from: [missedWindowThread],
            now: catchupNow,
            windowStart: catchupNow.addingTimeInterval(-48 * 60 * 60)
        )
        guard defaultWindowBrief.total == 0,
              catchupBrief.total == 1,
              catchupBrief.noteworthy.first?.threadID == missedWindowThread.id else {
            throw SmokeFailure("missed daily run was not covered by the catch-up window")
        }

        let sourceItem = DailyBriefItem(
            id: "duplicate", threadID: "demo-welcome", title: "重复", sender: "Demo",
            summary: "重复", whyItMatters: "测试", suggestedAction: nil, category: .notification
        )
        let invalidBrief = DailyBrief(
            date: "2026-08-07", generatedAt: ISO8601DateFormatter().string(from: .now), periodLabel: "过去24小时",
            headline: "重复映射测试", overview: "测试", total: 2,
            priority: [sourceItem, sourceItem], noteworthy: [], later: [], lowPriorityCount: 0
        )
        let invalidURL = directory.appendingPathComponent("invalid-brief.json")
        try JSONEncoder().encode(invalidBrief).write(to: invalidURL)
        do {
            try database.installDailyBrief(from: invalidURL)
            throw SmokeFailure("duplicate cloud brief mappings were accepted")
        } catch is SmokeFailure {
            throw SmokeFailure("duplicate cloud brief mappings were accepted")
        } catch {
            // Expected validation failure.
        }

        let noisyActionItem = DailyBriefItem(
            id: "noisy-action", threadID: "demo-invoice", title: "无效行动", sender: "Demo",
            summary: "测试", whyItMatters: "测试", suggestedAction: "null", category: .reading
        )
        let noisyBrief = DailyBrief(
            date: "2026-08-07", generatedAt: ISO8601DateFormatter().string(from: .now), periodLabel: "过去24小时",
            headline: "行动清洗测试", overview: "测试", total: 1,
            priority: [], noteworthy: [noisyActionItem], later: [], lowPriorityCount: 0
        )
        let noisyURL = directory.appendingPathComponent("noisy-brief.json")
        try JSONEncoder().encode(noisyBrief).write(to: noisyURL)
        try database.installDailyBrief(from: noisyURL)
        guard try database.loadDailyBrief().noteworthy.first?.suggestedAction == nil else {
            throw SmokeFailure("non-priority cloud action was not sanitized")
        }

        let historyBrief = DailyBrief(
            date: "2026-08-06", generatedAt: ISO8601DateFormatter().string(from: .now), periodLabel: "过去24小时",
            headline: "历史简报保存测试", overview: "测试", total: 0,
            priority: [], noteworthy: [], later: [], lowPriorityCount: 0
        )
        try database.saveDailyBrief(historyBrief, provider: "test")
        guard try database.loadBriefHistory().contains(where: { $0.headline == historyBrief.headline }) else {
            throw SmokeFailure("daily brief history did not persist")
        }

        print("EmailReader smoke tests passed: bootstrap, state, attention ownership, category, search, headers, classification, brief mapping, alert safety, catch-up window, brief history, install validation")
    }
}

private struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
