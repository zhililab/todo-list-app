# todo-quota-proxy

Cloudflare Worker：AI 托管额度代理。持有 DeepSeek API Key，按设备（`X-Device-Id`）计数：

- 免费用户：终身 **10** 条（key `free:{deviceId}`）
- Pro 用户（iOS StoreKit 订阅）：每日 **20** 条（key `daily:{deviceId}:{YYYY-MM-DD}`，UTC 日期）
- Pro 状态：每条 original transaction hash 对应一个 SQLite Durable Object；KV 仅保存 `appstore-device-subscription:{deviceId}:{originalHash}` 不可变指针

用户自己的 API Key 请求绕过此代理（客户端逻辑不在本 Worker 范围）。

## HTTP 契约

Base URL: `https://todo-quota-proxy.<subdomain>.workers.dev`

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/proxy/chat/completions` | 请求头 `X-Device-Id`；OpenAI 格式 body（`model` 强制为 `deepseek-v4-flash`）。无效输入在读取额度前拒绝；免费用完 → `402 quota_exceeded(kind=free)`；Pro 当日用完 → `402 quota_exceeded(kind=daily)`；上游错误 → 安全稳定的 `502 provider_error/provider_unavailable` 且不消耗配额；成功递增计数后返回上游响应。已删除设备 → `410 device_erased`。 |
| GET | `/proxy/quota` | 请求头 `X-Device-Id`。返回 `{"freeUsed":0,"freeLimit":10,"proUsed":0,"proLimit":20,"isPro":false,"today":"YYYY-MM-DD"}`；已删除设备 → `410 device_erased`。 |
| POST | `/proxy/register-pro` | 请求体 `{"transactionJwt":"<jwsRepresentation>"}`。Apple ES256 JWS、完整证书链与交易字段全部通过 → `200 {"ok":true,"expiry":"<ISO>"}`；无效证据统一 `401 invalid_jwt`；缺少 App Store 配置 → `503 service_not_configured`；已删除设备 → `410 device_erased`。 |
| POST | `/proxy/app-store-notifications` | App Store Server Notifications V2 回调，请求体 `{"signedPayload":"<JWS>"}`。业务通知同时验证外层与内层 JWS；`TEST` 验证外层签名和 App identity。成功幂等处理后只返回 `200 {"ok":true}`。 |
| POST | `/internal/erase-device` | 仅 owner 运维使用；独立 `ERASURE_ADMIN_TOKEN` Bearer + `{"supportId":"TD-<UUID>"}`。无 token → `401 unauthorized`；有在途 lease 或有界清理尚未完成 → `202 retry`；完成或重复删除 → `200 erased`。不是公开自助删除接口。 |

只开放表中的方法及其 `OPTIONS` 预检；已知路径使用错误方法返回 `405 method_not_allowed`，未知路径返回 `404 not_found`。

### 输入边界

- `X-Device-Id` 必须是客户端随机生成的匿名、不透明 ID：16–128 个字符，只允许 ASCII 字母、数字、`_`、`-`。不要发送邮箱、账号、路径或其他可识别信息。
- JSON body 最大 **64 KiB**。
- `messages` 必须包含 1–32 条；每条只接受 `system`、`user`、`assistant` role，`content` 必须是 1–16,000 字符的字符串。
- 客户端提供的 `model` 会被忽略，上游始终使用 `deepseek-v4-flash`。
- 绑定缺少 `QUOTA`、`ENTITLEMENTS` 或聊天请求缺少 `DEEPSEEK_API_KEY` 时返回 `503 service_not_configured`；响应不披露配置名、密钥或内部异常。

### 浏览器 CORS

原生客户端请求不含 `Origin`，无需 CORS。浏览器来源必须逐个加入 Worker 环境变量 `ALLOWED_ORIGINS`，值为逗号分隔的完整 origin，例如 `https://todo.example.com,https://app.example.com`。匹配是精确匹配，不支持 `*`，Worker 也不会反射未授权的 `Origin`。

## 部署步骤

正式部署、验证、回滚和数据删除的 owner checkpoints 见 [`Runbook/production-deployment.md`](Runbook/production-deployment.md)。以下命令只列出顺序，不代表已获授权或已执行；创建 Worker/KV/DO、写 secret、配置 App Store Connect 和写入 Release endpoint 都是外部 mutation。

```bash
# 1. 使用 Cloudflare Wrangler 支持的 Node.js 版本；推荐最新 Node.js LTS。
#    Wrangler 支持 Node.js Current、Active LTS 和 Maintenance LTS。
node --version

# 2. 安装 lockfile 固定的项目内 Wrangler v4
npm ci

# 3. 得到 Cloudflare account owner 明确授权后，首次部署触发 automatic provisioning
npx wrangler deploy

# 4. 确认 Cloudflare 已自动创建 <worker-name>-QUOTA，并核对 Wrangler 回写的 KV ID
#    已出现在 wrangler.toml。确认完成前不要把生产流量指向该 Worker。

# 5. 设置 DeepSeek API Key（绝不要把 key 写进代码、wrangler.toml 或仓库）
npx wrangler secret put DEEPSEEK_API_KEY

# 6. 配置 App Store 交易的 fail-closed 期望值；正式环境填 Production，
#    Sandbox Worker 填 Sandbox。缺任一项时 register-pro 固定返回 503。
npx wrangler secret put APP_STORE_BUNDLE_ID     # 输入 com.zhili.todo-native
npx wrangler secret put APP_STORE_ENVIRONMENT   # 输入 Sandbox 或 Production

# 7. 仅 Production 通知必须配置 App Store Connect 中该 App 的数字 Apple ID。
#    Sandbox 不要求该字段；不要填写 bundle ID、Team ID 或占位值。
npx wrangler secret put APP_STORE_APPLE_ID

# 8. 如启用浏览器调用，配置精确 origin 白名单；仅 iOS 使用时可跳过。
npx wrangler secret put ALLOWED_ORIGINS

# 9. 设置独立的删除运维 token；不得与任何其他 secret 复用
npx wrangler secret put ERASURE_ADMIN_TOKEN

# 10. 使用已回写的 KV binding 完成部署
npx wrangler deploy
```

仓库的 `wrangler.toml` 声明自动配置的 `QUOTA`、`ENTITLEMENTS` 与 `DEVICE_PRIVACY` binding，以及 SQLite migrations `v1`/`v2`，不预填真实 ID 或 placeholder。此服务从未部署，首次生产版本必须至少包含 privacy migration `v2`，且不能回滚到更早版本。首次部署后必须核对全部 binding/migration，再设置 secret 并进行最终部署。缺少任一请求路径所需 binding/secret 时安全返回 `503 service_not_configured`。

本地开发：先把只含空白名称的 `.dev.vars.example` 复制为 ignored `.dev.vars`，再运行 `npm run dev`（项目内固定版本的 Wrangler）。自测：`npm test`（纯 Node，内存 KV 存根 + 拦截 fetch，覆盖流式 body 边界、CORS、错误脱敏、缺失绑定、free 11 次 → 402、pro 21 次/日 → 402、删除后禁止重建等场景）。所有 Wrangler 命令均使用 `npx wrangler`，避免依赖未固定的全局版本。

## 计数与竞态

- 计数为「读当前值 +1 后 PUT 写回」，多请求并发可能少计。个人 app，近似可接受，不引入队列/锁。
- 配额只在上游返回 2xx 后递增；上游非 2xx 不消耗，且客户端不会收到上游原始错误 body。
- 计数的「今天」用 UTC：`new Date().toISOString().slice(0,10)`。
- Pro 判定：遍历 `appstore-device-subscription:{deviceId}:` 的全部 KV cursor 页，向每个 original hash 的 Durable Object 读取强一致状态并取最大有效 expiry。指针尚未跨 KV 位置可见时只会暂时 false-negative，不会绕过终态撤销。
- 本服务尚未生产部署，因此 v2 明确忽略旧开发期 `pro:{deviceId}`、`appstore-entitlement:*` 与 `appstore-original:*` key，不执行可能误授予权限的 legacy 迁移。

## register-pro 验签与持久化

`register-pro` 使用 WebCrypto 与固定版本 `@peculiar/x509` 对 Apple signed transaction 做离线验证，语义对应 Apple App Store Server Library 的 `enableOnlineChecks=false`。任何一步失败都不会写 entitlement：

1. compact JWS 必须恰好三段且总大小不超过 64 KiB；header/payload/证书分别有独立上限，Base64/Base64URL 必须规范编码。
2. `alg` 只接受 `ES256`，JWS 签名必须是 64-byte raw ECDSA `r || s`。
3. `x5c` 必须恰好按 leaf → WWDR intermediate → Apple root 排列；逐级核对 issuer/subject、证书签名、`signedDate` 时的有效期、Basic Constraints 与 Key Usage。Critical OID 按角色限定：leaf 只允许 Basic Constraints、Key Usage 与 App Store signing；intermediate 只允许 Basic Constraints、Key Usage 与 WWDR；root 只允许 Basic Constraints 与 Key Usage。Critical EKU、AIA、CRL Distribution Points、Certificate Policies、角色错位的 Apple OID 及未知 critical OID 均拒绝。
4. leaf 必须是 `CA=false`，Key Usage 必须恰好只有 `digitalSignature`（不接受 Key Encipherment、Key Agreement 或其他额外用途），并带 App Store signing OID `1.2.840.113635.100.6.11.1`；intermediate 必须是可签证书的 CA，并带 WWDR OID `1.2.840.113635.100.6.2.1`。
5. `x5c` 根必须精确命中仓库内版本化 Apple root DER：Apple Inc. Root、Apple Root CA - G2 或 G3；不会信任系统根库、运行时下载内容、fixture root 或 header 自带的任意 root。
6. 验签后才接受 `bundleId`、显式 `Sandbox`/`Production` environment、月/年产品白名单、合法 transaction/original transaction ID、`expiresDate > now`，并要求 `revocationDate` 字段完全缺失。Apple transaction payload 没有通用 JWT `exp`，实现不使用它。

持久层从不保存、返回或记录完整 JWS、原始 transaction ID 或原始 notification UUID：

- Entitlement Durable Object 名称只使用 `originalTransactionHash`；内部以哈希后的 transaction/notification identity 串行化 latest state、幂等记录和匿名设备映射。设备映射只保存 domain-separated SHA-256，不保存原始 device ID。
- KV 只写一次 `appstore-device-subscription:{deviceId}:{originalHash}` v3 指针，不保存 expiry 或可变授权判断。
- 注册先在 Durable Object 原子处理，再写设备指针。指针写入延迟只会使 quota 暂时判为免费；不会把已撤销订阅误判为 Pro。

同一 original hash 的注册和通知由一个 Durable Object transaction 串行化。更晚 `signedDate` 胜出、同时间终态优先，活跃状态同时间取更晚 expiry，因此并发和乱序请求不能缩短新订阅或让旧交易复活。

同一 original transaction 明确允许恢复到多个匿名 device，这是无账号产品支持第二台设备 restore 的既定策略，而不是全局去重失败。由于当前没有账号绑定或 App Attest，该策略存在合法 JWS 被跨设备共享的滥用风险；release evidence 应把它记录为当前可接受风险，后续可用账号绑定、App Attest 或设备数策略硬化，但不得破坏正常 restore。

注册请求会拒绝 payload 已带 `revocationDate` 的交易，但离线模式不执行 OCSP，也不声称掌握证书签发后的实时撤销状态；证书有效期按 JWS 的 `signedDate` 评估。生产上线前，release owner 必须在证据中明确接受该离线风险，或先实现并验证完整在线检查，不能加入半套 OCSP。退款、撤销和到期通过下述 App Store Server Notifications V2 路径持续同步。

## App Store Server Notifications V2

部署成功并得到真实 HTTPS Worker 域名后，才在 App Store Connect 登记回调：

```text
https://<实际部署域名>/proxy/app-store-notifications
```

仓库不写入或猜测生产域名。建议先把 Sandbox URL 配到隔离的 Sandbox Worker，使用 App Store Connect 的 Send Test Notification 验证 `200`，再配置 Production URL。Production Worker 必须同时配置 `APP_STORE_BUNDLE_ID=com.zhili.todo-native`、`APP_STORE_ENVIRONMENT=Production` 和数字 `APP_STORE_APPLE_ID`；Sandbox 仍严格核对外层与内层的 environment 和 bundle ID。

- 外层 `signedPayload` 和内层 `signedTransactionInfo` 分别通过与注册接口相同的完整 JWS/证书链边界；不接受仅 Base64 解码的 payload。`TEST` 是例外：完整验证外层签名与 App identity 后 `200 ignored`，按 Apple 格式不要求内层交易。
- 只处理官方 type/subtype 组合：`DID_RENEW`（空或 `BILLING_RECOVERY`）、`SUBSCRIBED`（`INITIAL_BUY`/`RESUBSCRIBE`）、`EXPIRED`（官方四种到期 subtype）、`REFUND` 和 `REVOKE`（空）。未来未知或非法组合在外层验签与 identity 校验成功后返回 `200 ignored`，不修改授权状态。
- `SUBSCRIBED`、`DID_RENEW` 将 Durable Object 状态推进为 active；`EXPIRED`、`REFUND`、`REVOKE` 只写强一致终态 tombstone，永久设备映射和 KV 指针都不删除。更晚续订可以恢复，旧终态不能覆盖新续订。
- notification UUID 先哈希再送入 Durable Object 做幂等判断；KV、Durable Object、日志与响应都不保存完整 JWS、原始 transaction ID 或原始 notification UUID。
- 完整验签但 Durable Object 尚无设备映射的通知返回安全 `200 unmapped`，同时保留强一致状态。以后 restore 会永久建立设备映射，但旧于终态的交易不能复活；更晚有效续订仍可恢复。
- Workers KV 只负责设备指针发现并遍历完整 cursor；它不决定 duplicate 或 latest。生产监控应只统计 5xx、`ignored` 与 `unmapped` 数量，不记录 payload。

## Managed data deletion ordering

本服务没有公开自助删除端点。每个 device identity 经 domain-separated SHA-256 命名一个 `DEVICE_PRIVACY` Durable Object。chat、quota、register-pro 在任何 device-bearing KV/DO 读取、写入或上游调用前从该 DO 获取强一致 lease，并在 `finally` 释放；已 erased 的 DO 拒绝新 lease，三路统一 `410 device_erased`。

首次部署契约把规范 UUID device ID 统一为大写，因此 iOS 大写 UUID 与 Web `randomUUID()` 常见的小写形式共享同一额度、entitlement 与 privacy identity；非 UUID opaque device ID 保持原样。持有 lease 的 quota/chat 在任何 KV read 前，把 free 与当前 daily 资源登记到 hashed Device Privacy DO；register 验签后先登记 original-transaction hash，再写 pointer，最后写 Entitlement DO mapping。catalog 不含 raw device ID，且 erase 已置位时仍允许已有 lease 完成登记。

owner-only `/internal/erase-device` 使用独立 `ERASURE_ADMIN_TOKEN`，先在 Device Privacy DO 原子标记 erased。若存在 lease 则 `202 retry` 且不清理；lease 全部结束后，每次授权重试只执行一个有界 catalog/legacy phase。KV key 删除后 catalog 项进入至少 65 秒的 pending verification，随后做 exact `get`；仍可见则重删并重新等待，确认为 `null` 才从强 catalog ack。Entitlement catalog 同时清理 pointer、精确 original-index prefix，并用强一致 `/erase-device` 删除 mapping。catalog 为空后还必须完成两轮相隔至少 65 秒的 legacy 空扫描/精确 read-back 才能返回 `200 erased`。并发 owner 重试用 catalog revision/phase 冲突跟随已提交进度。未知/无既有数据的有效 Support ID 也会建立 suppression 并走同样验证。Notifications V2 永不创建设备 mapping；最终只保留 hashed erased state/清理进度与必要交易级 hash。

孤儿 lease 永久 fail closed；没有 TTL、force release 或 un-erase 接口。操作员 helper `scripts/erase-device.mjs` 从 stdin 读取 token/Support ID，不把它们放进 argv 或输出。完整 owner approval、重试、read-back、崩溃调查和禁止回滚到 privacy migration 之前版本的流程见生产 runbook。

### Apple root 来源与轮换 runbook

根证书只来自 [Apple PKI](https://www.apple.com/certificateauthority/) 官方链接，版本化数据在 `src/apple-root-certificates.js`：

| 根证书 | 官方 URL | DER SHA-256 | 到期时间（UTC） |
|---|---|---|---|
| Apple Inc. Root | `https://www.apple.com/appleca/AppleIncRootCertificate.cer` | `b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024` | 2035-02-09 21:40:36 |
| Apple Root CA - G2 | `https://www.apple.com/certificateauthority/AppleRootCA-G2.cer` | `c2b9b042dd57830e7d117dac55ac8ae19407d38e41d88f3215bc3a890444a050` | 2039-04-30 18:10:09 |
| Apple Root CA - G3 | `https://www.apple.com/certificateauthority/AppleRootCA-G3.cer` | `63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179` | 2039-04-30 18:19:06 |

轮换时由安全负责人执行并审阅差异，禁止在请求路径动态下载证书：

```bash
curl -fL --proto '=https' --tlsv1.2 '<Apple PKI 页面上的官方 .cer URL>' -o /tmp/apple-root.cer
shasum -a 256 /tmp/apple-root.cer
openssl x509 -inform DER -in /tmp/apple-root.cer -noout -subject -issuer -dates -fingerprint -sha256
```

确认 URL 确实来自当时 Apple PKI 页面、subject=issuer、CA/Key Usage/有效期合理后，才更新 DER Base64、SHA-256、到期时间与本表。轮换发布必须保留 Apple 明示的重叠 roots，重跑 fixture 攻击矩阵、`npm audit`、完整 Worker 测试和 `npx wrangler deploy --dry-run`，再用 Sandbox 真交易灰度验证；删除旧 root 必须依据 Apple 官方下线信息与已观测链，不能仅因出现新 root 提前移除。至少在最早 root 到期前 180 天复核一次，并在每次 Apple PKI/WWDR 公告后复核。

依赖精确固定为 `@peculiar/x509@2.0.0` 与 `reflect-metadata@0.2.2`，lockfile 固定其完整传递树。本次 `npm audit` 为 0；Wrangler dry-run bundle 为 495.41 KiB（gzip 86.63 KiB）。该库负责 DER/X.509 解析和 WebCrypto 证书签名验证，本地代码仍负责 Apple 特定用途、顺序、根 pin、critical extension 与 payload 策略。

## 故障排查

- `503 service_not_configured`：在目标 Worker 环境核对 `QUOTA` KV binding；聊天接口还需核对 `DEEPSEEK_API_KEY` secret。
- 浏览器返回 `403 origin_not_allowed`：核对 `ALLOWED_ORIGINS` 是否包含浏览器实际的完整 origin（协议、域名、端口都必须一致）。
- `502 provider_error/provider_unavailable`：上游拒绝或网络不可用；客户端响应故意不包含 provider 原始错误，请在不记录密钥/请求正文的前提下查看服务端指标。
- Wrangler 安装失败：切换到 Cloudflare 支持的 Node.js Current、Active LTS 或 Maintenance LTS（推荐最新 LTS），再运行 `npm ci`；逻辑本身可用 `npm test` 本地验证。
