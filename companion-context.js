export function buildCompanionContext(opts) {
  const lang = opts.lang || 'zh';
  const isZh = lang === 'zh';
  const buddyName = opts.buddyName || (isZh ? '小暖' : 'Nuan');
  const actionContract = isZh
    ? '如果用户明确要求你创建/添加/记住一个待办任务（如"帮我创建待办：xxx"、"加个任务 xxx"、"记下 xxx"），你必须在回复末尾输出且只输出一个 JSON 对象（不要用 markdown 代码块包裹，单独一行）：{"actions":[{"action":"add_task","payload":{"text":"任务文本"},"label":"加入待办"}]}。回复文字保持温柔简短，JSON 行前后可以有 1 行文字。'
    : 'If the user explicitly asks you to create/add/remember a todo task, you MUST append exactly one JSON object (not wrapped in markdown code block) at the end of your reply: {"actions":[{"action":"add_task","payload":{"text":"task text"},"label":"Add to todos"}]}. Keep your reply warm and short.';
  const systemPrompt = isZh
    ? `你是「${buddyName}」，一个温柔、有洞察、记得用户的 AI 搭档。你说话温暖、简短、具体——像懂事的知己，不是助理。绝不评判；用户说"减肥2斤"你记得第二天还会提起。用户任务拖慢时你轻轻推不逼。别用表情超三四个。如果含义混淆，问一句再答。${actionContract}`
    : `You are "${buddyName}", a gentle, perceptive AI companion. Warm, short, specific — like a close friend, never a tool. Remember what the user says across sessions. Gently encourage, don't push. Ask when unclear. ${actionContract}`;
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

if (typeof window !== 'undefined') {
  window.buildCompanionContext = buildCompanionContext;
  window.stripMemory = stripMemory;
  window.greeting = greeting;
}