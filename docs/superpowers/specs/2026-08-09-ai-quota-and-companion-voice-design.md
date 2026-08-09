# AI 额度系统 + 伙伴语音/气泡动效 — 设计文档

日期：2026-08-09
状态：已确认设计，待实现

## 1. 背景与目标

Todo app（Web + iOS 双端，无后端）新增：

1. **伙伴语音输入 + iMessage 风格气泡动效**（双端）
2. **AI 额度商业模式**：
   - Free 用户：终身免费 10 条 AI 生成（走 app 托管额度）
   - Pro 订阅用户：app 托管 DeepSeek 额度，**每天 20 条，每月最多 600 条**
   - 自定义 API Key 用户：不限制，全用自己额度
   - DeepSeek Key 只存在于服务端，**绝不暴露给终端用户**

已确认决策：
- 代理部署：**Cloudflare Workers（轻量云函数）** + KV 计数
- 免费额度口径：**终身共 10 条**
- 额度身份：**按设备匿名 ID**（客户端生成 UUID，无需注册）
- Web 端变现：**只做免费 10 条 + 自定义 Key**；Pro 订阅只在 iOS（StoreKit）
- 订阅定价：月 ¥12 / 年 ¥88（用户已确认）

## 2. 架构总览

```
┌────────────┐   直连（自定义 Key）   ┌──────────────────┐
│  终端用户   │ ───────────────────▶ │  各 OpenAI 兼容  │
│ Web / iOS  │                      │  服务商（用户 Key）│
└────────────┘                      └──────────────────┘
      │
      │ app 托管额度（X-Device-Id）
      ▼
┌──────────────────────────────────────────┐
│  Cloudflare Worker（唯一持有 DeepSeek Key）│
│  - 转发 /chat/completions                 │
│  - KV 计数：free 10 条终身 / pro 20 条日  │
│  - iOS StoreKit JWS 验签 → 存 pro 身份     │
└──────────────────────────────────────────┘
```

设计原则：
- **额度只看「AI 调用次数」**，每次代理转发成功（2xx）= 消耗 1 条
- 自定义 Key 请求完全绕过代理，不计数
- Worker 纯 KV 计数无状态，额度用尽返回明确错误码

## 3. 组件设计

### 3.1 Cloudflare Worker（`workers/quota-proxy/`）

**端点**：
- `POST /proxy/chat/completions` — 客户端把请求体原样 POST 过来；Worker 校验 device id → 检查额度 → 附加 `Authorization: Bearer ${DEEPSEEK_API_KEY}` → 转发 DeepSeek → 返回上游响应
- `POST /proxy/register-pro` — iOS 端上传 StoreKit 交易 JWT；Worker 验签确认产品白名单 + 未过期，写入 `pro:{deviceId} → expiry`
- `GET /proxy/quota` — 返回当前设备额度快照（freeUsed/freeLimit/proUsed/proLimit/today）

**额度规则**：
- 无 pro 凭证：`freeUsed < 10` 生效；否则 `402 {code:"quota_exceeded", kind:"free"}`
- iOS pro 凭证有效：每日 20 条（KV key `daily:{deviceId}:{YYYY-MM-DD}`）
- 计数流程：读 → 校验 → 记录唯一请求（`req:{deviceId}:{uuid}` 去重窗口 60s）→ 2xx 后递增
- 上游 4xx/5xx 透传，**不消耗额度**
- 使用 KV 而非 Durable Objects（保持零成本）

**环境变量（Secret）**：
- `DEEPSEEK_API_KEY`（用户提供，仅存 Worker Secret，不入仓库）

### 3.2 设备匿名 ID

- Web：`localStorage['todo_device_id']`，无则 `crypto.randomUUID()` 生成
- iOS：`UserDefaults` 存 `device_id`，`UUID().uuidString`
- 每个托管请求带 `X-Device-Id`；不可解析出隐私、不关联账号

### 3.3 iOS Pro 额度（StoreKit 交易验证）

- iOS 通过 StoreKit2 的 `Transaction.currentEntitlements`/`Transaction.updates` 拿到 `verified` 交易后，调用 `/proxy/register-pro` 把交易 JWT（jwsRepresentation）传过去
- Worker 验签：解析 JWT payload 的 `exp > now` 且 productId 在 iOS 产品白名单内，写入 `pro:{deviceId} → expiry`
- 开发阶段支持 `X-DEBUG-PRO` 便于联调（Worker 端 env flag `ALLOW_DEBUG_PRO`）

### 3.4 语音输入

- **Web**：`SpeechRecognition`（Chrome/Edge 支持中文 `zh-CN`；Safari 不支持时隐藏按钮）。持麦按钮 → `recognition.start()` → `onresult` 填入输入框 → 发送
- **iOS**：`SFSpeechRecognizer`（zh-CN）+ `AVAudioEngine` 实时识别；Info.plist 加 `NSMicrophoneUsageDescription`（+`NSSpeechRecognitionUsageDescription`）；授权被拒时显示提示文案 + 跳设置

### 5. 气泡动效（iMessage 风格，双端）

- **Web**：`.buddy-msg` 增加发送动画（scale 0.9→1 + translateY + spring easing）、气泡尾巴（`::after` 三角）、`waiting` 打字指示器（三个跳动圆点）、失败重试入口
- **iOS**：`CompanionView` 对话行 `withAnimation(.spring)` 插入 + 气泡圆角 + 尾巴 + 打字指示器（`isTyping` 状态延迟渲染）

## 6. 错误处理

| 场景 | 行为 |
|---|---|
| 免费额度耗尽 | `402 quota_exceeded/free` → 双端弹「订阅或填自己的 Key」卡片（web：AI 设置；iOS：Paywall） |
| Pro 当日耗尽 | `402 {kind:"daily"}` → 显示「明日恢复」 |
| 无 DeepSeek Key | 500 `{code:"proxy_misconfig"}`（仅开发环境可见） |
| 上游超时 | 透传 5xx，客户端统一「AI 请求失败，请稍后重试」 |

## 7. 测试

- **Web**：`node --test` 增加 mock 测试（fetch stub 断言 402 分支、语音可用性探测）
- **iOS**：`TodoNativeTests` 补 `QuotaClientTests`（URL/deviceId/402 处理）、语音权限 helper mock
- **Worker**：本地 `wrangler dev` 手动 curl 覆盖 free/Pro/透传三条路径
- **E2E 冒烟**：web 手动录语音 → 下发 → 气泡；iOS 模拟器录音授权确认

## 8. 落地顺序

1. Worker（count + quota + proxy + register-pro）
2. 客户端 QuotaClient（web `window.quotaProxy` / ios `QuotaClient`）
3. 语音输入（web 先、iOS 后）
4. 气泡动效（web 先、iOS 后）
5. Paywall 文案（运费、额度说明）

## 9. 不做什么（YAGNI)

- 不做账号系统、不做跨设备同步额度
- 不做 Durable Objects / 队列
- 不做服务端计费报表（KV 计数即可，后期可加）
- Web 端不做付费（只做 free 额 + 自定义 Key）