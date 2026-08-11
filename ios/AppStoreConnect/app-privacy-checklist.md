# App Privacy 回答与证据清单

核对日期：2026-08-11
适用 Bundle ID：`com.zhili.todo-native`

> 本清单用于准备 App Store Connect 的 App Privacy 问卷。最终答案必须与**实际提交的 Release 构建及其当时可用的生产服务**一致。`NSPrivacyCollectedDataTypes` 为空只说明当前 Privacy Manifest 的声明状态，不替代 App Store Connect 问卷。

## 1. 提交构建的数据路径边界

| 路径 | 是否离开设备 | 当前实现证据 | App Privacy 处理 |
|---|---|---|---|
| 任务、上下文、验收标准、下一步 Prompt、状态、截止时间 | 默认不离开；保存在 SwiftData | `Models/TodoItem.swift`、`TodoNativeApp.swift` | 仅本地使用时不属于开发者“收集”。如果用户同意远程 AI，选中的任务内容会成为下述 User Content。 |
| 伙伴聊天、记忆摘要、AI brief/cache、语言和提醒偏好 | 默认不离开；保存在 UserDefaults | `ViewModels/CompanionViewModel.swift`、`Services/AIBriefCache.swift`、`Services/NotificationService.swift` | 仅本地使用时不属于开发者“收集”。相关聊天/摘要被远程 AI 请求采用时按 User Content 申报。 |
| BYOK API Key | Key 保存在本机 Keychain；远程调用时作为授权头直接给用户所选模型服务商 | `Services/KeychainStore.swift`、`Services/OpenAIService.swift` | 开发者 Worker 不接收 Key。不要把 Key 写入审核备注、截图或支持邮件。服务商可能按其条款处理账号/请求信息。 |
| BYOK 提示、任务/聊天上下文和输出请求 | 用户同意后直接发送到所选 OpenAI 兼容服务商 | `OpenAIService.currentConsentRoute()`、`directCall(messages:)`、`AIConsentManager.swift` | 建议申报 **User Content / Other User Content**，目的 **App Functionality**，不用于 Tracking。Linked 状态采用保守口径：**Yes**，因为 API Key/服务商账号可能把请求关联到用户；最终由隐私负责人确认。 |
| 托管 AI 内容 | 用户同意后先发 Worker，再由 Worker 发 DeepSeek | `QuotaClient.chat`、`workers/quota-proxy/src/index.js` | 生产 endpoint 当前缺失，Release 中此路径不可用。若提交前启用，申报 **User Content / Other User Content**，目的 **App Functionality**，Linked **Yes**（与随机设备 ID 同请求/同配额记录），Tracking **No**。 |
| 随机设备 ID / Support ID | 只有托管 endpoint 可用并发起 quota/chat/register-pro 时发送给 Worker；设置页把同一匿名 ID 显示为带 `TD-` 前缀的可复制 Support ID | `QuotaClient.deviceID`、`SupportIdentifier`、`X-Device-Id` 请求头 | 当前无生产 endpoint 时不上传。若启用，申报 **Identifiers / Device ID**，目的 **App Functionality**，Linked **Yes**（用于持续配额、权益记录和用户发起的删除请求），Tracking **No**。它不是 IDFA、姓名、邮箱或精确位置；不得进入公开截图。 |
| StoreKit 交易 JWS 与权益/到期信息 | Apple 在设备上提供；只有托管 endpoint 可用时才由 app 向 Worker 发送 JWS，Worker保存按设备 ID 索引的到期时间 | `PurchaseManager.registerVerifiedTransaction`、`QuotaClient.registerPro`、Worker `registerPro` | 当前无生产 endpoint 时 JWS 不离开设备。若启用，建议申报 **Purchases / Purchase History**，目的 **App Functionality**，Linked **Yes**（与随机设备 ID 关联），Tracking **No**。 |
| 支付卡、银行信息、Apple ID 付款资料 | 由 Apple/App Store 处理；当前代码没有读取或接收 | StoreKit 2 `Product.purchase()` / `Transaction.currentEntitlements` | **不要**申报为开发者收集的 Payment Info。Developer 可能接收的只是上行 JWS/产品/到期权益，不是卡号或付款账户。 |
| 原始语音录音 | app 通过 `AVAudioEngine` 捕获并交给 `SFSpeechRecognizer`；不会发送给 Worker或模型服务商。Apple Speech 是否协助处理取决于设备、系统、语言和网络 | `Services/CompanionVoiceRuntime.swift`、`Services/CompanionVoiceRecorder.swift`；`privacy.html` 麦克风段落 | 不得写成“始终完全在设备上”。`ACTION REQUIRED`：隐私负责人依据提交地区、Apple Speech 条款和 App Store Connect 当期说明，确认是否需选择 **Audio Data**。无论问卷选择如何，材料必须披露 Apple Speech 可能处理音频，且开发者 Worker/模型不接收原始录音。 |
| 语音转写文本 | 先进入输入框；只有用户随后选择发送远程 AI 请求且已同意时才离开设备 | `Views/CompanionView.swift`、`AIConsentView.swift` | 未发送时本地；发送后并入 **User Content / Other User Content**。 |
| 通知内容 | 由 app 安排本地 `UNUserNotificationRequest` | `Services/NotificationService.swift` | 当前没有推送服务器或远程通知 token；不申报开发者收集。通知可包含任务标题，截图和测试任务必须脱敏。 |
| 诊断、使用分析、广告、位置、通讯录 | 当前 iOS 源码未发现 SDK 或上传链路 | iOS 源码 URLSession 路径仅 `OpenAIService` / `QuotaClient`；`PrivacyInfo.xcprivacy` tracking=false | 当前回答为不收集、不追踪。每次引入 SDK 或服务后重新扫描。 |

## 2. 当前 Release（无生产 managed endpoint）的建议问卷基线

- [ ] Data Used to Track You：**No**。
- [ ] Tracking domains / IDFA：**None**；`NSPrivacyTracking` 为 `false`。
- [ ] User Content → Other User Content：**Yes**，仅在用户配置 BYOK、看到接收方说明并同意后发送；Purpose = App Functionality；Tracking = No；Linked = `ACTION REQUIRED — 建议保守选择 Yes，提交前由隐私负责人确认。`
- [ ] Identifiers → Device ID：**No for the current submitted configuration**，前提是 Release 确实没有 managed endpoint，且没有其他设备 ID 上传链路。
- [ ] Purchases / Purchase History：**No developer collection for the current submitted configuration**；StoreKit 本地读取不等于开发者收集，且 endpoint 缺失时交易 JWS 不上传。
- [ ] Payment Info：**No**；Apple 处理且开发者无法访问的卡/付款信息不可误报为开发者收集。
- [ ] Audio Data：`ACTION REQUIRED — 按 Apple Speech 的实际处理与当期问卷规则确认；不可仅凭“app 不上传 Worker”推断为 No。`
- [ ] Diagnostics / Analytics / Advertising / Location / Contacts / Health / Financial info：**No based on current code scan**。

## 3. 启用生产 managed AI 前必须改动的答案

生产 Worker 一旦写入 `ManagedAIBaseURL` 并可用，提交前重新回答：

- [ ] User Content → Other User Content：Yes；App Functionality；Linked Yes；Tracking No；接收方为开发者 Worker + DeepSeek。
- [ ] Identifiers → Device ID：Yes；App Functionality；Linked Yes；Tracking No。
- [ ] Purchases → Purchase History：Yes；App Functionality；Linked Yes；Tracking No；明确不包含支付卡信息。
- [ ] 在隐私政策中写清 Worker/DeepSeek、配额计数、订阅到期记录、保留与删除渠道。
- [ ] 确认 App 内同意页的接收方 host、隐私政策和问卷完全一致。

## 4. Worker 部署后必须重新核对的证据

- [ ] `Info.plist` / Archive 中 `ManagedAIBaseURL` 是真实 HTTPS 地址，不是空值或占位。
- [x] 仓库 `wrangler.toml` 已声明 `QUOTA` automatic provisioning、`ENTITLEMENTS` 与 `DEVICE_PRIVACY` SQLite Durable Objects 及 migrations `v1` / `v2`；Wrangler dry-run 已通过。这不代表生产 namespace/DO 已创建或迁移。
- [ ] 生产 Worker 存在 `DEEPSEEK_API_KEY` secret，且仓库、截图和日志无密钥。
- [ ] `/proxy/chat/completions`、`/proxy/quota`、`/proxy/register-pro` 的真实响应与文档契约一致。
- [x] Worker 提交 `5ee3606` 已实现 Apple transaction JWS 离线验签：ES256、固定 Apple roots、完整 leaf→WWDR→root 证书链、bundle ID、显式 environment、月/年产品、到期与 payload `revocationDate`；持久层不保存完整 JWS 或原始 transaction ID。
- [ ] `ACTION REQUIRED — 离线验签不执行 OCSP。` 发布负责人必须书面接受证书实时撤销不可见的风险，或上线前实现并验证完整在线检查；不得把离线校验描述成实时 Apple 状态查询。
- [x] 仓库已实现 App Store Server Notifications V2：外/内层 JWS、app identity/environment/product 校验，以及 `SUBSCRIBED`、`DID_RENEW`、`EXPIRED`、`REFUND`、`REVOKE` 幂等状态处理。
- [ ] `BLOCKED（外部）— Notifications V2 生产接入未验证。` 必须配置生产 `APP_STORE_APPLE_ID` 和 ASC URL，完成 Send Test Notification、Sandbox 续费/到期/退款/撤销及真实 read-back，才能上线托管订阅配额。
- [x] 仓库已实现 UUID identity canonicalization、`DEVICE_PRIVACY` 强一致 lease/erasure 与 hash-only resource catalog、三条设备请求 `410 device_erased`、KV 删除后 65 秒 exact read-back、两轮间隔 65 秒 legacy 空验证、Entitlement DO mapping 清理、无 raw device ID 与脱敏 owner helper 测试；无既有数据的有效 Support ID 也会保留 hashed suppression。
- [ ] `BLOCKED（外部）— 生产删除演练尚未完成。` 必须在真实隔离环境按 `managed-data-deletion-runbook.md` 完成 create → active lease/retry → erase → replay → read-back，并确认只保留已披露的 hashed erased/交易级状态，才能宣称生产删除可操作。
- [ ] 重新扫描 iOS 与 Worker 的所有网络请求和第三方 SDK；同步更新本清单、Privacy Manifest、App Store Connect 问卷和公开隐私政策。

## 5. 公开页面一致性证据

- [x] 2026-08-11 真实线上 Privacy 页面返回 HTTP 200，并说明远程 AI 明示同意、撤回、清除本地 AI 配置/Keychain 以及支持邮箱。
- [x] 2026-08-11 真实线上 Support 页面返回 HTTP 200，并发布 `lz123321@live.com` 和隐私删除请求说明。
- [x] 2026-08-11 真实线上 Terms 页面返回 HTTP 200，并区分设备本地 7 天体验与 App Store Introductory Offer。
- [ ] `ACTION REQUIRED — 法律主体`：线上隐私页仍以“App Store 产品页面显示的卖方/开发者”描述控制者；提交前必须与最终 seller/copyright/DSA 信息核对。
- [ ] 每次提交前再次用真实浏览器复核标题、正文、邮箱、删除请求说明和三页互链；仅 HTTP 成功不足以证明未来内容未变化。
