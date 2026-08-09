# iOS App 规划与落地（AI-native Todo）

本目录是 AI-native Todo 的 iOS 端实现（SwiftUI + SwiftData，iOS 17+），网页版核心功能已逻辑镜像移植。工程以可复用 Xcode 配置交付（`Project.yml` + 已生成的 `TodoNative.xcodeproj`），先跑通核心能力，再持续打磨视觉和商业化。运行前需具备 Xcode 与 Apple Developer 账号。

## 本次交付（已产出）

- `ios/TodoNative/`：SwiftUI 应用（模型、视图、VM、服务层）
- `ios/Runbook/parallel-handoff.md`：执行拆分清单（可并行认领给 agent）
- `ios/Design/ios-architecture-plan.md`：App 结构、权限边界、发布策略与数据库设计
- `ios/Runbook/iap-and-release-checklist.md`：IAP 与发布清单

## 当前状态（2026-08-08）

- [x] 核心信息架构完成：任务类型、上下文、验收标准、下一步 Prompt
- [x] 7 天试用 + 订阅 gating 入口完成（设置页主入口 + 启动自动弹窗）
- [x] 今日健康度看板（任务完成率、状态分布、今日计划卡片）
- [x] 任务卡片工作流升级（状态快速切换、状态可视化、滑动操作/上下文菜单）
- [x] Obsidian 导出面向付费态完善（分享、复制、文件名）
- [x] Companion 伙伴 Tab（聊天 + 跨会话记忆 + 关键时刻引擎：完成庆祝每日去重/逾期轻推 + 建议动作流）
- [x] Companion 体验升级：iMessage 风格气泡 + 打字指示器；语音输入（SFSpeechRecognizer + AVAudioEngine，双权限校验）
- [x] AI 配额客户端（QuotaClient：无 Key 时走托管代理 `deepseek-chat`，402 映射本地化提示；register-pro 验签）
- [x] 本地通知精确到分钟（DatePicker 时分，按期触发；任务完成自动取消；过期补发最小 60s；设置页授权状态）
- [x] 微交互与动画（打勾弹跳+闪光、按钮按压、列表过渡、统计 pop、气泡滑入/打字指示器，尊重 Reduce Motion）
- [x] 单元测试 target 接入（TodoNativeTests，93 用例 / 13 个测试文件，iOS 27 全绿）
- [x] iOS 27 (27.0) 模拟器构建 + 启动冒烟验证通过
- [x] 真实 AI 接口接入（OpenAI /v1/chat/completions + legacy /v1/responses，无 Key 自动本地降级；AI 工作台：智能拆解 / 复盘 / 今日计划）
- [x] 编辑已存任务（TaskEditView）+ 清除已完成
- [x] 中/英双语切换（Localization 字典 + 设置页入口，对齐 web I18N）
- [x] 4-Tab 布局：今日计划（Today）/ 任务（Tasks）/ 伙伴（Buddy）/ 设置（Settings）
- [ ] App Store 构建与截图、隐私清单、正式 TestFlight

## 运行建议

1. 已改为可复用的 Xcode 工程配置：
   - `ios/Project.yml`（源码配置，支持 `xcodegen generate` 自动产出）
   - `ios/TodoNative.xcodeproj`（本次已生成）
2. 进入项目后首次可直接构建（需本机有可用的 iOS Simulator runtime）：
   - `cd ios`
   - `xcodegen generate`（如需重新生成）
   - `open TodoNative.xcodeproj`
   - 在 Xcode 里选择一个 iOS 模拟器（iPhone/iPad）后点击运行
3. CLI 快速验证（当环境有可用 destination 时）：
   - `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'generic/platform=iOS Simulator' build`
   - `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -showdestinations`
4. 单元测试（93 个用例，覆盖模型 / 任务 ViewModel / AI 计划 / Obsidian 导出 / 试用 / Companion / 通知 / 配额客户端 / 本地化）：
   - `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test`
   - 或 `xcodegen generate` 后在 Xcode 中按 `Cmd+U`
5. 先在本地确认首页与任务流可用，再接入真实 AI 与付费。
6. 再配置 IAP（`com.zhili.todo.premium.monthly` / `com.zhili.todo.premium.yearly`）并启用 7 天试用。
7. 最后补上真实的 AI 后端（或代理服务）后，上 TestFlight。

## 本地预览命令（推荐）

1. 一键预览（支持回退目标）：
   - `scripts/ios-preview.sh "iPhone 17 Pro" 26.5 run`
   - `scripts/ios-preview.sh "iPhone 17 Pro" 26.5 run-simctl`
     - `run-simctl` 会改为 `xcodebuild build + simctl install + launch`，适合快速验证签名/启动链路。
2. 只做 CLI 编译（不启动）：
   - `scripts/ios-preview.sh "iPhone 17 Pro" 26.5 build`
3. 手动执行：
   - `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' run`
4. 如果 `showdestinations` 没有显示该设备，请先打开 Xcode 的 Platforms 组件下载对应的 iOS Simulator，然后再重试，或改为：
   - `xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'generic/platform=iOS Simulator' run`

## 里程碑（4 周）

- 第 1 周：任务模型 + 今日计划 + 导出 + 付费状态基础
- 第 2 周：Paywall、订阅态刷新、恢复购买、试用到期降级
- 第 3 周：高级交互（拖拽排序、动画、卡片体验、主题/无障碍）
- 第 4 周：StoreKit 回归测试、App 提交材料（截图、文案、隐私说明）提交审核