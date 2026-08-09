const DAY_MS = 86400000;
const NUDGE_DAYS = 3;

export function momentsFor({ tasks = [], completedToday = 0, now = Date.now(), nudgedIds = [] } = {}) {
    const moments = [];
    const nudged = new Set(nudgedIds);

    const recentDone = tasks.filter(t => t.completed).reverse();

    if (completedToday >= 1) {
        const last = recentDone[0];
        moments.push({
            type: 'celebrate',
            text: last
                ? `完成了「${last.text}」！这一步很扎实，我陪你记下它。`
                : `今天已经完成 ${completedToday} 件事，节奏很扎实。`
        });
    }

    const threshold = now - NUDGE_DAYS * DAY_MS;
    const stale = tasks
        .filter(t => !t.completed && t.createdAt < threshold && !nudged.has(t.id))
        .sort((a, b) => a.createdAt - b.createdAt)
        .slice(0, 2);
    for (const task of stale) {
        moments.push({
            type: 'nudge',
            taskId: task.id,
            text: `那个「${task.text}」已经放了几天了，要不要给它挪个位子？`
        });
    }

    return moments.slice(0, 3);
}

if (typeof window !== 'undefined') {
    window.momentsFor = momentsFor;
}