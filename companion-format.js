export function parseDueDate(dueDateStr) {
    if (typeof dueDateStr !== 'string' || !dueDateStr) return null;
    const match = /^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{1,2}))?$/.exec(dueDateStr.trim());
    if (!match) return null;
    const month = Number(match[2]);
    const day = Number(match[3]);
    if (!month || month > 12 || !day || day > 31) return null;
    const date = `${match[1]}-${match[2].padStart(2, '0')}-${match[3].padStart(2, '0')}`;
    let time;
    if (match[4] !== undefined) {
        const hour = Number(match[4]);
        const minute = Number(match[5]);
        if (hour > 23 || minute > 59) return null;
        time = `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
    }
    return { date, time };
}

function nowTimestamp(now) {
    if (typeof now !== 'string' || !now) return '';
    return now.includes('T') ? now.slice(0, 16) : `${now.slice(0, 10)}T00:00`;
}

function nowDatePart(now) {
    return typeof now === 'string' && now ? now.slice(0, 10) : '';
}

export function isDue(task, now) {
    if (!task || task.completed || typeof task.dueDate !== 'string' || !task.dueDate || typeof now !== 'string' || !now) return false;
    const parsed = parseDueDate(task.dueDate);
    if (!parsed) return false;
    if (parsed.time) {
        return `${parsed.date}T${parsed.time}` <= nowTimestamp(now);
    }
    return parsed.date <= nowDatePart(now);
}

export function formatDueDate(dueDate, lang) {
    if (typeof dueDate !== 'string' || !dueDate) return '';
    const parsed = parseDueDate(dueDate.trim());
    if (!parsed) return dueDate.trim();
    const month = Number(parsed.date.slice(5, 7));
    const day = Number(parsed.date.slice(8, 10));
    if (!month || !day) return '';
    const base = lang === 'en' ? `${month}/${day}` : `${month}月${day}日`;
    return parsed.time ? `${base} ${parsed.time}` : base;
}

export function isTaskOverdue(task, todayStr) {
    if (!task || task.completed || typeof task.dueDate !== 'string' || !task.dueDate || typeof todayStr !== 'string' || !todayStr) return false;
    const parsed = parseDueDate(task.dueDate);
    if (!parsed) return false;
    if (parsed.time) {
        return `${parsed.date}T${parsed.time}` < nowTimestamp(todayStr);
    }
    return parsed.date < nowDatePart(todayStr);
}

export function shouldNotify(task, todayStr, notified) {
    return Boolean(isDue(task, todayStr) && !notified);
}

if (typeof window !== 'undefined') {
    window.parseDueDate = parseDueDate;
    window.formatDueDate = formatDueDate;
    window.isTaskOverdue = isTaskOverdue;
    window.isDue = isDue;
    window.shouldNotify = shouldNotify;
}