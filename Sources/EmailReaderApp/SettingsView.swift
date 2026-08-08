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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("账户与更新")
                        .font(.editorial(27, weight: .semibold))
                    Text("第一版只读取 Gmail，不修改原邮箱状态。")
                        .font(.system(size: 12))
                        .foregroundStyle(ReaderTheme.muted)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)

            Divider().overlay(ReaderTheme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    settingSection("Gmail 账户") {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.account?.email.isEmpty == false ? model.account?.email ?? "" : "尚未连接 Gmail")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(accountStatus)
                                    .font(.system(size: 11))
                                    .foregroundStyle(ReaderTheme.muted)
                            }
                            Spacer()
                            Button(model.account?.authState == "connected" ? "重新授权" : "选择 OAuth 配置并连接") {
                                importingOAuth = true
                            }
                            .disabled(isConnecting)
                        }
                        Text("需要一个 Google Cloud ‘Desktop app’ OAuth 客户端 JSON。访问令牌与刷新令牌只存入 macOS Keychain。")
                            .font(.system(size: 11))
                            .foregroundStyle(ReaderTheme.faint)
                    }

                    settingSection("每日更新") {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(ReaderTheme.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("由 Codex 定时触发，Luna Medium 生成最终简报")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("每天 07:30 触发一次；Luna Medium 直接分析最近 24 小时邮件正文，逐封生成分类、摘要、关注判断和投资 Thesis，再完成跨邮件排序与最终简报。Email Reader 不注册 macOS 后台项目。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(ReaderTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                    }

                    settingSection("邮件解读") {
                        HStack {
                            Label(model.analysisAvailability, systemImage: "apple.intelligence")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button("重新检查") { model.checkAnalysisAvailability() }
                        }
                        Text("每日定时更新和右上角手动更新都使用 Luna Medium 直接完成逐封正文分析与最终简报。qwen3.5:4b 仍可作为显式离线备用，但不会参与或覆盖正式结果。若 Luna 失败，App 会保留上一份有效简报；右上角始终显示当前简报的实际生成模型。")
                            .font(.system(size: 11))
                            .foregroundStyle(ReaderTheme.faint)
                    }

                    settingSection("隐私") {
                        Label("远程图片与追踪像素默认阻止", systemImage: "eye.slash")
                        Label("邮件正文保存在本机 SQLite，OAuth 令牌保存在 Keychain", systemImage: "lock")
                        Label("第一版不申请发信、删除或归档权限", systemImage: "hand.raised")
                    }
                    .font(.system(size: 12))

                    if let localError {
                        Text(localError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
                .padding(28)
            }
        }
        .frame(width: 660, height: 610)
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

    private var accountStatus: String {
        switch model.account?.authState {
        case "connected": "已连接 · Gmail 只读"
        case "authorizing": "等待浏览器授权"
        default: "尚未连接 Gmail"
        }
    }

    private func settingSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(ReaderTheme.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 24)
        .overlay(alignment: .bottom) { Divider().overlay(ReaderTheme.divider) }
    }
}
