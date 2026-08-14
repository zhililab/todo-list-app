# App Store Connect 元数据草稿（简体中文）

核对日期：2026-08-11
Bundle ID：`com.zhili.todo-native`

> 本文件是填写 App Store Connect 的工作稿，不代表已在 App Store Connect 保存或审核通过。所有 `ACTION REQUIRED` 必须由有权限的账号所有者在提交前确认。

## 基本信息

- App 名称：`ACTION REQUIRED — 确认“AI Native Todo”在 App Store Connect 可用，并决定最终展示名称。`
- 副标题：`任务、提醒与可选 AI 规划`
- 当前提交路径：**Path B — managed backend 尚未完成，不作托管 AI 可用承诺。复制下方 Path B 文案。**
- 主要类别：`ACTION REQUIRED — 在 App Store Connect 选择类别；候选为“效率”。`
- 次要类别：`ACTION REQUIRED — 决定是否选择次要类别；候选为“工具”。`
- 内容版权：`ACTION REQUIRED — 填写真实年份及拥有版权的法律主体名称。`
- 支持 URL：`https://todo-list-app.zhili1993.chatgpt.site/support.html`
- 隐私政策 URL：`https://todo-list-app.zhili1993.chatgpt.site/privacy.html`
- 服务条款 URL：`https://todo-list-app.zhili1993.chatgpt.site/terms.html`
- 支持邮箱：`lz123321@live.com`

## Path B（当前默认：无 managed AI 承诺）

### 宣传文本

`把任务上下文、验收标准和下一步提示放进一个双语工作流；无需账号，可使用本地规划器，或在明确同意后使用自己的 AI Key。`

### 完整描述

AI Native Todo 是一款不需要注册账号的双语任务应用，帮助你把“要做什么”和“做到什么程度”放在一起管理。

你可以：

- 创建、编辑、归档和完成任务，并记录任务类型、优先级、预估时间和截止时间；
- 为任务补充上下文、验收标准和下一步 AI Prompt；
- 查看今日计划、任务健康度和状态分布；
- 为带截止时间的任务安排本地通知；
- 与 AI 伙伴对话、拆解目标、复盘进度，并把建议确认后写入任务；
- 用语音转写填写伙伴输入框，检查文字后再发送；
- 将任务导出为适合 Obsidian 的 Markdown；
- 在简体中文和英文之间切换。

任务和应用设置主要保存在设备上。无需联网的本地规划器始终可用。自带 API Key（BYOK）是可选能力：应用会在首次向当前接收方发送内容前说明数据范围并请求同意。你可以拒绝并继续使用本地规划器，也可以随时在设置中撤回同意。API Key 保存在 iOS 钥匙串中，请求会直接发送给所选模型服务商。

高级功能可通过月度或年度自动续订订阅解锁。应用还提供从首次启动开始计算、仅保存在本机的 7 天体验；它不是 App Store 首购优惠。实际价格、周期和可用优惠以 App Store 购买页面为准。

使用条款（Apple 标准 EULA）：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

AI 生成内容仅用于辅助规划，可能不准确。请在采取重要行动前自行核验。

## Path A（仅在 managed backend 发布闸门全部完成后使用）

### 宣传文本

`把任务上下文、验收标准和下一步提示放进一个双语工作流；可使用本地规划、自己的 AI Key，或在明确同意后使用托管 AI。`

### 完整描述

AI Native Todo 是一款不需要注册账号的双语任务应用，帮助你把“要做什么”和“做到什么程度”放在一起管理。

你可以：

- 创建、编辑、归档和完成任务，并记录任务类型、优先级、预估时间和截止时间；
- 为任务补充上下文、验收标准和下一步 AI Prompt；
- 查看今日计划、任务健康度和状态分布；
- 为带截止时间的任务安排本地通知；
- 与 AI 伙伴对话、拆解目标、复盘进度，并把建议确认后写入任务；
- 用语音转写填写伙伴输入框，检查文字后再发送；
- 将任务导出为适合 Markdown 知识库的文件；
- 在简体中文和英文之间切换。

任务和应用设置主要保存在设备上。远程 AI 是可选能力：应用会在首次向当前接收方发送内容前说明数据范围并请求同意。你可以拒绝并继续使用本地规划器，也可以随时在设置中撤回同意。使用自己的 API Key 时，Key 保存在 iOS 钥匙串中，请求会直接发送给所选模型服务商。使用托管 AI 时，内容和随机设备标识会先发送到托管服务，再转发给披露的模型服务商。

高级功能可通过月度或年度自动续订订阅解锁。应用还提供从首次启动开始计算、仅保存在本机的 7 天体验；它不是 App Store 首购优惠。实际价格、周期和可用优惠以 App Store 购买页面为准。

使用条款（Apple 标准 EULA）：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

AI 生成内容仅用于辅助规划，可能不准确。请在采取重要行动前自行核验。

`ACTION REQUIRED — 只有生产 endpoint、KV/secrets、Apple JWS 真验签、bundle/environment 校验、退款/撤销同步、App Privacy 和真实设备验证全部完成后，才可复制 Path A。`

## 关键词

候选：`待办事项,任务管理,每日计划,到期提醒,效率工具,目标拆解,进度复盘`

UTF-8 字节检查：`90 bytes`（`node Buffer.byteLength`，不含品牌/公司名，也没有长度小于等于 2 字符的关键词）。

## 后续版本“此版本更新内容”备用（1.0 首发不填写）

App Store Connect 的 1.0 首发版本不要求 What's New；以下内容仅供 1.0.1 或后续版本按真实差异改写：

- 支持带上下文、验收标准和下一步提示的任务管理。
- 新增今日计划、任务健康度、本地提醒和自然语言截止时间。
- 新增可选 AI 工作台、伙伴对话、语音转写和本地规划回退。
- 新增远程 AI 明示同意、撤回控制和 Keychain API Key 存储。
- 新增月度/年度订阅、恢复购买与高级 Markdown 导出。

## 提交前确认

- [ ] `ACTION REQUIRED` 名称、类别和版权主体已由账号所有者确认。
- [ ] 当前复制 **Path B**；托管 AI 仅在生产 endpoint、Worker secrets/KV 和交易验证达到发布要求后才切换到 Path A。
- [x] 2026-08-11 公开支持页面已返回 HTTP 200，并发布支持邮箱 `lz123321@live.com` 及隐私删除请求说明；提交前仍需再次核对线上内容未回退。
- [x] 候选关键词已在本地按 UTF-8 核对为 90 bytes；仍需在 App Store Connect 保存验证。
