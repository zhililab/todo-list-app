import test from 'node:test';
import assert from 'node:assert/strict';
import { momentsFor } from './companion-events.js';

const DAY = 86400000;
const now = Date.now();

test('celebrates on completing a task today', () => {
    const ms = momentsFor({
        tasks: [{ id: 1, text: '完成任务A', completed: true }],
        completedToday: 1,
        now
    });
    const celebrate = ms.find(m => m.type === 'celebrate');
    assert.ok(celebrate, 'expected a celebrate moment');
    assert.ok(celebrate.text.includes('完成任务A'));
});

test('nudges task older than 3 days not yet nudged', () => {
    const ms = momentsFor({
        tasks: [{ id: 2, text: '任务B', completed: false, createdAt: now - 4 * DAY }],
        completedToday: 0,
        now,
        nudgedIds: []
    });
    assert.ok(ms.some(m => m.type === 'nudge' && m.text.includes('任务B')));
});

test('skips already nudged tasks', () => {
    const ms = momentsFor({
        tasks: [{ id: 2, text: '任务B', completed: false, createdAt: now - 4 * DAY }],
        completedToday: 0,
        now,
        nudgedIds: [2]
    });
    assert.ok(!ms.some(m => m.type === 'nudge'));
});

test('skips fresh tasks and completed ones', () => {
    const ms = momentsFor({
        tasks: [
            { id: 3, text: '新任务', completed: false, createdAt: now },
            { id: 4, text: '已完成', completed: true, createdAt: now - 5 * DAY }
        ],
        completedToday: 0,
        now
    });
    assert.ok(!ms.some(m => m.type === 'nudge'));
});