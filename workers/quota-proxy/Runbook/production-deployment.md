# Managed AI production deployment and rollback

This runbook prepares a production release; it is not evidence that a Worker, KV namespace, Durable Object, secret, domain, App Store notification URL, or iOS endpoint exists. Replace every angle-bracket token only with an owner-verified value. Never paste secret values, device IDs, Support IDs, JWS bodies, request content, or full KV keys into tickets, logs, screenshots, or release evidence.

## 1. Required owners and explicit approval gates

Record names only for these roles in the private release ticket: Cloudflare account owner, Apple App Store Connect Account Holder/Admin, iOS release signer, privacy owner, and rollback operator.

Stop for **owner approval** before each external mutation group:

1. First `wrangler deploy`, which creates or updates the Worker, the automatically provisioned `QUOTA` KV namespace, `ENTITLEMENTS` plus `DEVICE_PRIVACY` Durable Object bindings, and SQLite migrations `v1`/`v2`.
2. Every `wrangler secret put` command.
3. The final Worker deployment and traffic enablement.
4. App Store Connect Production/Sandbox notification URL changes and Send Test Notification.
5. Adding `ManagedAIBaseURL` to the Release app configuration, signing, archiving, uploading, or distributing the app.
6. Any production KV write/delete used for a user data deletion or erasure reversal.

No command in this document authorizes those mutations by itself.

## 2. Configuration inventory

| Name | Production rule | Storage / owner check |
|---|---|---|
| `DEEPSEEK_API_KEY` | Real managed-model credential | Cloudflare encrypted secret; model-service owner supplies interactively |
| `APP_STORE_BUNDLE_ID` | Exact `com.zhili.todo-native` | Cloudflare encrypted secret; iOS release owner verifies |
| `APP_STORE_ENVIRONMENT` | Exact `Production` | Cloudflare encrypted secret; never point Sandbox traffic at this Worker |
| `APP_STORE_APPLE_ID` | Numeric App Store Connect Apple ID, not bundle ID/Team ID | Cloudflare encrypted secret; ASC owner verifies |
| `ALLOWED_ORIGINS` | Comma-separated exact HTTPS origins, or empty when only native iOS uses the Worker | Cloudflare encrypted secret; Web owner verifies every origin |
| `ERASURE_ADMIN_TOKEN` | Independent random 32–256 character bearer credential used only by the owner erasure route | Cloudflare encrypted secret; privacy owner generates and stores it separately from model/App Store credentials |

`.dev.vars.example` contains names with blank values only. Copy it to ignored `.dev.vars` for local work; do not reuse production values locally and do not commit `.dev.vars`.

## 3. Local release gate (no external mutation)

From `workers/quota-proxy`:

```bash
npm ci
npm test
npm audit
npx wrangler deploy --dry-run
git diff --check
```

Expected: tests and audit pass; dry-run builds the Worker and recognizes all three bindings (`QUOTA`, `ENTITLEMENTS`, and `DEVICE_PRIVACY`) plus migrations `v1` and `v2`. A dry-run does not prove account access, KV creation, secrets, notification delivery, or a live domain.

Review the planned mutations without running them:

```text
CREATE/UPDATE Worker todo-quota-proxy
CREATE/UPDATE automatically provisioned KV binding QUOTA
CREATE/UPDATE Durable Object bindings ENTITLEMENTS and DEVICE_PRIVACY with SQLite migrations v1/v2
SET six named Worker secrets (values never recorded)
SET App Store Connect Production notification URL
ADD ManagedAIBaseURL to the iOS Release configuration and rebuild
```

## 4. Owner-authorized Cloudflare deployment

After Cloudflare owner approval and a fresh authenticated-account check:

```bash
npx wrangler whoami
npx wrangler deployments list --name todo-quota-proxy --json
npx wrangler deploy
```

Checkpoint: record only the account label, Worker name, generated deployment/version ID, UTC time, and owner name. Verify Wrangler resolved `QUOTA`, `ENTITLEMENTS`, and `DEVICE_PRIVACY`, and applied migrations `v1` and `v2`; do not copy namespace IDs into git. This service has never been deployed, so the minimum first-deploy and rollback baseline is the version containing privacy migration `v2`. A version earlier than the privacy migration must never receive production traffic. The first deployment is intentionally fail-closed until secrets exist.

Set values interactively, one at a time; the shell command contains names only:

```bash
npx wrangler secret put DEEPSEEK_API_KEY
npx wrangler secret put APP_STORE_BUNDLE_ID
npx wrangler secret put APP_STORE_ENVIRONMENT
npx wrangler secret put APP_STORE_APPLE_ID
npx wrangler secret put ALLOWED_ORIGINS
npx wrangler secret put ERASURE_ADMIN_TOKEN
npx wrangler secret list
npx wrangler deploy
npx wrangler deployments list --name todo-quota-proxy --json
```

Checkpoint: secret list contains all six names, never their values. If native-only, `ALLOWED_ORIGINS` may be omitted; browser origins require exact HTTPS entries and no wildcard. Record the real base URL privately as `https://<actual-worker-domain>` only after Cloudflare reports it. Do not infer or publish a domain from the Worker name.

## 5. Redacted live checks

Use a new synthetic device ID held only in the controlled terminal. Do not use a customer Support ID. Store response bodies only in the terminal and record status/code aggregates in evidence.

```bash
read -r -s WORKER_BASE_URL
SYNTHETIC_DEVICE_ID="release-check-$(openssl rand -hex 12)"
curl --fail-with-body --silent --show-error \
  -H "X-Device-Id: $SYNTHETIC_DEVICE_ID" \
  "$WORKER_BASE_URL/proxy/quota"
curl --silent --show-error --output /dev/null --write-out '%{http_code}\n' \
  -X POST -H 'Content-Type: application/json' \
  -H "X-Device-Id: $SYNTHETIC_DEVICE_ID" \
  --data '{"transactionJwt":"invalid-release-check"}' \
  "$WORKER_BASE_URL/proxy/register-pro"
```

Expected: quota is safe JSON; invalid registration returns `401`; no secret/provider error or JWS is reflected. Run chat only with non-sensitive synthetic content and record HTTP status plus quota delta, never request/response content. Validate a real monthly/yearly purchase only through App Store Sandbox on an isolated Sandbox Worker; never paste its JWS into a shell transcript.

## 6. App Store Server Notifications V2

After a real HTTPS domain exists, the ASC owner enters exactly:

```text
Production URL: https://<actual-worker-domain>/proxy/app-store-notifications
```

Use App Store Connect **Send Test Notification**. A verified `TEST` must receive HTTP `200`; record the Apple test outcome/UTC time and Worker 2xx metric only. Do not record `signedPayload`. Sandbox must use a separately configured Sandbox Worker with `APP_STORE_ENVIRONMENT=Sandbox`; do not send Sandbox notifications to Production. Only after `SUBSCRIBED`, `DID_RENEW`, `EXPIRED`, `REFUND`, and `REVOKE` have passed the Sandbox matrix may the owner enable managed subscription quota.

## 7. Release `ManagedAIBaseURL` rebuild

After live checks pass, the iOS release owner adds the verified base URL (without `/proxy`) as the `ManagedAIBaseURL` property under the `TodoNative` target in `ios/project.yml`, regenerates the project, and reviews the only intended diff:

```bash
cd ../../ios
xcodegen generate
git diff -- project.yml TodoNative.xcodeproj/project.pbxproj TodoNative/Info.plist
xcodebuild -project TodoNative.xcodeproj -scheme TodoNative \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:TodoNativeTests/QuotaClientTests \
  -only-testing:TodoNativeTests/PurchaseManagerTests test
```

Then create a signed Release Archive with the owner’s Apple Distribution identity. Read back the archived app’s `Info.plist` and confirm `ManagedAIBaseURL` equals the verified HTTPS base URL, `get-task-allow=false`, and no `.storekit` file or debug override is bundled. This repository does not claim those signed checks until they run successfully.

## 8. Strongly ordered managed-data erasure

The app has no public self-service destructive endpoint. The owner-only `/internal/erase-device` route requires the independent `ERASURE_ADMIN_TOKEN`, a bounded JSON body, and exact `TD-<UUID>` Support ID. Copy it from the app; do not type or case-edit it. The helper accepts an all-uppercase or all-lowercase UUID and sends the canonical uppercase value; mixed-case UUID input is rejected. Because this Worker has never been deployed, the first-deploy contract canonicalizes UUID device IDs to uppercase across every route, while leaving non-UUID opaque IDs unchanged. It never returns or logs the identifier. `DEVICE_PRIVACY` names one Durable Object from the domain-separated canonical device hash; every chat, quota, and register operation obtains a strong lease before any device-bearing KV/DO read, write, or provider call, and releases it in `finally`.

Erasure atomically marks that Device Privacy DO erased. If a lease is active it returns HTTP `202 retry` and performs no cleanup. No new lease can begin; an already-held lease may still add its hash-only resource catalog entry before writing. quota/chat pre-register free/current-daily resources, and register pre-registers the original-transaction hash before pointer/DO writes.

After leases finish, each authorized retry executes one bounded catalog/legacy phase. A KV delete marks its catalog item pending for at least 65 seconds; the next eligible retry performs an exact read-back. A visible value is deleted again and starts another 65-second window; only `null` acknowledges the item. Entitlement cleanup covers the exact pointer and original-index prefix, while strong Entitlement DO `/erase-device` removes its mapping. Once the catalog is empty, the route requires at least two empty legacy scans/exact read-backs separated by at least 65 seconds before `200 erased`. Thus `200` means the strong catalog is empty, every cataloged KV key passed the propagation-window read-back, the hashed mapping was removed, and the two time-separated legacy verification passes were empty—not merely that one eventually-consistent list returned empty. Concurrent owner retries are revision/phase-safe. A no-data Support ID still establishes suppression and completes the same empty verification. Notifications cannot recreate mappings; future register/chat/quota return `410 device_erased`.

The helper keeps the token and Support ID off argv and stdout. In a private terminal, read both without echo and pipe them over stdin:

```bash
read -r -s ERASURE_ADMIN_TOKEN_INPUT
read -r -s SUPPORT_ID_INPUT
printf '%s\n%s\n' "$ERASURE_ADMIN_TOKEN_INPUT" "$SUPPORT_ID_INPUT" \
  | node scripts/erase-device.mjs 'https://<actual-worker-domain>'
unset ERASURE_ADMIN_TOKEN_INPUT SUPPORT_ID_INPUT
```

Output is only `erased`, `retry`, or a stable status error. On `retry`, an active request must finish first. For a pending KV verification or between the two empty scans, wait at least 65 seconds before retrying; other bounded phases may continue immediately. Stop if retries do not converge within the approved operational bound and investigate for an orphan lease or storage failure; never force progress. Then use a synthetic replay to verify chat/quota/register return `410 device_erased`, and use exact-prefix KV read-back to verify no raw-device keys exist. Never copy the token, Support ID, full keys, or JWS into a transcript.

An orphan lease caused by a crashed invocation remains fail-closed: erasure stays `202` and cleanup does not run. There is deliberately no TTL or force-release route because a late write after forced cleanup would violate deletion ordering. Stop, drain/investigate the deployed version, and obtain a separate privacy/security decision before any recovery implementation.

There is no un-erase endpoint. A future restore capability requires a separately reviewed design, explicit user request, privacy-owner approval, and audit trail; ordinary launch, purchase restore, notifications, deploy, or rollback cannot clear erased state.

## 9. Rollback

Before deployment, save the prior healthy Worker version ID from `npx wrangler deployments list --name todo-quota-proxy --json`. The rollback target must contain `DEVICE_PRIVACY`, migration `v2`, and lease enforcement. Never roll back to a version earlier than the privacy migration. On a code regression, the authorized rollback operator runs:

```bash
npx wrangler rollback <previous-healthy-version-id> --name todo-quota-proxy --message 'release rollback'
npx wrangler deployments list --name todo-quota-proxy --json
```

Do not delete KV, Durable Object data, secrets, or Device Privacy erased state during code rollback. If no privacy-capable healthy version exists, disable traffic instead of rolling back. If the endpoint is unsafe, remove `ManagedAIBaseURL` from a new iOS build and disable managed-AI claims; an already shipped binary cannot be remotely rewritten. App Store notification URL changes require separate ASC owner approval. Record the rollback version, UTC time, owner, redacted health-check outcomes, and next action.
