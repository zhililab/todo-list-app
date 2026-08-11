# App Store 截图采集与无障碍检查清单

Apple 官方规格核对日期：2026-08-11
官方来源：[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)、[Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)

## 1. 必须遵守的文件规格

Apple 当前文档要求每个截图组上传 **1–10 张**，格式为 `.jpeg`、`.jpg` 或 `.png`，且图片**不能带 alpha channel 或透明度**。

| 截图组 | 本项目采用方向 | Apple 接受的像素尺寸 |
|---|---|---|
| iPhone 6.9 英寸 | 竖屏 | `1260 × 2736`、`1290 × 2796` 或 `1320 × 2868` |
| iPad 13 英寸 | 竖屏 | `2064 × 2752` 或 `2048 × 2732` |

- [ ] 截图来自匹配尺寸的真实模拟器或设备，或经过不失真的规范化导出。
- [ ] 同一截图组使用一致的方向和视觉模板。
- [ ] 导出后用文件检查工具确认像素、色彩空间和 alpha 状态；不能只看 Finder 缩略图。
- [ ] zh-Hans 与 en-US 分别采集，画面语言与对应元数据一致。
- [ ] 每组至少 1 张、最多 10 张；建议 6–7 张，按价值而不是按功能数量排序。

## 2. 推荐截图顺序

| 顺序 | 画面 | 必须表达 | 准备数据 |
|---|---|---|---|
| 1 | Today / 今日计划 | 今日重点、健康度、清晰的本地/远程 AI 来源标签 | 3–5 条无隐私示例任务；不得在 endpoint 缺失时展示“托管 AI 已连接”。 |
| 2 | Tasks / 任务列表 | 类型、优先级、状态、截止时间 | 覆盖待开始/进行中/已完成；避免真实姓名、公司项目和通知正文泄漏。 |
| 3 | Task editor / 任务编辑 | 上下文、验收标准、下一步 Prompt | 使用通用示例，如发布周报或准备读书计划。 |
| 4 | AI workbench | 目标拆解/复盘及结果来源 | 当前生产 endpoint 缺失时只展示“本地规划器”；如展示远程结果，先完成生产服务和同意验证。 |
| 5 | Buddy / 伙伴 | 聊天气泡、建议动作、语音转写入口 | 使用合成对话；输入框、历史与转写不含个人内容。 |
| 6 | Reminders / 提醒与设置 | 通知状态、语言、隐私入口 | 不展示真实通知中心；用 app 内设置页表达可控权限。 |
| 7 | Premium / 订阅与导出 | StoreKit 产品、恢复购买、Obsidian 导出 | 价格必须来自实际 StoreKit/ASC 产品；价格未确定前不要把本地 StoreKit 测试价写进营销图。 |

## 3. iPhone 6.9 英寸采集

- [ ] 使用能输出上述任一 6.9 英寸接受尺寸的设备配置。
- [ ] 分别采集 zh-Hans light、zh-Hans dark、en-US light、en-US dark 候选；最终同一 storefront 截图组保持一致视觉主题。
- [ ] 小屏安全区、动态岛、底部 Tab、Sheet 和 Paywall 无裁切。
- [ ] 语音权限 alert、通知 alert、远程 AI consent full-screen cover 各保留一张内部审核证据；只有在信息清晰且无临时凭据时才作为商店截图。

## 4. iPad 13 英寸采集

- [ ] 使用能输出 `2064 × 2752` 或 `2048 × 2732` 竖屏截图的 iPad 13 英寸配置。
- [ ] Today 与 Tasks 的宽屏布局没有大面积空白、重叠或伸展失真。
- [ ] 表单、Sheet、Paywall 和设置页在 iPad 弹层尺寸中信息层级完整。
- [ ] 额外内部验证横屏布局；如上传横屏资产，应重新按 Apple 官方横屏尺寸核对，不能旋转竖屏图冒充。

## 5. 内容与安全检查

- [ ] 使用专门的无隐私演示数据集；不使用真实姓名、邮箱、工作项目、客户名、行程、健康或财务内容。
- [ ] 不显示 API Key、Bearer header、Worker secret、匿名设备 ID、交易 JWS、Sandbox Apple Account 或调试 endpoint。
- [ ] 不显示系统通知中心中的个人通知；任务提醒内容可能含任务标题。
- [ ] 状态栏时间、电量、网络状态合理；没有录屏红点、开发调试浮层、测试 banner 或未读私人通知。
- [ ] 不用伪造的系统 UI、未经许可的第三方商标或无法在提交构建中复现的结果。
- [ ] 托管 AI 未上线时，截图文案明确为本地规划器/BYOK，不出现剩余额度或“已注册 Pro 配额”等误导状态。
- [ ] 截图中展示的订阅价格、试用和优惠与 App Store Connect 当时配置一致；本地 7 天体验不能标为 Apple Intro Offer。

## 6. 本地化与文案一致性

- [ ] zh-Hans 画面全部使用简体中文，en-US 画面全部使用英文；没有混合占位符、未翻译 key 或截断。
- [ ] App 名称与已确认的 App Store Connect 名称一致。
- [ ] 权限说明、同意页、Paywall、Privacy/Terms/Support 链接与提交构建一致。
- [ ] 同一功能在 iPhone/iPad 的标题和状态含义一致。

## 7. 无障碍与视觉 QA

- [ ] Light/Dark 下文字、图标、禁用态和错误态对比清晰。
- [ ] 系统字体最大辅助字号下，任务卡、按钮、Paywall 价格和 consent 内容可滚动且无重叠。
- [ ] VoiceOver 顺序覆盖 Tab、任务卡、主要操作、语音按钮、同意/拒绝、购买/恢复和法律链接。
- [ ] Reduce Motion 开启时不依赖动画传达成功、完成或错误。
- [ ] 颜色不是状态的唯一线索；待办/进行中/完成、配额和权限状态有文字或图标标签。
- [ ] 截图本身不使用过小营销字、低对比渐变或遮挡 app 核心内容的装饰框。

## 8. 上传前证据记录

- [ ] 在 `release-evidence.md` 记录设备、OS、App build、语言、主题、原始文件名、导出尺寸和 SHA-256。
- [ ] 逐张打开最终导出文件，确认没有被压缩工具加回 alpha、裁切或颜色偏移。
- [ ] 在 App Store Connect Media Manager 预览 zh-Hans/en-US、iPhone/iPad 的实际排序。
- [ ] `ACTION REQUIRED — 账号所有者确认最终 1–10 张资产并完成上传；仓库中的计划不等于 App Store Connect 已完成。`
