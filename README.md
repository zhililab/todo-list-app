# AI-native Todo

一个支持任务类型、上下文、验收标准、AI 下一步 Prompt、今日计划与 Obsidian 导出的双语待办应用，Web 与 iOS 双端实现。

An AI-native bilingual todo app with task types, context fields, acceptance criteria, next-step prompts, today plan, and Obsidian export. Available on Web and iOS.

## 功能需求核对

- [x] 任务支持类型（Personal / Code / Product / Learning / Life）
- [x] 任务支持上下文字段（Context）
- [x] 任务支持验收标准（Acceptance Criteria）
- [x] 任务支持下一步 prompt（Next AI Prompt）
- [x] 一键导出 Obsidian Markdown（`todo-list-app-YYYY-MM-DD.md`）
- [x] 今日计划视图（Today Top 5 / 今日计划面板）

## Repository

当前仓库名已统一为：`todo-list-app`

## 功能特性汇总（Web）

- **任务管理**：增删改查、完成状态切换、批量清除已完成；类型（个人/代码/产品/学习/生活）+ 状态（全部/进行中/已完成/高优先级）+ 优先级筛选排序；新增任务自动推断元数据（中文关键词推优先级、正则解析预估时长、按关键词推类型）
- **截止时间**：支持日期 + 精确到分钟的时间（`YYYY-MM-DD HH:mm`），到期判断、逾期高亮均为分钟级
- **健康度仪表盘**：完成率进度条 + 统计卡；健康分算法（完成度 45 + 上下文完备度 35 + 活跃负荷 20 − 高优先级积压罚分）；今日 Top 5 视图 + 下一步建议
- **AI 工作台**：8 家 OpenAI 兼容服务商（OpenAI/DeepSeek/Moonshot/Zhipu GLM/Qwen/Groq/SiliconFlow/Custom + 自定义）；智能拆解目标为 5-8 条可勾选任务并可一键导入、AI 复盘与下一步、AI 今日计划、任务行「拆小」；全部能力无 API Key 时自动本地降级
- **Companion（AI 温柔知己）**：对话聊天（人格设定 + 上下文打包 + 最近 40 条历史 + 记忆压缩）；关键时刻引擎（完成庆祝每日去重 + 逾期 3 天轻推）；建议动作流（严格 JSON 契约，白名单 `add_task/complete_task/breakdown`，写操作需用户点击确认）；无 AI 回复时从用户消息本地提取任务意图兜底；每日问候（带 Key 时后台换用 LLM 生成）
- **Obsidian 导出**：一键导出带 YAML frontmatter 的 Markdown 文件（含今日计划与任务上下文字段）
- **到期通知**：分钟级到期判断，到点发系统通知；60 秒轮询 + 去重标记，完成任务或改期自动清除标记
- **微交互**：统计数字 pop、完成任务高亮闪烁、删除任务淡出、逾期任务呼吸提醒、伙伴消息滑入、进度条 shimmer，全部支持 `prefers-reduced-motion`
- **其他**：中英双语（i18n 字典 + 本地化日期，持久化语言偏好）；PWA（favicon + webmanifest）；三栏响应式布局、键盘快捷键（⌘/Ctrl + Enter 快速添加）

## iOS 端功能特性（SwiftUI + SwiftData，iOS 17+，XcodeGen 工程）

与 Web 端为「逻辑镜像」移植（各模块注释标注与 web 逻辑一致），数据完全独立（SwiftData + UserDefaults），无后端、无跨端同步。

- **布局**：4-Tab 导航（今日计划 / 任务 / 伙伴 / 设置）；任务模型含上下文/验收标准/下一步 Prompt/来源目标；表单新增 + 自然语言捕捉（对齐 web 元数据推断）；编辑（TaskEditView）、删除/归档、清除已完成；状态筛选 + 优先级排序
- **AI 工作台**：智能拆解 / 复盘 / 今日计划，无 Key 自动本地降级；8 家兼容服务商注册表，兼容 `chat/completions` 与 `responses` 两种响应格式
- **Companion**：聊天 Tab（上下文打包 + 记忆压缩 + 历史 40 条）；关键时刻引擎（完成庆祝每日去重 / 逾期轻推）；建议动作流（白名单 + 批量入库）；每日问候可开关
- **通知**：截止日期精确到分钟（DatePicker 日期 + 时分），按用户选择时刻触发并用 `UNTimeIntervalNotificationTrigger` 调度；过期任务补发间隔最小 60s；完成任务自动取消提醒；设置页展示授权状态
- **商业化**：7 天试用（过期自动降级）+ StoreKit 2 月/年订阅 + 恢复购买 + 交易监听；功能门控（AI 今日计划/高级 Obsidian 导出/任务模板/分析看板/主题包）；付费入口在设置页，试用结束后启动弹出自弹窗
- **Obsidian 导出**：生成每日 Markdown，支持系统分享面板 + 复制剪贴板（付费功能）
- **体验**：动画全套尊重 `accessibilityReduceMotion`（完成打勾弹跳 + 闪光覆盖、按钮按压反馈、列表插入移除过渡、统计数字 pop、气泡滑入）；iPad 宽屏双栏；中英双语
- **质量**：84 个单元测试（12 个测试文件，覆盖模型 / 任务 VM / AI 计划 / Obsidian 导出 / 试用 / Companion / 通知 / 本地化），iOS 27 模拟器构建 + 启动冒烟通过

## 文件结构

```text
/
├── index.html            # UI + i18n 标记
├── styles.css            # 页面样式
├── app.js                # 任务管理 / AI 流程 / 多语言逻辑
├── companion-actions.js  # Companion 动作解析（JSON 契约 + 白名单）
├── companion-context.js  # Companion 上下文 / 记忆打包
├── companion-events.js   # 关键时刻引擎（庆祝 / 轻推）
├── companion-format.js   # 日期解析 / 逾期 / 通知判断
├── companion-*.test.js   # 对应模块单元测试（node --test）
├── public/               # PWA 资源（favicon、site.webmanifest）
├── docs/                 # 设计文档与实现计划
├── scripts/              # 构建 / iOS 预览脚本
└── ios/                  # iOS 端（SwiftUI + SwiftData）
    ├── TodoNative/       # App 源码（Models / ViewModels / Views / Services）
    ├── TodoNativeTests/  # 84 个单元测试
    ├── Project.yml       # XcodeGen 源码配置
    └── README.md         # iOS 规划与落地说明
```

## 快速开始

```bash
# Web：在项目根目录
python3 -m http.server
```

打开：`http://localhost:8000`

iOS 运行方式见 `ios/README.md`（`xcodegen generate` + Xcode 运行，或 `scripts/ios-preview.sh` 一键预览）。

## 在线部署

- Production: https://todo-list-app.zhili1993.chatgpt.site
- GitHub 仓库： https://github.com/zhililab/todo-list-app

## iOS 版本（进行中）

- 当前状态与运行说明：`ios/README.md`
- 架构与订阅实现建议：`ios/Design/ios-architecture-plan.md`
- 多任务并行执行清单：`ios/Runbook/parallel-handoff.md`
- IAP 与发布清单：`ios/Runbook/iap-and-release-checklist.md`

## 截图

<img width="2740" height="3088" alt="image" src="https://github.com/user-attachments/assets/932a221e-968f-4fd5-8f56-51b4cc2b71f5" />

## 更新日志

- 2026-08-08：支持精确到分钟的截止时间与到期提醒（Web + iOS 双端）；Companion 新增本地任务意图兜底；新增微交互与动画（双端，尊重系统减弱动态设置）。
- 2026-08-08：README 功能特性汇总更新（Web / iOS 双端），同步 iOS 测试用例数（84 个，12 个测试文件）。
- 2026-08-08：已补充网站 favicon 配置（Tab icon）并上线到 https://todo-list-app.zhili1993.chatgpt.site。
- 2026-08-08：新增 `site.webmanifest`，增强移动端/站点安装体验，图标统一使用高识别度专业 favicon。

## 配置说明

- 本地语言偏好与 API Key 会持久化到 `localStorage`
- `.env` 不需要配置（纯前端，API Key 在浏览器输入框中保存到本地）

## 运行说明（English）

1. Start service: `python3 -m http.server`
2. Open `http://localhost:8000`
3. Add tasks, set task type/priority, fill context + acceptance criteria, run AI features if needed
4. Export to Obsidian Markdown for daily planning/archive