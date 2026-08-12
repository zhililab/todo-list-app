# iOS 订阅与 App Store 发布执行清单

更新日期：2026-08-11
Bundle ID：`com.zhili.todo-native`

> 证据分层：仓库完成、构建/测试通过、外部控制面完成、真实 TestFlight/App Review 状态必须分别记录。任何一层完成都不能替代其他层。

## 0) 提交材料入口

- [简体中文元数据](../AppStoreConnect/metadata.zh-Hans.md)
- [英文元数据](../AppStoreConnect/metadata.en-US.md)
- [App Privacy 回答清单](../AppStoreConnect/app-privacy-checklist.md)
- [App Review Notes 与 TestFlight 矩阵](../AppStoreConnect/review-notes.md)
- [截图采集清单](../AppStoreConnect/screenshot-capture-checklist.md)
- [订阅文案](../AppStoreConnect/subscription-copy.md)
- [发布证据](../AppStoreConnect/release-evidence.md)

## 1) 仓库内完成项（可由代码复核）

- [x] Bundle ID 配置为 `com.zhili.todo-native`。
- [x] StoreKit 2 商品白名单：
  - `com.zhili.todo.premium.monthly.v2`
  - `com.zhili.todo.premium.yearly.v2`
- [x] 购买、恢复、`Transaction.currentEntitlements` 与 `Transaction.updates` 已实现。
- [x] 本地 premium gating 只接受已验证、未过期且未撤销的白名单商品。
- [x] Paywall 从 StoreKit 展示本地化价格/周期，并提供自动续订、取消、Privacy 与 Terms 披露。
- [x] 7 天体验明确为设备本地体验，不是 App Store Introductory Offer；当前 StoreKit 配置没有 intro offer。
- [x] 无 app 账号/登录；任务使用 SwiftData，伙伴历史和偏好使用本地存储。
- [x] BYOK API Key 使用 Keychain；远程 AI 按 consent version + recipient 明示同意，可拒绝/撤回。
- [x] Privacy / Terms / Support HTTPS URL 已写入 app 配置。
- [x] 2026-08-11 真实线上 privacy/support 页面已包含当前同意/撤回/清除控制和支持邮箱；集成法律页提交后、最终上架前仍需复核未回退。

## 2) 仓库验证与 Archive

- [ ] 根目录 `node --test` 全绿，并把通过数量写入 `release-evidence.md`。
- [ ] iOS 测试按仓库规范运行：
  - `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test`
- [ ] 使用 Release 配置 Archive；记录 commit、Xcode/SDK、marketing version、唯一 build number 和签名 Team。
- [ ] 检查 Archive 的 `Info.plist`：法律 URL、权限说明、Bundle ID 与 managed endpoint 状态正确。
- [ ] 检查 `PrivacyInfo.xcprivacy` 与 App Store Connect App Privacy 回答对应；Manifest 为空不代表问卷可填“不收集”。
- [ ] 禁止把 `dist/`、`build/`、Xcode user data、API Key、Worker secret 或 `.superpowers/` 暂存/提交。

## 3) Apple Developer 与 App Store Connect 所有者操作

以下动作必须由有权限的账号在外部控制面完成；仓库不能证明：

- [ ] `ACTION REQUIRED — Identifier/Bundle ID`：在 Certificates, Identifiers & Profiles 核对 `com.zhili.todo-native`、Team 与 capabilities。
- [ ] `ACTION REQUIRED — 证书与描述文件`：确认 App Store Distribution certificate 和 provisioning profile；用真实 Archive 验证。
- [ ] `ACTION REQUIRED — App record`：创建/核对 SKU、Bundle ID、默认语言、版本和 build。
- [ ] `ACTION REQUIRED — Paid Apps Agreement`：Account Holder 接受当前有效协议。
- [ ] `ACTION REQUIRED — Tax/Banking`：税务和银行状态有效、无待处理项。
- [ ] `ACTION REQUIRED — Base App Price`：在 Pricing and Availability 确认基础 App 免费或选择真实价格；不要因存在订阅而推断。
- [ ] `ACTION REQUIRED — App Availability`：选择 App 本体销售区域/可用性，并与订阅产品销售区域分别复核。
- [ ] `ACTION REQUIRED — Category`：选择主要/次要类别。
- [ ] `ACTION REQUIRED — Age Rating`：按任务、可选 AI 内容和联网能力如实完成问卷。
- [ ] `ACTION REQUIRED — Content Rights`：根据 app 内文本、图标、AI 输出和第三方服务如实填写。
- [ ] `ACTION REQUIRED — Export Compliance`：按最终二进制与当期 Apple 问卷确认加密/豁免答案。
- [ ] `ACTION REQUIRED — DSA`：由真实法律主体决定 trader status 并填写所需联系信息。
- [ ] `ACTION REQUIRED — Copyright/Controller`：填写真实法律主体与年份，并与隐私政策一致。
- [ ] `ACTION REQUIRED — Review Contact`：填写真实姓名、电话和邮箱；公开支持邮箱不能替代所有私有审核字段。

## 4) App Store Connect 订阅产品

- [ ] `ACTION REQUIRED — 创建/核对 Subscription Group`：`Todo Premium`。
- [ ] `ACTION REQUIRED — 创建/核对 monthly/yearly 两个自动续订产品`，Product ID 与代码逐字一致。
- [ ] `ACTION REQUIRED — 决定实际价格档位、销售地区、本地化和税务分类`；不得从 `TodoNative.storekit` 的测试价格推断。
- [ ] `ACTION REQUIRED — 决定是否另建 Apple Introductory Offer`。若不建，保持当前“本地 7 天体验不是 Intro Offer”；若要建，先修改并重新审核产品行为和条款。
- [ ] 为每个 IAP 上传所需审核截图和本地化，状态达到可随 app 版本提交。
- [ ] Sandbox 验证：产品加载、月/年购买、取消、pending、unverified、恢复、过期、退款/撤销。
- [ ] 第二台测试设备或重装后，用相同 Sandbox Apple Account 验证恢复购买。

## 5) App Privacy 与公开合规页面

- [ ] 按 `app-privacy-checklist.md` 区分仅本地、BYOK、managed Worker、随机设备 ID、购买 JWS、Apple Speech 和转写文本。
- [ ] Apple 处理且开发者无法访问的支付卡/付款资料不得误报为开发者收集。
- [ ] `ACTION REQUIRED — Audio Data`：确认 Apple Speech 在目标系统/地区的实际处理与当期问卷口径，不能宣称语音始终完全在设备上。
- [ ] Privacy/Terms/Support 三个公开 URL 返回真实页面、互链正确，并在浏览器核对正文而不只看 HTTP 状态。
- [ ] 支持页面公开 `lz123321@live.com`，能接收回复和隐私删除请求；隐私政策同步当前撤回/删除本地 AI 配置控制。
- [ ] managed endpoint 启用后重新回答 User Content、Device ID、Purchases 的 collected/purpose/linked/tracking，并同步公开政策。

## 6) Managed AI 生产服务发布闸门

当前状态：**生产 endpoint 缺失，Release 必须诚实显示 unavailable，本地规划器继续可用。**

- [ ] `ACTION REQUIRED — 选择提交路径`：完成生产服务后提交，或以 managed AI 不可用状态提交且删除所有可用性承诺。
- [ ] `ACTION REQUIRED — Worker endpoint`：真实 HTTPS 地址写入 Release `ManagedAIBaseURL`，Archive 复核无 debug override。
- [ ] `ACTION REQUIRED — 首次部署`：按 Worker production runbook 部署 `QUOTA` automatic provisioning、`ENTITLEMENTS` 与 `DEVICE_PRIVACY` Durable Objects，并确认 `v1` / `v2` migration 与三项 binding 的真实 read-back。
- [ ] `ACTION REQUIRED — Secrets`：配置 `DEEPSEEK_API_KEY`、`APP_STORE_BUNDLE_ID`、`APP_STORE_ENVIRONMENT`、`APP_STORE_APPLE_ID`、`ALLOWED_ORIGINS` 与 `ERASURE_ADMIN_TOKEN`；密钥不进入仓库、日志或截图。
- [ ] `ACTION REQUIRED — Apple 交易验证`：仓库已实现完整离线 JWS/证书链与 app identity 校验；必须使用 Sandbox/Production 真交易验证，并由发布负责人接受无 OCSP 的边界或先实现在线检查。
- [ ] `ACTION REQUIRED — Notifications V2`：仓库已实现通知验签与续订/到期/退款/撤销状态机；在 App Store Connect 配置生产 URL，执行 Send Test Notification，并完成 Sandbox 全链路与 Worker 状态 read-back。
- [ ] 真实服务验证 chat/quota/register-pro、非 2xx、额度耗尽、订阅到期和回退；记录日志/告警与人工关闭入口。
- [ ] Worker 上线后重跑 App Privacy、公开政策、同意接收方 host 和 App Review Notes 一致性检查。

## 7) 截图与元数据

- [ ] 按 `screenshot-capture-checklist.md` 采集 iPhone 6.9 与 iPad 13、zh-Hans/en-US、light/dark 候选。
- [ ] 每组 1–10 张、接受尺寸、无 alpha；截图不含 API Key、设备 ID、JWS、个人任务或私人通知。
- [ ] `ACTION REQUIRED — App 名称、类别、copyright、生产价格和最终截图排序` 由账号所有者确认。
- [ ] 元数据、截图和审核备注只描述提交构建中真实可用的能力。

## 8) TestFlight 与提交

- [ ] `ACTION REQUIRED — 创建 TestFlight internal/external groups`，记录 tester、build 与设备矩阵。
- [ ] iPhone + iPad 完成任务、编辑、Today、AI local/BYOK/managed（按实际）、购买/恢复、导出、通知和语音 smoke。
- [ ] iPad 横屏 Dashboard/Tasks 完整；Dynamic Type、VoiceOver、Reduce Motion、light/dark 通过。
- [ ] 同意接受/拒绝/撤回和删除本地 AI 配置四条路径通过。
- [ ] Sandbox 购买/恢复/过期/撤销证据完成；至少三位测试者只是建议，关键是设备和交易状态覆盖完整。
- [ ] 上传 build 后记录 processing 状态；完成 App Privacy、export、age rating、DSA、review contact、IAP 关联和 review notes。
- [ ] `ACTION REQUIRED — Version Release`：选择 Manual、Automatic 或 Scheduled release，并记录负责人、时间与回退方案。
- [ ] 最终提交前更新 `release-evidence.md`，明确未关闭阻塞、例外批准人与回退方案。
