import test from 'node:test';
import assert from 'node:assert/strict';
import { formatDueDate, isTaskOverdue, shouldNotify, isDue, parseDueDate } from './companion-format.js';

test('formats due date in Chinese', () => {
    assert.equal(formatDueDate('2026-08-10', 'zh'), '8月10日');
});

test('formats due date in English', () => {
    assert.equal(formatDueDate('2026-08-10', 'en'), '8/10');
});

test('returns empty string for empty or missing due date', () => {
    assert.equal(formatDueDate('', 'zh'), '');
    assert.equal(formatDueDate(null, 'zh'), '');
});

test('isTaskOverdue true for open overdue task', () => {
    assert.equal(isTaskOverdue({ completed: false, dueDate: '2026-08-01' }, '2026-08-08'), true);
});

test('isTaskOverdue false for completed overdue task', () => {
    assert.equal(isTaskOverdue({ completed: true, dueDate: '2026-08-01' }, '2026-08-08'), false);
});

test('isTaskOverdue false for future due date', () => {
    assert.equal(isTaskOverdue({ completed: false, dueDate: '2026-08-20' }, '2026-08-08'), false);
});

test('isTaskOverdue false for task due today', () => {
    assert.equal(isTaskOverdue({ completed: false, dueDate: '2026-08-08' }, '2026-08-08'), false);
});

test('shouldNotify true for task due today not yet notified', () => {
    assert.equal(shouldNotify({ completed: false, dueDate: '2026-08-08' }, '2026-08-08', false), true);
});

test('shouldNotify true for overdue task', () => {
    assert.equal(shouldNotify({ completed: false, dueDate: '2026-08-01' }, '2026-08-08', false), true);
});

test('shouldNotify false when already notified', () => {
    assert.equal(shouldNotify({ completed: false, dueDate: '2026-08-08' }, '2026-08-08', true), false);
});

test('shouldNotify false for completed task', () => {
    assert.equal(shouldNotify({ completed: true, dueDate: '2026-08-08' }, '2026-08-08', false), false);
});

test('shouldNotify false for future due date', () => {
    assert.equal(shouldNotify({ completed: false, dueDate: '2026-08-20' }, '2026-08-08', false), false);
});

test('parseDueDate returns date only for date input', () => {
    assert.deepEqual(parseDueDate('2026-08-10'), { date: '2026-08-10', time: undefined });
});

test('parseDueDate returns time for time input', () => {
    assert.deepEqual(parseDueDate('2026-08-10T14:30'), { date: '2026-08-10', time: '14:30' });
});

test('parseDueDate accepts space separator', () => {
    assert.deepEqual(parseDueDate('2026-08-10 09:05'), { date: '2026-08-10', time: '09:05' });
});

test('parseDueDate returns null for invalid input', () => {
    assert.equal(parseDueDate(''), null);
    assert.equal(parseDueDate(null), null);
    assert.equal(parseDueDate('2026-13-40'), null);
    assert.equal(parseDueDate('2026-08-10T25:00'), null);
    assert.equal(parseDueDate('tomorrow'), null);
});

test('isDue true at exact due minute', () => {
    assert.equal(isDue({ completed: false, dueDate: '2026-08-08T14:30' }, '2026-08-08T14:30'), true);
});

test('isDue false before due minute', () => {
    assert.equal(isDue({ completed: false, dueDate: '2026-08-08T14:30' }, '2026-08-08T14:29'), false);
});

test('isDue false for future timed task', () => {
    assert.equal(isDue({ completed: false, dueDate: '2026-08-09T14:30' }, '2026-08-08T23:59'), false);
});

test('isDue true for pure date task any time on due day', () => {
    assert.equal(isDue({ completed: false, dueDate: '2026-08-08' }, '2026-08-08T09:00'), true);
});

test('shouldNotify waits for exact due time', () => {
    assert.equal(shouldNotify({ completed: false, dueDate: '2026-08-08T14:30' }, '2026-08-08T14:30', false), true);
    assert.equal(shouldNotify({ completed: false, dueDate: '2026-08-08T14:30' }, '2026-08-08T14:29', false), false);
});

test('shouldNotify date-only task fires at 00:00 of due day', () => {
    assert.equal(shouldNotify({ completed: false, dueDate: '2026-08-08' }, '2026-08-08T00:00', false), true);
});

test('isTaskOverdue precise with time', () => {
    assert.equal(isTaskOverdue({ completed: false, dueDate: '2026-08-08T14:00' }, '2026-08-08T15:00'), true);
    assert.equal(isTaskOverdue({ completed: false, dueDate: '2026-08-08T14:00' }, '2026-08-08T14:00'), false);
});

test('formats due date with time', () => {
    assert.equal(formatDueDate('2026-08-10T14:30', 'zh'), '8月10日 14:30');
    assert.equal(formatDueDate('2026-08-10T09:05', 'en'), '8/10 09:05');
});
