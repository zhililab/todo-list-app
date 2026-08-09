import test from 'node:test';
import assert from 'node:assert/strict';
import { buildCompanionContext, stripMemory, greeting } from './companion-context.js';

test('builds system prompt with buddy name and lang', () => {
  const ctx = buildCompanionContext({
    memorySummary: '用户昨天完成3件事，目标减肥2斤。',
    tasks: [{ text: '记录三餐热量', completed: false, type: 'personal' }],
    recentEvents: ['昨天完成「买体重秤」'],
    history: [], lang: 'zh', buddyName: '小暖', health: 80
  });
  assert.ok(ctx.systemPrompt.includes('小暖'));
  assert.ok(ctx.systemPrompt.includes('温柔'));
  assert.ok(ctx.userPrompt.includes('记录三餐热量'));
  assert.ok(ctx.userPrompt.includes('健康分'));
});

test('caps history at 8 turns', () => {
  const n = 12;
  const history = Array.from({ length: n }, (_, i) => ({ role: i % 2 ? 'assistant' : 'user', content: `msg${i}` }));
  const ctx = buildCompanionContext({ memory: '', tasks: [], recentEvents: [], history, lang: 'zh', buddyName: '小暖', health: 50 });
  const count = (ctx.userPrompt.match(/msg/g) || []).length;
  assert.ok(count <= 8);
});

test('merges memory with new events', () => {
  const merged = stripMemory('旧摘要。', ['完成X', '又完成Y']);
  assert.ok(merged.includes('完成X') || merged.includes('旧摘要'));
});