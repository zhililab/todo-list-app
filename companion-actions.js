const ALLOWED_KINDS = ['add_task', 'complete_task', 'breakdown'];

const INTENT_PATTERNS = [
    /(?:帮我|请|麻烦)?\s*(?:创建|新建|添加|加上|加个|记下|加入|收下)\s*(?:一个)?\s*(?:任务|待办|事项|todo)?\s*[:：]?\s*(.+)/,
    /(?:帮我|请)\s*(?:创建|添加|记下|收下)\s*(.+)/
];
const EN_INTENT_PATTERN = /(?:create|add|remember|note)\s+(?:a\s+)?(?:task|todo)?\s*(?:[:：]\s*)?(.+)/i;

export function extractTaskIntent(userText) {
    const text = String(userText || '').trim();
    if (!text) return null;
    let captured = null;
    for (const pattern of INTENT_PATTERNS) {
        const match = text.match(pattern);
        if (match && match[1]) {
            captured = match[1];
            break;
        }
    }
    if (captured === null) {
        const match = text.match(EN_INTENT_PATTERN);
        captured = match ? match[1] : null;
    }
    if (captured === null) return null;
    let taskText = captured.trim()
        .replace(/^[:：\-、\s]+/, '')
        .replace(/^["'「『“”]|["'」』”’]+$/, '')
        .trim();
    if (taskText.length < 2 || taskText.length > 40) return null;
    if (/[?？]/.test(taskText) || /什么|吗|怎么|如何|why|what|how/i.test(taskText)) return null;
    return { taskText };
}

export function parseBuddyActions(reply, maxActions = 2) {
    const text = String(reply || '').trim();
    if (!text) return { text: '', actions: [] };

    const firstBrace = text.indexOf('{');
    const lastBrace = text.lastIndexOf('}');
    if (firstBrace < 0 || lastBrace <= firstBrace) {
        return { text, actions: [] };
    }

    const head = text.slice(0, firstBrace).trim();
    const tail = text.slice(lastBrace + 1).trim();
    let json;
    try {
        json = JSON.parse(text.slice(firstBrace, lastBrace + 1));
    } catch (_error) {
        return { text, actions: [] };
    }

    const rawActions = Array.isArray(json && json.actions) ? json.actions : [];
    const actions = [];
    for (const raw of rawActions) {
        if (actions.length >= maxActions) break;
        if (!raw || typeof raw !== 'object') continue;
        const kind = raw.action;
        if (!ALLOWED_KINDS.includes(kind)) continue;
        const rawPayload = raw.payload && typeof raw.payload === 'object' ? raw.payload : {};
        const payload = Object.fromEntries(Object.entries(rawPayload).filter(([, v]) => typeof v === 'string'));
        if (kind === 'add_task' || kind === 'breakdown') {
            payload.text = rawPayload.text ?? rawPayload.title ?? rawPayload.name ?? rawPayload.task ?? rawPayload.goal ?? '';
        }
        const label = typeof raw.label === 'string' && raw.label ? raw.label : kind;
        actions.push({ action: kind, payload, label });
    }

    const clean = [head, tail].filter(Boolean).join('\n');
    return { text: clean || text, actions };
}

if (typeof window !== 'undefined') {
    window.parseBuddyActions = parseBuddyActions;
    window.extractTaskIntent = extractTaskIntent;
}