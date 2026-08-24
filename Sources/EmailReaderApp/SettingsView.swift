import EmailReaderCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var importingOAuth = false
    @State private var isConnecting = false
    @State private var localError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(ReaderTheme.divider.opacity(0.8))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    gmailCard
                    updateCard
                    analysisCard
                    privacyCard

                    if let localError {
                        Label(localError, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ReaderTheme.danger)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ReaderTheme.dangerSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 700, height: 660)
        .background(ReaderTheme.reader)
        .fileImporter(isPresented: $importingOAuth, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                isConnecting = true
                Task {
                    defer { isConnecting = false }
                    do {
                        try await model.connectGmail(oauthConfigurationURL: url)
                    } catch {
                        localError = error.localizedDescription
                    }
                }
            case .failure(let error):
                localError = error.localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ReaderTheme.accentSoft)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ReaderTheme.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("账户、模型与更新")
                    .font(.editorial(27, weight: .semibold))
                    .foregroundStyle(ReaderTheme.ink)
                Text("本地只读邮件工作台 · Gmail 原状态不会被修改")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ReaderTheme.muted)
            }
            Spacer()
            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(ReaderTheme.accent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var gmailCard: some View {
        settingCard(title: "Gmail 账户", symbol: "envelope.badge.shield.half.filled", tint: ReaderTheme.positive) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(isConnected ? ReaderTheme.positiveSoft : ReaderTheme.accentSoft)
                    Circle().fill(isConnected ? ReaderTheme.positive : ReaderTheme.accent)
                        .frame(width: 8, height: 8)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.account?.email.isEmpty == false ? model.account?.email ?? "" : "尚未连接 Gmail")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ReaderTheme.ink)
                    Text(accountStatus)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isConnected ? ReaderTheme.positive : ReaderTheme.muted)
                }
                Spacer()
                Button(isConnected ? "更新授权" : "选择 OAuth 配置并连接") {
                    importingOAuth = true
                }
                .buttonStyle(.bordered)
                .disabled(isConnecting)
            }

            infoLine(
                "授权成功后刷新令牌保存在 macOS Keychain；正常使用不会反复登录。只有撤销授权、令牌失效或主动更换账号时才需要重新授权。",
                symbol: "key.horizontal"
            )
        }
    }

    private var updateCard: some View {
        settingCard(title: "每日简报", symbol: "sunrise.fill", tint: ReaderTheme.accent) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("每天 07:30 · Codex 定时任务")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ReaderTheme.ink)
                    Text("Luna Medium 分析最近 24 小时正文，再完成跨邮件排序、分类和投资 Thesis 汇总。")
                        .font(.system(size: 13))
                        .foregroundStyle(ReaderTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 14)
                statusBadge("已启用", tint: ReaderTheme.positive)
            }
            infoLine("Email Reader 不注册 macOS 后台项目；手动“更新简报”也调用同一条 Luna 流程。", symbol: "clock.arrow.2.circlepath")
        }
    }

    private var analysisCard: some View {
        settingCard(title: "解读引擎", symbol: "sparkles", tint: ReaderTheme.accent) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Luna Medium")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ReaderTheme.ink)
                    Text("正式简报模型 · 逐封正文分析 + 跨邮件综合")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ReaderTheme.muted)
                }
                Spacer()
                Button("检查本地能力") { model.checkAnalysisAvailability() }
                    .buttonStyle(.bordered)
            }

            infoLine(model.analysisAvailability, symbol: "desktopcomputer")
            infoLine("qwen3.5:4b 仅保留为显式离线备用，不参与或覆盖正式结果。Luna 失败时保留上一份有效简报。", symbol: "arrow.triangle.branch")
        }
    }

    private var privacyCard: some View {
        settingCard(title: "隐私与权限", symbol: "lock.shield.fill", tint: ReaderTheme.positive) {
            VStack(alignment: .leading, spacing: 10) {
                privacyRow("远程图片与追踪像素默认阻止", symbol: "eye.slash")
                privacyRow("邮件正文保存在本机 SQLite，OAuth 令牌保存在 Keychain", symbol: "internaldrive")
                privacyRow("只申请读取权限；不发送、不删除、不归档邮件", symbol: "hand.raised")
            }
        }
    }

    private var isConnected: Bool { model.account?.authState == "connected" }

    private var accountStatus: String {
        switch model.account?.authState {
        case "connected": "已连接 · Gmail 只读"
        case "authorizing": "等待浏览器授权"
        default: "尚未连接 Gmail"
        }
    }

    private func settingCard<Content: View>(
        title: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .bold))
                .tracking(0.35)
                .foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(ReaderTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ReaderTheme.divider.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: ReaderTheme.shadow.opacity(0.32), radius: 10, y: 3)
    }

    private func infoLine(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .frame(width: 16)
        }
        .font(.system(size: 12))
        .foregroundStyle(ReaderTheme.muted)
    }

    private func privacyRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ReaderTheme.positive)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ReaderTheme.ink)
        }
    }

    private func statusBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
    }
}
