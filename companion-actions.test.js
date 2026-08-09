import test from 'node:test';
import assert from 'node:assert/strict';
import { parseBuddyActions } from './companion-actions.js';

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