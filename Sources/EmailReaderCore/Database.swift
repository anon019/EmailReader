import CSQLite
import Foundation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum EmailReaderDatabaseError: Error, LocalizedError {
    case open(String)
    case prepare(String)
    case step(String)

    public var errorDescription: String? {
        switch self {
        case .open(let message), .prepare(let message), .step(let message): message
        }
    }
}

public final class EmailReaderDatabase: @unchecked Sendable {
    public static let shared = EmailReaderDatabase()
    public let path: URL

    public init(path: URL? = nil) {
        if let path {
            self.path = path
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.path = base.appendingPathComponent("EmailReader/email_reader.sqlite3")
        }
    }

    public func bootstrap(seedDemo: Bool = true) throws {
        try withDatabase { db in
            try executeScript(db, sql: Self.schema)
            let threadColumns = Set(try rows(db, sql: "PRAGMA table_info(threads)").map { $0.string("name") })
            if !threadColumns.contains("user_attention") {
                try execute(db, sql: "ALTER TABLE threads ADD COLUMN user_attention INTEGER NOT NULL DEFAULT 0")
            }
            let now = Self.isoDate(.now)
            try execute(db, sql: "INSERT OR IGNORE INTO accounts(id,email,provider,display_name,auth_state,created_at,updated_at) VALUES(?,?,?,?,?,?,?)", values: ["gmail-primary", "", "gmail", "", "disconnected", now, now])
            try execute(db, sql: "INSERT OR IGNORE INTO settings(key,value) VALUES('schedule_time','07:30'),('analysis_provider','codex_daily_brief'),('initial_lookback_days','7'),('block_remote_images','1')")
            if seedDemo {
                let existing = try scalarInt(db, sql: "SELECT COUNT(*) FROM threads")
                if existing == 0 { try seedDemoData(db) }
            }
        }
    }

    public func loadAccount() throws -> MailAccount? {
        try withDatabase { db in
            guard let row = try rows(db, sql: "SELECT * FROM accounts ORDER BY created_at LIMIT 1").first else { return nil }
            return MailAccount(
                id: row.string("id"),
                email: row.string("email"),
                provider: row.string("provider"),
                displayName: row.string("display_name"),
                authState: row.string("auth_state"),
                lastSyncAt: Self.parseDate(row.optionalString("last_sync_at"))
            )
        }
    }

    public func loadThreads(filter: LibraryFilter, category: MailCategory? = nil, search: String = "") throws -> [MailThread] {
        try withDatabase { db in
            var clauses: [String] = []
            var values: [String] = []
            switch filter {
            case .today:
                clauses.append("date(received_at, 'localtime') = date('now', 'localtime')")
            case .unread:
                clauses.append("reading_state = 'unread'")
            case .later:
                clauses.append("reading_state = 'later'")
            case .attention:
                clauses.append("(needs_attention = 1 OR user_attention = 1)")
            case .completed:
                clauses.append("reading_state = 'completed'")
            case .history:
                clauses.append("1 = 0")
            case .all:
                break
            }
            if let category {
                clauses.append("category = ?")
                values.append(category.rawValue)
            }
            if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clauses.append("(subject LIKE ? OR sender_name LIKE ? OR sender_email LIKE ? OR summary LIKE ? OR body_plain LIKE ?)")
                let pattern = "%\(search)%"
                values.append(contentsOf: Array(repeating: pattern, count: 5))
            }
            let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            let sql = "SELECT * FROM threads \(whereSQL) ORDER BY (needs_attention OR user_attention) DESC, importance DESC, received_at DESC"
            return try rows(db, sql: sql, values: values).map(Self.thread(from:))
        }
    }

    public func loadThread(id: String) throws -> MailThread? {
        try withDatabase { db in
            try rows(db, sql: "SELECT * FROM threads WHERE id = ?", values: [id]).first.map(Self.thread(from:))
        }
    }

    public func loadCounts() throws -> FilterCounts {
        try withDatabase { db in
            var counts = FilterCounts()
            counts.today = try scalarInt(db, sql: "SELECT COUNT(*) FROM threads WHERE date(received_at, 'localtime') = date('now', 'localtime')")
            counts.unread = try scalarInt(db, sql: "SELECT COUNT(*) FROM threads WHERE reading_state='unread'")
            counts.later = try scalarInt(db, sql: "SELECT COUNT(*) FROM threads WHERE reading_state='later'")
            counts.attention = try scalarInt(db, sql: "SELECT COUNT(*) FROM threads WHERE needs_attention=1 OR user_attention=1")
            counts.completed = try scalarInt(db, sql: "SELECT COUNT(*) FROM threads WHERE reading_state='completed'")
            counts.all = try scalarInt(db, sql: "SELECT COUNT(*) FROM threads")
            return counts
        }
    }

    public func loadDailyBrief() throws -> DailyBrief {
        if let data = try? Data(contentsOf: dailyBriefURL),
           let brief = try? JSONDecoder().decode(DailyBrief.self, from: data) {
            return brief
        }
        return DailyBriefBuilder.build(from: try loadThreads(filter: .all))
    }

    public func loadBriefHistory(limit: Int = 30) throws -> [DailyBrief] {
        guard FileManager.default.fileExists(atPath: briefHistoryDirectory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: briefHistoryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(max(1, limit))
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(DailyBrief.self, from: data)
            }
    }

    public func exportBriefInput(to destination: URL, days: Int = 7) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, days), to: .now) ?? .distantPast
        let mails = try loadThreads(filter: .all)
            .filter { !$0.isDemo && $0.receivedAt >= cutoff }
            .map {
                BriefInputMail(
                    id: $0.id,
                    senderName: $0.senderName,
                    senderEmail: $0.senderEmail,
                    subject: $0.subject,
                    receivedAt: Self.isoDate($0.receivedAt),
                    snippet: String($0.snippet.prefix(800)),
                    bodyPlain: String($0.bodyPlain.prefix(12_000)),
                    hasAttachments: $0.hasAttachments
                )
            }
        let envelope = BriefInputEnvelope(
            generatedAt: Self.isoDate(.now),
            scope: "过去 \(days) 天；每日简报优先总结最近 24 小时，同时可引用一周内仍值得关注的上下文。",
            mails: mails
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(envelope).write(to: destination, options: .atomic)
    }

    public func exportCompactBriefInput(to destination: URL) throws {
        let brief = try loadDailyBrief()
        let selectedIDs = brief.priority.map(\.threadID) + brief.noteworthy.map(\.threadID) + brief.later.map(\.threadID)
        let threadByID = Dictionary(uniqueKeysWithValues: try loadThreads(filter: .all).map { ($0.id, $0) })
        let mails = selectedIDs.compactMap { id -> CompactBriefInputMail? in
            guard let thread = threadByID[id] else { return nil }
            return CompactBriefInputMail(
                id: thread.id,
                sender: thread.senderName.isEmpty ? thread.senderEmail : thread.senderName,
                subject: thread.subject,
                receivedAt: Self.isoDate(thread.receivedAt),
                category: thread.category,
                summary: thread.summary,
                whyImportant: thread.whyImportant,
                suggestedAction: thread.actionItems.first,
                importance: thread.importance,
                needsAttention: thread.needsAttention
            )
        }
        let envelope = CompactBriefInputEnvelope(
            generatedAt: Self.isoDate(.now),
            scope: brief.periodLabel,
            total: brief.total,
            lowPriorityCount: brief.lowPriorityCount,
            mails: mails
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(envelope).write(to: destination, options: .atomic)
    }

    public func installDailyBrief(from source: URL) throws {
        let sourceData = try Data(contentsOf: source)
        let decoded = try JSONDecoder().decode(DailyBrief.self, from: sourceData)
        let brief = DailyBrief(
            date: decoded.date,
            generatedAt: decoded.generatedAt,
            periodLabel: decoded.periodLabel,
            headline: decoded.headline,
            overview: decoded.overview,
            total: decoded.total,
            priority: decoded.priority.map { Self.normalizedBriefItem($0, allowsAction: true) },
            noteworthy: decoded.noteworthy.map { Self.normalizedBriefItem($0, allowsAction: false) },
            later: decoded.later.map { Self.normalizedBriefItem($0, allowsAction: false) },
            lowPriorityCount: decoded.lowPriorityCount
        )
        let knownIDs = Set(try loadThreads(filter: .all).map(\.id))
        let items = brief.priority + brief.noteworthy + brief.later
        let referencedIDs = items.map(\.threadID)
        let itemIDs = items.map(\.id)
        guard !brief.date.isEmpty,
              !brief.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              brief.total >= 0,
              brief.lowPriorityCount >= 0,
              brief.priority.count <= 8,
              brief.noteworthy.count <= 5,
              brief.later.count <= 5,
              Set(referencedIDs).count == referencedIDs.count,
              Set(itemIDs).count == itemIDs.count else {
            throw EmailReaderDatabaseError.step("简报结构或计数不合法，未安装。")
        }
        guard referencedIDs.allSatisfy(knownIDs.contains) else {
            throw EmailReaderDatabaseError.step("简报引用了本地不存在的邮件，未安装。")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(brief)
        try FileManager.default.createDirectory(at: dailyBriefURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: dailyBriefURL, options: .atomic)
        try archiveBrief(data: data, date: brief.date)
        try setSetting("last_codex_brief_at", value: Self.isoDate(.now))
        try setSetting("last_brief_provider", value: "codex:gpt-5.6-luna-medium")
        try setSetting("last_brief_at", value: Self.isoDate(.now))
    }

    public func saveDailyBrief(_ brief: DailyBrief, provider: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: dailyBriefURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(brief)
        try data.write(to: dailyBriefURL, options: .atomic)
        try archiveBrief(data: data, date: brief.date)
        try setSetting("last_brief_provider", value: provider)
        try setSetting("last_brief_at", value: Self.isoDate(.now))
    }

    public func updateAnalysis(threadID: String, result: MailAnalysisResult) throws {
        try withDatabase { db in
            try execute(db, sql: """
                UPDATE threads SET category=?, needs_attention=?, importance=?, summary=?, why_important=?,
                  action_items=?, deadline=?, confidence=?, updated_at=? WHERE id=?
                """, values: [
                    result.category.rawValue, result.needsAttention ? "1" : "0", String(result.importance),
                    result.summary, result.whyImportant, result.actionItems.joined(separator: "\n"),
                    result.deadline ?? "", String(result.confidence), Self.isoDate(.now), threadID
                ])
        }
    }

    public func updateReadingState(threadID: String, state: ReadingState) throws {
        try withDatabase { db in
            try execute(db, sql: "UPDATE threads SET reading_state=?, updated_at=? WHERE id=?", values: [state.rawValue, Self.isoDate(.now), threadID])
        }
    }

    public func markOpened(threadID: String) throws {
        try withDatabase { db in
            try execute(db, sql: "UPDATE threads SET reading_state=CASE WHEN reading_state='unread' THEN 'read' ELSE reading_state END, updated_at=? WHERE id=?", values: [Self.isoDate(.now), threadID])
        }
    }

    public func toggleAttention(threadID: String) throws {
        try withDatabase { db in
            try execute(db, sql: "UPDATE threads SET user_attention=CASE user_attention WHEN 1 THEN 0 ELSE 1 END, updated_at=? WHERE id=?", values: [Self.isoDate(.now), threadID])
        }
    }

    public func loadLatestReceipt() throws -> SyncReceipt? {
        try withDatabase { db in
            guard let row = try rows(db, sql: "SELECT * FROM sync_runs ORDER BY id DESC LIMIT 1").first else { return nil }
            return SyncReceipt(
                id: Int64(row.int("id")),
                trigger: row.string("trigger"),
                startedAt: Self.parseDate(row.optionalString("started_at")) ?? .now,
                finishedAt: Self.parseDate(row.optionalString("finished_at")),
                status: row.string("status"),
                discoveredCount: row.int("discovered_count"),
                analyzedCount: row.int("analyzed_count"),
                failedCount: row.int("failed_count"),
                detail: row.string("detail")
            )
        }
    }

    @discardableResult
    public func recordRun(trigger: String, status: String, discovered: Int, analyzed: Int, failed: Int, detail: String) throws -> Int64 {
        try withDatabase { db in
            let now = Self.isoDate(.now)
            try execute(db, sql: "INSERT INTO sync_runs(trigger,started_at,finished_at,status,discovered_count,analyzed_count,failed_count,detail) VALUES(?,?,?,?,?,?,?,?)", values: [trigger, now, now, status, String(discovered), String(analyzed), String(failed), detail])
            return sqlite3_last_insert_rowid(db)
        }
    }

    public func setAccountAuthState(_ state: String, email: String? = nil) throws {
        try withDatabase { db in
            if let email {
                try execute(db, sql: "UPDATE accounts SET email=?, display_name=?, auth_state=?, updated_at=? WHERE id='gmail-primary'", values: [email, email, state, Self.isoDate(.now)])
            } else {
                try execute(db, sql: "UPDATE accounts SET auth_state=?, updated_at=? WHERE id='gmail-primary'", values: [state, Self.isoDate(.now)])
            }
        }
    }

    public func lastHistoryID() throws -> String? {
        try withDatabase { db in
            try rows(db, sql: "SELECT last_history_id FROM accounts WHERE id='gmail-primary'").first?.optionalString("last_history_id")
        }
    }

    public func finishAccountSync(email: String, historyID: String) throws {
        try withDatabase { db in
            try execute(db, sql: "UPDATE accounts SET email=?,display_name=?,auth_state='connected',last_history_id=?,last_sync_at=?,updated_at=? WHERE id='gmail-primary'", values: [email, email, historyID, Self.isoDate(.now), Self.isoDate(.now)])
        }
    }

    public func finishPartialAccountSync(email: String) throws {
        try withDatabase { db in
            try execute(db, sql: "UPDATE accounts SET email=?,display_name=?,auth_state='connected',last_sync_at=?,updated_at=? WHERE id='gmail-primary'", values: [email, email, Self.isoDate(.now), Self.isoDate(.now)])
        }
    }

    public func removeDemoThreads() throws {
        try withDatabase { db in
            try execute(db, sql: "DELETE FROM threads WHERE is_demo=1")
        }
    }

    public func upsertThread(_ thread: MailThread) throws {
        try withDatabase { db in
            try execute(db, sql: """
                INSERT INTO threads(
                  id,account_id,provider_thread_id,subject,sender_name,sender_email,received_at,snippet,body_plain,
                  category,reading_state,gmail_unread,needs_attention,importance,summary,why_important,
                  action_items,deadline,confidence,message_count,has_attachments,gmail_url,is_demo,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                  subject=excluded.subject,sender_name=excluded.sender_name,sender_email=excluded.sender_email,
                  received_at=excluded.received_at,snippet=excluded.snippet,body_plain=excluded.body_plain,
                  category=excluded.category,gmail_unread=excluded.gmail_unread,importance=excluded.importance,
                  summary=CASE WHEN threads.body_plain=excluded.body_plain AND threads.summary<>''
                    THEN threads.summary ELSE excluded.summary END,
                  why_important=excluded.why_important,action_items=excluded.action_items,
                  deadline=excluded.deadline,confidence=excluded.confidence,message_count=excluded.message_count,
                  has_attachments=excluded.has_attachments,gmail_url=excluded.gmail_url,is_demo=0,updated_at=excluded.updated_at
                """, values: [
                    thread.id, thread.accountID, thread.providerThreadID, thread.subject, thread.senderName, thread.senderEmail,
                    Self.isoDate(thread.receivedAt), thread.snippet, thread.bodyPlain, thread.category.rawValue,
                    thread.readingState.rawValue, thread.gmailUnread ? "1" : "0", thread.needsAttention ? "1" : "0",
                    String(thread.importance), thread.summary, thread.whyImportant, thread.actionItems.joined(separator: "\n"),
                    thread.deadline ?? "", String(thread.confidence), String(thread.messageCount), thread.hasAttachments ? "1" : "0",
                    thread.gmailURL?.absoluteString ?? "", "0", Self.isoDate(.now), Self.isoDate(.now)
                ])
        }
    }

    public func setting(_ key: String) throws -> String? {
        try withDatabase { db in
            try rows(db, sql: "SELECT value FROM settings WHERE key=?", values: [key]).first?.optionalString("value")
        }
    }

    public func setSetting(_ key: String, value: String) throws {
        try withDatabase { db in
            try execute(db, sql: "INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", values: [key, value])
        }
    }

    private var dailyBriefURL: URL {
        path.deletingLastPathComponent().appendingPathComponent("daily_brief.json")
    }

    private var briefHistoryDirectory: URL {
        path.deletingLastPathComponent().appendingPathComponent("brief_history", isDirectory: true)
    }

    private func archiveBrief(data: Data, date: String) throws {
        let safeDate = date.replacingOccurrences(of: "[^0-9-]", with: "", options: .regularExpression)
        guard !safeDate.isEmpty else { return }
        try FileManager.default.createDirectory(at: briefHistoryDirectory, withIntermediateDirectories: true)
        try data.write(to: briefHistoryDirectory.appendingPathComponent("\(safeDate).json"), options: .atomic)
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            if let handle { sqlite3_close(handle) }
            throw EmailReaderDatabaseError.open(message)
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 5000)
        sqlite3_exec(handle, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA foreign_keys=ON", nil, nil, nil)
        return try body(handle)
    }

    private func executeScript(_ db: OpaquePointer, sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(error)
            throw EmailReaderDatabaseError.step(message)
        }
    }

    private func execute(_ db: OpaquePointer, sql: String, values: [String] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw EmailReaderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, sqliteTransient)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw EmailReaderDatabaseError.step(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func rows(_ db: OpaquePointer, sql: String, values: [String] = []) throws -> [[String: Any?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw EmailReaderDatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, sqliteTransient)
        }
        var result: [[String: Any?]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw EmailReaderDatabaseError.step(String(cString: sqlite3_errmsg(db))) }
            var row: [String: Any?] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, index)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, index))
                default: row[name] = nil
                }
            }
            result.append(row)
        }
        return result
    }

    private func scalarInt(_ db: OpaquePointer, sql: String) throws -> Int {
        let row = try rows(db, sql: sql).first
        return row?.values.compactMap { $0 as? Int }.first ?? 0
    }

    private static func thread(from row: [String: Any?]) -> MailThread {
        let actions = row.string("action_items").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return MailThread(
            id: row.string("id"),
            accountID: row.string("account_id"),
            providerThreadID: row.string("provider_thread_id"),
            subject: row.string("subject"),
            senderName: row.string("sender_name"),
            senderEmail: row.string("sender_email"),
            receivedAt: parseDate(row.optionalString("received_at")) ?? .now,
            snippet: row.string("snippet"),
            bodyPlain: row.string("body_plain"),
            category: MailCategory(rawValue: row.string("category")) ?? .notification,
            readingState: ReadingState(rawValue: row.string("reading_state")) ?? .unread,
            gmailUnread: row.int("gmail_unread") == 1,
            needsAttention: row.int("needs_attention") == 1 || row.int("user_attention") == 1,
            predictedAttention: row.int("needs_attention") == 1,
            userAttention: row.int("user_attention") == 1,
            importance: row.int("importance"),
            summary: row.string("summary"),
            whyImportant: row.string("why_important"),
            actionItems: actions,
            deadline: row.optionalString("deadline").flatMap { $0.isEmpty ? nil : $0 },
            confidence: row.double("confidence"),
            messageCount: row.int("message_count"),
            hasAttachments: row.int("has_attachments") == 1,
            gmailURL: URL(string: row.string("gmail_url")),
            isDemo: row.int("is_demo") == 1
        )
    }

    private static func normalizedBriefItem(_ item: DailyBriefItem, allowsAction: Bool) -> DailyBriefItem {
        let rawAction = item.suggestedAction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = allowsAction && rawAction?.lowercased() != "null" && rawAction?.isEmpty == false ? rawAction : nil
        return DailyBriefItem(
            id: item.id,
            threadID: item.threadID,
            title: item.title,
            sender: item.sender,
            summary: item.summary,
            whyItMatters: item.whyItMatters,
            suggestedAction: action,
            category: item.category
        )
    }

    private func seedDemoData(_ db: OpaquePointer) throws {
        try execute(db, sql: "UPDATE accounts SET auth_state='demo',updated_at=? WHERE id='gmail-primary'", values: [Self.isoDate(.now)])

        let calendar = Calendar.current
        let samples: [[String]] = [
            ["demo-security", "Google", "no-reply@accounts.google.com", "新的登录活动需要确认", "检测到一台新设备登录你的 Google 账号，请确认是否由你本人操作。", "Google 检测到新的 macOS 登录活动，需要确认设备是否可信。", "这类安全通知具有时间敏感性；如果不是本人操作，需要立即修改密码并撤销会话。", "确认登录设备是否为本人\n若非本人，立即修改密码并检查恢复邮箱", "今天", MailCategory.security.rawValue, ReadingState.unread.rawValue, "1", "96", "0"],
            ["demo-contract", "Maya Chen", "maya@example.com", "请在周一前确认新版合作协议", "附件中是根据上次讨论更新的合作协议。请重点查看付款周期和终止条款，并在周一上午前回复。", "合作协议已更新，等待你在周一上午前确认付款周期与终止条款。", "存在明确截止时间，并且需要你回复确认；附件可能影响后续付款安排。", "查看附件中的付款周期\n确认终止条款\n周一上午前回复 Maya", "周一 10:00", MailCategory.action.rawValue, ReadingState.unread.rawValue, "1", "94", "1"],
            ["demo-invoice", "Stripe", "receipts@stripe.com", "7 月服务账单与付款收据", "你的 7 月订阅费用已成功支付。本邮件包含付款金额、税费明细和 PDF 收据。", "7 月订阅费用已支付成功，PDF 收据可用于报销或归档。", "无需立即处理，但属于财务凭证，建议按月归档。", "下载并归档 PDF 收据", "", MailCategory.finance.rawValue, ReadingState.later.rawValue, "0", "70", "1"],
            ["demo-project", "Lena · Product", "lena@example.com", "Reader 项目：本周决策记录", "我们确定第一版先做只读同步、今日简报和本地状态，不在这一轮加入发信和自动归档。", "团队确认第一版边界：只读同步、今日简报、本地状态；暂不支持发信和自动归档。", "这是范围确认邮件，后续评审应以这里的边界为准。", "将范围结论加入项目记录", "", MailCategory.project.rawValue, ReadingState.read.rawValue, "0", "82", "0"],
            ["demo-newsletter", "Stratechery", "updates@stratechery.com", "AI assistants and the new inbox", "This week’s analysis looks at how personal agents are changing inbox triage, notification design, and the economics of attention.", "本期讨论个人 AI 助手如何改变收件箱筛选、通知设计与注意力分配。", "与 Email Reader 的产品方向相关，但没有即时行动要求，适合稍后深度阅读。", "阅读关于 inbox triage 的章节", "", MailCategory.reading.rawValue, ReadingState.later.rawValue, "0", "62", "0"],
            ["demo-flight", "Singapore Airlines", "notification@singaporeair.com", "行程提醒：周日航班办理登机", "你的航班将在周日出发。线上值机开放后可选择座位，请确认护照与签证材料。", "周日航班即将开放线上值机，需要确认旅行证件并选择座位。", "涉及临近行程和证件检查，漏看可能影响出行。", "确认护照和签证\n值机开放后选择座位", "周六 20:00", MailCategory.action.rawValue, ReadingState.unread.rawValue, "1", "91", "0"],
            ["demo-github", "GitHub", "notifications@github.com", "[EmailReader] Build workflow completed", "The latest build workflow completed successfully. All checks passed and no action is required.", "最新构建流程已通过，所有检查成功，无需处理。", "这是可安全折叠的一般通知，保留结果即可。", "", "", MailCategory.notification.rawValue, ReadingState.completed.rawValue, "0", "25", "0"],
            ["demo-family", "Jackson", "family@example.com", "周末晚餐安排", "周六晚上七点已经订好位置，如果时间不方便请提前告诉我。", "周六 19:00 已预订晚餐，如时间冲突需要提前回复。", "属于个人安排，有明确时间但风险较低。", "确认周六 19:00 是否方便", "周六 19:00", MailCategory.personal.rawValue, ReadingState.read.rawValue, "0", "58", "0"]
        ]

        for (index, sample) in samples.enumerated() {
            let received = calendar.date(byAdding: .minute, value: -(index * 47 + 12), to: .now) ?? .now
            try execute(db, sql: """
                INSERT INTO threads(
                  id,account_id,provider_thread_id,subject,sender_name,sender_email,received_at,snippet,body_plain,
                  category,reading_state,gmail_unread,needs_attention,importance,summary,why_important,
                  action_items,deadline,confidence,message_count,has_attachments,gmail_url,is_demo,created_at,updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, values: [
                    sample[0], "gmail-primary", sample[0], sample[3], sample[1], sample[2], Self.isoDate(received),
                    sample[4], sample[4], sample[9], sample[10], sample[10] == ReadingState.unread.rawValue ? "1" : "0",
                    sample[11], sample[12], sample[5], sample[6], sample[7], sample[8], "0.91", "1", sample[13],
                    "https://mail.google.com/mail/u/0/#inbox", "1",
                    Self.isoDate(.now), Self.isoDate(.now)
                ])
        }
        _ = try recordRunInside(db, trigger: "demo_seed", status: "complete", discovered: samples.count, analyzed: samples.count, failed: 0, detail: "演示数据已准备；连接 Gmail 后会自动替换为真实增量邮件。")
        try execute(db, sql: "INSERT OR IGNORE INTO settings(key,value) VALUES('schedule_time','07:30'),('analysis_provider','apple_on_device'),('initial_lookback_days','7'),('block_remote_images','1')")
    }

    private func recordRunInside(_ db: OpaquePointer, trigger: String, status: String, discovered: Int, analyzed: Int, failed: Int, detail: String) throws -> Int64 {
        let now = Self.isoDate(.now)
        try execute(db, sql: "INSERT INTO sync_runs(trigger,started_at,finished_at,status,discovered_count,analyzed_count,failed_count,detail) VALUES(?,?,?,?,?,?,?,?)", values: [trigger, now, now, status, String(discovered), String(analyzed), String(failed), detail])
        return sqlite3_last_insert_rowid(db)
    }

    private static func isoDate(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func parseDate(_ value: String?) -> Date? { value.flatMap { ISO8601DateFormatter().date(from: $0) } }

    private static let schema = """
        CREATE TABLE IF NOT EXISTS accounts(
          id TEXT PRIMARY KEY,
          email TEXT NOT NULL,
          provider TEXT NOT NULL,
          display_name TEXT NOT NULL DEFAULT '',
          auth_state TEXT NOT NULL DEFAULT 'disconnected',
          last_history_id TEXT,
          last_sync_at TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS threads(
          id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          provider_thread_id TEXT NOT NULL,
          subject TEXT NOT NULL,
          sender_name TEXT NOT NULL DEFAULT '',
          sender_email TEXT NOT NULL DEFAULT '',
          received_at TEXT NOT NULL,
          snippet TEXT NOT NULL DEFAULT '',
          body_plain TEXT NOT NULL DEFAULT '',
          category TEXT NOT NULL DEFAULT '一般通知',
          reading_state TEXT NOT NULL DEFAULT 'unread',
          gmail_unread INTEGER NOT NULL DEFAULT 1,
          needs_attention INTEGER NOT NULL DEFAULT 0,
          user_attention INTEGER NOT NULL DEFAULT 0,
          importance INTEGER NOT NULL DEFAULT 0,
          summary TEXT NOT NULL DEFAULT '',
          why_important TEXT NOT NULL DEFAULT '',
          action_items TEXT NOT NULL DEFAULT '',
          deadline TEXT,
          confidence REAL NOT NULL DEFAULT 0,
          message_count INTEGER NOT NULL DEFAULT 1,
          has_attachments INTEGER NOT NULL DEFAULT 0,
          gmail_url TEXT NOT NULL DEFAULT '',
          is_demo INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          UNIQUE(account_id, provider_thread_id)
        );
        CREATE INDEX IF NOT EXISTS idx_threads_received ON threads(received_at DESC);
        CREATE INDEX IF NOT EXISTS idx_threads_state ON threads(reading_state,needs_attention);
        CREATE TABLE IF NOT EXISTS sync_runs(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trigger TEXT NOT NULL,
          started_at TEXT NOT NULL,
          finished_at TEXT,
          status TEXT NOT NULL,
          discovered_count INTEGER NOT NULL DEFAULT 0,
          analyzed_count INTEGER NOT NULL DEFAULT 0,
          failed_count INTEGER NOT NULL DEFAULT 0,
          detail TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        """
}

private extension Dictionary where Key == String, Value == Any? {
    func string(_ key: String) -> String { self[key] as? String ?? "" }
    func optionalString(_ key: String) -> String? { self[key] as? String }
    func int(_ key: String) -> Int { self[key] as? Int ?? 0 }
    func double(_ key: String) -> Double { self[key] as? Double ?? 0 }
}
