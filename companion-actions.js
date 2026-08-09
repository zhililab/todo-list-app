const ALLOWED_KINDS = ['add_task', 'complete_task', 'breakdown'];

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
        const payload = raw.payload && typeof raw.payload === 'object'
            ? Object.fromEntries(Object.entries(raw.payload).filter(([, v]) => typeof v === 'string'))
            : {};
        const label = typeof raw.label === 'string' && raw.label ? raw.label : kind;
        actions.push({ action: kind, payload, label });
    }

    const clean = [head, tail].filter(Boolean).join('\n');
    return { text: clean || text, actions };
}

if (typeof window !== 'undefined') {
    window.parseBuddyActions = parseBuddyActions;
}