import test from 'node:test';
import assert from 'node:assert/strict';
import { parseBuddyActions, extractTaskIntent } from './companion-actions.js';

test('extracts add_task action and cleans text', () => {
    const { text, actions } = parseBuddyActions(
        '要不要试试这个？\n{"actions":[{"action":"add_task","payload":{"text":"记录三餐热量"},"label":"加入待办"}]}\n明天再说。'
    );
    assert.equal(actions.length, 1);
    assert.equal(actions[0].action, 'add_task');
    assert.equal(actions[0].payload.text, '记录三餐热量');
    assert.ok(text.includes('要不要试试这个'));
});

test('caps actions at maxActions', () => {
    const { actions } = parseBuddyActions(
        JSON.stringify({ actions: [
            { action: 'add_task', payload: { text: 'A' }, label: 'A' },
            { action: 'complete_task', payload: { text: 'B' }, label: 'B' },
            { action: 'breakdown', payload: { text: 'C' }, label: 'C' }
        ] }),
        2
    );
    assert.equal(actions.length, 2);
});

test('ignores disallowed kinds', () => {
    const { actions } = parseBuddyActions(
        JSON.stringify({ actions: [
            { action: 'delete_all', payload: {}, label: 'nope' },
            { action: 'add_task', payload: { text: 'OK' }, label: '好的' }
        ] })
    );
    assert.equal(actions.length, 1);
    assert.equal(actions[0].action, 'add_task');
});

test('returns plain text when no json', () => {
    const { text, actions } = parseBuddyActions('没有动作的回复');
    assert.deepEqual(actions, []);
    assert.equal(text, '没有动作的回复');
});

test('gracefully handles broken json', () => {
    const { actions } = parseBuddyActions('{"actions": [broken');
    assert.deepEqual(actions, []);
});

test('normalizes add_task payload field names to text', () => {
    const { actions } = parseBuddyActions('{"actions":[{"action":"add_task","payload":{"name":"喝水"},"label":"x"}]}');
    assert.equal(actions[0].payload.text, '喝水');
});

test('extracts task intent in chinese with colon', () => {
    assert.deepEqual(extractTaskIntent('帮我创建待办：明天买牛奶'), { taskText: '明天买牛奶' });
});

test('extracts task intent with 加个', () => {
    assert.deepEqual(extractTaskIntent('加个任务 跑步'), { taskText: '跑步' });
});

test('extracts task intent with 记下', () => {
    assert.deepEqual(extractTaskIntent('记下：写周报'), { taskText: '写周报' });
});

test('rejects question-shaped create request', () => {
    assert.equal(extractTaskIntent('帮我创建待办吗？'), null);
});

test('rejects plain chat without task intent', () => {
    assert.equal(extractTaskIntent('今天天气怎么样'), null);
});

test('extracts english task intent', () => {
    assert.deepEqual(extractTaskIntent('create a task: buy milk'), { taskText: 'buy milk' });
});

test('extracts english task intent with trailing phrase', () => {
    assert.deepEqual(extractTaskIntent('add remember the meeting'), { taskText: 'remember the meeting' });
});