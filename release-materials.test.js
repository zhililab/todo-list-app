import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

test('App Store materials describe the committed offline JWS boundary without claiming deployment', async () => {
  const files = await Promise.all([
    read('./ios/AppStoreConnect/release-evidence.md'),
    read('./ios/AppStoreConnect/app-privacy-checklist.md'),
    read('./ios/AppStoreConnect/subscription-copy.md'),
  ]);

  for (const contents of files) {
    assert.match(contents, /离线验签|offline/i);
    assert.match(contents, /(?:不保存完整 JWS|未用 Sandbox\/Production 真 JWS|does not store.*JWS)/i);
    assert.match(contents, /OCSP/i);
    assert.match(contents, /Notifications V2/i);
    assert.match(contents, /(?:已实现|repository.*implements?)/i);
    assert.match(contents, /(?:ASC URL|App Store Connect)/i);
    assert.match(contents, /(?:BLOCKED|未执行|未配置|ACTION REQUIRED)/i);
    assert.doesNotMatch(contents, /PASTE_NAMESPACE_ID_HERE|仍含 KV 占位/);
    assert.doesNotMatch(contents, /已部署生产|production deployment complete/i);
  }

  const evidence = files[0];

  assert.match(evidence, /3f38fb9f2e16221545f19eef839f04051ded74b7/);
  assert.match(evidence, /产品验证 HEAD[\s\S]*Worker 部署版本[\s\S]*docs HEAD/);
  assert.doesNotMatch(evidence, /验证材料基线[^\n]*(?:c7ec121|5ee3606)/);
  assert.doesNotMatch(evidence, /70b3a25|cba6986|61738ae/);
  assert.match(evidence, /Root tests[^\n]*\*\*PASS\*\*[^\n]*135 passed, 0 failed/i);
  assert.match(evidence, /Worker tests[^\n]*\*\*PASS\*\*[^\n]*66 passed, 0 failed/i);
  assert.match(evidence, /iOS tests[^\n]*\*\*PASS\*\*[^\n]*342 passed, 0 failed/i);
  assert.match(evidence, /Task 5 iOS focused tests[^\n]*15 passed, 0 failed/i);
  assert.match(evidence, /Unsigned static Archive[^\n]*\*\*PASS/i);
  assert.match(evidence, /\/private\/tmp\/todo-archive\.3UdF8w\/TodoNative\.xcarchive/);
  assert.match(evidence, /536\.02 KiB[^\n]*93\.64 KiB/);
  assert.match(evidence, /QUOTA[^\n]*ENTITLEMENTS[^\n]*DEVICE_PRIVACY/);
  assert.doesNotMatch(evidence, /\bSTALE\b|pending worktree|81 passed|14 passed/);
});

test('managed data deletion runbook is operator-only and keyed by the in-app Support ID', async () => {
  const contents = await read('./ios/AppStoreConnect/managed-data-deletion-runbook.md');

  assert.match(contents, /Support ID/);
  assert.match(contents, /TD-/);
  assert.match(contents, /free:\{deviceId\}/);
  assert.match(contents, /daily:\{deviceId\}:/);
  assert.match(contents, /appstore-entitlement:\{deviceId\}:/);
  assert.match(contents, /appstore-original:/);
  assert.match(contents, /不提供公开删除端点/);
  assert.match(contents, /不得.*(?:日志|截图)/);
  assert.match(contents, /BLOCKED/);
  assert.match(contents, /suppression/i);
  assert.match(contents, /erased-device/);
  assert.match(contents, /自动.*(?:注册|register).*重建/);
});
