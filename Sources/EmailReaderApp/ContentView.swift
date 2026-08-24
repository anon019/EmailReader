import EmailReaderCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 286)
            Divider().overlay(ReaderTheme.divider.opacity(0.75))
            if case .library(.today) = model.selection, model.showingDailyBrief {
                DailyBriefReaderView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if case .library(.history) = model.selection {
                BriefHistoryView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ThreadQueueView()
                    .frame(width: 372)
                Divider().overlay(ReaderTheme.divider)
                ReaderView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(ReaderTheme.paper)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: model.selection)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: model.showingDailyBrief)
        .sheet(isPresented: $model.showingSettings) {
            SettingsView()
                .environmentObject(model)
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sourceLibraryExpanded = false

    private let primaryFilters: [LibraryFilter] = [.today, .attention, .unread, .later]
    private let sourceFilters: [LibraryFilter] = [.completed, .history, .all]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Image(systemName: "waveform.path.ecg.rectangle")
                                .font(.system(size: 12, weight: .semibold))
                            Text("EMAIL READER")
                                .tracking(1.45)
                        }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ReaderTheme.accent)
                        Text("今日情报")
                            .font(.editorial(31, weight: .semibold))
                            .foregroundStyle(ReaderTheme.ink)
                        Text(Date.now.formatted(.dateTime.month(.wide).day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ReaderTheme.faint)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 28)
                    .padding(.bottom, 18)

                    todayPulse

                    Text("工作台")
                        .sidebarSectionTitle()
                    ForEach(primaryFilters) { filter in
                        SidebarButton(
                            title: workbenchTitle(filter),
                            symbol: filter.symbol,
                            count: workbenchCount(filter),
                            selected: model.selection == .library(filter)
                        ) { model.changeSelection(.library(filter)) }
                    }

                    if !model.dailyResearchThemes.isEmpty {
                        Text("今日关注主题")
                            .sidebarSectionTitle(topPadding: 22)
                        VStack(spacing: 0) {
                            ForEach(model.dailyResearchThemes.prefix(4)) { theme in
                                ResearchThemeButton(theme: theme) { model.openResearchTheme(theme) }
                            }
                        }
                        .padding(.horizontal, 12)
                    }

                    Text("邮件类型")
                        .sidebarSectionTitle(topPadding: 20)
                    VStack(spacing: 2) {
                        ForEach(model.dailyCategoryCounts) { entry in
                            CategoryButton(
                                entry: entry,
                                selected: model.selection == .category(entry.category)
                            ) { model.changeSelection(.category(entry.category)) }
                        }
                    }
                    .padding(.horizontal, 8)

                    if !model.dailyTickerCounts.isEmpty {
                        Text("重点标的")
                            .sidebarSectionTitle(topPadding: 20)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 72), spacing: 7)],
                            alignment: .leading,
                            spacing: 7
                        ) {
                            ForEach(model.dailyTickerCounts) { ticker in
                                TickerButton(ticker: ticker) { model.openTicker(ticker) }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    DisclosureGroup(isExpanded: $sourceLibraryExpanded) {
                        VStack(spacing: 0) {
                            ForEach(sourceFilters) { filter in
                                SidebarButton(
                                    title: filter.rawValue,
                                    symbol: filter.symbol,
                                    count: filter == .history ? model.briefHistory.count : model.counts[filter],
                                    selected: model.selection == .library(filter)
                                ) { model.changeSelection(.library(filter)) }
                            }
                        }
                        .padding(.top, 5)
                    } label: {
                        Label("来源与历史", systemImage: "archivebox")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ReaderTheme.muted)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 22)
                    .tint(ReaderTheme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    ZStack {
                        Circle().fill(model.account?.authState == "connected" ? ReaderTheme.positiveSoft : ReaderTheme.accentSoft)
                        Circle()
                            .fill(model.account?.authState == "connected" ? ReaderTheme.positive : ReaderTheme.accent)
                            .frame(width: 7, height: 7)
                    }
                    .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.account?.email ?? "未连接 Gmail")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ReaderTheme.ink)
                            .lineLimit(1)
                        Text("简报引擎 · \(model.briefProviderLabel)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ReaderTheme.faint)
                    }
                }
                Button {
                    model.showingSettings = true
                } label: {
                    Label("账户、模型与更新", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ReaderTheme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider().overlay(ReaderTheme.divider) }
        }
        .background(ReaderTheme.sidebar.opacity(0.96))
    }

    private var todayPulse: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(model.dailyAlertThreads.isEmpty ? ReaderTheme.positiveSoft : ReaderTheme.dangerSoft)
                Image(systemName: model.dailyAlertThreads.isEmpty ? "checkmark" : "exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(model.dailyAlertThreads.isEmpty ? ReaderTheme.positive : ReaderTheme.danger)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.dailyAlertThreads.isEmpty ? "今日状态" : "必须过目")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(model.dailyAlertThreads.isEmpty ? ReaderTheme.positive : ReaderTheme.danger)
                    Spacer()
                    Text("\(model.dailyAlertThreads.count)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(model.dailyAlertThreads.isEmpty ? ReaderTheme.positive : ReaderTheme.danger)
                }
                Text(model.dailyAlertThreads.count == 0 ? "警报已清零" : "\(model.dailyAlertThreads.count) 项警报待核实")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ReaderTheme.ink)
                Text("\(model.dailyUnreadThreads.count) 封今日未读 · \(model.dailyInvestmentThesisCount) 封投资研究已提炼 thesis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ReaderTheme.muted)
                    .lineSpacing(3)
            }
        }
        .padding(15)
        .background(ReaderTheme.surface.opacity(0.80), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ReaderTheme.divider.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: ReaderTheme.shadow.opacity(0.45), radius: 12, y: 4)
        .padding(.horizontal, 14)
        .padding(.bottom, 22)
    }

    private func workbenchTitle(_ filter: LibraryFilter) -> String {
        switch filter {
        case .today: "今日总览"
        case .attention: "警报巡检"
        case .unread: "全部未读"
        case .later: "稍后研究"
        default: filter.rawValue
        }
    }

    private func workbenchCount(_ filter: LibraryFilter) -> Int {
        switch filter {
        case .today: model.dailyUnreadThreads.count
        case .attention: model.dailyAlertThreads.count
        case .later: model.brief.later.count
        default: model.counts[filter]
        }
    }
}

private struct SidebarButton: View {
    let title: String
    let symbol: String
    let count: Int?
    let selected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 15, weight: selected ? .semibold : .medium))
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? ReaderTheme.accent : ReaderTheme.muted)
                }
            }
            .foregroundStyle(selected ? ReaderTheme.ink : ReaderTheme.muted)
            .padding(.horizontal, 13)
            .frame(height: 43)
            .background(
                selected ? ReaderTheme.selectedStrong : isHovered ? ReaderTheme.surface.opacity(0.55) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(ReaderTheme.accent)
                    .frame(width: 3, height: selected ? 22 : 0)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 8)
            .scaleEffect(isHovered && !selected ? 1.008 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { isHovered = hovered }
        }
    }
}

private struct ResearchThemeButton: View {
    let theme: DailyResearchTheme
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Image(systemName: "scope")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ReaderTheme.accent)
                        .frame(width: 16)
                    Text(theme.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ReaderTheme.ink)
                    Spacer()
                    Text("\(theme.signalLabel) · \(theme.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ReaderTheme.accent)
                }
                Text(theme.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(ReaderTheme.muted)
                    .lineLimit(2)
                    .padding(.leading, 25)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .background(isHovered ? ReaderTheme.surface.opacity(0.58) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { isHovered = hovered }
        }
    }
}

private struct TickerButton: View {
    let ticker: DailyTickerCount
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(ticker.ticker)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                if ticker.count > 1 {
                    Text("\(ticker.count)篇")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ReaderTheme.muted)
                }
            }
            .foregroundStyle(ReaderTheme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isHovered ? ReaderTheme.selected : ReaderTheme.reader.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(ReaderTheme.accent.opacity(0.28)))
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isHovered = hovered }
        }
    }
}

private struct CategoryButton: View {
    let entry: DailyCategoryCount
    let selected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: entry.category.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(shortTitle)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(entry.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? ReaderTheme.accent : ReaderTheme.muted)
            }
            .foregroundStyle(selected ? ReaderTheme.ink : ReaderTheme.muted)
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(
                selected ? ReaderTheme.selected : isHovered ? ReaderTheme.surface.opacity(0.52) : .clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { isHovered = hovered }
        }
    }

    private var shortTitle: String {
        switch entry.category {
        case .security: "账户安全"
        case .finance: "账单财务"
        case .project: "工作项目"
        case .reading: "资讯阅读"
        default: entry.category.rawValue
        }
    }
}

private struct ThreadQueueView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .font(.editorial(27, weight: .semibold))
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(model.isSyncing ? ReaderTheme.muted : .white)
                    .frame(width: 32, height: 32)
                    .background(model.isSyncing ? ReaderTheme.selected : ReaderTheme.accent, in: Circle())
                    .shadow(color: model.isSyncing ? .clear : ReaderTheme.accent.opacity(0.22), radius: 8, y: 3)
                    .rotationEffect(model.isSyncing && !reduceMotion ? .degrees(360) : .zero)
                    .animation(
                        model.isSyncing && !reduceMotion
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : nil,
                        value: model.isSyncing
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.isSyncing)
            .help("读取 Gmail 增量，并由 Luna Medium 直接分析正文和生成简报")
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 16)
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
                .font(.system(size: 13))
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
                            .onTapGesture {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                                    model.selectThread(thread.id)
                                }
                            }
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
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if thread.readingState == .unread {
                    Circle().fill(ReaderTheme.accent).frame(width: 6, height: 6)
                    Text("未读")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ReaderTheme.accent)
                }
                Text(thread.senderName.isEmpty ? thread.senderEmail : thread.senderName)
                    .font(.system(size: 13, weight: thread.readingState == .unread ? .semibold : .medium))
                    .foregroundStyle(ReaderTheme.ink)
                    .lineLimit(1)
                Spacer()
                Text(thread.receivedAt, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(ReaderTheme.faint)
            }

            Text(thread.subject)
                .font(.system(size: 15, weight: thread.readingState == .unread ? .semibold : .medium))
                .foregroundStyle(ReaderTheme.ink)
                .lineLimit(2)

            Text(thread.summary)
                .font(.system(size: 13))
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
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ReaderTheme.faint)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(
            selected ? ReaderTheme.selectedStrong : isHovered ? ReaderTheme.surface.opacity(0.48) : .clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, 6)
        .onHover { hovered in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { isHovered = hovered }
        }
    }
}

private struct DailyBriefReaderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("今日情报简报", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(ReaderTheme.ink)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(ReaderTheme.positive).frame(width: 6, height: 6)
                    Text("\(model.briefProviderLabel) · \(model.briefGeneratedLabel)")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ReaderTheme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ReaderTheme.surfaceRaised, in: Capsule())
                Button { model.syncNow() } label: {
                    Label(model.isSyncing ? model.syncPhase : "更新简报", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(ReaderTheme.accent)
                .controlSize(.small)
                .font(.system(size: 11, weight: .semibold))
                .disabled(model.isSyncing)
                .help("读取 Gmail 增量，由 Luna Medium 直接完成逐封分类、摘要、投资 thesis 和每日简报")
            }
            .padding(.horizontal, 22)
            .frame(height: 54)

            Divider().overlay(ReaderTheme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    briefHero
                        .opacity(contentAppeared ? 1 : 0)
                        .offset(y: contentAppeared || reduceMotion ? 0 : 10)

                    briefStatusStrip
                        .padding(.top, 30)
                        .opacity(contentAppeared ? 1 : 0)

                    if model.dailyAlertThreads.isEmpty {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(ReaderTheme.positiveSoft)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                            }
                                .frame(width: 32, height: 32)
                                .foregroundStyle(ReaderTheme.positive)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("警报巡检已清零")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("没有尚未核实的安全、付款、截止日期或必须回复事项。")
                                    .font(.system(size: 13))
                                    .foregroundStyle(ReaderTheme.muted)
                            }
                            Spacer()
                            Text("SAFE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(ReaderTheme.positive)
                        }
                        .padding(16)
                        .background(ReaderTheme.positiveSoft.opacity(0.62), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.vertical, 26)
                    } else {
                        dailyAlertReview
                    }

                    dailyCategoryOverview
                    dailyUnreadReview
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
                .padding(.vertical, 42)
            }
        }
        .background(ReaderTheme.reader)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.34)) { contentAppeared = true }
        }
    }

    private var briefHero: some View {
        HStack(alignment: .top, spacing: 18) {
            Capsule()
                .fill(model.dailyAlertThreads.isEmpty ? ReaderTheme.positive : ReaderTheme.accent)
                .frame(width: 4, height: 108)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(model.brief.date) · \(model.brief.periodLabel)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ReaderTheme.faint)
                    .tracking(0.45)
                Text(model.todayFocusTitle)
                    .font(.chineseEditorial(40, weight: .semibold))
                    .foregroundStyle(model.dailyAlertThreads.isEmpty ? ReaderTheme.positive : ReaderTheme.accent)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                Text(model.brief.headline)
                    .font(.chineseEditorial(23, weight: .medium))
                    .foregroundStyle(ReaderTheme.ink)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                Text(model.brief.overview)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ReaderTheme.muted)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 13)
            }
            .layoutPriority(1)
        }
    }

    private var briefStatusStrip: some View {
        HStack(spacing: 0) {
            briefStat(model.dailyAlertThreads.count, "待巡检", symbol: "exclamationmark.shield")
            stripDivider
            briefStat(model.dailyUnreadThreads.count, "今日未读", symbol: "envelope.badge")
            stripDivider
            briefStat(model.dailyCategoryCounts.count, "涉及类别", symbol: "square.grid.2x2")
            stripDivider
            briefStat(model.brief.lowPriorityCount, "已过滤", symbol: "line.3.horizontal.decrease")
        }
        .padding(.vertical, 17)
        .background(ReaderTheme.surfaceRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(ReaderTheme.divider.opacity(0.65), lineWidth: 1)
        }
    }

    private var stripDivider: some View {
        Rectangle().fill(ReaderTheme.divider).frame(width: 1, height: 32)
    }

    private func briefStat(_ value: Int, _ label: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(value > 0 && label == "待巡检" ? ReaderTheme.danger : ReaderTheme.faint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(ReaderTheme.ink)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ReaderTheme.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var dailyAlertReview: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label("今日警报巡检", systemImage: "exclamationmark.triangle.fill")
                    .font(.editorial(24, weight: .semibold))
                    .foregroundStyle(ReaderTheme.danger)
                Text("逐项核实后清零；未处理项目会延续到下一份简报")
                    .font(.system(size: 12))
                    .foregroundStyle(ReaderTheme.faint)
            }
            .padding(.bottom, 10)

            ForEach(model.dailyAlertThreads) { thread in
                auditRow(thread, showsAlert: true)
            }
        }
        .padding(.bottom, 30)
    }

    private var dailyCategoryOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日分类概况")
                    .font(.editorial(24, weight: .semibold))
                    .foregroundStyle(ReaderTheme.ink)
                Spacer()
                Text("点击进入该类邮件")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ReaderTheme.faint)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(model.dailyCategoryCounts) { entry in
                    Button { model.changeSelection(.category(entry.category)) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: entry.category.symbol)
                                .foregroundStyle(ReaderTheme.accent)
                            Text(entry.category.rawValue)
                            Spacer()
                            Text("\(entry.count)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ReaderTheme.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(ReaderTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(ReaderTheme.divider.opacity(0.7), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 30)
    }

    private var dailyUnreadReview: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日未读清单")
                    .font(.editorial(24, weight: .semibold))
                    .foregroundStyle(ReaderTheme.ink)
                Text("最近 24 小时每一封尚未打开的邮件；已标明类别与关注状态")
                    .font(.system(size: 12))
                    .foregroundStyle(ReaderTheme.faint)
            }
            .padding(.bottom, 10)

            if model.dailyUnreadThreads.isEmpty {
                Label("今日邮件已全部过目", systemImage: "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ReaderTheme.positive)
                    .padding(.vertical, 14)
            } else {
                ForEach(model.dailyUnreadThreads) { thread in
                    auditRow(thread, showsAlert: false)
                }
            }
        }
        .padding(.bottom, 30)
    }

    private func auditRow(_ thread: MailThread, showsAlert: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.selectThread(thread.id) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(thread.readingState == .unread ? ReaderTheme.accent : ReaderTheme.faint)
                            .frame(width: 6, height: 6)
                        Text(thread.readingState == .unread ? "未读" : "已读")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(thread.readingState == .unread ? ReaderTheme.accent : ReaderTheme.faint)
                        Text(thread.senderName.isEmpty ? thread.senderEmail : thread.senderName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ReaderTheme.muted)
                        Spacer()
                        Label(thread.category.rawValue, systemImage: thread.category.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(ReaderTheme.faint)
                    }
                    Text(thread.subject)
                        .font(.chineseEditorial(21, weight: .semibold))
                        .foregroundStyle(ReaderTheme.ink)
                        .lineSpacing(4)
                        .multilineTextAlignment(.leading)
                    if let thesis = thread.investmentThesis {
                        InvestmentThesisView(thesis: thesis, compact: true)
                    } else {
                        Text(thread.summary)
                            .font(.system(size: 15))
                            .foregroundStyle(ReaderTheme.muted)
                            .lineSpacing(5)
                            .multilineTextAlignment(.leading)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsAlert {
                HStack {
                    Button("已核实并处理") { model.setState(.completed, threadID: thread.id) }
                        .buttonStyle(.borderedProminent)
                        .tint(ReaderTheme.accent)
                    Button("稍后提醒") { model.setState(.later, threadID: thread.id) }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) { Divider().overlay(ReaderTheme.divider.opacity(0.78)) }
    }

    @ViewBuilder
    private func briefSection(_ title: String, subtitle: String, items: [DailyBriefItem], accent: Bool) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.editorial(24, weight: .semibold))
                            .foregroundStyle(accent ? ReaderTheme.danger : ReaderTheme.ink)
                        Spacer()
                        Text("\(items.count) 条")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(ReaderTheme.faint)
                    }
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
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
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ReaderTheme.muted)
                                    Spacer()
                                    Label(item.category.rawValue, systemImage: item.category.symbol)
                                        .font(.system(size: 11))
                                        .foregroundStyle(ReaderTheme.faint)
                                }
                                Text(item.title)
                                    .font(.chineseEditorial(20, weight: .semibold))
                                    .foregroundStyle(ReaderTheme.ink)
                                    .lineSpacing(4)
                                    .multilineTextAlignment(.leading)
                                if let thesis = item.investmentThesis {
                                    InvestmentThesisView(thesis: thesis, compact: true)
                                        .padding(.top, 2)
                                }
                                if item.investmentThesis == nil {
                                    Text(item.summary)
                                        .font(.system(size: 15))
                                        .foregroundStyle(ReaderTheme.ink)
                                        .lineSpacing(5)
                                        .multilineTextAlignment(.leading)
                                }
                                Text(item.whyItMatters)
                                    .font(.system(size: 14))
                                    .foregroundStyle(ReaderTheme.muted)
                                    .lineSpacing(4)
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
                        .padding(.vertical, 22)
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
                    Divider().overlay(ReaderTheme.divider.opacity(0.78))
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
                            .frame(maxWidth: 800, alignment: .leading)
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
                .labelStyle(.iconOnly)
                .help(thread.userAttention ? "取消手工关注" : "加入关注")
            }
            Button { model.setState(.later) } label: {
                Label("待看", systemImage: thread.readingState == .later ? "bookmark.fill" : "bookmark")
            }
            .labelStyle(.iconOnly)
            .help("稍后阅读")
            Button { model.setState(.completed) } label: {
                Label("处理完成", systemImage: "checkmark.circle")
            }
            Divider().frame(height: 18)
            Button { model.openInGmail() } label: {
                Label("在 Gmail 打开", systemImage: "arrow.up.right.square")
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(ReaderTheme.muted)
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(ReaderTheme.surfaceRaised.opacity(0.6))
    }

    @ViewBuilder
    private func readerContent(_ thread: MailThread) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(thread.needsAttention ? "需要关注" : thread.readingState.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(thread.needsAttention ? ReaderTheme.accent : ReaderTheme.muted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(thread.needsAttention ? ReaderTheme.dangerSoft : ReaderTheme.surfaceRaised, in: Capsule())
                Spacer()
                Text(thread.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(ReaderTheme.faint)
            }

            Text(thread.subject)
                .font(.chineseEditorial(36, weight: .semibold))
                .foregroundStyle(ReaderTheme.ink)
                .lineSpacing(6)
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
                        .font(.system(size: 12))
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
                Text(thread.investmentThesis == nil ? "AI 解读" : "投资研究解读")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(ReaderTheme.accent)
                if let thesis = thread.investmentThesis {
                    InvestmentThesisView(thesis: thesis, compact: false)
                        .padding(.top, 4)
                    Text("邮件概览")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ReaderTheme.muted)
                        .padding(.top, 10)
                }
                Text(thread.summary)
                    .font(.chineseEditorial(21, weight: .medium))
                    .foregroundStyle(ReaderTheme.ink)
                    .lineSpacing(8)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("为什么值得关注")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ReaderTheme.muted)
                Text(thread.whyImportant)
                    .font(.system(size: 15))
                    .foregroundStyle(ReaderTheme.ink)
                    .lineSpacing(5)
            }

            if !thread.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("建议行动")
                            .font(.system(size: 13, weight: .semibold))
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
                                .font(.system(size: 15))
                                .foregroundStyle(ReaderTheme.ink)
                                .lineSpacing(4)
                        }
                    }
                }
            }
        }
        .padding(22)
        .padding(.leading, 8)
        .background(ReaderTheme.surfaceRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ReaderTheme.divider.opacity(0.65), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            Capsule().fill(ReaderTheme.accent).frame(width: 3).padding(.vertical, 18)
        }
        .shadow(color: ReaderTheme.shadow.opacity(0.25), radius: 12, y: 5)
    }
}

private struct InvestmentThesisView: View {
    let thesis: InvestmentThesis
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 20) {
            HStack(spacing: 8) {
                Text("核心 THESIS")
                    .font(.system(size: compact ? 11 : 12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(ReaderTheme.accent)
                if let horizon = thesis.horizon, !horizon.isEmpty {
                    Text(horizon)
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(ReaderTheme.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(ReaderTheme.selected, in: Capsule())
                }
                Spacer()
            }

            Text(thesis.thesis)
                .font(.chineseEditorial(compact ? 18 : 24, weight: .semibold))
                .foregroundStyle(ReaderTheme.ink)
                .lineSpacing(compact ? 5 : 8)
                .multilineTextAlignment(.leading)
                .lineLimit(compact ? 4 : nil)

            if !thesis.tickers.isEmpty {
                HStack(spacing: 6) {
                    ForEach(thesis.tickers, id: \.self) { ticker in
                        Text(ticker)
                            .font(.system(size: compact ? 11 : 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(ReaderTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .overlay(Capsule().stroke(ReaderTheme.accent.opacity(0.35)))
                    }
                }
            }

            if compact {
                HStack(spacing: 14) {
                    compactCount("关键依据", count: thesis.evidence.count, symbol: "checkmark.seal")
                    compactCount("催化剂", count: thesis.catalysts.count, symbol: "bolt")
                    compactCount("风险", count: thesis.risks.count, symbol: "exclamationmark.triangle")
                    Spacer()
                    Label("打开查看完整研究", systemImage: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ReaderTheme.faint)
                }
            } else {
                if !thesis.evidence.isEmpty {
                    thesisList("关键依据", items: thesis.evidence, symbol: "checkmark")
                }
                if !thesis.catalysts.isEmpty || !thesis.risks.isEmpty {
                    HStack(alignment: .top, spacing: 26) {
                        if !thesis.catalysts.isEmpty {
                            thesisList("潜在催化剂", items: thesis.catalysts, symbol: "arrow.up.right")
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        if !thesis.risks.isEmpty {
                            thesisList("证伪与风险", items: thesis.risks, symbol: "exclamationmark")
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
            }
        }
        .padding(compact ? 16 : 22)
        .background(compact ? ReaderTheme.surfaceRaised.opacity(0.78) : ReaderTheme.queue.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(compact ? ReaderTheme.accent.opacity(0.18) : ReaderTheme.divider, lineWidth: 1)
        }
    }

    private func compactCount(_ title: String, count: Int, symbol: String) -> some View {
        Label("\(title) \(count)", systemImage: symbol)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(ReaderTheme.muted)
    }

    private func thesisList(_ title: String, items: [String], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            Text(title)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(ReaderTheme.muted)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: compact ? 9 : 10, weight: .bold))
                        .foregroundStyle(ReaderTheme.accent)
                        .padding(.top, 4)
                    Text(item)
                        .font(.system(size: compact ? 14 : 15))
                        .foregroundStyle(ReaderTheme.ink)
                        .lineSpacing(compact ? 5 : 6)
                        .multilineTextAlignment(.leading)
                }
            }
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
    func sidebarSectionTitle(topPadding: CGFloat = 0) -> some View {
        self
            .font(.system(size: 12, weight: .bold))
            .tracking(0.55)
            .foregroundStyle(ReaderTheme.muted)
            .padding(.horizontal, 20)
            .padding(.top, topPadding)
            .padding(.bottom, 8)
    }
}
