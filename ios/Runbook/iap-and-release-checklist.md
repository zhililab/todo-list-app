# iOS 订阅与上架执行清单

## 1) App Store Connect 订阅设置

- [ ] 创建 `Subscription Group`
- [ ] 新建两个订阅（自动续费）：
  - `com.zhili.todo.premium.monthly`
  - `com.zhili.todo.premium.yearly`
- [ ] 配置 7 天试用（Intro Offer）
- [ ] 选择可见区域：`All` 或按目标人群
- [ ] 配置价格/展示说明、账单周期文案
- [ ] 记录每个 Product ID 到 `ios/TodoNative/Services/PurchaseManager.swift`
- [ ] 订阅恢复/退订流程文案放入 Paywall：`App内说明 + App Store页面`

## 2) App 代码验收

- [ ] Trial 状态能显示：`TrialManager`
- [ ] 支付入口：`PaywallView`
- [ ] 订阅恢复：`restorePurchases`
- [ ] 订单变化监听：`Transaction.updates`
- [ ] 付费功能入口加白名单（当前 `PurchaseManager.canUse(_:)`）

## 3) 本地设备验证（最少）

- [ ] 安装 sandbox build
- [ ] 免费用户仍可打开，付费功能 blocked 并显示升级
- [ ] sandbox 购买 -> features 即时解锁
- [ ] 恢复购买：从另一个测试机验证
- [ ] 试用期过期场景：切换到 `free`（无权限）且能提示订阅
- [ ] 任务状态流程（待开始/进行中/已完成）和健康度看板无闪烁可读
- [ ] 动态字体（最小/大字号）下无布局越界

## 4) App Store 提交

- [ ] App 名称、截图、隐私清单（Privacy Manifest）
- [ ] 截图：iPhone / iPad（至少一版）
- [ ] 订阅说明文字（条款、取消、续费）
- [ ] 联系方式与支持链接

## 5) TestFlight 验证清单（发布前）

- [ ] 上线前一轮 TestFlight：iPhone + iPad 全量 smoke 测试
- [ ] iPad 横屏（Landscape）下 Dashboard 与 Tasks 布局完整显示
- [ ] VoiceOver 基础可读性（输入、按钮、任务卡片）检查
- [ ] 至少 3 位测试者通过购买/恢复购买主路径
