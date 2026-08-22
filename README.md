# Email Reader

[简体中文](README.md) · [English](README_EN.md)

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-111827?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License](https://img.shields.io/badge/license-MIT-22c55e)](LICENSE)

一个本地优先的 macOS Gmail 邮件情报工作台。它不会复制 Gmail
收件箱，而是把每天的新邮件整理成一份可以快速处理的中文简报：风险预警、
行动事项、主题信号、投资 Thesis，以及真正值得稍后阅读的内容。

> 目标不是“换一个地方逐封看邮件”，而是先看结论、处理预警，只有必要时
> 才回到 Gmail 查看完整原文。

## 它解决什么问题

- **减少逐封阅读**：长邮件先提炼核心事实、数字、日期和行动要求。
- **每天给出判断顺序**：优先呈现必须处理、需要关注和新增强信号，而不是邮件数量。
- **把资讯变成研究材料**：投资 Substack 会提取核心 Thesis、证据、催化剂、反证风险、Ticker 和时间范围。
- **保留来源证据**：每个结论都绑定原始邮件，必要时可以返回 Gmail 核查。
- **本地管理状态**：未读、待看、关注和完成状态留在本机，不反写 Gmail。

## 核心能力

| 能力 | 当前实现 |
| --- | --- |
| Gmail 同步 | 首次仅导入 Inbox 最近 7 天，之后使用 `historyId` 增量读取 |
| 每日简报 | 07:30 Codex Automation 自动执行，也支持 App 内手动更新 |
| 正式分析模型 | `gpt-5.6-luna`，Medium reasoning |
| 邮件解读 | 逐封分类、摘要、重要性判断、行动和截止日期提取 |
| 投资研究 | 结构化 Thesis、证据、催化剂、反证风险、Ticker、时间范围 |
| 跨邮件整理 | 聚类、去重、排序、降噪，并形成风险/强信号/稍后阅读 |
| 本地存储 | SQLite 保存邮件、阅读状态、分析结果和历史简报 |
| 离线备用 | Ollama `qwen3.5:4b`，仅显式调用，不覆盖 Luna 正式简报 |

## 系统架构与每日流程

正式生产路径坚持“简报优先”：Gmail 是只读信息源，Luna Medium 负责正式
解读，SQLite 是阅读状态和已发布简报的本地事实来源。

### 本地优先架构

[![Email Reader 本地优先架构](Docs/assets/email-reader-architecture.png)](Docs/email-reader-architecture.html)

### 每日情报简报流程

[![Email Reader 每日情报流程](Docs/assets/daily-intelligence-flow.png)](Docs/daily-intelligence-flow.html)

点击图片可以打开独立 HTML/SVG 文件，查看大图并导出高清 PNG 或 PDF。
组件职责、信任边界和失败保护详见[架构说明](Docs/ARCHITECTURE.md)。图表设计系统
基于 [Cocoon AI Architecture Diagram Generator](https://github.com/Cocoon-AI/architecture-diagram-generator)
的 MIT 授权版本。

## 当前版本：1.0

- 原生 SwiftUI 情报工作台，原始邮件库默认折叠为证据层。
- 侧边栏展示每日警报、跨邮件研究主题、重点 Ticker、邮件类型和历史简报。
- 正式构建不会插入演示邮件。
- Gmail OAuth Desktop App + PKCE + loopback callback。
- OAuth Token 保存于 macOS Keychain。
- 本地确定性规则在同步后先提供安全分类，随后由 Luna 生成权威分析和简报。
- 长邮件分段提炼；未变化正文可通过摘要指纹避免无意义重复处理。
- 系统风险与用户手工关注状态分离，重新分析不会隐藏安全预警或抹掉用户决定。
- 每次成功简报都会在本地归档，可按日期回看。
- App 不注册 macOS 后台项目；定时执行由 Codex Automation 负责。
- 不渲染邮件远程图片和追踪像素。

## 准备条件

- macOS 14 或更高版本。
- Swift 6 / Xcode Command Line Tools。
- 一个 Google Cloud **Desktop app** OAuth Client，并已启用 Gmail API。
- 已登录的 Codex 环境，用于正式 Luna Medium 每日分析。
- 可选：本机 Ollama 与 `qwen3.5:4b`，仅在需要离线备用时使用。

## 构建与安装

```bash
./scripts/build_app.sh
./scripts/install_personal_app.sh
open "$HOME/Applications/Email Reader.app"
```

默认构建使用 ad-hoc 签名，仅适合个人本机安装，不应直接分发。公开发布二进制
文件必须使用 Apple Developer ID Application 证书、Hardened Runtime 和
Apple notarization：

```bash
EMAILREADER_SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" ./scripts/build_app.sh
```

## 连接 Gmail

1. 在 Google Cloud 创建类型为 **Desktop app** 的 OAuth Client。
2. 启用 Gmail API，并下载 Client JSON。
3. 打开 Email Reader 的**账户与更新设置**。
4. 选择 Client JSON，在浏览器中完成一次 Gmail 授权。

App 只申请账户身份信息和 `gmail.readonly`。它不能发送、删除、归档、加标签，
也不能把 Gmail 邮件标记为已读。

## 模型与发布边界

- 定时更新和 App 内“更新并重新整理”都走同一条 Luna Medium 正式管线。
- Luna 先分析每一封入选邮件，再进行跨邮件聚类、排序和全局简报编辑。
- 输出必须完整匹配本次导出的精确邮件 ID Manifest，并通过 Schema、分类和动作规则校验。
- 单封分析和当前简报在一个 SQLite Transaction 中原子发布。
- Luna 生成或校验失败时保留上一份有效简报，不安装部分结果，也不静默切换到 Qwen。
- 界面显示当前简报真实使用的模型，而不是固定模型名称。

完整约束见 [Codex 每日情报契约](CODEX_DAILY_BRIEF.md)。

## 隐私与安全

- 仓库不包含邮箱数据库、OAuth Client JSON、Access/Refresh Token 或真实简报产物。
- OAuth 凭据保存为一个 macOS Keychain 项，新项目使用 `AfterFirstUnlockThisDeviceOnly`。
- 固定本地 Helper 负责日常 Keychain 访问，普通 App 重建不会反复替换它。
- 邮件正文按不可信输入处理，Prompt 明确忽略邮件中试图控制模型的指令。
- 正式 Luna 路径会把本次选中的邮件元数据和每封最多 9,000 字符纯文本正文发送到用户已认证的 Codex Task。
- 临时分析目录会在运行结束后删除；其余邮箱数据保留在本机。
- 导入的 OAuth JSON 不能重定向凭据，授权和刷新只使用代码内固定的 Google 官方端点。
- 不渲染远程图片和追踪像素。

进一步说明见 [SECURITY.md](SECURITY.md)。请勿在公开 Issue 中提交真实邮件、
OAuth 配置、Token、数据库、日志或包含私人邮件的截图。

## 本地数据位置

| 数据 | 位置 |
| --- | --- |
| SQLite | `~/Library/Application Support/EmailReader/email_reader.sqlite3` |
| OAuth 凭据 | macOS Keychain：`com.sota.EmailReader.oauth.v4` |
| 安装后的 App | `~/Applications/Email Reader.app` |
| 历史简报 | `~/Library/Application Support/EmailReader/brief_history/` |
| 稳定同步 Helper | `~/Library/Application Support/EmailReader/EmailReaderWorker` |

构建产物和分析中间文件不会提交到 Git。运行 `./scripts/verify.sh` 可以重新构建并
执行项目验证。

## 文档

- [系统架构与数据边界](Docs/ARCHITECTURE.md)
- [Codex 每日情报契约](CODEX_DAILY_BRIEF.md)
- [产品与视觉设计契约](DESIGN_CONTRACT.md)
- [安全策略](SECURITY.md)

## 后续方向

- 多 Gmail 账户和其他邮箱 Provider。
- iPhone 客户端与个人服务器同步。
- 基于“有用 / 太吵”反馈的本地偏好学习。
- 跨日主题变化、持续风险和未解决行动回看。

## 参与项目

欢迎提交 Issue 或 Pull Request。提交前请运行 `./scripts/verify.sh`，并确认没有把
OAuth 配置、Token、邮箱数据库、真实邮件或个人分析结果加入 Git。

## License

本项目使用 [MIT License](LICENSE)。
