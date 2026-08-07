# AI-native Todo

一个支持任务标签、上下文、AI 辅助与导出的双语待办应用。

This is a bilingual todo app with task types, context fields, AI assist and one-click Obsidian export.

## 项目定位 | Why this project

- 任务入口从“想到啥就写啥”到“可执行的下一步”
- 支持任务类型、优先级、预估时长、项目维度
- 支持上下文、验收标准、下一步 AI prompt
- 支持今日计划视图与状态看板
- 支持 AI 规划（可选 OpenAI）和本地降级方案
- 一键导出 Obsidian Markdown
- 支持中文/English 两种界面

## Repository name (规范)

当前仓库约定名建议使用：`todo-list-app`

Current recommended repository name: `todo-list-app`

> 说明：当前本地目录为 `todolist_app`，后续若需与 GitHub 名称完全一致，可在 GitHub 侧重命名。

## Feature overview

- ✅ Add task
- ✅ Mark as completed / delete
- ✅ Filter: All / Active / Completed / High Priority
- ✅ Type filter (Personal / Code / Product / Learn / Life)
- ✅ AI assistant actions: breakdown, summary, today plan
- ✅ Context area: context / acceptance criteria / next prompt
- ✅ Health score and quick suggestions
- ✅ Export current queue as Obsidian Markdown
- ✅ Bilingual UI (Chinese + English)

## 快速开始 | Quick start

1. 启动服务

```bash
cd /Users/lizhi/code/todolist_app
python3 -m http.server
```

2. 打开：`http://localhost:8000`

## 截图 | Screenshots

### Main / Main

![Main interface](screenshots/main-interface.svg)

### Completed list / Completed tasks

![Completed tasks](screenshots/completed-tasks.svg)

## 核心功能

### 中文

- 支持任务类型（个人 / 代码 / 产品 / 学习 / 生活）
- 支持任务优先级与预估
- 支持任务上下文、验收标准、AI 下一步 Prompt
- 支持任务队列 AI 拆解、复盘、今日计划生成（有 OpenAI Key 时调用 API，无 Key 时使用本地规划器）
- 支持今日计划 Top5 视图
- 支持 Obsidian Markdown 一键导出（`todo-list-app-YYYY-MM-DD.md`）

### English

- Support task types (Personal / Code / Product / Learning / Life)
- Track task priority and estimate
- Maintain task context, acceptance criteria, and next prompt
- AI assist: breakdown, review, and today plan (OpenAI if key exists, local fallback otherwise)
- Today plan Top 5 panel
- One-click export Markdown for Obsidian (`todo-list-app-YYYY-MM-DD.md`)

## 文件结构 | Project structure

```text
/
├── index.html       # UI shell and i18n labels
├── styles.css       # Visual style
├── app.js           # All interaction and i18n runtime logic
└── README.md        # Project docs
```

## Language toggle

Click the language selector in the left sidebar to switch between:

- 中文（`zh`）
- English（`en`）

语言配置会持久化到浏览器本地存储。

The selected language is persisted in localStorage.

