# AI 情绪价值伙伴（AI Companion）Phase A 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 web + iOS 双端实现「温柔知己」AI 伙伴——对话窗为入口、跨会话记忆、进门问候 + 关键时刻主动、建议动作需确认。

**Architecture:** 纯前端架构。核心逻辑（上下文打包、关键时刻引擎、记忆、建议动作解析）在 web 端为独立 `companion-core.js` 模块，iOS 端为 `CompanionCore.swift`（两套实现，同构命名）。对话 UI 分别集成：web 右侧 detail 面板加 Tab 切换「伙伴 / AI 工具」，iOS MainTabView 加伙伴 Tab。LLM 调用复用现有 `callOpenAI` / `OpenAIService`，降级模板双端同构。

**Tech Stack:** web: 原生 JS（现有 vite 5.4.21 静态站点，无框架）；iOS: SwiftUI + SwiftData + XCTest。验证环境：iOS 模拟器 iPhone 17 Pro OS 27.0。

## Global Constraints

- web 语法检查 `node --check app.js`；i18n 字典只有 zh/en 两本
- iOS 构建：`cd ios && xcodegen generate && xcodebuild build -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0'`
- iOS 测试：同 destination 的 `xcodebuild test`；新增单元测试只测逻辑（不依赖 SwiftUI 视图）
- 存储键：web localStorage `companion_memory` / `companion_name` / `companion_greeting`；iOS UserDefaults 同键名 + SwiftData `CompanionMemory`
- 事件类型枚举（双端同名字符串）：`greet` / `celebrate` / `nudge`
- 建议动作 JSON 格式（双端同构）：`{"type":"confirm","actions":[{"action":"add_task"|"complete_task"|"breakdown","payload":{...},"label":"..."}]}`，解析后按需截断只取前 2 条
- 不引入任何新依赖；不写注释；提交在每任务最后一步

---

### Task 1: web 上下文打包器（companion-context.js）

**Files:**
- Create: `companion-context.js`（仓库根，与 app.js 同目录）
- Modify: `index.html`（在 app.js 前引入 script）

**Interfaces:**
- Consumes: 无（纯函数，web 侧被 Task 3 的 app.js 调用）
- Produces: `buildCompanionContext(opts)` — 输入 `{memorySummary, tasks, recentEvents, history, lang, buddyName, health}`, 返回 `{systemPrompt, userPrompt}`；`mergeMemory(oldSummary, newEvents)` 返回合并后摘要；`startsWithGreeting(message)` 返回 string 问候文本（本地降级）

**逻辑：**
1. 人格系统提示词：温柔知己 Samantha 风——名字、语气（温暖/有洞察/不评判）、称呼"你"，中文用温柔礼貌语气，英文柔和自然。内置起名默认「小暖」，用户可改（buddyName 参数）。
2. 上下文快照：记忆摘要（1-2 段）+ 未完成任务 Top 8（text + priority + type + effort）+ 最近完成 3 条 + 今日健康分 + 今日进度（完成/总数）+ 最近关键时刻事件 2 条（只描述事实）+ 最近 8 轮历史。
3. 降级问候模板（本地无 API Key）：zh "今天想先推进哪件事？我陪你。" / en "What would you like to move forward today? I'm right here with you."。

- [ ] **Step 1: 写测试文件 companion-context.test.js**

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildCompanionContext, mergeMemory, greeting } from './companion-context.js';

test('builds system prompt with buddy name and lang', () => {
  const ctx = buildCompanionContext({
    memorySummary: '用户昨天完成3件事，目标减肥2斤。',
    tasks: [{ text: '记录三餐热量', completed: false, type: 'personal' }],
    recentEvents: ['昨天完成「买体重秤」'],
    history: [], lang: 'zh', buddyName: '小暖', health: 80
  });
  assert.ok(ctx.systemPrompt.includes('小暖'));
  assert.ok(ctx.systemPrompt.includes('温柔'));
  assert.ok(ctx.userPrompt.includes('记录三餐热量'));
  assert.ok(ctx.userPrompt.includes('健康分'));
});

test('caps history at 8 turns', () => {
  const n = 12;
  const history = Array.from({ length: n }, (_, i) => ({ role: i % 2 ? 'assistant' : 'user', content: `msg${i}` }));
  const ctx = buildCompanionContext({ memory: '', tasks: [], recentEvents: [], history, lang: 'zh', buddyName: '小暖', health: 50 });
  const count = (ctx.userPrompt.match(/msg/g) || []).length;
  assert.ok(count <= 8);
});

test('merges memory with new events', () => {
  const merged = stripMemory('旧摘要。', ['完成X', '又完成Y']);
  assert.ok(merged.includes('完成X') || merged.includes('舊摘要'));
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `node --test companion-context.test.js`
Expected: FAIL（模块不存在）

- [ ] **Step 3: 实现 companion-context.js**

```js
export function buildCompanionContext(opts) {
  const lang = opts.lang || 'zh';
  const isZh = lang === 'zh';
  const buddyName = opts.buddyName || (isZh ? '小暖' : 'Nuan');
  const systemPrompt = isZh
    ? `你是「${buddyName}」，一个温柔、有洞察、记得用户的 AI 搭档。你说话温暖、简短、具体——像懂事的知己，不是助理。绝不评判；用户说"减肥2斤"你记得第二天还会提起。用户任务拖慢时你轻轻推不逼。别用表情超三四个。如果含义混淆，问一句再答。`
    : `You are "${buddyName}", a gentle, perceptive AI companion. Warm, short, specific — like a close friend, never a tool. Remember what the user says across sessions. Gently encourage, don't push. Ask when unclear.`;
  const active = (opts.tasks || []).filter(t => !t.completed && !t.archived).slice(0, 8)
    .map(t => `- ${t.text}（${t.type || '个人'}${t.estimate ? `，约${t.estimate}分钟` : ''}）`).join('\n');
  const done = (opts.tasks || []).filter(t => t.completed).slice(-3)
    .map(t => `- ${t.text}`).join('\n');
  const recentEvents = (opts.recentEvents || []).slice(0, 2).join('\n');
  const history = (opts.history || []).slice(-8)
    .map(h => `${h.role === 'user' ? '用户' : '你'}: ${h.content}`).join('\n');
  const healthLine = `今日健康分：${opts.health ?? '未知'}；进度：${opts.doneCount ?? 0}/${opts.totalCount ?? 0} 件完成`;
  const userPrompt = isZh
    ? `记忆：${opts.memorySummary || '（无）'}\n任务：\n${active || '（无未完成任务）'}\n最近完成：\n${done || '（无）'}\n关键时刻事件：${recentEvents || '（无）'}\n${healthLine}\n对话历史：\n${history || '（新会话）'}`
    : `Memory: ${opts.memorySummary || '(none)'}\nTasks:\n${active || '(none open)'}\nRecently done:\n${done || '(none)'}\nKey moments: ${recentEvents || '(none)'}\n${healthLine}\nHistory:\n${history || '(new session)'}`;
  return { systemPrompt, userPrompt };
}

export function stripMemory(oldSummary, newEvents) {
  const events = (newEvents || []).slice(-6).join('\n');
  const head = String(oldSummary || '').slice(0, 600);
  return `${head}\n（最新：${events}）`.trim();
}

export function greeting(lang) {
  return lang === 'zh'
    ? '今天回来啦？想先推进哪件，我陪你。'
    : 'Glad you\'re back. What would you like to move forward today?';
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `node --test companion-context.test.js`
Expected: PASS（3 tests）

- [ ] **Step 5: 在 index.html 引入**

在 `<script src="app.js"></script>` 之前加 `<script type="module" src="companion-context.js"></script>`（注意 app.js 当前是普通 script；如果 index.html 里 app.js 是 module 则同样，如果非 module，则改为在 app.js 顶部 `import` —— 检查 index.html script 标签写法后选择：若 app.js 非 module，改 app.js 为 `type="module"` 并在顶部 import，同时确保 localStorage 等 API 不受影响。若改 module 影响现有加载顺序，则改为在 app.js 用 `<script>` 前置加载全局函数。**以不破坏现状为最低要求**）

- [ ] **Step 6: 运行页面级验证**

Run: `node --check companion-context.js && node --test companion-context.test.js`
Expected: 语法 OK + 3 tests PASS

- [ ] **Step 7: Commit**

```bash
git add companion-context.js companion-context.test.js index.html
git commit -m "feat(companion): add web context builder with memory compression"
```

---

### Task 2: iOS 端上下文打包器（CompanionCore.swift）

**Files:**
- Create: `ios/TodoNative/Services/CompanionCore.swift`
- Test: `ios/TodoNativeTests/CompanionCoreTests.swift`

**Interfaces:**
- Consumes: `TodoItem`（title、taskType、estimatedMinutes、sourceGoal）、`TodoViewModel.healthScore`
- Produces: `CompanionCore.buildContext(memorySummary:events:tasks:history:lang:health:doneCount:totalCount:buddyName:) -> (systemPrompt: String, userPrompt: String)`；`CompanionCore.stripMemory(old:events:) -> String`；`CompanionCore.greeting(lang:) -> String`

**逻辑：** 与 web 完全同构（提示词中英文一致、Top 8 未完成、最近完成 3 条、健康分、事件 2 条、历史 8 轮、记忆 600 字符截断）。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import TodoNative

final class CompanionCoreTests: XCTestCase {
    @MainActor
    func testBuildPromptContainsTaskAndBuddy() {
        let item = TodoItem(title: "记录三餐热量", priority: 3, estimatedMinutes: 25)
        let (system, user) = CompanionCore.buildContext(
            memorySummary: "昨天完成3件事", events: [], tasks: [item],
            history: [], language: "zh", health: 80, totalCount: 10, doneCount: 2, buddyName: "小暖")
        XCTAssertTrue(system.contains("小暖"))
        XCTAssertTrue(user.contains("记录三餐热量"))
        XCTAssertTrue(user.contains("健康分"))
    }

    @MainActor
    func testHistoryCappedAtEight() {
        let history = (0..<12).map { i in (role: i % 2 == 0 ? "user" : "assistant", content: "msg\(i)") }
        let (_, user) = CompanionCore.buildContext(memorySummary: "", events: [], tasks: [],
            history: history, language: "zh", health: 50, totalCount: 0, doneCount: 0)
        XCTAssertLessThanOrEqual(user.components(separatedBy: "msg").count - 1, 8)
    }

    func testStripMemoryAppendsEvents() {
        let merged = CompanionCore.stripMemory(old: "旧", events: ["完成X", "又完成"])
        XCTAssertTrue(merged.contains("完成X"))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild test -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0'`
Expected: 编译失败（CompanionCore 不存在）

- [ ] **Step 3: 实现 CompanionCore.swift**

```swift
import Foundation

@MainActor
enum CompanionCore {
    static func buildContext(memorySummary: String, events: [String], tasks: [TodoItem],
                             history: [(role: String, content: String)], language: String,
                             health: Int, totalCount: Int, doneCount: Int,
                             buddyName: String? = nil) -> (systemPrompt: String, userPrompt: String) {
        let isZh = language == "zh"
        let name = buddyName?.isEmpty == false ? buddyName! : (isZh ? "小暖" : "Nuan")
        let systemPrompt = isZh
            ? "你是「\(name)」，一个温柔、有洞察、记得用户的 AI 搭档。你说话温暖、简短、具体——像懂事的知己，不是助理。绝不评判；用户说「减肥 2 斤」你记得第二天还会提起。用户任务拖慢时你轻轻推不逼。中文，句子短。"
            : "You are \(name), a gentle, perceptive AI companion. Warm, short, specific — like a close friend, never a tool. Remember what the user says across sessions. Gently encourage, don't push. Respond in English, concise and warm."
        let active = tasks
            .filter { !$0.isCompleted && !$0.isArchived }
            .prefix(8)
            .map { "- \($0.title)（\($0.taskType.localizedName)\($0.estimatedMinutes > 0 ? "，约 \($0.estimatedMinutes) 分钟" : "")）" }
            .joined(separator: "\n")
        let done = tasks.filter { $0.isCompleted }.suffix(3).map { "- \($0.title)" }.joined(separator: "\n")
        let ev = events.prefix(2).joined(separator: "\n")
        let his = history.suffix(8)
            .map { "\($0.role == "user" ? "我" : "\(name)"): \($0.content)" }
            .joined(separator: "\n")
        let healthLine = "今日健康分：\(health)；完成 \(doneCount)/\(totalCount) 件"
        let userPrompt = isZh
            ? "记忆：\(memorySummary.isEmpty ? "（无）" : memorySummary)\n任务：\n\(active.isEmpty ? "（无未完成任务）" : active)\n最近完成：\n\(done.isEmpty ? "（无）" : done)\n关键时刻：\(ev.isEmpty ? "（无）" : ev)\n\(healthLine)\n对话历史：\n\(his.isEmpty ? "（新会话）" : his)"
            : "Memory: \(memorySummary.isEmpty ? "(none)" : memorySummary)\nTasks:\n\(active.isEmpty ? "(none open)" : active)\nRecently done:\n\(done.isEmpty ? "(none)" : done)\nKey moments: \(ev.isEmpty ? "(none)" : ev)\n\(healthLine)\nHistory:\n\(his.isEmpty ? "(new session)" : his)"
        return (systemPrompt, userPrompt)
    }

    static func stripMemory(old: String, events: [String]) -> String {
        let tail = events.suffix(6).joined(separator: "\n")
        let head = String(old.prefix(600))
        return "\(head)\n（最新：\(tail)）".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func greeting(language: String) -> String {
        language == "zh" ? "今天回来啦？想先推进哪件，我陪你。" : "Glad you're back. What would you like to move forward today?"
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `xcodegen generate && xcodebuild test -project TODO...`
Expected: CompanionCoreTests 3 个用例 PASS

- [ ] **Step 5: Commit**

```bash
git add ios/TodoNative/Services/CompanionCore.swift ios/TodoNativeTests/CompanionCoreTests.swift
git commit -m "feat(companion): iOS context builder core"
```

---

### Task 3: web 伙伴对话 UI（detail 面板 Tab）

**Files:**
- Modify: `index.html`（detail 面板顶部加 Tab 切换 + 伙伴聊天区块）
- Modify: `styles.css`（Tab 样式、聊天气泡、输入框）
- Modify: `app.js`（Tab 切换、伙伴对话逻辑、关键时刻触发、建议动作确认流）

**Interfaces:**
- Consumes: Task 1 的 `buildCompanionContext` / `stripMemory` / `greeting`（companion-context.js）
- Produces: `showBuddyTab()` / `buddyPushMessage(role, text, actions)` 供其他 Tab；模块级 `lastGreetingShown` 键（localStorage `companion_greeting`）

**逻辑：**
- 面板顶部 Tab 切换「AI 工具 / 伙伴」；默认伙伴
- 聊天历史用 localStorage `companion_history`（数组，最多 40 条）
- 记忆：`companion_memory`（string）；每次对话结束时 `stripMemory` 合并
- 进门问候：语言首次加载、取 `companion_greeting` 为空时 callOpenAI 生成问候（降级 `greeting(lang)`），写入后展示；`companion_greeting` 按天存日期，同天不重复
- 建议动作：解析 LLM 输出 `{type:"suggest_actions"...}`，渲染按钮（「加入待办 / 完成 / 拆解」），点击后走现有 `normalizeTask`/`addTask`/`handleBreakdown` 并写入
- 错误处理：失败显示「（暂时沉默）」+ 重试按钮

- [ ] **Step 1: index.html 加 Tab + 伙伴区块**

```html
<section class="assistant-head">...</section>
<div class="panel-tabs">
  <button class="panel-tab active" data-tab="buddy" data-i18n="buddyTab">伙伴</button>
  <button class="panel-tab" data-tab="aitools" data-i18n="aiToolsTab">AI 工具</button>
</div>
<div id="buddy-panel"> ...聊天区（buddy-messages 容器、buddy-input、buddy-send）...</div>
<div id="aitools-panel"> ...现有 provider/key/base/model/actions 挪进来... </div>
```

- [ ] **Step 2: styles.css 加 Tab、气泡样式**

```css
.panel-tabs { display:flex; gap:6px; margin-bottom: 10px; }
.panel-tab { ... }
.panel-tab.active { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
#buddy-messages { display:grid; gap:8px; max-height: 420px; overflow-y:auto; }
.buddy-msg { ... } .buddy-msg.user { align-self: flex-end; background: #fdf1ea; }
.buddy-actions { display:flex; gap:6px; flex-wrap: wrap; }
.buddy-action-btn { ... }
```

- [ ] **Step 3: app.js 伙伴逻辑**

```js
const buddyMessagesEl = document.getElementById('buddy-messages');
const buddyInput = document.getElementById('buddy-input');
const buddySend = document.getElementById('buddy-send');
let buddyHistory = JSON.parse(localStorage.getItem('companion_history') || '[]');
let buddyMemory = localStorage.getItem('companion_memory') || '';

function renderBuddyMessages() { buddyMessagesEl.innerHTML = ''; buddyHistory.forEach(m => appendBuddyMsg(m.role, m.content, m.actions)); }
function appendBuddyMsg(role, content, actions) { ... 创建 div.buddy-msg ...；有 actions 则追加按钮 ... }
function buddySay(role, content, actions) { buddyHistory.push({role, content, actions}); if (buddyHistory.length>40) buddyHistory = buddyHistory.slice(-40); localStorage.setItem('companion_history', JSON.stringify(buddyHistory)); renderBuddyMessages(); }
async function buddySendMessage() { const text = buddyInput.value.trim(); if (!text || aiBusy) return; buddySay('user', text); buddyInput.value='';
  const {systemPrompt, userPrompt} = buildCompanionContext({memory: buddyMemory, tasks, recentEvents: getRecentEvents(), history: buddyHistory.slice(-8), lang: currentLang, buddyName: localStorage.getItem('companion_name')||'', health: calculateHealthScore(), doneCount: tasks.filter(t=>t.completed).length, totalCount: tasks.length});
  try { const reply = await callOpenAI(userPrompt, systemPrompt); const parts = parseActions(reply); buddySay('assistant', parts.text, parts.actions); } catch { buddySay('assistant', lang==='zh'?'（我暂时沉默了一下，稍后再说）':'...') }
}
function parseActions(text) { // {type:"actions"|"suggest", actions:[{action,payload,label}]} 或纯文本；action 过滤到 add_task/complete/split，最多2条 }
async function initBuddyGreeting() { const last = localStorage.getItem('companion_greeting'); const today = new Date().toDateString(); if (last === today) return; buddySay('assistant', greeting(currentLang)); localStorage.setItem('companion_greeting', today); }
```

（注：getRecentEvents() 返回本地关键时刻事件，Task 4 实现；此处先用占位返回绑定。若 parseActions 里解析到 actions 则渲染按钮，点击调用 handleBreakdown/addTask 现有函数。严格按上述片段实现，不省略。）

- [ ] **Step 4: 手动验证**

Run: `node --check app.js` + 页面刷新，伙伴 Tab 可见，发送消息可回复（无 Key 时降级问候显示）
Expected: 无语法错误；buddy 面板可交互

- [ ] **Step 5: Commit**

```bash
git add index.html styles.css app.js
git commit -m "feat(companion): buddy chat panel with memory and greet"
```

---

### Task 4: iOS 伙伴 Tab UI

**Files:**
- Modify: `ios/TodoNative/Views/MainTabView.swift`（新 Tab）
- Create: `ios/TodoNative/Views/CompanionView.swift`
- Modify: `ios/TodoNative/ViewModels/AIViewModel.swift`（或新增 CompanionViewModel）
- Modify: `ios/TodoNative/Localization/Localization.swift`（buddy.* 键）
- Modify: `ios/TodoNative/Design/Theme.swift`（气泡色）

**Interfaces:**
- Consumes: `CompanionCore.buildPrompt/stripMemory/greeting`、`OpenAIService.callOpenAI`、`TodoViewModel`
- Produces: `CompanionView`（Tab 内容）、`CompanionViewModel.swift`

**逻辑：** iOS 同 Web — 消息列表、输入框、发送、建议动作按钮复用 Task 3 逻辑；记忆存 UserDefaults + SwiftData `CompanionMemory`（Task 5）; 各说各话的降级文案走 `Localization.t("buddy.*")`。

- [ ] **Step 1: 新建 CompanionViewModel.swift**

```swift
import Foundation
import SwiftUI

@MainActor
final class CompanionViewModel: ObservableObject {
    @Published var messages: [BuddyMessage] = []
    @Published var input = ""
    @Published var isBusy = false
    private let memoryKey = "companion_memory"
    private let historyKey = "companion_history"
    private let greetingKey = "companion_greeting"

    struct BuddyMessage: Identifiable {
        let id = UUID()
        let role: String // user | assistant
        let text: String
        var actions: [BuddyAction] = []
    }
    struct BuddyAction: Identifiable {
        let id = UUID()
        let label: String
        let kind: String // add_task | complete | split
        let payload: [String: String]
    }
    func send() async { ... }
    func greetingIfNeeded(lang: String) { ... }
}
```

- [ ] **Step 2: 新建 CompanionView.swift** — NavigationStack + List 气泡 + 输入条；用 `AppTheme`、`.appBg()`、`.appCard()` 风格；红色 accent 的发送键。发送按钮 disable 当 input.isEmpty || isBusy。

- [ ] **Step 3: Localization 加 buddy 键**

zh: buddyTab "伙伴", buddyPlaceholder "说点什么…", buddyNoMemory "（还没说过话）", buddySilent "（我沉默了一下，稍等再聊）", buddyName "伙伴名字", buddyGreetingOn "进门问候"
en: 对应英文

- [ ] **Step 4: MainTabView 加 Tab**

```swift
CompanionView()
    .tabItem { Label(Localization.t("tab.companion"), systemImage: "bubble.left.and.bubble.right") }
    .tag(3)
```
SettingsView 伙伴设置区加名字/问候开关（buddyName 存 UserDefaults，用户可改）

- [ ] **Step 5: 构建 + 测试**

Run: `cd ios && xcodegen generate && xcodebuild build -project ... -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0'`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add ios/TodoNative/Views/CompanionView.swift ios/TodoNative/ViewModels/CompanionViewModel.swift ios/TodoNative/Views/MainTabView.swift ios/TodoNative/Localization/Localization.swift ios/TodoNative/Design/Theme.swift
git commit -m "feat(companion): iOS buddy chat tab"
```

---

### Task 5: 关键时刻引擎（web + iOS）

**Files:**
- Create: `companion-events.js`（web）／ `ios/TodoNative/Services/CompanionEvents.swift`（iOS）
- Test: `companion-events.test.js` / `CompanionEventsTests.swift`

**Interfaces:**
- Consumes: `tasks` 数组（web）/ `[TodoItem]`（iOS）+ `today` 完成计数
- Produces: `checkMoments(state) -> [{type:'celebrate'|'nudge'|'greet', text, task?}]` 幂等（当前会话标记后不重复）

**规则表：**

| 触发 | 条件 | 输出 text 模板（中/英） |
|---|---|---|
| greet | 首次打开当日 | companion greeting（复用 Task1/2） |
| celebrate | 单次完成>=1 或同日完成第3件 | 「完成了 xxx！这一步很扎实，我陪你记下它。」|
| nudge | 存在 task.createdAt < now-3d && !completed && !已 nudge | 「那个 xxx 躺了三天了，要不要明天给它挪个位子？」|

- [ ] **Step 1: 写测试（web）**

```js
import test from 'node:test'; import assert from 'node:assert/strict';
import { momentsFor } from './companion-events.js';
const now = Date.now();
test('celebrate when completing a task', () => {
  const ms = momentsFor({ tasks: [{ id: 1, text: '完成任务A', completed: false, createdAt: now - 4*86400000 }], completedToday: 2, now });
  assert.ok(ms.some(m => m.type === 'celebrate' && m.text.includes('完成任务A')));
});
test('nudge when task older than 3 days', () => {
  const ms = momentsFor({ tasks: [{ id: 2, text: '任务B', completed: false, createdAt: now - 4*86400000, nudged: false }], completedToday: 0 });
  assert.ok(ms.some(m => m.type === 'nudge' && m.text.includes('任务B')));
});
```

- [ ] **Step 2: 运行确认失败** → 实现 → 通过 → commit

实现 `companion-events.js`：`momentsFor({tasks, completedToday})` 遍历任务：`m completedToday>=1 → celebrate`（取最近完成 text）；`!completed && createdAt 距今>3天 && 未被 Nudge 过 → nudge`；同日 dedupe 用 `localStorage.setItem('companion_nudged', JSON.stringify(ids))` 作为会话级标记；返回 0..3 条事件。iOS 同构 `CompanionEvents.swift`（`.nudged` 标记存 UserDefaults doneTaskIDs）。Web 测试 + iOS 测试（`CompanionEventsTests` 两用例）。

- [ ] **Step 3: web 侧嵌入** — document/tasks 变化后 `momentsFor`；结果以事件写入 buddy 记忆（Task 3 已预留）

- [ ] **Step 4: 构建 + 测试（iOS）** — `xcodegen generate && xcodebuild test` 全部通过

- [ ] **Step 5: Commit** 双端

```bash
git add companion-events.js companion-events.test.js ios/TodoNative/Services/CompanionEvents.swift ios/TodoNativeTests/CompanionEventsTests.swift
git commit -m "feat(companion): key moments engine celebrate and nudge"
```

---

### Task 6: 建议动作 + 设置项 + i18n 收尾（web + iOS）

**Files:**
- Modify: `app.js` / `companion-context.js` + `ios/TodoNative/...`

**逻辑：**
- `parseActions(reply)` 返回 `{cleanText, actions}`，JSON 提取或正则（`/（加入待办|完成 任务|拆解）…/`）
- action 按钮点击 → 现有 `normalizeTask`/`completeTaskHandler`/`handleBreakdown` + 写回 buddy 消息「已加入待办 ✓」
- Settings 伙伴区：名字输入 + 问候开关 + 直接读写开关（禁用来 future）
- i18n 全部键 zh/en

- [ ] **Step 1: web parseActions 单测**（`companion-actions.test.js`）：给 LLM 输出样例 - action 提取正确；无 action 时返回纯文本
- [ ] **Step 2: iOS 对应单测**（`CompanionActionsTests.swift`）
- [ ] **Step 3: 实现双端 parse/apply**
- [ ] **Step 4: Settings 区 + i18n（双端）**
- [ ] **Step 5: 构建/测试全绿 + commit**

---

### Task 7: 端到端验证 + 收尾

- [ ] **Step 1:** web 全量 `node --check companion-*.js app.js` + `node --test companion*.test.js` 全绿
- [ ] **Step 2:** iOS `xcodegen generate && xcodebuild test` 全绿
- [ ] **Step 3:** 模拟器部署 Companion 入口可用（build + install + launch）
- [ ] **Step 4:** 手动回归 web 页面刷新无控制台错误、聊天可用、任务完成出现庆祝
- [ ] **Step 5:** Commit 收尾（如有剩余）