import Foundation

public struct GmailSyncResult: Sendable {
    public let discovered: Int
    public let analyzed: Int
    public let failed: Int
}

public enum GmailHeaderNormalizer {
    public static func normalize(_ headers: [(String, String)]) -> [String: String] {
        var result: [String: String] = [:]
        for (name, value) in headers {
            result[name.lowercased()] = value
        }
        return result
    }
}

public final class GmailSyncEngine: Sendable {
    private let database: EmailReaderDatabase
    private let client: GmailClient
    private let analyzer: MailAnalyzer

    public init(database: EmailReaderDatabase = .shared, client: GmailClient = GmailClient(), analyzer: MailAnalyzer = MailAnalyzer()) {
        self.database = database
        self.client = client
        self.analyzer = analyzer
    }

    public func sync(trigger: String) async throws -> GmailSyncResult {
        let profile = try await client.profile()
        let priorHistory = try database.lastHistoryID()
        let lookbackDays = Int((try database.setting("initial_lookback_days")) ?? "7") ?? 7
        let needsSevenDayBackfill = try database.setting("seven_day_backfill_v2") != "complete"
        let threadIDs: [String]
        do {
            if needsSevenDayBackfill {
                var ids = Set(try await client.listRecentThreadIDs(days: lookbackDays, limit: 500))
                if let priorHistory, !priorHistory.isEmpty {
                    ids.formUnion(try await client.changedThreadIDs(since: priorHistory))
                }
                threadIDs = Array(ids)
            } else if let priorHistory, !priorHistory.isEmpty {
                threadIDs = try await client.changedThreadIDs(since: priorHistory)
            } else {
                threadIDs = try await client.listRecentThreadIDs(days: lookbackDays, limit: 500)
            }
        } catch let error as GmailClientError where error.statusCode == 404 {
            threadIDs = try await client.listRecentThreadIDs(days: lookbackDays, limit: 500)
        }

        var analyzed = 0
        var failed = 0
        for id in threadIDs {
            do {
                let payload = try await client.thread(id: id)
                guard let parsed = Self.parse(payload) else { continue }
                let analysis = await analyzer.analyze(subject: parsed.subject, sender: parsed.senderEmail, body: parsed.body)
                let thread = MailThread(
                    id: "gmail:\(payload.id)",
                    accountID: "gmail-primary",
                    providerThreadID: payload.id,
                    subject: parsed.subject,
                    senderName: parsed.senderName,
                    senderEmail: parsed.senderEmail,
                    receivedAt: parsed.receivedAt,
                    snippet: parsed.snippet,
                    bodyPlain: parsed.body,
                    category: analysis.category,
                    readingState: parsed.gmailUnread ? .unread : .read,
                    gmailUnread: parsed.gmailUnread,
                    needsAttention: analysis.needsAttention,
                    importance: analysis.importance,
                    summary: analysis.summary,
                    whyImportant: analysis.whyImportant,
                    actionItems: analysis.actionItems,
                    deadline: analysis.deadline,
                    confidence: analysis.confidence,
                    messageCount: payload.messages.count,
                    hasAttachments: parsed.hasAttachments,
                    gmailURL: URL(string: "https://mail.google.com/mail/u/0/#inbox/\(payload.id)"),
                    isDemo: false
                )
                try database.upsertThread(thread)
                analyzed += 1
            } catch {
                failed += 1
            }
        }

        try database.removeDemoThreads()
        if failed == 0 {
            try database.finishAccountSync(email: profile.emailAddress, historyID: profile.historyId)
            if needsSevenDayBackfill {
                try database.setSetting("seven_day_backfill_v2", value: "complete")
            }
        } else {
            // Do not advance Gmail's history watermark after a partial fetch. The
            // same changed thread IDs must remain eligible for the next retry.
            try database.finishPartialAccountSync(email: profile.emailAddress)
        }
        let detail: String
        if threadIDs.isEmpty {
            detail = "没有发现新邮件。"
        } else if failed == 0 {
            detail = needsSevenDayBackfill
                ? "已补齐过去 \(lookbackDays) 天并合并增量，共 \(threadIDs.count) 个线程，已解读 \(analyzed) 个。"
                : "新增或变化 \(threadIDs.count) 个线程，已解读 \(analyzed) 个。"
        } else {
            detail = "发现 \(threadIDs.count) 个变化，完成 \(analyzed) 个，\(failed) 个将在下次重试。"
        }
        try database.recordRun(trigger: trigger, status: failed == 0 ? "complete" : "partial", discovered: threadIDs.count, analyzed: analyzed, failed: failed, detail: detail)
        return GmailSyncResult(discovered: threadIDs.count, analyzed: analyzed, failed: failed)
    }

    @discardableResult
    public func reanalyzeStoredThreads() async throws -> Int {
        let threads = try database.loadThreads(filter: .all).filter { !$0.isDemo }
        for thread in threads {
            let result = await analyzer.analyze(
                subject: thread.subject,
                sender: thread.senderEmail,
                body: thread.bodyPlain
            )
            try database.updateAnalysis(threadID: thread.id, result: result)
        }
        try database.setSetting("analysis_rules_version", value: "2")
        return threads.count
    }

    private struct ParsedThread {
        let subject: String
        let senderName: String
        let senderEmail: String
        let receivedAt: Date
        let snippet: String
        let body: String
        let gmailUnread: Bool
        let hasAttachments: Bool
    }

    private static func parse(_ thread: GmailThreadPayload) -> ParsedThread? {
        guard let message = thread.messages.max(by: { milliseconds($0.internalDate) < milliseconds($1.internalDate) }) else { return nil }
        // RFC 5322 permits repeated fields (most commonly Received). Building a
        // Dictionary with uniqueKeysWithValues traps when Gmail returns them.
        let headers = GmailHeaderNormalizer.normalize(
            (message.payload?.headers ?? []).map { ($0.name, $0.value) }
        )
        let from = parseSender(headers["from"] ?? "")
        let subject = headers["subject"] ?? "（无主题）"
        let receivedAt = Date(timeIntervalSince1970: TimeInterval(milliseconds(message.internalDate)) / 1000)
        let plain = findBody(message.payload, mimeType: "text/plain")
        let html = findBody(message.payload, mimeType: "text/html")
        let body = plain ?? html.map(stripHTML) ?? message.snippet ?? ""
        return ParsedThread(
            subject: subject,
            senderName: from.name,
            senderEmail: from.email,
            receivedAt: receivedAt,
            snippet: message.snippet ?? String(body.prefix(180)),
            body: body,
            gmailUnread: message.labelIds?.contains("UNREAD") == true,
            hasAttachments: hasAttachment(message.payload)
        )
    }

    private static func findBody(_ payload: GmailThreadPayload.Message.Payload?, mimeType: String) -> String? {
        guard let payload else { return nil }
        if payload.mimeType == mimeType, let encoded = payload.body?.data, let decoded = decodeBase64URL(encoded) { return decoded }
        for part in payload.parts ?? [] {
            if let found = findBody(part, mimeType: mimeType), !found.isEmpty { return found }
        }
        return nil
    }

    private static func hasAttachment(_ payload: GmailThreadPayload.Message.Payload?) -> Bool {
        guard let payload else { return false }
        if !(payload.filename ?? "").isEmpty { return true }
        return (payload.parts ?? []).contains { hasAttachment($0) }
    }

    private static func decodeBase64URL(_ value: String) -> String? {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func stripHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: [.caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseSender(_ value: String) -> (name: String, email: String) {
        if let open = value.lastIndex(of: "<"), let close = value.lastIndex(of: ">"), open < close {
            let name = value[..<open].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (name.isEmpty ? String(value[value.index(after: open)..<close]) : name, String(value[value.index(after: open)..<close]))
        }
        return (value, value)
    }

    private static func milliseconds(_ value: String?) -> Int64 { Int64(value ?? "0") ?? 0 }
}
