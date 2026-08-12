# AI 额度系统 + 伙伴语音/气泡动效 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 双端实现 AI 托管额度（免费 10 条终身 / Pro 20 条日，DeepSeek key 只在 Cloudflare Worker 内）+ 伙伴语音输入 + iMessage 风格气泡动效。

**Architecture:** 无后端架构保持不变——新增一个 Cloudflare Worker（`workers/quota-proxy/`）持有 DeepSeek Key 并按设备匿名 ID 计费；Web/iOS 客户端通过统一 HTTP 契约调用 /proxy 三端点；自定义 Key 用户绕过代理直连原有逻辑。语音输入 Web 用 SpeechRecognition、iOS 用 SFSpeechRecognizer。

**Tech Stack:** Cloudflare Workers + KV（wrangler）、原生 JS（Vite、无需新依赖）、SwiftUI + SFSpeechRecognition + StoreKit2。

**并发执行策略：** 三路并行 agent（worker / web / ios），共用下方"HTTP 契约"作唯一接口。每个 agent 完成自己的任务后自测并独立 commit。最后我来合并验证。

## 并发契约（HTTP Contract / 唯一事实）

Base URL：`https://todo-quota-proxy.<USER_SUBDOMAIN>.workers.dev`（本地产实施阶段可配置 `localStorage['quota_base_url']` / iOS `UserDefaults` key `quota_base_url`，默认空 = 不启用托管额度）。

### 端点 1: POST /proxy/chat/completions
请求（客户端原样转发 body）：
```
POST /proxy/chat/completions
X-Device-Id: <uuid>
Content-Type: application/json
{ "model": "deepseek-chat", "messages": [...], "stream": false }
```
响应：
- 200：DeepSeek 原文 JSON（透传，客户端按现有 extractOutputText 解析）
- 402：`{"error":{"code":"quota_exceeded","kind":"free"|"daily"}}` —— free=终身 10 条用完；daily=Pro 当日 20 条用完
- 500：`{"error":{"code":"proxy_error","message":"..."}}`

### 端点 2: GET /proxy/quota
```
GET /proxy/quota
X-Device-Id: <uuid>
```
响应 200：`{"freeUsed":0,"freeLimit":10,"proUsed":0,"proLimit":20,"isPro":false,"today":"2026-08-09"}`

### 端点 3: POST /proxy/register-pro（仅 iOS）
```
POST /proxy/register-pro
X-Device-Id: <uuid>
{ "transactionJwt": "<StoreKit jwsRepresentation>" }
```
- 200 `{"ok":true,"expiry":"..."}`
- 401 `{"error":{"code":"invalid_jwt"}}`

### 客户端行为（两端一致）
1. 无 `quota_base_url` 或用户填了自定义 API Key → 直连原逻辑（用户 Key，无限）
2. 否则走代理：POST body 增加 `"model":"deepseek-chat"`（覆盖），带 device id
3. 收到 402 kind=free → 文案「免费额度已用完：订阅 Pro 或填自己的 API Key」+ 引导（web: 打开 AI 设置；iOS: 弹 Paywall）
4. 收到 402 kind=daily → 「今日额度已用完，明天恢复」+ 指引订阅
5. /proxy/quota 用于展示剩余额度（可选，UI 用 .5 步骤）

### 设备匿名 ID
- Web：`localStorage['todo_device_id']`，无则 `crypto.randomUUID()` 生成
- iOS：`UserDefaults` key `device_id`，无则 `UUID().uuidString`

---

### Task 1（Agent A — Worker）
**Files:**
- Create: `workers/quota-proxy/src/index.js`
- Create: `workers/quota-proxy/wrangler.toml`（placeholder 但完整结构）
- Create: `workers/quota-proxy/package.json`
- Create: `workers/quota-proxy/README.md`

**Implement（无测试框架，wrangler dev + curl 验证）:**
- freeCount KV: `free:{deviceId}`（数字）
- proExpiry KV: `pro:{deviceId}`（ISO Date）
- daily KV: `daily:{deviceId}:{YYYY-MM-DD}`（数字）
- DEEPSEEK_API_KEY env (secret)
- 端点三件套按契约；免费额度逻辑、Pro 日额度逻辑、JWT 验签（仅 exp 校验 + productId 白名单 `com.zhili.todo.premium.monthly.v2` / `com.zhili.todo.premium.yearly.v2`，release 环境由 ALLOW_DEBUG_PRO 控制）
- 透传：fetch `https://api.deepseek.com/chat/completions`，Authorization: Bearer DEEPSEEK_API_KEY
- 2xx 才递增计数；错误透传状态码
- commit: `feat(worker): quota proxy with free/pro limits`

### Task B（Agent B）：Web 伙伴 = 语音输入 + iMessage 气泡 + 额度客户端
**Files:**
- Modify: `index.html`（buddy 面板 mic 按钮 + 气泡容器样式类）
- Modify: `styles.css`（气泡动画、打字指示器、mic 按钮）
- Modify: `app.js`（QuotaClient、device id、402 处理、语音识别集成、气泡动画）
- Create/Modify: `companion-quota.test.js`（新，模拟 fetch 覆盖 402/quota 解析/device_id）

**Interfaces:**
- 产出 `window/QuotaProxy = { baseUrl(), deviceId(), configure(base?), request(messages) }`（tests 可纯逻辑模拟）
- buddySend 前判断 Key/Quota 路由一致：见契约"客户端行为"
- 语音：按住 mic 说话 → SpeechRecognition zh-CN → textarea.value → 自动发送；不支持时隐藏按钮
- 气泡动效：`.buddy-msg` 弹入动画（scale 0.9→1 + opacity + spring easing），用户消息右对齐大圆角、assistant 左对齐、时间戳可选、打字指示器（"." 三连点动画）typing 期间
- 测试：现有 44 个 companion 测试保持全绿 + 新增（quota 分支、语音可用性探测 mock）
- commit: `feat(web): quota client, buddy voice input, iMessage bubbles`

### Task C（Agent C）：iOS 伙伴 + 语音 + 额度
**Files:**
- Create: `ios/TodoNative/Services/QuotaClient.swift`
- Modify: `ios/TodoNative/Services/OpenAIService.swift`（callOpenAI 增加 quota 分支：有 base_url → 走代理；402 异常分类 `QuotaExceededError(kind:)`）
- Modify: `ios/TodoNative/ViewModels/AIViewModel.swift`（暴露 quota 状态、处理方法）
- Modify: `ios/TodoNative/Views/CompanionView.swift`（mic 按钮 + SFSpeechRecognizer 录音、气泡样式 + 打字指示器 + 插入动画）
- Modify: `ios/TodoNative/Views/PaywallView.swift`（402 引导样式文案可选）
- Modify: `ios/TodoNative/Info.plist`（NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription）→ 注：xcodegen 工程在 TodoNative 目录，Info.plist 路径 `ios/TodoNative/Info.plist`
- Modify: `ios/TodoNative/Localization/Localization.swift`（quota.* / voice.* / bubble.* 文案）
- Create: `ios/TodoNativeTests/QuotaClientTests.swift`

**Interfaces:**
- `QuotaClient` enum：`baseURL() -> String?`（UserDefaults `quota_base_url`）、`deviceID() -> String`、`chat(payload) async throws -> Data`、`quota() async throws -> QuotaSnapshot`、`registerPro(jwt:) async throws`
- `enum QuotaError: Error { case quotaExceeded(kind: String) }`
- 语音：SFSpeechRecognizer zh-CN + AVAudioEngine 实时；按钮显示/隐藏跟随 `SFSpeechRecognizer.isAvailable`；Info.plist 权限文案
- 测试：QuotaClientTests（mock URLProtocol 断言 URL/deviceId header/402 解码/透传）；现有 85 全绿
- commit: `feat(ios): quota client buddy voice & bubbles`

### Task D（合并验证，本会话执行）
- web `node --test companion-*.test.js` 全绿（≥ 44）
- iOS `xcodegen generate && xcodebuild test …` 全绿（≥ 85）
- 手动 web 冒烟：语音按钮可见（Chrome）、气泡动画、额度文案
- 最终 commit 如有合并冲突

## Global Constraints
- Key 绝不出现于客户端代码/仓库（除 Worker Secret 说明）
- Web 端不做付费；Pro 验证仅 iOS
- 现有 44（web）/85（ios）测试不得回归（除新增）
- 所有 UI 文案中英双语（i18n 字典）
- 不引入新 npm/pod 依赖（web 无依赖、iOS 复用系统 framework）

## Status（最后更新 2026-08-09）
- ✅ Task 1（Worker）— commit `6038123`，test.mjs 14/14
- ✅ Task B（Web）— commit `75bcf11`，62/62 测试绿
- ✅ Task C（iOS）— commit `21fd62f`：QuotaClient / CompanionVoiceRecorder / OpenAIService 代理路由 / CompanionView 气泡+typing+mic / Info.plist 权限 / quota.* voice.* 双语 / QuotaClientTests 8 项 → 93/93 绿
- ✅ Task D（合并验证）— web 62/62、iOS 93/93；本地 dev server（:5173 vite 源码直供）冒烟：HTTP 200、`#buddy-mic`/`#quota-banner`/`companion-quota.js` module 均已加载、`window.QuotaProxy` + `decideRoute` 分流 + mic click 监听（SpeechRecognition 可用时）均接线；PaywallView 402 引导为自愿项（未做，低优先级）