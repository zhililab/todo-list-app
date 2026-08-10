# App Store 托管 AI 首发设计

## 目标

将 TodoNative 准备为可提交 App Review 的首发版本：用户可订阅托管 AI，付费权益和 Worker 配额一致；向第三方 AI 传输任务或对话前取得明确许可；法律页面、隐私披露和审核材料可在现有公开站点使用。

## 首发产品边界

- 平台：iOS 17+，同时支持 iPhone 和 iPad。
- 商业模式：自动续费月度和年度订阅，Product ID 固定为 `com.zhili.todo.premium.monthly` 与 `com.zhili.todo.premium.yearly`，并置于同一个 Subscription Group。
- 托管 AI：无自带 API Key 时使用生产 quota worker；免费额度为 10 次，订阅用户为每日 20 次。
- 自带 Key：用户选择的兼容服务商直接处理请求；仍须在首次远程调用前同意数据传输。
- 不包含用户账号、云端任务同步、广告、追踪或推送通知。任务、聊天历史和 API 配置默认存于本机。
- 不将本地 7 天体验期称为 App Store Intro Offer。若 App Store Connect 后续配置 Intro Offer，界面必须使用 StoreKit eligibility 显示，不与本地体验期混用。

## 公开页面与链接

首发公开 HTTPS 基址为 `https://todo-list-app.zhili1993.chatgpt.site`。

| 页面 | 路径 | 必含内容 |
|---|---|---|
| 隐私政策 | `/privacy.html` | 本地数据、任务/聊天/语音文本、匿名设备 ID、订阅交易、第三方 AI、用途、保留与删除方式、联系渠道 |
| 服务条款 | `/terms.html` | 订阅、续费、取消、AI 输出限制、可接受使用、责任限制 |
| 支持页 | `/support.html` | 联系方式、版本与系统要求、隐私删除请求、购买/恢复购买与通知/语音故障排查 |

这三个链接在 Paywall、设置页和 App Store Connect 元数据中保持一致。更换正式域名时保留旧页面重定向，并同时更新 App Store Connect 与下一个 iOS 版本中的 URL。

## 隐私与 AI 同意

### 用户可见行为

在第一次远程 AI 请求前，App 展示不可预选的同意页：

1. 说明会发送的内容：用户提交的目标、任务字段、聊天消息和用于生成结果的必要上下文；语音仅在系统识别后以文本形式参与 AI 请求。
2. 说明接收方：托管模式为 quota worker 与其配置的模型服务商；自带 Key 模式为用户所选服务商。
3. 提供隐私政策链接、拒绝按钮和继续按钮。
4. 拒绝或撤回后，所有 AI 操作使用本地规划器；不发送任务或对话内容到网络。
5. 设置页可重新阅读政策、撤回授权、清除本地 AI 配置和 Keychain 中 API Key。

同意记录只保存授权版本、服务模式和时间；不保存模型输入副本。切换到不同的第三方服务商、或隐私政策版本变化时重新请求同意。

### App Store 隐私披露

App Store Connect 的 App Privacy 回答必须以实际生产链路为准，至少评估：

- User Content：任务、目标和聊天文本；
- Identifiers：匿名 `X-Device-Id`；
- Purchases：交易 JWS 与订阅状态；
- Usage Data：额度计数；
- Audio Data：仅按系统语音服务和实际远程处理方式披露。

Privacy Manifest 与 App Store Privacy 标签分别维护：前者申报 Required Reason API，后者披露数据收集和处理方式。

## iOS 架构

### 配置与凭据

- 引入 `AppConfiguration`，从 Release Info.plist 读取生产 quota base URL、隐私政策 URL、服务条款 URL 与支持 URL。
- Debug 可以覆盖 quota URL；Release 不允许以空 URL 静默宣称托管 AI 可用。若生产 URL 缺失，托管 AI 状态显示不可用且不会向用户承诺额度。
- API Key 改存 Keychain；首次运行迁移旧 UserDefaults 值后立即删除旧值。
- 加入 `PrivacyInfo.xcprivacy`，申报本应用使用的 Required Reason API。

### AI 请求门控

`AIConsentManager` 只负责同意状态和版本迁移；`AIAssistantService`、Companion 和 AI Workbench 都通过同一门控检查。门控结果为：

- `allowed`：执行现有远程路径；
- `needsConsent`：展示同意页，不发送请求；
- `declined`：执行本地规划器。

自动每日简报在未授权时只显示本地结果或提示用户主动启用 AI，不得后台传输任务内容。

### 订阅与配额

`PurchaseManager` 在 verified purchase、restore 和 `Transaction.updates` 中将 `transaction.jwsRepresentation` 交给 quota client。Worker 验证后以匿名设备 ID 记录有效期；本地 entitlement 仍由 StoreKit 作为 UI 的即时来源。

Paywall 使用 `Product.SubscriptionInfo` 显示商品周期、价格和适用的 Intro Offer；在购买按钮之前显示自动续费、续费价格/周期、取消路径、隐私政策和服务条款。设置页提供恢复购买及系统订阅管理入口。

### 生产 Worker

Worker 使用真实 KV namespace、`DEEPSEEK_API_KEY` secret 和生产 URL。禁止 `DEBUG_PRO_ALLOWED=1`。

`/proxy/register-pro` 必须验证 Apple 交易 JWS 的签名、证书链、bundle ID、environment、product ID、过期/撤销状态；不得只解码 payload。注册成功后保存 transaction 到匿名设备映射。App Store Server Notifications V2 端点验证 notification JWS 后更新或移除对应设备的 Pro 权益，以覆盖退款、撤销、到期和续费。

## Storefront 与审核材料

### 仓库内交付物

- 中英文隐私政策、服务条款、支持页；
- 中英文 App Store 标题、副标题、描述、关键词、订阅说明、审核备注和更新说明；
- 截图采集清单，覆盖 iPhone 6.9 英寸与 iPad 13 英寸、浅色/深色、任务、AI 同意、Paywall、通知和 Companion；
- Privacy Manifest、InfoPlist 本地化、正确图标资源、方向策略和 Release 验证脚本；
- StoreKit 本地测试配置和购买/恢复/撤销/过期的回归测试。

### App Store Connect 人工交付物

- App Record、Bundle ID、类别、年龄分级、版权、Support URL、Privacy Policy URL；
- Paid Apps Agreement、税务和银行信息；
- Subscription Group、月度/年度商品、价格、地区、本地化、审核截图和审核备注；
- App Privacy、出口合规、DSA trader 状态、内容权利和审核联系人；
- 第一组自动续费订阅与 1.0 build 一起提交。

## 质量与验收

1. Release Archive 与 App Store Connect export 均使用 Apple Distribution，`get-task-allow` 为 false。
2. 第一台新设备无 Key 时，已配置生产 URL 的托管 AI 经同意后可用；拒绝同意时不出现网络 AI 请求。
3. 月度和年度购买、恢复购买和交易更新都让 Worker 的 Pro 额度生效；撤销或退款后不再保留 Pro 权益。
4. Paywall 的全部承诺均在购买后可验证；免费、体验期、订阅三种状态文案不互相冲突。
5. iPhone 与 iPad 在横竖屏、深色模式、最大动态字体和 VoiceOver 下可完成任务、同意、购买、恢复购买、通知和语音主流程。
6. `PrivacyInfo.xcprivacy` 被 App target 打包，App Store Privacy 标签与隐私政策一致。
7. 运行全量 iOS、Web 和 Worker 测试；完成 StoreKit Sandbox 与 TestFlight 真机矩阵。

## 非目标

- 本首发不新增登录、账号同步、广告、分析 SDK 或用户追踪。
- 不在 iOS 客户端保存 DeepSeek 或 App Store Server API 私钥。
- 不将 AI 输出描述为医疗、法律或财务建议。
