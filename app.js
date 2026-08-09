document.addEventListener('DOMContentLoaded', () => {
    const taskInput = document.getElementById('task-input');
    const taskTypeSelect = document.getElementById('task-type');
    const taskDueInput = document.getElementById('task-due');
    const taskDueTimeInput = document.getElementById('task-due-time');
    const addTaskBtn = document.getElementById('add-task');
    const taskList = document.getElementById('task-list');
    const filterBtns = document.querySelectorAll('.filter-btn');
    const typeFilterSelect = document.getElementById('type-filter');
    const taskCount = document.getElementById('task-count');
    const clearCompletedBtn = document.getElementById('clear-completed');
    const quickFocusBtn = document.getElementById('quick-focus');
    const planTodayBtn = document.getElementById('plan-today');
    const todayPlanList = document.getElementById('today-plan-list');
    const todayPlanDate = document.getElementById('today-plan-date');

    const statTotal = document.getElementById('stat-total');
    const statActive = document.getElementById('stat-active');
    const statCompleted = document.getElementById('stat-completed');
    const statHealth = document.getElementById('stat-health');
    const sideHealth = document.getElementById('side-health');
    const sideHealthLabel = document.getElementById('side-health-label');
    const nextAction = document.getElementById('next-action');
    const progressFill = document.getElementById('progress-fill');
    const progressText = document.getElementById('progress-text');
    const progressTrack = document.querySelector('.progress-track');
    const currentDate = document.getElementById('current-date');

    const openaiKeyInput = document.getElementById('openai-key');
    const aiProviderSelect = document.getElementById('ai-provider');
    const aiBaseUrlInput = document.getElementById('ai-base-url');
    const aiModelInput = document.getElementById('ai-model');
    const goalInput = document.getElementById('goal-input');
    const aiBreakdownBtn = document.getElementById('ai-breakdown');
    const aiSummaryBtn = document.getElementById('ai-summary');
    const aiStatus = document.getElementById('ai-status');
    const aiOutput = document.getElementById('ai-output');
    const addAiTasksBtn = document.getElementById('add-ai-tasks');

    const selectedTaskLabel = document.getElementById('selected-task-label');
    const taskContextInput = document.getElementById('task-context');
    const taskAcceptanceInput = document.getElementById('task-acceptance');
    const taskPromptInput = document.getElementById('task-prompt');
    const saveNotesBtn = document.getElementById('save-notes');
    const exportObsidianBtn = document.getElementById('export-obsidian');

    const buddyPanel = document.getElementById('buddy-panel');
    const aitoolsPanel = document.getElementById('aitools-panel');
    const buddyMessagesEl = document.getElementById('buddy-messages');
    const buddyInput = document.getElementById('buddy-input');
    const buddySendBtn = document.getElementById('buddy-send');
    const buddyMic = document.getElementById('buddy-mic');
    const panelTabs = document.querySelectorAll('.panel-tab');
    const notifToggleBtn = document.getElementById('notif-toggle');

    const STORAGE_KEYS = {
        TASKS: 'tasks',
        OPENAI_KEY: 'openai_api_key',
        LANG: 'todo_i18n_lang',
        AI_PROVIDER: 'ai_provider',
        AI_BASE_URL: 'ai_base_url',
        AI_MODEL: 'ai_model'
    };
    const langSelect = document.getElementById('lang-select');

    // ---------- 额度客户端（QuotaProxy） ----------
    // 设备匿名 ID：localStorage 无 id 时用 crypto.randomUUID() 生成并保存
    function quotaDeviceId() {
        return typeof window.getDeviceId === 'function'
            ? window.getDeviceId(localStorage)
            : (localStorage.getItem('todo_device_id') || createId());
    }

    // 代理请求对象：baseUrl 为空 = 未启用托管额度
    const QuotaProxy = {
        baseUrl() {
            return localStorage.getItem('quota_base_url') || '';
        },
        configure(base) {
            const value = String(base || '').trim();
            if (value) localStorage.setItem('quota_base_url', value);
            else localStorage.removeItem('quota_base_url');
            return value;
        },
        deviceId() {
            return quotaDeviceId();
        },
        request(body) {
            const base = this.baseUrl();
            if (typeof window.proxyRequest === 'function') {
                return window.proxyRequest({ baseUrl: base, deviceId: this.deviceId(), body });
            }
            throw new Error(t('quota.exceeded'));
        },
        async quota() {
            const snapshot = await window.fetchQuota({ baseUrl: this.baseUrl(), deviceId: this.deviceId() });
            return snapshot;
        }
    };
    window.QuotaProxy = QuotaProxy;

    const I18N = {
        zh: {
            appTitle: 'AI-native Todo',
            personalWorkspace: '个人工作台',
            language: '语言',
            quickFocus: '+ 捕捉想法',
            mainNav: '主导航',
            mainNavAria: '主导航',
            navTodayPlan: '今日计划',
            navInbox: 'AI 收件箱',
            navAgentNotes: 'Agent Notes',
            navHealth: '健康分',
            myProjects: '我的项目',
            todayAIAdvice: '今日 AI 建议',
            healthWait: '等待任务输入',
            healthGood: '节奏很稳',
            healthForward: '可以推进',
            healthNeedContext: '需要补上下文',
            healthBreakDown: '先降噪拆小',
            healthLabel: '健康分',
            generateTodayPlan: '生成今日计划',
            inboxTag: '自然语言收件箱',
            headline: '把脑内噪音变成可执行下一步',
            taskInputPlaceholder: '例如：梳理 AI-native todo 的今天目标',
            captureTask: '捕捉',
            taskTypeLabel: '任务类型',
            executionStatus: '执行态势',
            progressText: '完成率 {completionRate}% · 健康分 {healthScore}',
            progressAriaLabel: '任务完成进度',
            statTotal: '全部任务',
            statActive: '进行中',
            statCompleted: '已完成',
            statHealth: '健康分',
            todayPlan: '今日计划视图',
            todayTop5: '今日 Top 5',
            filterAll: '全部',
            filterActive: '进行中',
            filterCompleted: '已完成',
            filterHigh: '高优先级',
            allTypes: '全部类型',
            taskQueue: '任务队列',
            tasksInProgress: '{count} 个任务进行中',
            clearCompleted: '清除已完成',
            aiAssistantTag: 'AI 助手',
            assistantName: 'Agent Copilot',
            assistantDesc: '拆解目标、生成今日计划，并保存每个任务的执行上下文。',
            openaiKeyLabel: 'API Key',
            aiProviderLabel: 'AI 服务商',
            aiBaseUrlLabel: 'Base URL（OpenAI 兼容）',
            aiModelLabel: '模型',
            goalLabel: '目标 / 需求 / 想法',
            goalInputPlaceholder: '例如：本周发布一个迭代说明，并同步给相关同伴。',
            aiBreakdown: '智能拆解',
            aiSummary: '复盘 / 下一步',
            aiOutput: 'AI 输出',
            aiOutputEmpty: '还没有内容。没有 API Key 时会使用本地规划器；填入 Key 后会调用所选服务商。',
            addToTodo: '加入待办',
            exportObsidian: '一键导出 Obsidian Markdown',
            notesPanelTitle: 'Agent Notes',
            noTaskSelected: '未选择任务',
            selectedTaskPrefix: '当前任务',
            contextLabel: '上下文',
            contextPlaceholder: '补充任务背景、输入来源、关联文档链接',
            acceptanceLabel: '验收标准',
            acceptancePlaceholder: '补充明确的可验收标准：如预期输出、验证方式、完成定义',
            promptLabel: '下一条给 AI 的 prompt',
            promptPlaceholder: '例如：请继续拆解这个任务的下一步。',
            saveNotes: '保存上下文',
            fallbackNextAction: '先捕捉一个目标，我来帮你压成下一步。',
            noTaskHint: '还没有任务。先捕捉一个目标，我会把它压成可执行下一步。',
            noTaskExample: '例：今天完成 AI-native todo 的 Agent Notes 体验',
            taskContextReady: '已补上下文',
            taskContextMissing: '未补上下文',
            acceptanceReady: '已补验收标准',
            acceptanceMissing: '未补验收标准',
            chipContext: '上下文',
            chipAcceptance: '验收',
            chipPrompt: 'Prompt',
            chipSource: '源自：{goal}',
            notesBtn: '上下文',
            splitBtn: '拆小',
            deleteBtn: '删除',
            noTaskInPlan: '暂无进行中任务。先添加任务并设置类型/上下文。',
            planTopItem: '{index}. {text}（{effort} · {priority}）',
            planBadgeNoContext: '未补上下文',
            planBadgeNoAcceptance: '未补验收标准',
            aiWorking: '处理中...',
            aiBreakdownBusy: '正在调用 AI 拆解...',
            aiBreakdownLocal: '使用本地规划器拆解...',
            aiSummaryBusy: '正在生成复盘...',
            aiSummaryLocal: '使用本地状态生成复盘...',
            aiPlanBusy: '正在生成今日计划...',
            aiPlanLocal: '使用本地队列生成今日计划...',
            aiPlanDone: '今日计划已生成。',
            aiNoTaskToBreakdown: '先输入一个目标或想法。',
            aiNoImport: '当前没有可导入的 AI 任务。请先执行“智能拆解”。',
            aiImported: 'AI 任务已加入待办。',
            aiSaved: 'Agent Notes 已保存。',
            aiNoSave: '先选中一个任务再保存。',
            aiExported: '已导出：{fileName}，可直接放入 Obsidian。',
            aiExportEmpty: '队列清空了。可以做一次复盘，或者捕捉下一个目标。',
            aiExportGenerated: '队列清空了。可以做一次复盘，或者捕捉下一个目标。',
            nextActionEmpty: '队列清空了。可以做一次复盘，或者捕捉下一个目标。',
            nextActionNoContext: '下一步：给「{text}」补 1 条上下文或验收标准。',
            nextActionWithEffort: '下一步：推进「{text}」，建议投入 {effort}。',
            noTaskInPlan: '暂无进行中任务。先添加任务并设置类型/上下文。',
            noActiveTasks: '当前暂无进行中任务。',
            currentActiveTasks: '当前已有进行中任务：{tasks}',
            noTasksLabel: '暂无',
            empty: '暂无',
            activeTasksLabel: '进行中任务',
            completedTasksLabel: '已完成任务',
            localBreakdownStep1: '明确「{subject}」的完成定义和不可做范围',
            localBreakdownStep2: '列出当前已有资料、相关文件、约束和风险',
            localBreakdownStep3: '拆出 1 个 30 分钟内能完成的最小版本',
            localBreakdownStep4: '完成核心实现，并记录关键决策到 Agent Notes',
            localBreakdownStep5: '补一条验收标准和一次手动验证记录',
            localBreakdownStep6: '复盘剩余问题，生成下一条交给 AI 的 prompt',
            aiBreakdownResult: '已生成 {count} 条任务，可一键加入待办。',
            localSummaryLine1: '进展概览：已完成 {completed} 条，进行中 {active} 条。当前健康分 {health}，{healthLabel}。',
            localSummaryTitle: '下一步建议：',
            localSummaryStep1: '1. 先推进高优先级任务：{text}',
            localSummaryStep1Fallback: '1. 选择一个最小任务推进，不要同时开太多分支。',
            localSummaryStep2: '2. 给「{text}」补上下文和验收标准。',
            localSummaryStep2Fallback: '2. 已有任务上下文不错，可以直接进入执行。',
            localSummaryStep3: '3. 今日只保留 3 个主任务：{tasks}',
            aiSummaryDone: '复盘已生成。',
            planItem: '{index}. {text}（{effort} · {priority}）',
            planFirstStep: '第一步：{next}',
            todayPlanPrompt: '你是今日计划助手。请只保留最关键的 3-5 件事，按上午/下午/收尾组织，最后给出第一步。中文输出。',
            aiBreakdownPrompt: '你是 AI-native todo 的任务规划助手。请给出 5-8 条可执行、可勾选的短任务清单，每行一条，不要额外解释。任务要包含明确动作，避免空泛。语言用中文。',
            aiSummaryPrompt: '你是项目助理。请输出：1）进展概览（2-3句）；2）下一步建议（3条）；3）最适合交给 AI 的下一条 prompt。语言简洁。',
            buildDefaultPrompt: '请帮我完成这个任务：{text}\\n类型：{type}\\n项目：{project}\\n优先级：{priority}\\n请先确认目标，再给出最小可执行步骤和验收方式。',
            planEstimateLabel: '预估',
            buildAiPromptForTask: '请帮我执行这条任务：{text}\\n先给出最小步骤，再说明如何验证完成。',
            obsidianTitle: 'Todo 导出',
            obsidianExportTime: '导出时间',
            obsidianTaskList: '任务清单',
            obsidianStatusLabel: '状态',
            obsidianStatusDone: '[x] 已完成',
            obsidianStatusActive: '[ ] 进行中',
            obsidianProjectLabel: '项目',
            obsidianPriorityLabel: '优先级',
            obsidianEffortLabel: '预计时长',
            aiNoAction: '当前没有可导入的 AI 任务。请先执行“智能拆解”。',
            taskSavedToLocal: '已使用本地规划器，当前任务队列已同步。',
            aiErrorCallFailed: 'AI 请求失败（{status}）：{error}',
            aiErrorEmpty: 'AI 返回内容为空，请重试。',
            aiErrorFallback: '调用失败，请稍后重试。',
            aiErrorNoBaseUrl: '请填写 Base URL。',
            aiErrorNoModel: '请填写模型名称。',
            aiStatusSaved: '已保存',
            taskType: {
                personal: '个人',
                code: '代码',
                product: '产品',
                learning: '学习',
                life: '生活'
            },
            placeholderOpenAiKey: 'sk-...',
            priorityHigh: '高优先级',
            priorityMedium: '中优先级',
            priorityLow: '低优先级',
            contextLabelShort: '上下文',
            acceptanceLabelShort: '验收',
            planSummaryTitle: '今日计划：',
            emptyTaskPlan: '队列为空。捕捉一个目标。',
            buddyTab: '伙伴',
            aiToolsTab: 'AI 工具',
            buddyPlaceholder: '说点什么…',
            buddySend: '发送',
            buddySilent: '（我暂时沉默了一下，稍后再聊）',
            buddyRetry: '重试',
            buddyEmpty: '还没说过话。先打个招呼吧。',
            buddyAdded: '已加入待办：{text}',
            buddyAddTaskBtn: '加入待办',
            buddyNoKey: '还没配 API Key。到 AI 设置里填一个，我就能陪你聊了。',
            buddyTyping: '伙伴正在输入…',
            taskDueLabel: '截止',
            taskDueTimeLabel: '时间',
            editBtn: '编辑',
            editTitlePrompt: '新的任务名称：',
            editDuePrompt: '新截止日期（YYYY-MM-DD 或 YYYY-MM-DD HH:mm，留空清除）：',
            notificationDueTitle: '任务到期',
            notificationDueBody: '「{text}」今天到期',
            notifEnable: '开启到期提醒',
            notifEnabled: '到期提醒已开启',
            notifDenied: '通知被浏览器禁用，点此查看',
            notifDeniedMsg: '通知权限已被浏览器拒绝，是否重新尝试请求？',
            notifUnavailable: '当前环境不支持通知',
            quota: {
                freeLimit: '免费额度：{used}/{limit}',
                exceeded: 'AI 额度已用完',
                exceededFree: '免费额度已用完：订阅 Pro 或填自己的 API Key',
                exceededDaily: '今日额度已用完，明天恢复',
                proxyHint: '正在使用 App 托管额度（DeepSeek V4 Flash）',
                signIn: '登录',
                goSettings: '去 AI 设置',
                close: '关闭'
            }
        },
        en: {
            appTitle: 'AI-native Todo',
            personalWorkspace: 'Personal Workspace',
            language: 'Language',
            quickFocus: '+ Capture idea',
            mainNav: 'Main navigation',
            mainNavAria: 'Main navigation',
            navTodayPlan: 'Today Plan',
            navInbox: 'AI Inbox',
            navAgentNotes: 'Agent Notes',
            navHealth: 'Health Score',
            myProjects: 'My Projects',
            todayAIAdvice: 'Today AI Advice',
            healthWait: 'Waiting for tasks',
            healthGood: 'Steady pace',
            healthForward: 'Ready to move',
            healthNeedContext: 'Need more context',
            healthBreakDown: 'Decompose task chunks',
            healthLabel: 'Health',
            generateTodayPlan: 'Generate Today Plan',
            inboxTag: 'Natural language inbox',
            headline: 'Turn scattered thoughts into executable next steps',
            taskInputPlaceholder: 'For example: clarify goals for today around AI-native todo',
            captureTask: 'Capture',
            taskTypeLabel: 'Task Type',
            executionStatus: 'Execution status',
            progressText: 'Completion {completionRate}% · Health {healthScore}',
            progressAriaLabel: 'Task completion progress',
            statTotal: 'All tasks',
            statActive: 'Active',
            statCompleted: 'Done',
            statHealth: 'Health Score',
            todayPlan: 'Today Plan',
            todayTop5: 'Today Top 5',
            filterAll: 'All',
            filterActive: 'Active',
            filterCompleted: 'Completed',
            filterHigh: 'High priority',
            allTypes: 'All types',
            taskQueue: 'Task Queue',
            tasksInProgress: '{count} active tasks',
            clearCompleted: 'Clear completed',
            aiAssistantTag: 'AI Assistant',
            assistantName: 'Agent Copilot',
            assistantDesc: 'Break down goals, generate a daily plan, and save execution context for each task.',
            openaiKeyLabel: 'API Key',
            aiProviderLabel: 'AI Provider',
            aiBaseUrlLabel: 'Base URL (OpenAI compatible)',
            aiModelLabel: 'Model',
            goalLabel: 'Goal / Requirement / Idea',
            goalInputPlaceholder: 'For example: release an iteration note and share with team.',
            aiBreakdown: 'AI Breakdown',
            aiSummary: 'Review / Next step',
            aiOutput: 'AI Output',
            aiOutputEmpty: 'No output yet. Without API key, a local planner is used.',
            addToTodo: 'Add to Todo',
            exportObsidian: 'Export Obsidian Markdown',
            notesPanelTitle: 'Agent Notes',
            noTaskSelected: 'No task selected',
            selectedTaskPrefix: 'Current task',
            contextLabel: 'Context',
            contextPlaceholder: 'Add task context, sources, and related docs',
            acceptanceLabel: 'Acceptance Criteria',
            acceptancePlaceholder: 'Add clear acceptance criteria: expected output, validation method, completion definition',
            promptLabel: 'Next AI prompt',
            promptPlaceholder: 'For example: continue to split this task into smaller steps.',
            saveNotes: 'Save Notes',
            fallbackNextAction: 'Capture one goal first, then I can break it into next steps.',
            noTaskHint: "No tasks yet. Capture one goal and I'll convert it into next steps.",
            noTaskExample: 'Example: complete the Agent Notes experience in AI-native todo today',
            taskContextReady: 'Context added',
            taskContextMissing: 'Context missing',
            acceptanceReady: 'Acceptance added',
            acceptanceMissing: 'Acceptance missing',
            chipContext: 'Context',
            chipAcceptance: 'Acceptance',
            chipPrompt: 'Prompt',
            chipSource: 'From: {goal}',
            notesBtn: 'Notes',
            splitBtn: 'Split',
            deleteBtn: 'Delete',
            noTaskInPlan: 'No active tasks yet. Add a task and set type/context first.',
            planTopItem: '{index}. {text} ({effort} · {priority})',
            planBadgeNoContext: 'No context',
            planBadgeNoAcceptance: 'No acceptance',
            aiWorking: 'Processing...',
            aiBreakdownBusy: 'Calling AI to split tasks...',
            aiBreakdownLocal: 'Using local planner...',
            aiSummaryBusy: 'Generating review...',
            aiSummaryLocal: 'Using local review generator...',
            aiPlanBusy: 'Generating today plan...',
            aiPlanLocal: 'Using local plan generator...',
            aiPlanDone: 'Today plan generated.',
            aiNoTaskToBreakdown: 'Please enter a goal or idea first.',
            aiNoImport: 'No AI tasks available. Run "AI Breakdown" first.',
            aiImported: 'AI tasks added to todo.',
            aiSaved: 'Agent Notes saved.',
            aiNoSave: 'Please select a task first.',
            aiExported: 'Exported: {fileName}. You can import it into Obsidian.',
            aiExportEmpty: 'The queue is empty. Review or capture a new goal.',
            aiExportGenerated: 'The queue is empty. Review or capture a new goal.',
            nextActionEmpty: 'The queue is empty. You can review completed work or capture a new goal.',
            nextActionNoContext: 'Next: add one context or acceptance criteria to "{text}".',
            nextActionWithEffort: 'Next: proceed with "{text}", estimated effort {effort}.',
            noTaskInPlan: 'No active tasks yet. Add a task and set type/context first.',
            noActiveTasks: 'No active tasks.',
            currentActiveTasks: 'Current active tasks: {tasks}',
            noTasksLabel: 'None',
            empty: 'None',
            activeTasksLabel: 'Active tasks',
            completedTasksLabel: 'Completed tasks',
            localBreakdownStep1: 'Clarify the completion definition and out-of-scope for "{subject}".',
            localBreakdownStep2: 'List current references, constraints, and risks.',
            localBreakdownStep3: 'Extract one minimum task that can finish within 30 minutes.',
            localBreakdownStep4: 'Implement core work and record key decisions in Agent Notes.',
            localBreakdownStep5: 'Add one acceptance criterion and one manual verification note.',
            localBreakdownStep6: 'Review remaining gaps and generate the next AI prompt.',
            aiBreakdownResult: 'Generated {count} tasks, ready to import.',
            localSummaryLine1: 'Progress: completed {completed} tasks, active {active} tasks. Health score is {health}. {healthLabel}.',
            localSummaryTitle: 'Next suggestions:',
            localSummaryStep1: '1. Prioritize the urgent task: {text}',
            localSummaryStep1Fallback: '1. Pick one smallest task and continue; avoid too many contexts.',
            localSummaryStep2: '2. Add context and acceptance criteria for "{text}".',
            localSummaryStep2Fallback: '2. Task context is enough, start execution directly.',
            localSummaryStep3: '3. Keep only 3 main tasks today: {tasks}',
            aiSummaryDone: 'Review generated.',
            planItem: '{index}. {text} ({effort} · {priority})',
            planFirstStep: 'First step: {next}',
            todayPlanPrompt: 'You are a daily planning assistant. Keep only the top 3-5 items, organize by morning/afternoon/wrap up, and output the first step.',
            aiBreakdownPrompt: 'You are a task-planning assistant. Return 5-8 concrete checklist items, one line each. No extra explanation. Keep the output in English.',
            aiSummaryPrompt: 'You are a project assistant. Output: 1) a short progress summary (2-3 lines), 2) next suggestions (3 items), 3) a practical next prompt for AI.',
            buildDefaultPrompt: 'Please help me complete this task: {text}\\nType: {type}\\nProject: {project}\\nPriority: {priority}\\nConfirm objective first, then provide minimal executable steps and acceptance criteria.',
            planEstimateLabel: 'Est.',
            buildAiPromptForTask: 'Please execute this task: {text}\\nFirst provide minimal steps, then verification checks.',
            obsidianTitle: 'Todo Export',
            obsidianExportTime: 'Export time',
            obsidianTaskList: 'Task list',
            obsidianStatusLabel: 'Status',
            obsidianStatusDone: '[x] Done',
            obsidianStatusActive: '[ ] Active',
            obsidianProjectLabel: 'Project',
            obsidianPriorityLabel: 'Priority',
            obsidianEffortLabel: 'Estimate',
            aiNoAction: 'No AI tasks available. Run AI Breakdown first.',
            taskSavedToLocal: 'Using local planner, todo queue synced.',
            aiErrorCallFailed: 'AI request failed ({status}): {error}',
            aiErrorEmpty: 'Empty AI output, please retry.',
            aiErrorFallback: 'Failed to generate result, please retry later.',
            aiErrorNoBaseUrl: 'Please fill in the Base URL.',
            aiErrorNoModel: 'Please fill in the model name.',
            aiStatusSaved: 'Saved',
            taskType: {
                personal: 'Personal',
                code: 'Code',
                product: 'Product',
		learning: 'Learning',
                life: 'Life'
            },
            placeholderOpenAiKey: 'sk-...',
            priorityHigh: 'High',
            priorityMedium: 'Medium',
            priorityLow: 'Low',
            contextLabelShort: 'Context',
            acceptanceLabelShort: 'Acceptance',
            planSummaryTitle: 'Today plan:',
            emptyTaskPlan: 'No active tasks. Capture one goal first.',
            buddyTab: 'Buddy',
            aiToolsTab: 'AI Tools',
            buddyPlaceholder: 'Say something…',
            buddySend: 'Send',
            buddySilent: '（I went quiet for a moment — talk again soon）',
            buddyRetry: 'Retry',
            buddyEmpty: 'No messages yet. Say hello.',
            buddyAdded: 'Added to todos: {text}',
            buddyAddTaskBtn: 'Add to todos',
            buddyNoKey: 'No API key yet. Add one in AI settings and I\'ll be here.',
            buddyTyping: 'Buddy is typing…',
            taskDueLabel: 'Due',
            taskDueTimeLabel: 'Time',
            editBtn: 'Edit',
            editTitlePrompt: 'New task name:',
            editDuePrompt: 'New due date (YYYY-MM-DD or YYYY-MM-DD HH:mm, empty to clear):',
            notificationDueTitle: 'Task due',
            notificationDueBody: '"{text}" is due today',
            notifEnable: 'Enable due reminders',
            notifEnabled: 'Due reminders on',
            notifDenied: 'Notifications blocked — click for details',
            notifDeniedMsg: 'Notification permission is blocked by the browser. Try requesting again?',
            notifUnavailable: 'Notifications not supported here',
            quota: {
                freeLimit: 'Free quota: {used}/{limit}',
                exceeded: 'AI quota used up',
                exceededFree: 'Free quota used up: subscribe to Pro or add your own API Key',
                exceededDaily: 'Daily quota used up, back again tomorrow',
                proxyHint: 'Using app-managed quota (DeepSeek V4 Flash)',
                signIn: 'Sign in',
                goSettings: 'Open AI settings',
                close: 'Close'
            }
        }
    };
    let currentLang = localStorage.getItem(STORAGE_KEYS.LANG) === 'en' ? 'en' : 'zh';

    const FILTERS = {
        ALL: 'all',
        ACTIVE: 'active',
        COMPLETED: 'completed',
        HIGH: 'high'
    };

    // 多家 OpenAI 兼容服务商：标记请求走 chat/completions
    const AI_PROVIDERS = {
        openai: { name: 'OpenAI', baseUrl: 'https://api.openai.com/v1', model: 'gpt-4.1-mini' },
        deepseek: { name: 'DeepSeek', baseUrl: 'https://api.deepseek.com', model: 'deepseek-v4-flash' },
        moonshot: { name: 'Moonshot (Kimi)', baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k' },
        zhipu: { name: 'Zhipu GLM', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-flash' },
        qwen: { name: 'Qwen', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-plus' },
        groq: { name: 'Groq', baseUrl: 'https://api.groq.com/openai/v1', model: 'llama-3.3-70b-versatile' },
        siliconflow: { name: 'SiliconFlow', baseUrl: 'https://api.siliconflow.cn/v1', model: 'deepseek-ai/DeepSeek-V3' },
        custom: { name: 'Custom', baseUrl: '', model: '' }
    };
    const DEFAULT_PROVIDER = 'openai';
    const PRIORITY_ORDER = { high: 0, medium: 1, low: 2 };
    const TASK_TYPES = ['个人', '代码', '产品', '学习', '生活'];
    const DEFAULT_TASK_TYPE = '个人';

    let currentFilter = FILTERS.ALL;
    let currentTypeFilter = 'all';
    let tasks = loadTasks();
    let aiSuggestedTasks = [];
    let lastBreakdownGoal = '';
    let buddyHistory = [];
    let buddyMemory = '';
    let buddyNudged = [];
    let selectedTaskId = tasks[0]?.id || null;

    openaiKeyInput.value = localStorage.getItem(STORAGE_KEYS.OPENAI_KEY) || '';
    if (langSelect) langSelect.value = currentLang;

    // 初始化服务商配置
    let currentProvider = localStorage.getItem(STORAGE_KEYS.AI_PROVIDER) || DEFAULT_PROVIDER;
    if (!AI_PROVIDERS[currentProvider]) currentProvider = DEFAULT_PROVIDER;
    const storedBaseUrl = localStorage.getItem(STORAGE_KEYS.AI_BASE_URL) || '';
    const storedModel = localStorage.getItem(STORAGE_KEYS.AI_MODEL) || '';

    // useStored=true 时优先用已保存的全局覆盖值；provider 切换时加载该服务商默认值
    function applyProviderUI(useStored) {
        if (aiProviderSelect) aiProviderSelect.value = currentProvider;
        const cfg = AI_PROVIDERS[currentProvider];
        if (aiBaseUrlInput) aiBaseUrlInput.value = useStored && storedBaseUrl ? storedBaseUrl : cfg.baseUrl;
        if (aiModelInput) aiModelInput.value = useStored && storedModel ? storedModel : cfg.model;
    }

    function persistProvider() {
        localStorage.setItem(STORAGE_KEYS.AI_PROVIDER, currentProvider);
        localStorage.setItem(STORAGE_KEYS.AI_BASE_URL, aiBaseUrlInput ? aiBaseUrlInput.value.trim() : '');
        localStorage.setItem(STORAGE_KEYS.AI_MODEL, aiModelInput ? aiModelInput.value.trim() : '');
    }

    if (aiProviderSelect) {
        aiProviderSelect.addEventListener('change', () => {
            currentProvider = aiProviderSelect.value;
            if (!AI_PROVIDERS[currentProvider]) currentProvider = DEFAULT_PROVIDER;
            applyProviderUI(false);
            persistProvider();
        });
    }
    [aiBaseUrlInput, aiModelInput].forEach(input => {
        if (input) input.addEventListener('input', persistProvider);
    });
    applyProviderUI(true);

    function locale() {
        return currentLang === 'en' ? 'en-US' : 'zh-CN';
    }

    function formatTemplate(template, vars = {}) {
        if (typeof template !== 'string') return '';
        return template.replace(/\{(\w+)\}/g, (match, key) => String(vars[key] ?? match));
    }

    function getI18nValue(dictionary, key) {
        return String(key)
            .split('.')
            .reduce((acc, part) => (acc && typeof acc === 'object' ? acc[part] : undefined), dictionary);
    }

    function t(key, vars) {
        const dict = I18N[currentLang] || I18N.zh;
        const fallback = getI18nValue(I18N.zh, key);
        const value = getI18nValue(dict, key) || fallback || key;

        if (typeof value === 'string') {
            return vars ? formatTemplate(value, vars) : value;
        }

        return value;
    }

    function applyI18n() {
        const html = document.documentElement;
        html.lang = locale() === 'en-US' ? 'en' : 'zh-CN';

        document.querySelectorAll('[data-i18n]').forEach(node => {
            const key = node.dataset.i18n;
            const value = t(key);
            if (typeof value === 'string') node.textContent = value;
        });

        document.querySelectorAll('[data-i18n-placeholder]').forEach(node => {
            const key = node.dataset.i18nPlaceholder;
            if (key) node.placeholder = t(key);
        });

        document.querySelectorAll('[data-i18n-aria-label]').forEach(node => {
            const key = node.dataset.i18nAriaLabel;
            if (key) node.setAttribute('aria-label', t(key));
        });

        const options = document.querySelectorAll('option[data-i18n]');
        options.forEach(option => {
            const key = option.dataset.i18n;
            const value = t(key);
            if (typeof value === 'string') option.textContent = value;
        });

        if (langSelect) langSelect.setAttribute('aria-label', `${t('language')}: ${currentLang === 'en' ? 'English' : '中文'}`);
        if (openaiKeyInput) openaiKeyInput.placeholder = t('placeholderOpenAiKey');
        setCurrentDate();
        renderTasks(currentFilter);
        syncNotifToggle();
    }

    function setUiText(key, element, vars) {
        if (!element) return;
        const message = t(key, vars);
        element.textContent = typeof message === 'string' ? message : '';
    }

    function createId() {
        if (window.crypto?.randomUUID) return window.crypto.randomUUID();
        return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    }

    function inferMeta(text) {
        const lower = text.toLowerCase();
        const highWords = ['上线', '发布', '修复', '紧急', '今天', 'deadline', 'bug', '安全', '阻塞'];
        const lowWords = ['阅读', '整理', '以后', ' someday ', '备忘', '想法'];
        const codeWords = ['code', 'api', '测试', 'bug', '部署', 'repo', 'codex', 'claude', 'cursor', '组件'];
        const productWords = ['用户', '产品', '需求', '页面', '体验', '上线', '设计'];
        const lifeWords = ['买', '健身', '运动', '吃', '家', '缴费', '约'];
        const learningWords = ['学习', '阅读', '课程', '笔记', '研究'];

        const priority = highWords.some(word => lower.includes(word))
            ? 'high'
            : lowWords.some(word => lower.includes(word))
                ? 'low'
                : 'medium';
        const effortMatch = text.match(/(\d+)\s*(分钟|min|小时|h)/i);
        const effort = effortMatch ? effortMatch[0].replace(/\s+/g, '') : priority === 'high' ? '45分钟' : '25分钟';
        const project = codeWords.some(word => lower.includes(word))
            ? '代码'
            : productWords.some(word => lower.includes(word))
                ? '产品'
                : learningWords.some(word => lower.includes(word))
                    ? '学习'
                    : lifeWords.some(word => lower.includes(word))
                        ? '生活'
                        : '个人';

        return { priority, effort, project };
    }

    function inferType(text) {
        const lower = text.toLowerCase();
        if (/\b(api|deploy|pr|merge|commit|repo|code|component|frontend|backend)\b/.test(lower)) return '代码';
        if (/(产品|需求|体验|页面|设计|迭代|上线|发布)/.test(text)) return '产品';
        if (/(学习|课程|阅读|笔记|复盘|调研)/.test(text)) return '学习';
        if (/(生活|购物|健身|运动|家|缴费|约|出行)/.test(text)) return '生活';
        return DEFAULT_TASK_TYPE;
    }

    function normalizeTask(task) {
        const text = typeof task?.text === 'string' ? task.text.trim() : '';
        const meta = inferMeta(text);

        return {
            id: typeof task?.id === 'string' ? task.id : createId(),
            text,
            completed: Boolean(task?.completed),
            dueDate: typeof task?.dueDate === 'string' ? task.dueDate : '',
            type: TASK_TYPES.includes(task?.type) ? task.type : inferType(text),
            priority: ['high', 'medium', 'low'].includes(task?.priority) ? task.priority : meta.priority,
            effort: typeof task?.effort === 'string' && task.effort ? task.effort : meta.effort,
            project: typeof task?.project === 'string' && task.project ? task.project : meta.project,
            createdAt: typeof task?.createdAt === 'string' ? task.createdAt : new Date().toISOString(),
            context: typeof task?.context === 'string' ? task.context : '',
            acceptance: typeof task?.acceptance === 'string' ? task.acceptance : '',
            nextPrompt: typeof task?.nextPrompt === 'string' ? task.nextPrompt : '',
            sourceGoal: typeof task?.sourceGoal === 'string' && task.sourceGoal ? task.sourceGoal : ''
        };
    }

    function loadTasks() {
        try {
            const raw = localStorage.getItem(STORAGE_KEYS.TASKS);
            if (!raw) return [];
            const parsed = JSON.parse(raw);
            if (!Array.isArray(parsed)) return [];

            return parsed
                .filter(task => task && typeof task.text === 'string' && task.text.trim())
                .map(normalizeTask);
        } catch (_error) {
            return [];
        }
    }

    function saveTasks() {
        localStorage.setItem(STORAGE_KEYS.TASKS, JSON.stringify(tasks));
    }

    function normalizeFilter(filter) {
        if (Object.values(FILTERS).includes(filter)) return filter;
        return FILTERS.ALL;
    }

    function priorityLabel(priority) {
        return {
            high: t('priorityHigh'),
            medium: t('priorityMedium'),
            low: t('priorityLow')
        }[priority] || t('priorityMedium');
    }

    function calculateHealthScore() {
        if (!tasks.length) return 0;

        const completed = tasks.filter(task => task.completed).length;
        const active = tasks.length - completed;
        const withContext = tasks.filter(task => task.context || task.acceptance || task.nextPrompt).length;
        const highOpen = tasks.filter(task => !task.completed && task.priority === 'high').length;
        const completionScore = Math.round((completed / tasks.length) * 45);
        const contextScore = Math.round((withContext / tasks.length) * 35);
        const loadScore = active <= 5 ? 20 : Math.max(4, 20 - (active - 5) * 3);
        const penalty = Math.min(15, Math.max(0, highOpen - 2) * 5);

        return Math.max(0, Math.min(100, completionScore + contextScore + loadScore - penalty));
    }

    function healthLabel(score) {
        if (!score) return t('healthWait');
        if (score >= 80) return t('healthGood');
        if (score >= 60) return t('healthForward');
        if (score >= 40) return t('healthNeedContext');
        return t('healthBreakDown');
    }

    function getNextAction() {
        const open = tasks
            .filter(task => !task.completed)
            .sort((a, b) => PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority]);

        if (!open.length) return t('nextActionEmpty');
        const task = open[0];
        if (!task.acceptance && !task.context) return t('nextActionNoContext', { text: task.text });
        return t('nextActionWithEffort', { text: task.text, effort: task.effort });
    }

    const lastStatValues = {};

    function updateStats() {
        const total = tasks.length;
        const active = tasks.filter(task => !task.completed).length;
        const completed = total - active;
        const completionRate = total === 0 ? 0 : Math.round((completed / total) * 100);
        const healthScore = calculateHealthScore();

        statTotal.textContent = String(total);
        statActive.textContent = String(active);
        statCompleted.textContent = String(completed);
        statHealth.textContent = String(healthScore);
        sideHealth.textContent = String(healthScore);
        sideHealthLabel.textContent = healthLabel(healthScore);
        taskCount.textContent = t('tasksInProgress', { count: active });
        nextAction.textContent = getNextAction();
        progressFill.style.width = `${completionRate}%`;
        progressText.textContent = t('progressText', { completionRate, healthScore });
        if (progressTrack) {
            progressTrack.setAttribute('aria-valuenow', String(completionRate));
        }

        const statEls = [statTotal, statActive, statCompleted, statHealth];
        const statValues = [total, active, completed, healthScore];
        statEls.forEach((el, index) => {
            if (statValues[index] === lastStatValues[index]) return;
            lastStatValues[index] = statValues[index];
            el.classList.remove('stat-pop');
            void el.offsetWidth;
            el.classList.add('stat-pop');
            setTimeout(() => el.classList.remove('stat-pop'), 180);
        });
    }

    function setCurrentDate() {
        if (!currentDate) return;
        const formatted = new Date().toLocaleDateString(locale(), {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            weekday: 'short'
        });
        currentDate.textContent = formatted;
    }

    function setActiveFilterButton(filter) {
        filterBtns.forEach(btn => {
            btn.classList.toggle('active', btn.dataset.filter === filter);
        });
    }

    function setActiveTypeFilter(value) {
        const normalized = value === 'all' || TASK_TYPES.includes(value) ? value : 'all';
        currentTypeFilter = normalized;
        if (typeFilterSelect) typeFilterSelect.value = normalized;
    }

    function buildDefaultPrompt(task) {
        return t('buildDefaultPrompt', {
            text: task.text,
            type: task.type,
            project: task.project,
            priority: priorityLabel(task.priority)
        });
    }

    function createTaskItem(task) {
        const taskItem = document.createElement('li');
        taskItem.classList.add('task-item');
        taskItem.classList.toggle('selected', task.id === selectedTaskId);
        taskItem.dataset.id = task.id;

        const checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        checkbox.classList.add('task-checkbox');
        checkbox.dataset.id = task.id;
        checkbox.checked = task.completed;

        const taskBody = document.createElement('div');
        taskBody.classList.add('task-body');

        const topLine = document.createElement('div');
        topLine.classList.add('task-topline');

        const taskText = document.createElement('span');
        taskText.classList.add('task-text');
        if (task.completed) taskText.classList.add('completed');
        taskText.textContent = task.text;

        const taskMeta = document.createElement('span');
        taskMeta.classList.add('task-meta');
        taskMeta.textContent = `${task.type} · ${task.project} · ${priorityLabel(task.priority)} · ${task.effort}`;
        if (task.dueDate) {
            const due = document.createElement('span');
            const formatted = window.formatDueDate ? window.formatDueDate(task.dueDate, currentLang) : task.dueDate;
            due.textContent = ` · ${t('taskDueLabel')} ${formatted}`;
            if (!task.completed && window.isTaskOverdue && window.isTaskOverdue(task, nowString())) {
                due.classList.add('task-overdue');
            }
            taskMeta.appendChild(due);
        }

        const chips = document.createElement('div');
        chips.classList.add('task-chips');
        ['context', 'acceptance', 'nextPrompt'].forEach(key => {
            if (!task[key]) return;
            const chip = document.createElement('span');
            chip.textContent = key === 'context' ? t('chipContext') : key === 'acceptance' ? t('chipAcceptance') : t('chipPrompt');
            chips.appendChild(chip);
        });

        if (task.sourceGoal) {
            const goalChip = document.createElement('span');
            goalChip.classList.add('chip-source');
            goalChip.textContent = t('chipSource', { goal: task.sourceGoal });
            chips.appendChild(goalChip);
        }

        const actions = document.createElement('div');
        actions.classList.add('task-actions');

        const notesBtn = document.createElement('button');
        notesBtn.classList.add('mini-btn');
        notesBtn.dataset.action = 'select';
        notesBtn.dataset.id = task.id;
        notesBtn.textContent = t('notesBtn');

        const splitBtn = document.createElement('button');
        splitBtn.classList.add('mini-btn');
        splitBtn.dataset.action = 'split';
        splitBtn.dataset.id = task.id;
        splitBtn.textContent = t('splitBtn');

        const editBtn = document.createElement('button');
        editBtn.classList.add('mini-btn');
        editBtn.dataset.action = 'edit';
        editBtn.dataset.id = task.id;
        editBtn.textContent = t('editBtn');

        const deleteBtn = document.createElement('button');
        deleteBtn.classList.add('delete-btn');
        deleteBtn.dataset.action = 'delete';
        deleteBtn.dataset.id = task.id;
        deleteBtn.textContent = t('deleteBtn');

        topLine.appendChild(taskText);
        taskBody.appendChild(topLine);
        taskBody.appendChild(taskMeta);
        taskBody.appendChild(chips);
        actions.appendChild(notesBtn);
        actions.appendChild(splitBtn);
        actions.appendChild(editBtn);
        actions.appendChild(deleteBtn);

        taskItem.appendChild(checkbox);
        taskItem.appendChild(taskBody);
        taskItem.appendChild(actions);

        return taskItem;
    }

    function renderEmptyState() {
        const emptyItem = document.createElement('li');
        emptyItem.classList.add('task-item', 'empty-state');

        const emptyBody = document.createElement('div');
        emptyBody.classList.add('task-body');

        const emptyText = document.createElement('span');
        emptyText.classList.add('task-text');
        emptyText.textContent = t('noTaskHint');

        const emptyMeta = document.createElement('span');
        emptyMeta.classList.add('task-meta');
        emptyMeta.textContent = t('noTaskExample');

        emptyBody.appendChild(emptyText);
        emptyBody.appendChild(emptyMeta);
        emptyItem.appendChild(emptyBody);
        taskList.replaceChildren(emptyItem);
    }

    function renderTasks(filter = currentFilter) {
        currentFilter = normalizeFilter(filter);
        setActiveFilterButton(currentFilter);
        updateStats();
        syncNotesPanel();
        renderTodayPlanView();

        const fragment = document.createDocumentFragment();
        const sortedTasks = [...tasks].sort((a, b) => {
            if (a.completed !== b.completed) return Number(a.completed) - Number(b.completed);
            return PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority];
        });

        sortedTasks.forEach(task => {
            const shouldRender =
                currentFilter === FILTERS.ALL ||
                (currentFilter === FILTERS.ACTIVE && !task.completed) ||
                (currentFilter === FILTERS.COMPLETED && task.completed) ||
                (currentFilter === FILTERS.HIGH && task.priority === 'high');
            const matchType = currentTypeFilter === 'all' || task.type === currentTypeFilter;

            if (shouldRender && matchType) fragment.appendChild(createTaskItem(task));
        });

        if (!fragment.childNodes.length) {
            renderEmptyState();
            return;
        }

        taskList.replaceChildren(fragment);
    }

    function addTask(textValue = taskInput.value.trim(), overrides = {}) {
        const text = textValue.trim();
        if (!text) return null;

        const dateValue = taskDueInput ? taskDueInput.value : '';
        const timeValue = taskDueTimeInput ? taskDueTimeInput.value : '';
        const dueDate = dateValue ? (timeValue ? `${dateValue}T${timeValue}` : dateValue) : '';
        const meta = inferMeta(text);
        const task = normalizeTask({
            text,
            completed: false,
            type: taskTypeSelect ? taskTypeSelect.value : DEFAULT_TASK_TYPE,
            dueDate,
            ...meta,
            ...overrides
        });

        tasks.push(task);
        selectedTaskId = task.id;
        if (taskDueInput) taskDueInput.value = '';
        if (taskDueTimeInput) taskDueTimeInput.value = '';
        if (task.dueDate) requestNotificationPermission();
        saveTasks();
        renderTasks(currentFilter);
        taskInput.value = '';
        return task;
    }

    function findTask(id) {
        return tasks.find(task => task.id === id);
    }

    function toggleTask(id) {
        const task = findTask(id);
        if (!task) return;
        task.completed = !task.completed;
        saveTasks();
        renderTasks(currentFilter);
        if (task.completed) {
            localStorage.removeItem(`notified_${task.id}`);
            const item = findRenderedTaskItem(id);
            if (item) {
                item.classList.add('just-completed');
                setTimeout(() => item.classList.remove('just-completed'), 360);
            }
        }
    }

    function findRenderedTaskItem(id) {
        return Array.from(taskList.children).find(el =>
            el.classList.contains('task-item') && el.querySelector('.task-checkbox')?.dataset.id === String(id)
        );
    }

    function deleteTask(id) {
        const item = findRenderedTaskItem(id);
        const commit = () => {
            if (!findTask(id)) return;
            tasks = tasks.filter(task => task.id !== id);
            if (selectedTaskId === id) selectedTaskId = tasks[0]?.id || null;
            saveTasks();
            renderTasks(currentFilter);
        };
        if (item && !item.classList.contains('removing')) {
            item.classList.add('removing');
            setTimeout(commit, 250);
        } else {
            commit();
        }
    }

    function clearCompleted() {
        const hasCompleted = tasks.some(task => task.completed);
        if (!hasCompleted) return;
        tasks = tasks.filter(task => !task.completed);
        if (!tasks.some(task => task.id === selectedTaskId)) selectedTaskId = tasks[0]?.id || null;
        saveTasks();
        renderTasks(currentFilter);
    }

    function syncNotesPanel() {
        const task = findTask(selectedTaskId);
        const hasTask = Boolean(task);

        selectedTaskLabel.textContent = task ? task.text : t('noTaskSelected');
        taskContextInput.value = task?.context || '';
        taskAcceptanceInput.value = task?.acceptance || '';
        taskPromptInput.value = task?.nextPrompt || (task ? buildDefaultPrompt(task) : '');

        [taskContextInput, taskAcceptanceInput, taskPromptInput, saveNotesBtn].forEach(element => {
            element.disabled = !hasTask;
        });
    }

    function saveSelectedNotes() {
        const task = findTask(selectedTaskId);
        if (!task) return;

        task.context = taskContextInput.value.trim();
        task.acceptance = taskAcceptanceInput.value.trim();
        task.nextPrompt = taskPromptInput.value.trim();
        saveTasks();
        renderTasks(currentFilter);
        setAiStatus(t('aiSaved'));
    }

    function renderTodayPlanView() {
        if (!todayPlanList || !todayPlanDate) return;

        const today = new Date().toLocaleDateString(locale(), {
            month: 'long',
            day: 'numeric',
            weekday: 'short'
        });
        const topTitle = t('todayTop5');
        todayPlanDate.textContent = `${today} · ${topTitle}`;

        const active = tasks
            .filter(task => !task.completed)
            .sort((a, b) => PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority])
            .slice(0, 5);

        todayPlanList.replaceChildren();

        if (!active.length) {
            const empty = document.createElement('li');
            empty.className = 'today-plan-list-empty';
            empty.textContent = t('noTaskInPlan');
            todayPlanList.appendChild(empty);
            return;
        }

        active.forEach((task, index) => {
            const item = document.createElement('li');
            item.className = 'plan-item';
            const hasContext = task.context ? t('taskContextReady') : t('taskContextMissing');
            const hasAcceptance = task.acceptance ? t('acceptanceReady') : t('acceptanceMissing');
            item.innerHTML = `<strong>${t('planTopItem', { index: index + 1, text: task.text, effort: task.effort, priority: priorityLabel(task.priority) })}</strong>
                <span>${task.type} / ${priorityLabel(task.priority)} / ${t('planEstimateLabel')} ${task.effort}</span>
                <span class="plan-badge">
                    ${hasContext}
                    <span>·</span>
                    ${hasAcceptance}
                </span>`;
            todayPlanList.appendChild(item);
        });
    }

    function setAiBusy(isBusy) {
        aiBreakdownBtn.disabled = isBusy;
        aiSummaryBtn.disabled = isBusy;
        planTodayBtn.disabled = isBusy;
        aiBreakdownBtn.textContent = isBusy ? t('aiWorking') : t('aiBreakdown');
    }

    function setAiStatus(message) {
        aiStatus.textContent = message || '';
    }

    // ---------- 伙伴（Buddy） ----------
    const BUDDY_KEYS = {
        HISTORY: 'companion_history',
        MEMORY: 'companion_memory',
        NUDGED: 'companion_nudged',
        GREETING: 'companion_greeting',
        NAME: 'companion_name'
    };

    function buddyLoad() {
        try { buddyHistory = JSON.parse(localStorage.getItem(BUDDY_KEYS.HISTORY) || '[]'); } catch { buddyHistory = []; }
        if (!Array.isArray(buddyHistory)) buddyHistory = [];
        buddyMemory = localStorage.getItem(BUDDY_KEYS.MEMORY) || '';
        try { buddyNudged = JSON.parse(localStorage.getItem(BUDDY_KEYS.NUDGED) || '[]'); } catch { buddyNudged = []; }
        if (!Array.isArray(buddyNudged)) buddyNudged = [];
    }

    function buddySay(role, content, actions) {
        buddyHistory.push({ role, content, ts: Date.now(), actions: actions || [] });
        if (buddyHistory.length > 40) buddyHistory = buddyHistory.slice(-40);
        localStorage.setItem(BUDDY_KEYS.HISTORY, JSON.stringify(buddyHistory));
        renderBuddyMessages();
    }

    function renderBuddyMessages() {
        if (!buddyMessagesEl) return;
        buddyMessagesEl.innerHTML = '';
        if (!buddyHistory.length) {
            buddyMessagesEl.innerHTML = `<div class="buddy-empty">${t('buddyEmpty')}</div>`;
            return;
        }
        buddyHistory.forEach((msg, index) => {
            const div = document.createElement('div');
            div.classList.add('buddy-msg', msg.role === 'user' ? 'user' : 'assistant');
            if (index < buddyHistory.length - 1) div.classList.add('no-anim');
            const textNode = document.createElement('span');
            textNode.classList.add('msg-text');
            textNode.textContent = msg.content;
            div.appendChild(textNode);
            if (msg.ts) {
                const timeEl = document.createElement('time');
                timeEl.textContent = new Date(msg.ts).toLocaleTimeString(locale(), { hour: '2-digit', minute: '2-digit' });
                div.appendChild(timeEl);
            }
            buddyMessagesEl.appendChild(div);
            if (msg.role === 'assistant' && msg.actions && msg.actions.length) {
                const row = document.createElement('div');
                row.classList.add('buddy-actions');
                msg.actions.forEach(action => {
                    const btn = document.createElement('button');
                    btn.type = 'button';
                    btn.classList.add('buddy-action-btn');
                    btn.textContent = action.label;
                    btn.addEventListener('click', () => runBuddyAction(action));
                    row.appendChild(btn);
                });
                buddyMessagesEl.appendChild(row);
            }
        });
        buddyMessagesEl.scrollTop = buddyMessagesEl.scrollHeight;
    }

    function switchPanelTab(tabId) {
        const showBuddy = tabId === 'buddy';
        const panel = showBuddy ? buddyPanel : aitoolsPanel;
        if (buddyPanel) buddyPanel.hidden = !showBuddy;
        if (aitoolsPanel) aitoolsPanel.hidden = showBuddy;
        panelTabs.forEach(btn => btn.classList.toggle('active', btn.dataset.tab === tabId));
        if (panel) {
            panel.classList.remove('panel-reveal');
            void panel.offsetWidth;
            panel.classList.add('panel-reveal');
        }
    }

    function showTypingIndicator() {
        if (!buddyMessagesEl) return;
        const typing = document.createElement('div');
        typing.className = 'typing';
        typing.setAttribute('role', 'status');
        typing.setAttribute('aria-label', t('buddyTyping'));
        for (let i = 0; i < 3; i++) {
            const dot = document.createElement('span');
            dot.className = 'dot';
            typing.appendChild(dot);
        }
        buddyMessagesEl.appendChild(typing);
        buddyMessagesEl.scrollTop = buddyMessagesEl.scrollHeight;
    }

    function removeTypingIndicator() {
        if (!buddyMessagesEl) return;
        buddyMessagesEl.querySelectorAll('.typing').forEach(el => el.remove());
    }

    function showQuotaBanner(message) {
        const banner = document.getElementById('quota-banner');
        const bannerText = document.getElementById('quota-banner-text');
        if (!banner) return;
        if (bannerText) bannerText.textContent = message;
        banner.hidden = false;
    }

    function hideQuotaBanner() {
        const banner = document.getElementById('quota-banner');
        if (banner) banner.hidden = true;
    }

    // 路由决策：有自定义 Key → 直连；否则有代理地址 → 走托管额度；再否则本地
    function buddyRoute(hasCustomKey) {
        return typeof window.decideRoute === 'function'
            ? window.decideRoute(hasCustomKey, QuotaProxy.baseUrl())
            : (hasCustomKey ? 'direct' : (QuotaProxy.baseUrl() ? 'proxy' : 'local'));
    }

    async function buddySend(userText) {
        const text = (userText || '').trim();
        if (!text || typeof callOpenAI !== 'function') return;

        buddySay('user', text);
        buddyInput.value = '';
        buddySendBtn.disabled = true;
        hideQuotaBanner();
        showTypingIndicator();

        try {
            const name = localStorage.getItem(BUDDY_KEYS.NAME) || '';
            const tasksNow = tasks;
            const ctx = typeof window.buildCompanionContext === 'function'
                ? window.buildCompanionContext({
                    memorySummary: buddyMemory,
                    tasks: tasksNow,
                    recentEvents: momentTexts(tasksNow),
                    history: buddyHistory.slice(-8),
                    lang: currentLang,
                    buddyName: name,
                    health: calculateHealthScore(),
                    doneCount: tasksNow.filter(t => t.completed).length,
                    totalCount: tasksNow.length
                })
                : { userPrompt: `用户: ${text}`, systemPrompt: '' };

            const route = buddyRoute(Boolean(openaiKeyInput.value.trim()));
            let reply;
            if (route === 'proxy') {
                // 走 app 托管额度：模型固定 deepseek-v4-flash
                setAiStatus(t('quota.proxyHint'));
                const data = await QuotaProxy.request({
                    model: 'deepseek-v4-flash',
                    messages: [
                        { role: 'system', content: ctx.systemPrompt },
                        { role: 'user', content: ctx.userPrompt }
                    ]
                });
                reply = extractOutputText(data);
            } else {
                reply = await callOpenAI(ctx.userPrompt, ctx.systemPrompt);
            }
            if (!reply) {
                buddySay('assistant', t('buddyNoKey'));
                return;
            }
            const parsed = window.parseBuddyActions ? window.parseBuddyActions(reply) : { text: reply, actions: [] };
            let actions = parsed.actions;
            if (!actions.length && window.extractTaskIntent) {
                const intent = window.extractTaskIntent(text);
                if (intent && intent.taskText) {
                    actions = [{ action: 'add_task', payload: { text: intent.taskText }, label: t('buddyAddTaskBtn') }];
                }
            }
            buddySay('assistant', parsed.text || t('buddySilent'), actions);
        } catch (error) {
            if (error && error.code === 'quota_exceeded') {
                // 额度超限 → 状态提示 + 输入框下方彩条（点击跳到 AI 设置）
                setAiStatus(t('quota.exceeded'));
                showQuotaBanner(error.kind === 'daily'
                    ? t('quota.exceededDaily')
                    : t('quota.exceededFree'));
                return;
            }
            buddySay('assistant', t('buddySilent'));
        } finally {
            buddySendBtn.disabled = false;
            removeTypingIndicator();
        }
    }

    async function buddyGreet() {
        const today = new Date().toDateString();
        if (localStorage.getItem(BUDDY_KEYS.GREETING) === today) return;
        const momentEvents = window.momentsFor ? window.momentsFor({
            tasks: tasks.map(t => ({ id: t.id, text: t.text, completed: t.completed, createdAt: t.createdAt })),
            completedToday: tasks.filter(t => t.completed).length,
            nudgedIds: buddyNudged
        }) : [];
        const name = localStorage.getItem(BUDDY_KEYS.NAME) || '';
        const ctx = window.buildCompanionContext && window.buildCompanionContext({
            memorySummary: buddyMemory,
            tasks,
            recentEvents: momentTexts(tasks),
            history: [],
            lang: currentLang,
            buddyName: name,
            health: calculateHealthScore(),
            doneCount: tasks.filter(t => t.completed).length,
            totalCount: tasks.length
        });
        const greetText = window.greeting ? window.greeting(currentLang) : t('buddyEmpty');
        buddySay('assistant', greetText);
        if (window.buildCompanionContext) {
            try {
                const reply = await callOpenAI(`${ctx.userPrompt}\n请用一句自然的问候开场，不要提\"记忆\"\"上下文\"等词。`, ctx.systemPrompt);
                if (reply) {
                    buddyHistory[buddyHistory.length - 1].content = reply;
                    renderBuddyMessages();
                }
            } catch (_error) {
                /* 保持本地问候 */
            }
        }
        localStorage.setItem(BUDDY_KEYS.GREETING, today);
    }

        function runBuddyAction(action) {
        if (!action || !action.action) return;
        const kind = action.action;
        if (kind === 'add_task') {
            const text = (action.payload && (action.payload.text || action.payload.title || action.payload.name || action.payload.task || action.payload.goal)) || '';
            if (!text) return;
            const task = addTask(text, { sourceGoal: lastBreakdownGoal || '' });
            if (task) buddySay('assistant', t('buddyAdded', { text }));
            return;
        }
        if (kind === 'complete_task') {
            const text = (action.payload && (action.payload.text || action.payload.title)) || '';
            const task = tasks.find(t => t.text === text || t.text.includes(text));
            if (task) toggleTask(task.id);
            return;
        }
        if (kind === 'breakdown') {
            const goal = (action.payload && (action.payload.text || action.payload.title || action.payload.name || action.payload.task || action.payload.goal)) || '';
            if (goal) {
                if (goalInput) goalInput.value = goal;
                handleBreakdown();
            }
        }
    }

    function momentTexts(tasks = []) {
        const ms = window.momentsFor ? window.momentsFor({
            tasks: tasks.map(t => ({ id: t.id, text: t.text, completed: t.completed, createdAt: t.createdAt })),
            completedToday: tasks.filter(t => t.completed).length,
            nudgedIds: buddyNudged
        }) : [];
        return ms.map(m => m.text);
    }

    function extractOutputText(data) {
        if (typeof data.output_text === 'string' && data.output_text.trim()) {
            return data.output_text.trim();
        }

        // chat/completions 格式：choices[0].message.content
        if (Array.isArray(data.choices)) {
            const choice = data.choices[0];
            const content = choice?.message?.content;
            if (typeof content === 'string' && content.trim()) {
                return content.trim();
            }
            if (Array.isArray(content)) {
                return content
                    .map(part => typeof part?.text === 'string' ? part.text : '')
                    .join('\n')
                    .trim();
            }
        }

        if (!Array.isArray(data.output)) return '';

        const chunks = [];
        data.output.forEach(item => {
            if (!Array.isArray(item.content)) return;
            item.content.forEach(content => {
                if (content.type === 'output_text' && typeof content.text === 'string') {
                    chunks.push(content.text.trim());
                }
            });
        });

        return chunks.join('\n').trim();
    }

    function extractTasksFromText(text) {
        return text
            .split('\n')
            .map(line => line.trim())
            .filter(Boolean)
            .map(line => line.replace(/^[-*\d\s.)）]+/, '').replace(/^\[[ xX]\]\s*/, '').trim())
            .map(line => line.replace(/^(任务|步骤|Task|Step)\s*[:：]\s*/i, '').trim())
            .filter(line => line.length >= 2 && !line.includes('：') || line.length >= 8)
            .slice(0, 10);
    }

    function localBreakdown(goal) {
        const cleanGoal = goal.replace(/\s+/g, ' ').trim();
        const subject = cleanGoal.length > 42 ? `${cleanGoal.slice(0, 42)}...` : cleanGoal;

        return [
            t('localBreakdownStep1', { subject }),
            t('localBreakdownStep2'),
            t('localBreakdownStep3'),
            t('localBreakdownStep4'),
            t('localBreakdownStep5'),
            t('localBreakdownStep6')
        ].join('\n');
    }

    function localSummary() {
        const completed = tasks.filter(task => task.completed);
        const active = tasks.filter(task => !task.completed);
        const high = active.filter(task => task.priority === 'high');
        const missingContext = active.filter(task => !task.context && !task.acceptance);

        return [
            t('localSummaryLine1', { completed: completed.length, active: active.length, health: calculateHealthScore(), healthLabel: healthLabel(calculateHealthScore()) }),
            '',
            t('localSummaryTitle'),
            high[0] ? t('localSummaryStep1', { text: high[0].text }) : t('localSummaryStep1Fallback'),
            missingContext[0] ? t('localSummaryStep2', { text: missingContext[0].text }) : t('localSummaryStep2Fallback'),
            t('localSummaryStep3', {
                tasks: active.slice(0, 3).map(task => task.text).join(currentLang === 'en' ? '; ' : '；') || t('empty')
            })
        ].join('\n');
    }

    function localTodayPlan() {
        const active = tasks
            .filter(task => !task.completed)
            .sort((a, b) => PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority])
            .slice(0, 5);

        if (!active.length) return t('emptyTaskPlan');

        return [
            t('planSummaryTitle'),
            ...active.map((task, index) => t('planItem', {
                index: index + 1,
                text: task.text,
                effort: task.effort,
                priority: priorityLabel(task.priority)
            })),
            '',
            t('planFirstStep', { next: getNextAction() })
        ].join('\n');
    }

    function escapeMarkdownValue(value) {
        return String(value)
            .replace(/\\/g, '\\\\')
            .replace(/\r?\n/g, '  \n')
            .replace(/\|/g, '\\|');
    }

    function buildObsidianMarkdown() {
        const now = new Date();
        const date = now.toLocaleDateString(locale());
        const time = now.toLocaleTimeString(locale(), { hour: '2-digit', minute: '2-digit' });
        const active = tasks.filter(task => !task.completed);
        const completed = tasks.filter(task => task.completed);

        const lines = [];
        lines.push('---');
        lines.push(`title: "todo-list-app-${currentLang === 'en' ? 'todo-export' : '待办导出'} ${date}"`);
        lines.push(`exported_at: "${now.toISOString()}"`);
        lines.push(`total: ${tasks.length}`);
        lines.push(`active: ${active.length}`);
        lines.push(`completed: ${completed.length}`);
        lines.push('---');
        lines.push('');
        lines.push(`# ${t('obsidianTitle')} ${date}`);
        lines.push('');
        lines.push(`- ${t('obsidianExportTime')}: ${time}`);
        lines.push(`- ${t('statTotal')}: ${tasks.length}`);
        lines.push(`- ${t('statActive')}: ${active.length}`);
        lines.push(`- ${t('statCompleted')}: ${completed.length}`);
        lines.push('');
        lines.push(`## ${t('todayPlan')}`);
        lines.push('```');
        lines.push(localTodayPlan());
        lines.push('```');
        lines.push('');
        lines.push(`## ${t('obsidianTaskList')}`);

        tasks.forEach((task, index) => {
            lines.push('');
            lines.push(`### ${index + 1}. ${escapeMarkdownValue(task.text)}`);
            lines.push(`- ${t('obsidianStatusLabel')}: ${task.completed ? t('obsidianStatusDone') : t('obsidianStatusActive')}`);
            lines.push(`- ${t('taskTypeLabel')}: ${escapeMarkdownValue(task.type)}`);
            lines.push(`- ${t('obsidianProjectLabel')}: ${escapeMarkdownValue(task.project)}`);
            lines.push(`- ${t('obsidianPriorityLabel')}: ${priorityLabel(task.priority)}`);
            lines.push(`- ${t('obsidianEffortLabel')}: ${escapeMarkdownValue(task.effort)}`);
            if (task.context) lines.push(`- ${t('contextLabel')}: ${escapeMarkdownValue(task.context)}`);
            if (task.acceptance) lines.push(`- ${t('acceptanceLabel')}: ${escapeMarkdownValue(task.acceptance)}`);
            if (task.nextPrompt) lines.push(`- ${t('promptLabel')}: ${escapeMarkdownValue(task.nextPrompt)}`);
        });

        return lines.join('\n');
    }

    function handleExportObsidian() {
        const content = buildObsidianMarkdown();
        const fileName = `todo-list-app-${new Date().toISOString().slice(0, 10)}.md`;
        const blob = new Blob([content], { type: 'text/markdown;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = fileName;
        anchor.click();
        URL.revokeObjectURL(url);
        setAiStatus(t('aiExported', { fileName }));
    }

    function getAIProviderConfig() {
        const cfg = AI_PROVIDERS[currentProvider];
        const baseUrl = (aiBaseUrlInput ? aiBaseUrlInput.value.trim() : '') || cfg.baseUrl;
        const model = (aiModelInput ? aiModelInput.value.trim() : '') || cfg.model;
        return { baseUrl, model };
    }

    async function callOpenAI(promptText, instructionText) {
        const apiKey = openaiKeyInput.value.trim();
        if (!apiKey) return null;

        localStorage.setItem(STORAGE_KEYS.OPENAI_KEY, apiKey);

        const { baseUrl, model } = getAIProviderConfig();
        if (!baseUrl) throw new Error(t('aiErrorNoBaseUrl'));
        if (!model) throw new Error(t('aiErrorNoModel'));

        const url = `${baseUrl.replace(/\/+$/, '')}/chat/completions`;

        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${apiKey}`
            },
            body: JSON.stringify({
                model,
                messages: [
                    {
                        role: 'system',
                        content: instructionText
                    },
                    {
                        role: 'user',
                        content: promptText
                    }
                ]
            })
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(t('aiErrorCallFailed', { status: response.status, error: errorText }));
        }

        const result = await response.json();
        const outputText = extractOutputText(result);
        if (!outputText) throw new Error(t('aiErrorEmpty'));
        return outputText;
    }

    async function getSmartText(promptText, instructionText, fallbackText) {
        const aiText = await callOpenAI(promptText, instructionText);
        return aiText || fallbackText;
    }

    async function handleBreakdown() {
        const goal = goalInput.value.trim() || taskInput.value.trim();
        if (!goal) {
            lastBreakdownGoal = '';
            setAiStatus(t('aiNoTaskToBreakdown'));
            taskInput.focus();
            return;
        }

        setAiBusy(true);
        setAiStatus(openaiKeyInput.value.trim() ? t('aiBreakdownBusy') : t('aiBreakdownLocal'));

        try {
            const activeTasks = tasks.filter(task => !task.completed).map(task => task.text);
            const context = activeTasks.length
                ? t('currentActiveTasks', { tasks: activeTasks.join('；') })
                : t('noActiveTasks');

            const text = await getSmartText(
                `目标：${goal}\n${context}`,
                t('aiBreakdownPrompt'),
                localBreakdown(goal)
            );

            aiOutput.textContent = text;
            aiSuggestedTasks = extractTasksFromText(text);
            lastBreakdownGoal = goal;
            setAiStatus(aiSuggestedTasks.length ? t('aiBreakdownResult', { count: aiSuggestedTasks.length }) : t('aiStatusSaved'));
        } catch (error) {
            lastBreakdownGoal = '';
            setAiStatus(error instanceof Error ? error.message : t('aiErrorFallback'));
        } finally {
            setAiBusy(false);
        }
    }

    async function handleSummary() {
        setAiBusy(true);
        setAiStatus(openaiKeyInput.value.trim() ? t('aiSummaryBusy') : t('aiSummaryLocal'));

        try {
            const completed = tasks.filter(task => task.completed).map(task => `- ${task.text}`).join('\n') || `- ${t('noTasksLabel')}`;
            const active = tasks
                .filter(task => !task.completed)
                .map(task => currentLang === 'en'
                    ? `- ${task.text} (${task.project}, ${priorityLabel(task.priority)}, ${task.effort})`
                    : `- ${task.text}（${task.project}，${priorityLabel(task.priority)}，${task.effort}）`)
                .join('\n') || `- ${t('noTasksLabel')}`;

            const text = await getSmartText(
                `${t('completedTasksLabel')}:\n${completed}\n\n${t('activeTasksLabel')}:\n${active}\n\n${t('healthLabel')}: ${calculateHealthScore()}`,
                t('aiSummaryPrompt'),
                localSummary()
            );

            aiOutput.textContent = text;
            aiSuggestedTasks = [];
            setAiStatus(t('aiSummaryDone'));
        } catch (error) {
            setAiStatus(error instanceof Error ? error.message : t('aiErrorFallback'));
        } finally {
            setAiBusy(false);
        }
    }

    async function handleTodayPlan() {
        setAiBusy(true);
        setAiStatus(openaiKeyInput.value.trim() ? t('aiPlanBusy') : t('aiPlanLocal'));

        try {
            const active = tasks
                .filter(task => !task.completed)
                .map(task => currentLang === 'en'
                    ? `- ${task.text} (${task.project}, ${priorityLabel(task.priority)}, ${task.effort})`
                    : `- ${task.text}（${task.project}，${priorityLabel(task.priority)}，${task.effort}）`)
                .join('\n') || `- ${t('noTasksLabel')}`;
            const text = await getSmartText(
                `${currentLang === 'en' ? "Generate today's plan from:\n" : '请基于这些任务生成今天的执行计划：\n'}${active}`,
                t('todayPlanPrompt'),
                localTodayPlan()
            );

            aiOutput.textContent = text;
            aiSuggestedTasks = [];
            setAiStatus(t('aiPlanDone'));
        } catch (error) {
            setAiStatus(error instanceof Error ? error.message : t('aiErrorFallback'));
        } finally {
            setAiBusy(false);
        }
    }

    function addAiTasksToList() {
        if (!aiSuggestedTasks.length) {
            setAiStatus(t('aiNoImport'));
            return;
        }

        aiSuggestedTasks.forEach(taskText => {
            if (!tasks.some(existing => existing.text === taskText)) {
                const meta = inferMeta(taskText);
                tasks.push(normalizeTask({
                    text: taskText,
                    completed: false,
                    sourceGoal: lastBreakdownGoal,
                    ...meta,
                nextPrompt: t('buildAiPromptForTask', { text: taskText })
                }));
            }
        });

        selectedTaskId = tasks[tasks.length - 1]?.id || selectedTaskId;
        saveTasks();
        renderTasks(currentFilter);
        setAiStatus(t('aiImported'));
    }

    function splitTask(id) {
        const task = findTask(id);
        if (!task) return;
        goalInput.value = task.text;
        handleBreakdown();
    }

    function editTask(id) {
        const task = findTask(id);
        if (!task) return;

        const newName = window.prompt(t('editTitlePrompt'), task.text);
        if (newName === null) return;
        const trimmedName = newName.trim();
        if (trimmedName) task.text = trimmedName;

        const newDue = window.prompt(t('editDuePrompt'), task.dueDate || '');
        if (newDue !== null) {
            const trimmedDue = newDue.trim();
            if (!trimmedDue) {
                task.dueDate = '';
                localStorage.removeItem(`notified_${task.id}`);
            } else if (/^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2})?$/.test(trimmedDue)) {
                const parsed = window.parseDueDate ? window.parseDueDate(trimmedDue) : null;
                if (parsed) {
                    task.dueDate = parsed.time ? `${parsed.date}T${parsed.time}` : parsed.date;
                    localStorage.removeItem(`notified_${task.id}`);
                    requestNotificationPermission();
                }
            }
        }

        saveTasks();
        renderTasks(currentFilter);
    }

    function nowString() {
        const now = new Date();
        const month = String(now.getMonth() + 1).padStart(2, '0');
        const day = String(now.getDate()).padStart(2, '0');
        const hour = String(now.getHours()).padStart(2, '0');
        const minute = String(now.getMinutes()).padStart(2, '0');
        return `${now.getFullYear()}-${month}-${day}T${hour}:${minute}`;
    }

    function requestNotificationPermission() {
        if (typeof Notification === 'undefined') return;
        if (Notification.permission !== 'default') {
            syncNotifToggle();
            return;
        }
        try {
            const result = Notification.requestPermission();
            if (result && typeof result.then === 'function') result.then(syncNotifToggle).catch(() => {});
            else syncNotifToggle();
        } catch (_error) {
            syncNotifToggle();
        }
    }

    function notifAvailable() {
        return typeof Notification !== 'undefined';
    }

    function syncNotifToggle() {
        if (!notifToggleBtn) return;
        if (!notifAvailable() || !('Notification' in window)) {
            notifToggleBtn.textContent = t('notifUnavailable');
            notifToggleBtn.disabled = true;
            return;
        }
        const status = Notification.permission;
        if (status === 'granted') {
            notifToggleBtn.textContent = t('notifEnabled');
            notifToggleBtn.classList.add('notif-on');
        } else if (status === 'denied') {
            notifToggleBtn.textContent = t('notifDenied');
            notifToggleBtn.classList.remove('notif-on');
        } else {
            notifToggleBtn.textContent = t('notifEnable');
            notifToggleBtn.classList.remove('notif-on');
        }
    }

    if (notifToggleBtn) {
        notifToggleBtn.addEventListener('click', () => {
            if (!notifAvailable()) return;
            if (Notification.permission === 'denied') {
                if (confirm(t('notifDeniedMsg'))) requestNotificationPermission();
                else return;
            }
            requestNotificationPermission();
        });
    }

    function checkDueNotifications() {
        if (typeof Notification === 'undefined' || Notification.permission !== 'granted') return;
        const now = nowString();
        tasks.forEach(task => {
            const key = `notified_${task.id}`;
            if (task.completed) {
                localStorage.removeItem(key);
                return;
            }
            if (!task.dueDate || localStorage.getItem(key)) return;
            if (!window.shouldNotify || !window.shouldNotify(task, now, false)) return;
            try {
                new Notification(t('notificationDueTitle'), { body: t('notificationDueBody', { text: task.text }) });
                localStorage.setItem(key, '1');
            } catch (_error) {
                /* skip */
            }
        });
    }

    addTaskBtn.addEventListener('click', () => addTask());
    quickFocusBtn.addEventListener('click', () => taskInput.focus());

    taskInput.addEventListener('keydown', event => {
        if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
            addTask();
        }
    });

    taskList.addEventListener('change', event => {
        if (event.target.classList.contains('task-checkbox')) {
            toggleTask(event.target.dataset.id);
        }
    });

    taskList.addEventListener('click', event => {
        const action = event.target.dataset.action;
        const id = event.target.dataset.id;
        if (!action || !id) return;

        if (action === 'delete') deleteTask(id);
        if (action === 'select') {
            selectedTaskId = id;
            renderTasks(currentFilter);
        }
        if (action === 'split') splitTask(id);
        if (action === 'edit') editTask(id);
    });

    filterBtns.forEach(btn => {
        btn.addEventListener('click', () => renderTasks(btn.dataset.filter));
    });
    if (typeFilterSelect) {
        typeFilterSelect.addEventListener('change', () => {
            setActiveTypeFilter(typeFilterSelect.value);
            renderTasks(currentFilter);
        });
    }

    clearCompletedBtn.addEventListener('click', clearCompleted);
    aiBreakdownBtn.addEventListener('click', handleBreakdown);
    aiSummaryBtn.addEventListener('click', handleSummary);
    planTodayBtn.addEventListener('click', handleTodayPlan);
    addAiTasksBtn.addEventListener('click', addAiTasksToList);
    saveNotesBtn.addEventListener('click', saveSelectedNotes);
    exportObsidianBtn.addEventListener('click', handleExportObsidian);

    panelTabs.forEach(btn => {
        btn.addEventListener('click', () => switchPanelTab(btn.dataset.tab));
    });
    if (buddySendBtn) {
        buddySendBtn.addEventListener('click', () => buddySend(buddyInput.value));
    }
    if (buddyInput) {
        buddyInput.addEventListener('keydown', event => {
            if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault();
                buddySend(buddyInput.value);
            }
        });
    }

    // ---------- 伙伴语音输入（SpeechRecognition） ----------
    const SpeechRecognitionCtor = window.SpeechRecognition || window.webkitSpeechRecognition;
    let buddyRecording = false;
    let buddyRecognition = null;

    function resetBuddyMic() {
        buddyRecording = false;
        buddyRecognition = null;
        if (buddyMic) {
            buddyMic.classList.remove('recording');
            buddyMic.textContent = '🎤';
        }
    }

    if (buddyMic && SpeechRecognitionCtor) {
        buddyMic.addEventListener('click', () => {
            if (buddyRecording) {
                try {
                    if (buddyRecognition) buddyRecognition.stop();
                } catch (_error) {
                    resetBuddyMic();
                }
                return;
            }
            try {
                const recognition = new SpeechRecognitionCtor();
                recognition.lang = currentLang === 'en' ? 'en-US' : 'zh-CN';
                recognition.continuous = true;
                recognition.interimResults = true;
                let voiceFinal = '';
                buddyRecognition = recognition;
                buddyRecording = true;
                buddyMic.classList.add('recording');
                buddyMic.textContent = '⏺';

                recognition.onresult = event => {
                    let interim = '';
                    for (let i = event.resultIndex; i < event.results.length; i++) {
                        const result = event.results[i];
                        if (result.isFinal) voiceFinal += result[0].transcript;
                        else interim += result[0].transcript;
                    }
                    voiceFinal = voiceFinal.trim();
                    // interim 实时填入输入框，final 追加保留
                    buddyInput.value = (voiceFinal ? `${voiceFinal} ` : '') + interim;
                };
                recognition.onend = resetBuddyMic;
                recognition.onerror = resetBuddyMic;
                recognition.start();
            } catch (_error) {
                resetBuddyMic();
            }
        });
    } else if (buddyMic) {
        // 浏览器不支持语音识别 → 隐藏 mic 按钮
        buddyMic.hidden = true;
    }

    // 额度彩条：点击跳到 AI 设置面板；× 关闭
    const quotaBanner = document.getElementById('quota-banner');
    if (quotaBanner) {
        quotaBanner.addEventListener('click', () => switchPanelTab('aitools'));
    }
    const quotaBannerClose = document.getElementById('quota-banner-close');
    if (quotaBannerClose) {
        quotaBannerClose.addEventListener('click', event => {
            event.stopPropagation();
            hideQuotaBanner();
        });
    }

    buddyLoad();
    renderBuddyMessages();
    buddyGreet();
    syncNotifToggle();
    requestNotificationPermission();
    checkDueNotifications();
    setInterval(checkDueNotifications, 60000);
    if (langSelect) {
        langSelect.addEventListener('change', () => {
            currentLang = langSelect.value === 'en' ? 'en' : 'zh';
            localStorage.setItem(STORAGE_KEYS.LANG, currentLang);
            applyI18n();
        });
    }

    if (taskTypeSelect) taskTypeSelect.value = taskTypeSelect.value || DEFAULT_TASK_TYPE;
    setActiveTypeFilter(typeFilterSelect?.value || 'all');

    saveTasks();
    applyI18n();
});
