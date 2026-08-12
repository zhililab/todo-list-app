# 订阅产品文案与配置清单

核对日期：2026-08-11
Bundle ID：`com.zhili.todo-native`

> `TodoNative.storekit` 中的 `4.99` / `39.99` 仅是本地 StoreKit 测试配置，不能据此声明生产价格。App 内通过 StoreKit 的本地化价格和周期展示实际商品信息。

## Subscription Group

- Reference Name：`Todo Premium`
- English Display Name：`Todo Premium`
- 简体中文展示名称：`Todo 高级版`
- English Description：`AI Today Plan, analytics dashboard, and advanced Markdown export.`
- 简体中文描述：`AI 今日计划、分析看板与高级 Markdown 导出。`
- `ACTION REQUIRED — 在 App Store Connect 创建/确认唯一 Subscription Group，并确认所有本地化字段。`

## 月度订阅

- Product ID：`com.zhili.todo.premium.monthly.v2`
- Reference Name：`Todo Premium Monthly`
- Duration：1 month
- en-US Display Name：`Monthly Premium`
- en-US Description：`Premium task planning and export features, billed monthly.`
- zh-Hans 展示名称：`高级版月度订阅`
- zh-Hans 描述：`按月续订的高级任务规划与导出功能。`
- `ACTION REQUIRED — 选择实际价格档位、税务区域和销售范围；不要从本地 StoreKit 配置复制价格。`

## 年度订阅

- Product ID：`com.zhili.todo.premium.yearly.v2`
- Reference Name：`Todo Premium Yearly`
- Duration：1 year
- en-US Display Name：`Yearly Premium`
- en-US Description：`Premium task planning and export features, billed yearly.`
- zh-Hans 展示名称：`高级版年度订阅`
- zh-Hans 描述：`按年续订的高级任务规划与导出功能。`
- `ACTION REQUIRED — 选择实际价格档位、税务区域和销售范围；不要从本地 StoreKit 配置复制价格。`

## App 内统一披露文案

### 简体中文

购买确认后，款项将从你的 Apple ID 账户扣除。订阅会自动续订，除非你至少在当前周期结束前 24 小时取消。续订费用会在当前周期结束前 24 小时内收取。你可以在 Apple ID 的订阅设置中管理或取消订阅。实际价格、周期和可用优惠以 App Store 购买页面为准。

本应用还提供从首次启动开始计算、仅保存在本机的 7 天体验。它不是 App Store 的首购优惠，不由 Apple 的订阅计费系统管理。清除应用数据或卸载应用可能影响本地体验记录。

### English

Payment is charged to your Apple ID account when the purchase is confirmed. The subscription renews automatically unless you cancel at least 24 hours before the current period ends. Your account is charged for renewal within 24 hours before the end of the current period. Manage or cancel the subscription in your Apple ID subscription settings. The App Store purchase sheet controls the actual price, billing period, and available offers.

The app also provides a seven-day experience that begins on first launch and is stored only on that device. It is not an App Store introductory offer and is not managed by Apple's subscription billing system. Clearing app data or uninstalling the app may affect the local record.

## 法律链接

- Privacy Policy：`https://todo-list-app.zhili1993.chatgpt.site/privacy.html`
- Terms of Use：`https://todo-list-app.zhili1993.chatgpt.site/terms.html`
- Support：`https://todo-list-app.zhili1993.chatgpt.site/support.html`
- Support email：`lz123321@live.com`
- `ACTION REQUIRED — 账号所有者确认 App Store Connect 使用 Apple Standard EULA 还是自定义 EULA；如使用自定义 EULA，提供经法律审核的最终文本。`

## Introductory Offer 决策

当前代码与公开条款描述的是**设备本地 7 天体验**。当前 `TodoNative.storekit` 中两个订阅的 `introductoryOffers` 均为空。

- [ ] `ACTION REQUIRED — 决定是否另行创建 App Store Introductory Offer。`
- [ ] 如果不创建：保留“本地 7 天体验不是 App Store 首购优惠”的披露，ASC 产品不要勾选 7-day free trial。
- [ ] 如果创建：必须修改产品行为/条款/Paywall/测试，使本地体验和 Apple offer 不重复或误导，并重新走实现评审；本 Task 不修改产品逻辑。

## App Store Connect 产品状态

- [ ] `ACTION REQUIRED — Paid Apps Agreement 已接受。`
- [ ] `ACTION REQUIRED — 税务与银行信息有效。`
- [ ] `ACTION REQUIRED — 月度/年度产品已创建，Product ID 与代码逐字一致。`
- [ ] `ACTION REQUIRED — 每个产品的价格、销售区域、本地化和审核截图已填写。`
- [ ] `ACTION REQUIRED — IAP 状态达到可随 App 版本提交审核的状态。`
- [ ] Sandbox 返回的产品标题、价格、周期与 App 内展示一致。
- [ ] 购买、取消、pending、unverified、恢复、过期、退款/撤销全部通过。

## 托管权益注册状态与阻塞

StoreKit 本地权益与托管 AI 配额是两个证据层：

- 当前 `PurchaseManager` 可以根据 StoreKit 已验证、未过期且未撤销的 entitlement 解锁本地高级功能。
- 只有配置生产 managed endpoint 后，app 才会把交易 JWS 与随机设备 ID 发给 Worker 注册远程 Pro 配额。
- 当前生产 endpoint 缺失；`wrangler.toml` 已声明 `QUOTA`、`ENTITLEMENTS` 与 `DEVICE_PRIVACY` bindings/migrations，但尚无真实 Cloudflare namespace、DO migration 或生产 read-back 证据。
- Worker 提交 `5ee3606` 已完成 Apple transaction JWS 离线验签，包含 ES256、固定 Apple roots/完整证书链、bundle/environment、月/年产品、到期与 payload 撤销字段；持久层不保存完整 JWS 或原始 transaction ID。
- Worker 提交 `5ee3606` 的 Entitlement DO 已实现 App Store Server Notifications V2 验签与续费、到期、退款、撤销状态处理。生产 ASC URL、`APP_STORE_APPLE_ID`、Send Test Notification 与 Sandbox 全链路仍未配置/验证。
- 离线验签不执行 OCSP，不能证明证书签发后的实时撤销状态；发布负责人必须接受该边界或在上线前实现完整在线检查。

- [ ] `ACTION REQUIRED — 在宣称订阅包含托管 AI 配额前，完成 endpoint、KV/DO/secrets 真实部署与 read-back、Sandbox/Production 真交易验证，并在 App Store Connect 配置 Notifications V2 URL、通过 Send Test Notification 及续费/到期/退款/撤销全链路验证。`
- [ ] `ACTION REQUIRED — 发布负责人接受无 OCSP 的离线校验边界，或先实现完整在线检查；不可把当前实现描述为实时 Apple 订阅查询。`
- [ ] 如果这些条件未完成，商品文案和截图不得承诺托管额度；审核备注须说明本地高级权益仍可用、远程注册不可用。
