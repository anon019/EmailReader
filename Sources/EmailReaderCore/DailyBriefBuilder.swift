import Foundation

public enum DailyBriefBuilder {
    public static func build(from threads: [MailThread], now: Date = .now, windowStart: Date? = nil) -> DailyBrief {
        let calendar = Calendar.current
        let defaultCutoff = calendar.date(byAdding: .hour, value: -24, to: now) ?? .distantPast
        let contextCutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        let requestedCutoff = windowStart.map { min($0, defaultCutoff) } ?? defaultCutoff
        let recentCutoff = max(requestedCutoff, contextCutoff)
        let recentThreads = threads.filter { $0.receivedAt >= recentCutoff && $0.readingState != .completed }
        let contextAttention = threads.filter {
            $0.receivedAt >= contextCutoff &&
            $0.receivedAt < recentCutoff &&
            $0.needsAttention &&
            $0.readingState != .completed
        }
        let todaysThreads = (recentThreads + contextAttention)
            .sorted { lhs, rhs in
                if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
                if lhs.importance != rhs.importance { return lhs.importance > rhs.importance }
                return lhs.receivedAt > rhs.receivedAt
            }

        // Never hide an unresolved risk behind a presentation cap. Additional
        // action mail is capped, but every attention item remains surfaced.
        let attentionThreads = todaysThreads.filter(\.needsAttention)
        let attentionIDs = Set(attentionThreads.map(\.id))
        let actionThreads = todaysThreads.filter {
            !attentionIDs.contains($0.id) && $0.category == .action && $0.importance >= 75
        }
        let priorityThreads = attentionThreads + Array(actionThreads.prefix(max(0, 4 - attentionThreads.count)))
        let priorityIDs = Set(priorityThreads.map(\.id))

        let noteworthyThreads = Array(todaysThreads.filter {
            !priorityIDs.contains($0.id) &&
            $0.importance >= 55 &&
            [.investment, .reading, .project, .finance, .personal].contains($0.category)
        }.prefix(4))
        let noteworthyIDs = Set(noteworthyThreads.map(\.id))

        let laterThreads = Array(todaysThreads.filter {
            !priorityIDs.contains($0.id) &&
            !noteworthyIDs.contains($0.id) &&
            [.investment, .reading].contains($0.category)
        }.prefix(4))
        let surfacedIDs = priorityIDs.union(noteworthyIDs).union(laterThreads.map(\.id))
        let surfacedRecentCount = recentThreads.filter { surfacedIDs.contains($0.id) }.count
        let lowPriorityCount = max(0, recentThreads.count - surfacedRecentCount)

        let priority = priorityThreads.map { item($0, action: $0.actionItems.first) }
        let noteworthy = noteworthyThreads.map { item($0, action: nil) }
        let later = laterThreads.map { item($0, action: nil) }
        let headline: String
        let overview: String
        if recentThreads.isEmpty && contextAttention.isEmpty {
            headline = "今天还没有需要整理的新邮件"
            overview = "下一次 Codex 整理完成后，重点、行动项与延伸阅读会出现在这里。"
        } else if priority.isEmpty {
            headline = "今天没有必须立即处理的邮件"
            overview = "本次窗口共整理 \(recentThreads.count) 封；筛出 \(noteworthy.count + later.count) 条值得集中阅读的信息，其余 \(lowPriorityCount) 封未进入今日焦点。"
        } else {
            headline = "今天有 \(priority.count) 件事值得优先处理"
            overview = "本次窗口共整理 \(recentThreads.count) 封；另外保留 \(noteworthy.count + later.count) 条值得关注或稍后阅读的信息，\(lowPriorityCount) 封未进入今日焦点。"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let generatedFormatter = ISO8601DateFormatter()
        return DailyBrief(
            date: dateFormatter.string(from: now),
            generatedAt: generatedFormatter.string(from: now),
            periodLabel: recentCutoff < defaultCutoff
                ? "自上次简报以来（最多 7 天），兼顾未处理风险"
                : "过去 24 小时，兼顾一周内未处理风险",
            headline: headline,
            overview: overview,
            total: recentThreads.count,
            priority: priority,
            noteworthy: noteworthy,
            later: later,
            lowPriorityCount: lowPriorityCount
        )
    }

    private static func item(_ thread: MailThread, action: String?) -> DailyBriefItem {
        DailyBriefItem(
            id: thread.id,
            threadID: thread.id,
            title: thread.subject,
            sender: thread.senderName.isEmpty ? thread.senderEmail : thread.senderName,
            summary: thread.summary,
            investmentThesis: thread.investmentThesis,
            whyItMatters: thread.whyImportant,
            suggestedAction: action,
            category: thread.category
        )
    }
}
