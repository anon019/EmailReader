import EmailReaderCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 226)
            Divider().overlay(ReaderTheme.divider)
            if case .library(.today) = model.selection, model.showingDailyBrief {
                DailyBriefReaderView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if case .library(.history) = model.selection {
                BriefHistoryView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ThreadQueueView()
                    .frame(width: 390)
                Divider().overlay(ReaderTheme.divider)
                ReaderView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ReaderTheme.paper)
        .sheet(isPresented: $model.showingSettings) {
            SettingsView()
                .environmentObject(model)
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sourceLibraryExpanded = false

    private let primaryFilters: [LibraryFilter] = [.today, .attention, .later, .completed, .history]
    private let sourceFilters: [LibraryFilter] = [.unread, .all]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EMAIL INTELLIGENCE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(ReaderTheme.accent)
                Text("邮件情报")
                    .font(.editorial(27, weight: .semibold))
                    .foregroundStyle(ReaderTheme.ink)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 22)

            Text("工作台")
                .sidebarSectionTitle()
            ForEach(primaryFilters) { filter in
                SidebarButton(
                    title: filter.rawValue,
                    symbol: filter.symbol,
                    count: filter == .today ? model.brief.priority.count : filter == .history ? nil : model.counts[filter],
                    selected: model.selection == .library(filter)
                ) { model.changeSelection(.library(filter)) }
            }

            DisclosureGroup(isExpanded: $sourceLibraryExpanded) {
                VStack(spacing: 0) {
                    ForEach(sourceFilters) { filter in
                        SidebarButton(
                            title: filter.rawValue,
                            symbol: filter.symbol,
                            count: filter == .all ? model.counts[filter] : nil,
                            selected: model.selection == .library(filter)
                        ) { model.changeSelection(.library(filter)) }
                    }
                    ForEach(MailCategory.allCases) { category in
                        SidebarButton(
                            title: category.rawValue,
                            symbol: category.symbol,
                            count: nil,
                            selected: model.selection == .category(category)
                        ) { model.changeSelection(.category(category)) }
                    }
                }
                .padding(.top, 4)
            } label: {
                Label("邮件来源库", systemImage: "archivebox")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ReaderTheme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .tint(ReaderTheme.muted)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.account?.authState == "connected" ? ReaderTheme.positive : ReaderTheme.accent)
                        .frame(width: 7, height: 7)
                    Text(model.account?.email ?? "未连接 Gmail")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ReaderTheme.ink)
                        .lineLimit(1)
                }
                Button {
                    model.showingSettings = true
                } label: {
                    Label("账户、模型与更新", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ReaderTheme.muted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider().overlay(ReaderTheme.divider) }
        }
        .background(ReaderTheme.sidebar)
    }
}

private struct SidebarButton: View {
    let title: String
    let symbol: String
    let count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(selected ? ReaderTheme.accent : ReaderTheme.muted)
                }
            }
            .foregroundStyle(selected ? ReaderTheme.ink : ReaderTheme.muted)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(selected ? ReaderTheme.selected : .clear, in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}

private struct ThreadQueueView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            queueHeader
            if model.isDemoMode { demoBanner }
            if case .library(.today) = model.selection {
                dailyBrief
                Divider().overlay(ReaderTheme.divider)
                briefQueue
            } else {
                searchField
                Divider().overlay(ReaderTheme.divider)
                threadList
            }
        }
        .background(ReaderTheme.queue)
    }

    private var queueHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.currentFilterTitle)
                    .font(.editorial(25, weight: .semibold))
                    .foregroundStyle(ReaderTheme.ink)
                if let receipt = model.receipt {
                    Text(receiptLabel(receipt))
                        .font(.system(size: 11))
                        .foregroundStyle(ReaderTheme.muted)
                }
            }
            Spacer()
            Button { model.syncNow() } label: {
                Image(systemName: model.isSyncing ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ReaderTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(ReaderTheme.selected, in: Circle())
                    .rotationEffect(model.isSyncing ? .degrees(360) : .zero)
                    .animation(model.isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: model.isSyncing)
            }
            .buttonStyle(.plain)
            .disabled(model.isSyncing)
            .help("读取增量并在本机重新整理")
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var demoBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
            Text("正在预览示例数据")
                .fontWeight(.medium)
            Spacer()
            Button("连接 Gmail") { model.showingSettings = true }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
        }
        .font(.system(size: 11))
        .foregroundStyle(ReaderTheme.accent)
        .padding(.horizontal, 18)
        .frame(height: 34)
        .background(ReaderTheme.accent.opacity(0.09))
    }

    private var dailyBrief: some View {
        HStack(spacing: 0) {
            BriefMetric(value: model.brief.total, label: "已整理")
            BriefMetric(value: model.brief.urgent, label: "优先处理")
            BriefMetric(value: model.brief.noteworthy.count, label: "值得关注")
            BriefMetric(value: model.brief.lowPriorityCount, label: "已折叠")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider().overlay(ReaderTheme.divider) }
    }

    private var briefQueue: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Button {
                    model.showDailyBrief()
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label("今日结论", systemImage: "text.page.badge.magnifyingglass")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(ReaderTheme.accent)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(ReaderTheme.faint)
                        }
                        Text(model.brief.headline)
                            .font(.chineseEditorial(17, weight: .semibold))
                            .foregroundStyle(ReaderTheme.ink)
                            .multilineTextAlignment(.leading)
                        Text(model.brief.overview)
                            .font(.system(size: 11))
                            .foregroundStyle(ReaderTheme.muted)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(model.showingDailyBrief ? ReaderTheme.selected : .clear)
                }
                .buttonStyle(.plain)

                briefQueueSection("优先处理", items: model.brief.priority, emptyText: "今天没有必须立即处理的事项")
                briefQueueSection("值得关注", items: model.brief.noteworthy, emptyText: nil)
                briefQueueSection("稍后阅读", items: model.brief.later, emptyText: nil)

                if model.brief.lowPriorityCount > 0 {
                    Label("另有 \(model.brief.lowPriorityCount) 封低优先级通知已自动折叠", systemImage: "archivebox")
                        .font(.system(size: 11))
                        .foregroundStyle(ReaderTheme.faint)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                }
            }
        }
    }

    @ViewBuilder
    private func briefQueueSection(_ title: String, items: [DailyBriefItem], emptyText: String?) -> some View {
        if !items.isEmpty || emptyText != nil {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(ReaderTheme.faint)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 7)
            if items.isEmpty, let emptyText {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(ReaderTheme.positive)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            } else {
                ForEach(items) { item in
                    Button { model.selectThread(item.threadID) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.sender)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ReaderTheme.muted)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: item.category.symbol)
                                    .font(.system(size: 10))
                                    .foregroundStyle(ReaderTheme.faint)
                            }
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ReaderTheme.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(item.summary)
                                .font(.system(size: 11))
                                .foregroundStyle(ReaderTheme.muted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(model.selectedThreadID == item.threadID && !model.showingDailyBrief ? ReaderTheme.selected : .clear)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(ReaderTheme.divider.opacity(0.7)).padding(.leading, 18)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ReaderTheme.faint)
            TextField("搜索发件人、主题或内容", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { model.reload(preserveSelection: false) }
            if !model.searchText.isEmpty {
                Button { model.searchText = ""; model.reload(preserveSelection: false) } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ReaderTheme.faint)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(ReaderTheme.paper.opacity(0.75), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var threadList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.threads.isEmpty {
                    ContentUnavailableView("这里已经清空", systemImage: "checkmark.circle", description: Text("切换分类或等待下一次更新。"))
                        .foregroundStyle(ReaderTheme.muted)
                        .padding(.top, 80)
                } else {
                    ForEach(model.threads) { thread in
                        ThreadRow(thread: thread, selected: model.selectedThreadID == thread.id)
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(.easeOut(duration: 0.16)) { model.selectThread(thread.id) } }
                        Divider().overlay(ReaderTheme.divider.opacity(0.75)).padding(.leading, 18)
                    }
                }
            }
        }
    }

    private func receiptLabel(_ receipt: SyncReceipt) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let relative = formatter.localizedString(for: receipt.finishedAt ?? receipt.startedAt, relativeTo: .now)
        return "上次更新 \(relative) · \(receipt.detail)"
    }
}

private struct BriefMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(label == "需关注" && value > 0 ? ReaderTheme.accent : ReaderTheme.ink)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(ReaderTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ThreadRow: View {
    let thread: MailThread
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if thread.readingState == .unread {
                    Circle().fill(ReaderTheme.accent).frame(width: 6, height: 6)
                }
                Text(thread.senderName.isEmpty ? thread.senderEmail : thread.senderName)
                    .font(.system(size: 12, weight: thread.readingState == .unread ? .semibold : .medium))
                    .foregroundStyle(ReaderTheme.ink)
                    .lineLimit(1)
                Spacer()
                Text(thread.receivedAt, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(ReaderTheme.faint)
            }

            Text(thread.subject)
                .font(.system(size: 14, weight: thread.readingState == .unread ? .semibold : .medium))
                .foregroundStyle(ReaderTheme.ink)
                .lineLimit(2)

            Text(thread.summary)
                .font(.system(size: 12))
                .foregroundStyle(ReaderTheme.muted)
                .lineLimit(2)
                .lineSpacing(2)

            HStack(spacing: 7) {
                Label(thread.category.rawValue, systemImage: thread.category.symbol)
                if thread.needsAttention {
                    Label("关注", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(ReaderTheme.accent)
                }
                if thread.readingState == .later {
                    Image(systemName: "bookmark.fill").foregroundStyle(ReaderTheme.accent)
                }
                if thread.hasAttachments {
                    Image(systemName: "paperclip")
                }
                Spacer()
                if thread.messageCount > 1 { Text("\(thread.messageCount) 封") }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(ReaderTheme.faint)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(selected ? ReaderTheme.selected : .clear)
    }
}

private struct DailyBriefReaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("今日情报简报", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(ReaderTheme.accent)
                Spacer()
                Text("\(model.briefProviderLabel) · \(model.briefGeneratedLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(ReaderTheme.muted)
                Button { model.syncNow() } label: {
                    Label(model.isSyncing ? model.syncPhase : "更新并重新整理", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ReaderTheme.accent)
                .disabled(model.isSyncing)
                .help("读取 Gmail 增量，并在本机重新生成完整简报")
            }
            .padding(.horizontal, 20)
            .frame(height: 48)

            Divider().overlay(ReaderTheme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(model.brief.date) · \(model.brief.periodLabel)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ReaderTheme.faint)
                        .tracking(0.5)

                    Text(model.todayFocusTitle)
                        .font(.chineseEditorial(38, weight: .semibold))
                        .foregroundStyle(model.brief.priority.isEmpty ? ReaderTheme.ink : ReaderTheme.accent)
                        .lineSpacing(6)
                        .padding(.top, 10)

                    Text(model.brief.headline)
                        .font(.chineseEditorial(22, weight: .medium))
                        .foregroundStyle(ReaderTheme.ink)
                        .lineSpacing(6)
                        .padding(.top, 16)

                    Text(model.brief.overview)
                        .font(.system(size: 14))
                        .foregroundStyle(ReaderTheme.muted)
                        .lineSpacing(5)
                        .padding(.top, 12)

                    HStack(spacing: 0) {
                        briefStat(model.brief.priority.count + model.brief.noteworthy.count, "需要知道")
                        briefStat(model.brief.later.count, "集中阅读")
                        briefStat(model.brief.lowPriorityCount, "已替你过滤")
                    }
                    .padding(.vertical, 24)
                    .overlay(alignment: .top) { Divider().overlay(ReaderTheme.divider) }
                    .overlay(alignment: .bottom) { Divider().overlay(ReaderTheme.divider) }
                    .padding(.top, 28)

                    if model.brief.priority.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(ReaderTheme.positive)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("没有必须立即处理的事项")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("可以直接从“值得关注”开始阅读。")
                                    .font(.system(size: 12))
                                    .foregroundStyle(ReaderTheme.muted)
                            }
                        }
                        .padding(.vertical, 28)
                    } else {
                        briefSection("优先处理", subtitle: "需要确认、回复或核对", items: model.brief.priority, accent: true)
                    }

                    briefSection("值得关注", subtitle: "已经从资讯流中筛出的关键信号", items: model.brief.noteworthy, accent: false)
                    briefSection("稍后阅读", subtitle: "有价值但没有时间压力", items: model.brief.later, accent: false)

                    if model.brief.lowPriorityCount > 0 {
                        HStack(spacing: 10) {
                            Image(systemName: "archivebox")
                            Text("其余 \(model.brief.lowPriorityCount) 封没有进入今日焦点；需要抽查时仍可在邮件来源库找到。")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(ReaderTheme.faint)
                        .padding(.vertical, 28)
                        .overlay(alignment: .top) { Divider().overlay(ReaderTheme.divider) }
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 46)
                .padding(.vertical, 38)
            }
        }
    }

    private func briefStat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(ReaderTheme.ink)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ReaderTheme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func briefSection(_ title: String, subtitle: String, items: [DailyBriefItem], accent: Bool) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.editorial(22, weight: .semibold))
                        .foregroundStyle(accent ? ReaderTheme.accent : ReaderTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(ReaderTheme.faint)
                }
                .padding(.bottom, 10)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button { model.selectThread(item.threadID) } label: {
                        HStack(alignment: .top, spacing: 16) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(accent ? ReaderTheme.accent : ReaderTheme.faint)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.sender)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(ReaderTheme.muted)
                                    Spacer()
                                    Label(item.category.rawValue, systemImage: item.category.symbol)
                                        .font(.system(size: 10))
                                        .foregroundStyle(ReaderTheme.faint)
                                }
                                Text(item.title)
                                    .font(.chineseEditorial(18, weight: .semibold))
                                    .foregroundStyle(ReaderTheme.ink)
                                    .multilineTextAlignment(.leading)
                                Text(item.summary)
                                    .font(.system(size: 13))
                                    .foregroundStyle(ReaderTheme.ink)
                                    .lineSpacing(4)
                                    .multilineTextAlignment(.leading)
                                Text(item.whyItMatters)
                                    .font(.system(size: 12))
                                    .foregroundStyle(ReaderTheme.muted)
                                    .lineSpacing(3)
                                    .multilineTextAlignment(.leading)
                                if let action = item.suggestedAction,
                                   !action.isEmpty,
                                   accent || item.category == .action || item.category == .security {
                                    Label(action, systemImage: "arrow.turn.down.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ReaderTheme.accent)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        .padding(.vertical, 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 8) {
                        if model.briefThreadStates[item.threadID] == .completed {
                            Label("已处理", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(ReaderTheme.positive)
                        } else {
                            Button(accent ? "已核实" : "已处理") {
                                model.setState(.completed, threadID: item.threadID)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent ? ReaderTheme.accent : ReaderTheme.positive)
                        }
                        Button("稍后阅读") {
                            model.setState(.later, threadID: item.threadID)
                        }
                        .buttonStyle(.bordered)
                        Button("查看来源") {
                            model.selectThread(item.threadID)
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.leading, 27)
                    .padding(.bottom, 14)
                    Divider().overlay(ReaderTheme.divider)
                }
            }
            .padding(.bottom, 30)
        }
    }
}

private struct BriefHistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedDate: String?

    private var selectedBrief: DailyBrief? {
        model.briefHistory.first { $0.date == selectedDate } ?? model.briefHistory.first
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("历史简报")
                        .font(.editorial(25, weight: .semibold))
                    Text("保留每日结论，不重新制造收件箱")
                        .font(.system(size: 11))
                        .foregroundStyle(ReaderTheme.muted)
                }
                .padding(20)
                Divider().overlay(ReaderTheme.divider)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.briefHistory, id: \.date) { brief in
                            Button {
                                selectedDate = brief.date
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(brief.date)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(ReaderTheme.accent)
                                    Text(brief.headline)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(ReaderTheme.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text("\(brief.priority.count) 项优先 · \(brief.noteworthy.count + brief.later.count) 条信号")
                                        .font(.system(size: 10))
                                        .foregroundStyle(ReaderTheme.faint)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedBrief?.date == brief.date ? ReaderTheme.selected : .clear)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(ReaderTheme.divider.opacity(0.7)).padding(.leading, 18)
                        }
                    }
                }
            }
            .frame(width: 310)
            .background(ReaderTheme.queue)

            Divider().overlay(ReaderTheme.divider)

            Group {
                if let brief = selectedBrief {
                    historyDetail(brief)
                } else {
                    ContentUnavailableView(
                        "还没有历史简报",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("下一次成功整理后会自动保存在这里。")
                    )
                    .foregroundStyle(ReaderTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ReaderTheme.reader)
        }
        .onAppear { selectedDate = selectedDate ?? model.briefHistory.first?.date }
    }

    private func historyDetail(_ brief: DailyBrief) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(brief.date)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ReaderTheme.accent)
                Text(brief.headline)
                    .font(.chineseEditorial(32, weight: .semibold))
                    .foregroundStyle(ReaderTheme.ink)
                Text(brief.overview)
                    .font(.system(size: 14))
                    .foregroundStyle(ReaderTheme.muted)
                    .lineSpacing(5)
                Divider().overlay(ReaderTheme.divider)
                historySection("优先处理", items: brief.priority)
                historySection("值得关注", items: brief.noteworthy)
                historySection("稍后阅读", items: brief.later)
                if brief.lowPriorityCount > 0 {
                    Label("另有 \(brief.lowPriorityCount) 封未进入当日焦点", systemImage: "archivebox")
                        .font(.system(size: 12))
                        .foregroundStyle(ReaderTheme.faint)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 44)
            .padding(.vertical, 38)
        }
    }

    @ViewBuilder
    private func historySection(_ title: String, items: [DailyBriefItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.editorial(20, weight: .semibold))
                    .padding(.bottom, 8)
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.sender)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(ReaderTheme.muted)
                            Spacer()
                            Label(item.category.rawValue, systemImage: item.category.symbol)
                                .font(.system(size: 10))
                                .foregroundStyle(ReaderTheme.faint)
                        }
                        Text(item.title)
                            .font(.chineseEditorial(17, weight: .semibold))
                        Text(item.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(ReaderTheme.ink)
                            .lineSpacing(3)
                    }
                    .padding(.vertical, 13)
                    Divider().overlay(ReaderTheme.divider)
                }
            }
        }
    }
}

private struct ReaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if case .library(.today) = model.selection, model.showingDailyBrief {
                DailyBriefReaderView()
            } else if let thread = model.selectedThread {
                VStack(spacing: 0) {
                    readerToolbar(thread)
                    Divider().overlay(ReaderTheme.divider)
                    ScrollView {
                        readerContent(thread)
                            .frame(maxWidth: 760, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 44)
                            .padding(.vertical, 34)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                ContentUnavailableView("选择一封邮件", systemImage: "envelope.open", description: Text("左侧队列会保留你的阅读位置。"))
                    .foregroundStyle(ReaderTheme.muted)
            }
        }
        .background(ReaderTheme.reader)
    }

    private func readerToolbar(_ thread: MailThread) -> some View {
        HStack(spacing: 8) {
            if case .library(.today) = model.selection {
                Button { model.showDailyBrief() } label: {
                    Label("返回简报", systemImage: "chevron.left")
                }
                .labelStyle(.titleAndIcon)
                Divider().frame(height: 18)
            }
            Text(thread.category.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ReaderTheme.muted)
            if thread.gmailUnread {
                Text("GMAIL 未读")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(ReaderTheme.accent)
            }
            Spacer()
            if thread.predictedAttention {
                Label("系统预警", systemImage: "lock.shield.fill")
                    .help("这是系统识别的风险；完成核实后可标记为已处理")
            } else {
                Button { model.toggleAttention() } label: {
                    Label(thread.userAttention ? "取消关注" : "需要关注", systemImage: thread.userAttention ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                }
            }
            Button { model.setState(.later) } label: {
                Label("待看", systemImage: thread.readingState == .later ? "bookmark.fill" : "bookmark")
            }
            Button { model.setState(.completed) } label: {
                Label("处理完成", systemImage: "checkmark.circle")
            }
            Divider().frame(height: 18)
            Button { model.openInGmail() } label: {
                Label("在 Gmail 打开", systemImage: "arrow.up.right.square")
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .font(.system(size: 13))
        .foregroundStyle(ReaderTheme.muted)
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    @ViewBuilder
    private func readerContent(_ thread: MailThread) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(thread.needsAttention ? "需要关注" : thread.readingState.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(thread.needsAttention ? ReaderTheme.accent : ReaderTheme.muted)
                Spacer()
                Text(thread.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(ReaderTheme.faint)
            }

            Text(thread.subject)
                .font(.chineseEditorial(32, weight: .semibold))
                .foregroundStyle(ReaderTheme.ink)
                .lineSpacing(4)
                .padding(.top, 12)

            HStack(spacing: 8) {
                Text(thread.senderName)
                    .font(.system(size: 13, weight: .semibold))
                Text("<\(thread.senderEmail)>")
                    .font(.system(size: 12))
                    .foregroundStyle(ReaderTheme.muted)
                if thread.messageCount > 1 {
                    Text("· \(thread.messageCount) 封邮件")
                        .foregroundStyle(ReaderTheme.muted)
                }
            }
            .padding(.top, 14)

            interpretation(thread)
                .padding(.top, 34)

            Divider().overlay(ReaderTheme.divider)
                .padding(.vertical, 34)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("来源证据")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ReaderTheme.muted)
                        .tracking(0.4)
                    Text("原文只在需要核实时展开；日常决策以解读和行动为主。")
                        .font(.system(size: 11))
                        .foregroundStyle(ReaderTheme.faint)
                }
                Spacer()
                Button { model.openInGmail() } label: {
                    Label("在 Gmail 查看完整原文", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            OriginalMailDisclosure(thread: thread)
                .padding(.top, 18)

            if thread.hasAttachments {
                Label("包含附件 · 第一版只显示附件信息，不会自动下载", systemImage: "paperclip")
                    .font(.system(size: 11))
                    .foregroundStyle(ReaderTheme.muted)
                    .padding(.top, 28)
            }

            Text("远程图片默认已阻止，以避免打开追踪像素。")
                .font(.system(size: 10))
                .foregroundStyle(ReaderTheme.faint)
                .padding(.top, 40)
                .padding(.bottom, 28)
        }
    }

    private func interpretation(_ thread: MailThread) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("AI 解读")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(ReaderTheme.accent)
                Text(thread.summary)
                    .font(.chineseEditorial(19, weight: .medium))
                    .foregroundStyle(ReaderTheme.ink)
                    .lineSpacing(6)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("为什么值得关注")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ReaderTheme.muted)
                Text(thread.whyImportant)
                    .font(.system(size: 13))
                    .foregroundStyle(ReaderTheme.ink)
                    .lineSpacing(4)
            }

            if !thread.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("建议行动")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if let deadline = thread.deadline {
                            Label(deadline, systemImage: "calendar.badge.clock")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ReaderTheme.accent)
                        }
                    }
                    ForEach(Array(thread.actionItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "circle")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(ReaderTheme.accent)
                                .padding(.top, 4)
                            Text(item)
                                .font(.system(size: 13))
                                .foregroundStyle(ReaderTheme.ink)
                        }
                    }
                }
            }
        }
        .padding(.leading, 20)
        .overlay(alignment: .leading) {
            Rectangle().fill(ReaderTheme.accent).frame(width: 2)
        }
    }
}

private struct OriginalMailDisclosure: View {
    let thread: MailThread
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(thread.bodyPlain)
                .font(.chineseEditorial(16))
                .foregroundStyle(ReaderTheme.ink)
                .lineSpacing(8)
                .textSelection(.enabled)
                .padding(.top, 16)
        } label: {
            Label(isExpanded ? "收起抓取文本" : "查看抓取文本", systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ReaderTheme.muted)
        }
        .tint(ReaderTheme.muted)
    }
}

private extension View {
    func sidebarSectionTitle() -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(ReaderTheme.faint)
            .padding(.horizontal, 20)
            .padding(.bottom, 7)
    }
}
