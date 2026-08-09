# todo-quota-proxy

Cloudflare Worker：AI 托管额度代理。持有 DeepSeek API Key，按设备（`X-Device-Id`）计数：

- 免费用户：终身 **10** 条（key `free:{deviceId}`）
- Pro 用户（iOS StoreKit 订阅）：每日 **20** 条（key `daily:{deviceId}:{YYYY-MM-DD}`，UTC 日期）
- Pro 状态：`pro:{deviceId}` → ISO 到期时间

用户自己的 API Key 请求绕过此代理（客户端逻辑不在本 Worker 范围）。

## HTTP 契约

Base URL: `https://todo-quota-proxy.<subdomain>.workers.dev`

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/proxy/chat/completions` | 请求头 `X-Device-Id`；OpenAI 格式 body（`model` 强制为 `deepseek-chat`）。无设备头 → `401 missing_device_id`；免费用完 → `402 quota_exceeded(kind=free)`；Pro 当日用完 → `402 quota_exceeded(kind=daily)`；上游非 2xx 原样透传、不消耗配额；成功递增计数后返回上游原文。 |
| GET | `/proxy/quota` | 请求头 `X-Device-Id`。返回 `{"freeUsed":0,"freeLimit":10,"proUsed":0,"proLimit":20,"isPro":false,"today":"YYYY-MM-DD"}` |
| POST | `/proxy/register-pro` | 请求体 `{"transactionJwt":"<jwsRepresentation>"}`。验签通过 → `200 {"ok":true,"expiry":"<ISO>"}` 并写入 `pro:{deviceId}`；失败 → `401 invalid_jwt` |

## 部署步骤

```bash
# 1. 安装 wrangler（本项目 package.json 仅声明脚本，未内置依赖）
npm install --save-dev wrangler

# 2. 创建 KV 命名空间，并把返回的 id 填进 wrangler.toml 的 [[kv_namespaces]]
npx wrangler kv namespace create QUOTA

# 3. 设置 DeepSeek API Key（重要的安全步骤——绝不要把 key 写进代码或仓库）
npx wrangler secret put DEEPSEEK_API_KEY

# 4. 部署
npx wrangler deploy

# 5.（可选）开发仿真 Pro：开启 debugPro 放行
npx wrangler secret put DEBUG_PRO_ALLOWED   # 输入 1
```

本地开发：`npm run dev`（wrangler dev）。自测：`npm test`（纯 Node，内存 KV 存根 + 拦截 fetch，覆盖 free 11 次 → 402、pro 21 次/日 → 402、透传不消耗等场景）。

## 计数与竞态

- 计数为「读当前值 +1 后 PUT 写回」，多请求并发可能少计。个人 app，近似可接受，不引入队列/锁。
- 配额只在上游返回 2xx 后递增；上游非 2xx 不消耗。
- 计数的「今天」用 UTC：`new Date().toISOString().slice(0,10)`。
- Pro 判定：`pro:{deviceId}` 存在且到期时间 > now；过期自动回落到 free 计数。

## register-pro 验签策略（重要）

当前为实现**简化验签**（契约允许）：仅解析 JWT payload，校验

1. `payload.exp` 未过期（秒）
2. `payload.productId` 在白名单 `com.zhili.todo.premium.monthly` / `com.zhili.todo.premium.yearly`
3. 到期时间取 `payload.expiresDate`（毫秒），缺省回落到 `exp`；`bundleId` 忽略

`DEBUG_PRO_ALLOWED=1` 且 payload 含 `debugPro: true` 时直接放行（开发仿真：写一年后的假到期时间）。

⚠️ 该简化模式**不校验 JWT 签名**——恶意客户端可伪造 productId。正式上线前建议升级：用 WebCrypto (RS256) 校验 Apple App Store 证书链（`x5c`），并考虑接入 Server Notifications V2 处理退款/撤销。升级不影响 KV 结构与 HTTP 契约。

## 故障排查

- 部署报 KV 无效：检查 wrangler.toml `[[kv_namespaces]].id` 是真实 id。
- 500 `proxy_error`：确认 `DEEPSEEK_API_KEY` 已通过 `wrangler secret put` 设置。
- wrangler 安装失败：确认 Node ≥ 18，`npm i -D wrangler` 后再试；逻辑本身可用 `npm test` 本地验证。