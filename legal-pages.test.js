import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import test from 'node:test';

const publicBase = 'https://todo-list-app.zhili1993.chatgpt.site';

const pageRequirements = {
    'privacy.html': [
        '隐私政策', 'Privacy Policy', '本地存储', 'local storage',
        '任务、聊天和语音转写文本', 'task, chat, and voice transcription text',
        '匿名设备标识符', 'anonymous device identifier',
        '托管 Worker', 'managed Worker', '模型服务商', 'model provider',
        '自带 API Key', 'Bring Your Own Key', '撤回', 'revoke',
        '保留', 'retention', '删除请求', 'deletion request',
        'Apple 的语音识别服务', 'Apple Speech service', '原始音频', 'raw audio',
        '明确同意', 'explicitly consent', 'Keychain', '本地规划器', 'local planner',
        '域分隔哈希', 'domain-separated hash', '完整 JWS', 'full JWS',
        '阻止自动重新注册', 'prevent automatic re-registration',
    ],
    'terms.html': [
        '服务条款', 'Terms of Use', '月度和年度', 'monthly and yearly',
        '自动续订', 'auto-renewing', 'App Store', '取消', 'cancel',
        '恢复购买', 'Restore Purchases', 'AI 输出', 'AI output',
        '可接受使用', 'acceptable use', '本地数据', 'local data',
        '7 天设备本地试用', '7-day device-local trial',
        '不是 App Store 的 Intro Offer', 'not an App Store Introductory Offer',
        'lz123321@live.com',
    ],
    'support.html': [
        '支持', 'Support', '应用和系统版本', 'app and system version',
        '联系请求模板', 'contact request template', '隐私删除请求', 'privacy deletion request',
        '购买', 'purchase', '恢复', 'restore', '通知', 'notification',
        '麦克风', 'microphone', '语音识别', 'speech recognition',
        'lz123321@live.com', '隐私删除请求', 'privacy deletion request',
    ],
};

test('legal and support pages publish the required bilingual disclosures safely', async () => {
    for (const [file, requiredText] of Object.entries(pageRequirements)) {
        const html = await readFile(new URL(file, import.meta.url), 'utf8');

        assert.match(html, new RegExp(`<link rel="canonical" href="${publicBase}/${file}">`));
        assert.match(html, /<a href="#zh">中文<\/a>/);
        assert.match(html, /<a href="#en">English<\/a>/);
        assert.doesNotMatch(html, /<form\b|<script\b|fonts\.googleapis\.com|fonts\.gstatic\.com|googletagmanager|google-analytics/i);
        assert.match(html, /href="mailto:lz123321@live\.com"/);

        for (const text of requiredText) {
            assert.ok(html.toLowerCase().includes(text.toLowerCase()), `${file} must disclose: ${text}`);
        }
    }
});

test('landing page exposes all public legal links without changing app scripts', async () => {
    const html = await readFile(new URL('index.html', import.meta.url), 'utf8');

    for (const file of Object.keys(pageRequirements)) {
        assert.match(html, new RegExp(`href="${file}"`));
    }
    assert.match(html, /<script type="module" src="companion-context\.js"><\/script>/);
    assert.match(html, /<script src="app\.js"><\/script>/);
});

test('production build declares every legal page as an HTML entry', async () => {
    const config = await readFile(new URL('vite.config.js', import.meta.url), 'utf8');

    for (const file of Object.keys(pageRequirements)) {
        assert.match(config, new RegExp(`['\"]${file}['\"]`));
    }
});

test('production build preserves the legacy app script referenced by its rendered homepage', () => {
    execFileSync(process.execPath, ['./node_modules/vite/bin/vite.js', 'build'], { stdio: 'pipe' });
    execFileSync(process.execPath, ['./scripts/build-sites-runtime.js'], { stdio: 'pipe' });

    const index = readFileSync('dist/index.html', 'utf8');
    const legacyScript = index.match(/<script src="([^\"]*app\.js)"><\/script>/)?.[1];
    assert.ok(legacyScript, 'the rendered homepage must retain the classic app.js reference');
    assert.ok(existsSync(`dist/${legacyScript}`), `the rendered homepage asset must exist: ${legacyScript}`);

    for (const page of ['index.html', ...Object.keys(pageRequirements)]) {
        const html = readFileSync(`dist/${page}`, 'utf8');
        for (const match of html.matchAll(/\b(?:href|src)="([^\"]+)"/g)) {
            const asset = match[1];
            if (/^(?:#|https?:|mailto:|data:)/i.test(asset)) continue;
            assert.ok(existsSync(`dist/${asset.replace(/^\//, '')}`), `${page} references an emitted local asset: ${asset}`);
        }
    }
});

test('generated Node preview runtime serves a legal page without Worker globals', async () => {
    const previous = process.env.PREVIEW_DISABLE_SERVER;
    process.env.PREVIEW_DISABLE_SERVER = '1';
    try {
        const runtime = await import(`${pathToFileURL('dist/server/index.js').href}?smoke=${Date.now()}`);
        const response = await runtime.default.fetch(new Request('https://preview.local/privacy.html'));
        assert.equal(response.status, 200);
        assert.match(await response.text(), /Privacy Policy/);
    } finally {
        if (previous === undefined) delete process.env.PREVIEW_DISABLE_SERVER;
        else process.env.PREVIEW_DISABLE_SERVER = previous;
    }
});
