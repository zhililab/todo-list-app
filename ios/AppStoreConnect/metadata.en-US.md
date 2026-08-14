# App Store Connect Metadata Draft (English, U.S.)

Checked: 2026-08-11
Bundle ID: `com.zhili.todo-native`

> This is a working copy for App Store Connect. It does not prove that metadata has been saved or approved. Every `ACTION REQUIRED` item must be confirmed by an authorized account owner before submission.

## General information

- App name: `ACTION REQUIRED — Confirm that “AI Native Todo” is available in App Store Connect and choose the final storefront name.`
- Subtitle: `Tasks, reminders, optional AI`
- Current submission path: **Path B — the managed backend is not complete, so make no managed-AI availability claim. Copy Path B below.**
- Primary category: `ACTION REQUIRED — Select in App Store Connect; Productivity is a candidate.`
- Secondary category: `ACTION REQUIRED — Decide whether to use a secondary category; Utilities is a candidate.`
- Copyright: `ACTION REQUIRED — Enter the real year and legal entity that owns the copyright.`
- Support URL: `https://todo-list-app.zhili1993.chatgpt.site/support.html`
- Privacy Policy URL: `https://todo-list-app.zhili1993.chatgpt.site/privacy.html`
- Terms of Use URL: `https://todo-list-app.zhili1993.chatgpt.site/terms.html`
- Support email: `lz123321@live.com`

## Path B (current default: no managed-AI claim)

### Promotional text

`Keep task context, acceptance criteria, and next prompts in one bilingual workflow. No account required: plan on device or bring your own AI key with consent.`

### Full description

AI Native Todo is a bilingual task app with no account required. It keeps what you need to do next beside the context that defines a useful result.

You can:

- create, edit, archive, and complete tasks with type, priority, estimated effort, and due time;
- add context, acceptance criteria, and a next AI prompt to each task;
- review a Today plan, task health, and status distribution;
- schedule local notifications for tasks with due times;
- chat with an AI companion, break down goals, review progress, and confirm suggested task actions;
- dictate into the companion composer, review the transcript, and then choose whether to send it;
- export tasks as Obsidian-friendly Markdown; and
- switch between Simplified Chinese and English.

Tasks and app settings are primarily stored on your device. The on-device planner remains available without a network request. Bring Your Own Key (BYOK) is optional. Before content is sent to a recipient for the first time, the app explains the data involved and asks for consent. You can decline and continue with the on-device planner, or revoke consent later in Settings. Your API key is stored in the iOS Keychain and requests go directly to your selected model provider.

Premium features may be unlocked with monthly or yearly auto-renewing subscriptions. The app also includes a seven-day experience that begins on first launch and is stored only on that device; it is not an App Store introductory offer. The App Store purchase sheet controls the actual price, billing period, and any available offer.

Terms of Use (Apple Standard EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

AI output is planning assistance and may be inaccurate. Verify important information before acting on it.

## Path A (use only after every managed-backend release gate is complete)

### Promotional text

`Keep task context, acceptance criteria, and next prompts in one bilingual workflow. Plan on device, bring your own AI key, or use managed AI after explicit consent.`

### Full description

AI Native Todo is a bilingual task app with no account required. It keeps what you need to do next beside the context that defines a useful result.

You can:

- create, edit, archive, and complete tasks with type, priority, estimated effort, and due time;
- add context, acceptance criteria, and a next AI prompt to each task;
- review a Today plan, task health, and status distribution;
- schedule local notifications for tasks with due times;
- chat with an AI companion, break down goals, review progress, and confirm suggested task actions;
- dictate into the companion composer, review the transcript, and then choose whether to send it;
- export tasks as Markdown for a knowledge base; and
- switch between Simplified Chinese and English.

Tasks and app settings are primarily stored on your device. Remote AI is optional. Before content is sent to a recipient for the first time, the app explains the data involved and asks for consent. You can decline and continue with the on-device planner, or revoke consent later in Settings. If you bring your own API key, it is stored in the iOS Keychain and requests go directly to your selected model provider. With managed AI, content and a random device identifier go first to the managed service and then to the disclosed model provider.

Premium features may be unlocked with monthly or yearly auto-renewing subscriptions. The app also includes a seven-day experience that begins on first launch and is stored only on that device; it is not an App Store introductory offer. The App Store purchase sheet controls the actual price, billing period, and any available offer.

Terms of Use (Apple Standard EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

AI output is planning assistance and may be inaccurate. Verify important information before acting on it.

`ACTION REQUIRED — Copy Path A only after the production endpoint, KV/secrets, real Apple JWS and bundle/environment verification, refund/revocation synchronization, App Privacy, and real-device checks are complete.`

## Keywords

Candidate: `todo list,tasks,planner,reminders,productivity,goals,review,bilingual,workflow`

UTF-8 check: `78 bytes` (`node Buffer.byteLength`; no brand/company name and no keyword of two characters or fewer).

## What's New template for a later version (leave blank for the 1.0 launch)

App Store Connect does not require What's New for the first 1.0 release. Rewrite the following from the real diff for 1.0.1 or later:

- Manage tasks with context, acceptance criteria, and next prompts.
- Plan the day with task health, local reminders, and natural-language due times.
- Use an optional AI workbench, companion chat, voice transcription, or on-device fallback.
- Review and control remote-AI consent; keep BYOK credentials in Keychain.
- Restore monthly or yearly subscriptions and export premium Markdown.

## Pre-submission checks

- [ ] `ACTION REQUIRED` app name, categories, and copyright owner are confirmed by the account owner.
- [ ] Copy **Path B** now. Switch to Path A only after the production endpoint, Worker secrets/KV, and transaction verification are release-ready.
- [x] On 2026-08-11, the public support page returned HTTP 200 and published `lz123321@live.com` with privacy-deletion instructions. Recheck the live content immediately before submission.
- [x] The candidate keyword string is 78 UTF-8 bytes locally; App Store Connect must still accept it when saved.
