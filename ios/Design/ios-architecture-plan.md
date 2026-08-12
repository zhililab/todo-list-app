# AI-native Todo iOS 架构方案

## 目标

- 以“轻量 + 高品质 UI”为第一原则，保留网页的核心生产力能力。
- 通过订阅与试用提升价值认知：免费可用 7 天试用，期后引导订阅。

## 技术边界

### 核心栈
- SwiftUI
- SwiftData（本地任务与设置）
- StoreKit 2（订阅与试用）
- 后端网关（可选）: 代理 AI 请求，隐藏第三方 Key

### 模块划分

- `Models`: 任务模型、类型、状态、权限
- `Services`: `TrialManager`、`PurchaseManager`、`AIPlanService`、`ObsidianExporter`
- `ViewModels`: 任务流与今日计划逻辑
- `Views`: 首页、今日计划、设置、试用/订阅拦截页
- `Assets`: 图标、色板、字体

## 数据模型（MVP）

- `TodoItem`
  - `id`, `title`, `status`, `priority`
  - `taskType`（Personal/Code/Product/Learning/Life）
  - `context`, `acceptanceCriteria`, `nextPrompt`
  - `estimatedMinutes`, `createdAt`, `updatedAt`, `dueDate?`
  - `isCompleted`, `isArchived`

- `PlanSession`
  - `date`, `generatedAt`, `items:[UUID]`
  - `summary`, `focusScore`, `source`（localAI/remoteAI）

## 权限与付费策略（推荐）

免费用户：
- 查看与新增基础任务
- 今日看板展示
- 本地导出（基础）

试用/订阅用户：
- AI 智能拆解、今日计划高级排序
- 任务上下文模板
- 完整导出（含多模板/标签）
- 自定义视图主题
- 跨设备同步（后续）

## 线上化与发布

- 先做 App 内“试用状态驱动 UI”（`canUsePremiumFeature`）
- App Store Connect 配置订阅：
  - 自动续费月度：`com.zhili.todo.premium.monthly.v2`
  - 自动续费年度：`com.zhili.todo.premium.yearly.v2`
  - Intro Offer：7-day free trial（7 天）
- 试用结束后进入“只保留免费功能 + 付费引导弹窗”降级逻辑
- 上线前检查：
  - 恢复购买按钮可见且可用
  - 审核页文案与隐私说明清晰
  - 订阅取消流程和计费说明可追溯
