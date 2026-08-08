# 并行协作执行清单（可直接发给 agent）

## A 组：付费与账号（优先级 P0）
目标：在第 3 天前可在真机验证订阅状态更新。

- [ ] 完成 App Store Connect：
  - 创建两个 subscription group
  - 创建月度/年度订阅档位
  - 配置 7 day Intro Offer（仅新订阅用户可见）
  - 记录 product IDs 至 `PurchaseManager`
- [ ] 验证 StoreKit sandbox 流程（购买、恢复购买、订阅失效）
- [ ] 订阅状态下发至 UI（`isPremium` / `isTrial`）

## B 组：任务核心体验（优先级 P0）
目标：任务生命周期闭环可上线。

- [ ] 完成 `TodoItem` 建模（type/context/acceptance/nextPrompt）
- [ ] `TodayPlanGenerator` 实现基础策略（优先级 + deadline + 重要性）
- [ ] 任务卡片 UI（完成、延期、归档、筛选）
- [ ] Obsidian 导出（UTF-8 markdown，时间戳文件名）

## C 组：高级 UX 与品质（优先级 P1）
目标：视觉从“可用”上升到“应用级”。

- [x] 卡片系统：圆角、层次、微交互（按压反馈/过渡动画）
- [ ] 夜间模式与字体缩放（Dynamic Type）
- [ ] 空态、骨架屏、空任务引导（empty + CTA）
- [x] iPad 多窗格 / 横屏适配

## D 组：发布与风险清单（优先级 P1）

- [ ] App 隐私说明与数据使用声明
- [ ] IAP 文案合规
- [ ] TestFlight 3 人内测用例
- [ ] 监控：
  - 应用启动、任务新增、计划生成、导出、付费触发、恢复购买成功率
