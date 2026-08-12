# App Review Notes 与 TestFlight 验证矩阵

核对日期：2026-08-11
Bundle ID：`com.zhili.todo-native`

## 可粘贴到 App Review Information 的说明（英文）

AI Native Todo does not require account creation or sign-in. Tasks, settings, companion history, and the seven-day device-local experience are stored on the device.

The app has three AI routes:

1. On-device planner: available without an API key and without sending task or chat content to a model provider.
2. Bring Your Own Key (BYOK): optional. A user can enter an API key in Settings. The key is stored in the iOS Keychain, and requests go directly to the selected provider only after the app shows the recipient and transmitted-content disclosure and the user agrees.
3. Managed AI: intended to use our Worker and DeepSeek after the same explicit consent. `ACTION REQUIRED — The production managed-AI endpoint is not configured in the current Release build. Do not represent this route as available unless the endpoint and backend release gates below are completed.` When unavailable, the app keeps the on-device planner available and shows managed service/registration as unavailable rather than silently using a hidden endpoint.

Consent can be declined; no remote request is sent and local planning remains available. Consent can be revoked in Settings > Privacy. The next remote request for that recipient asks again. “Delete Local AI Configuration” removes the API key from Keychain, provider/model/base-URL preferences, and the local consent record; it does not claim to delete data retained by a remote provider or managed service.

Monthly and yearly subscriptions use StoreKit 2:

- `com.zhili.todo.premium.monthly.v2`
- `com.zhili.todo.premium.yearly.v2`

Use a Sandbox Apple Account to purchase. Restore Purchases is available in both the paywall and Settings. A verified, unexpired, non-revoked current entitlement unlocks premium features; expiry or revocation removes the local entitlement after an entitlement refresh/relaunch. The seven-day experience shown by the app is local to the device and is not an App Store introductory offer.

Notifications are optional and requested only when the user enables reminders in Settings. Voice input is optional and requests both microphone and speech-recognition permission. The transcript is placed in the composer for review before sending. Raw audio is not sent to our Worker or the model provider; Apple Speech may process or assist with recognition depending on the device and environment.

Support: `lz123321@live.com`
Privacy: `https://todo-list-app.zhili1993.chatgpt.site/privacy.html`
Terms: `https://todo-list-app.zhili1993.chatgpt.site/terms.html`
Support page: `https://todo-list-app.zhili1993.chatgpt.site/support.html`

`ACTION REQUIRED — Add the real review contact name, phone, and email fields in App Store Connect. Do not assume the public support email alone completes the private review-contact fields.`

## Reviewer test path

1. Launch the app. No login or demo account is required.
2. In Tasks, create a harmless task such as “Prepare weekly plan tomorrow 15:00”, add context and acceptance criteria, save it, then edit its status.
3. In Today, inspect health/status cards and the daily brief. With no remote route configured, the local planner remains usable.
4. Open the AI workbench and run a plan or breakdown. Verify local output is clearly labeled as on-device/local when no remote route is available.
5. Optional BYOK consent test: `ACTION REQUIRED — If App Review must test BYOK, provide a temporary review-only provider credential through the secure App Review notes field, never in this repository or screenshots.` Enter it in Settings, start an AI action, review the consent screen, and choose one branch:
   - Decline: the content is not sent; local planning remains usable.
   - Agree: the request is sent to the named provider; later choose Settings > Privacy > Revoke Remote AI Consent and confirm the next request asks again.
6. Open the paywall. Confirm products load from StoreKit Sandbox and purchase one approved product. Verify premium features unlock.
7. Use Restore Purchases. Then simulate expiry/refund/revocation in StoreKit testing or Sandbox, relaunch/refresh entitlements, and verify local premium gating is removed.
8. In Settings, enable reminders. Accept notification permission and create a task with a near-future due time; verify a local notification. Repeat the denied branch and verify the app offers a route to iOS Settings.
9. In Buddy, tap voice input. Accept microphone and speech-recognition permissions, speak a harmless phrase, stop, review the transcript, and send only if desired. Repeat one denied-permission branch and verify the error/settings path.
10. In Settings, open Privacy Policy, Terms, and Support and verify the public HTTPS pages.

## Managed AI unavailable scenario

The production managed AI endpoint is currently absent. For a build submitted in this state:

- reviewers can fully test task management, local notifications, local AI planning, local storage, export, subscription purchase/restore, and BYOK if a secure temporary key is supplied;
- managed quota, Worker-forwarded DeepSeek requests, and remote Pro-quota registration are unavailable;
- the app must not show a fake service address or claim that managed quota registration succeeded;
- StoreKit premium entitlement can still unlock local premium features; failure to register remote quota must remain a separate, visible state.

`ACTION REQUIRED — Choose one honest submission path:`

- **Path A:** deploy and verify the production Worker, then replace this section with the real reviewer endpoint behavior; or
- **Path B:** submit with managed AI unavailable, ensure product-page copy/screenshots do not advertise it as usable, and retain this limitation in review notes.

## StoreKit Sandbox / TestFlight matrix

| Scenario | Device/account state | Expected evidence |
|---|---|---|
| Fresh install, no purchase | New install, Sandbox account signed in | App opens without app account; local 7-day experience disclosure is visible; StoreKit products load. |
| Monthly purchase | `com.zhili.todo.premium.monthly.v2` | Verified transaction finishes; local premium features unlock; product price comes from StoreKit. |
| Yearly purchase | `com.zhili.todo.premium.yearly.v2` | Same as monthly; billing period/display text matches StoreKit. |
| User cancels/pending/unverified | Exercise each StoreKit test state | No false premium entitlement; localized status/error is visible. |
| Restore | Reinstall or second test device using same Sandbox Apple Account | Restore Purchases calls App Store sync and current entitlement unlocks locally. |
| Expired | Accelerated renewal/expiry | Refresh or relaunch removes local premium entitlement after expiration. |
| Revoked/refunded | StoreKit test or Sandbox revocation | `revocationDate` causes local entitlement removal. The repository implements Notifications V2 refund/revocation processing; `ACTION REQUIRED` configure the production ASC URL and verify Send Test Notification plus Sandbox refund/revocation before managed quota ships. |
| No managed endpoint | Current Release configuration | Premium local features work; remote Pro registration reports unavailable; no JWS is uploaded. |
| Consent accept | BYOK test credential or verified managed service | First request shows recipient/content disclosure; accept permits only matching route/version. |
| Consent decline | Same route | No remote request; local planner remains available. |
| Consent revoke | Stored consent exists | Settings revoke clears record; next remote request asks again. |
| Delete local AI config | BYOK configured | Keychain key, provider/model/base URL preferences, and consent record are removed; remote deletion is not claimed. |
| Notification allowed/denied | Test both OS states | Local reminder works when allowed; denied/restricted state is explained with Settings route. |
| Voice allowed/denied | Test microphone and speech permissions separately | Transcript enters composer; denied state explains the missing permission; raw audio does not go to Worker/model. |

## Pre-submission blockers visible to review

- [ ] `ACTION REQUIRED` production managed endpoint decision is resolved and notes match the submitted binary.
- [ ] `ACTION REQUIRED` Worker KV ID and secret are production values if Path A is chosen.
- [x] Worker repository code performs Apple JWS verification and Notifications V2 renewal/expiry/refund/revocation state processing.
- [ ] `ACTION REQUIRED` production ASC Notifications V2 URL, `APP_STORE_APPLE_ID`, Send Test Notification, Sandbox transactions, and production read-back are configured and verified before managed subscription quota ships.
- [ ] `ACTION REQUIRED` App Store Connect review contact and any secure review credential are entered by the account owner.
- [x] On 2026-08-11, public support/privacy pages returned HTTP 200 and matched the current consent/revocation controls and confirmed support email; recheck before submission.
