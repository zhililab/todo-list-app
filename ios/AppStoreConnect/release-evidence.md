# App Store Release Evidence

更新日期：2026-08-12
Bundle ID：`com.zhili.todo-native`

证据基线分层：

- 产品验证 HEAD：`3f38fb9f2e16221545f19eef839f04051ded74b7`（tree `91be5883d540541250fa544b7816e44b81626ac0`）。这是历史规整后的可复现产品树；2026-08-12 在该规整树上 fresh 验证根目录 `136/136`、Worker `67/67`、iOS `367/367`，Debug 与 Release 模拟器 build 均通过。
- Worker 部署版本：Production deployment `7df8cd2a-3970-46bf-bbec-adb759fe5ac8` / version `5452a702-104d-4238-a8fc-accaa7709eaf`；Sandbox deployment `acb0544d-3601-4a8b-a288-f030e40a3db1` / version `1d994964-0990-4464-bf83-2c29da0ed20d`。这些是外部控制面版本，不等同于 Git HEAD。
- docs HEAD：本 docs commit（checkout 后用 `git rev-parse HEAD` 解析）。文档修复后的材料测试必须单独重跑；产品测试结果不归因于 docs-only HEAD。

> 本文件把仓库证据、构建/测试、外部控制面和真实线上状态分开记录。`PASS` 只表示该行命令或静态检查通过，不代表 Apple Distribution 签名、App Store Connect 上传、TestFlight 或 App Review 已完成。
>
> **2026-08-12 superseding update：** 下方 2026-08-11 Archive 与部署前审计仍作为历史证据保留；凡其关于“Release 缺少 `ManagedAIBaseURL`”或“Worker/KV/DO/secrets 未部署”的结论与 2026-08-12 证据冲突，均以本更新和第 1.1 节为准。该更新不把模拟器、通用真机构建或 HTTP 探针提升为指定真机交互验收。

## 1. 结论

当前结论：**BLOCKED — 材料仍不可提交。**

- `PASS（仓库/构建）`：2026-08-12 产品验证 HEAD `3f38fb9f2e16221545f19eef839f04051ded74b7` fresh 全量为根目录 `136/136`、Worker `67/67`、iOS `367/367`；Debug 与 Release 模拟器 build 通过。通用签名 Debug-iphoneos build 已在规整前的等价产品内容上通过，本轮未重复执行。2026-08-11 历史基线仍为根目录 `135/135`、Worker `66/66`、iOS `342/342`、Task 5 定向 `15/15`，以及当时的无签名 Release Archive。
- `PASS（供应链/包检查）`：根目录与 Worker `npm audit` 均为 0；Wrangler dry-run 成功，包大小 `536.02 KiB` / gzip `93.64 KiB`，声明 `QUOTA` + `ENTITLEMENTS` + `DEVICE_PRIVACY` bindings。
- `PASS / BLOCKED（外部只读）`：Privacy、Terms、Support 三条公开 URL 均返回 HTTP 200 且正文包含支持邮箱；但线上 Privacy 尚未包含删除后的有限哈希保留披露，启用 managed AI 的 Path A 前必须重新发布并 live 核对。Terms 与 Support 当前通过。
- `PASS（本机身份可用性）/ BLOCKED（发布闭环）`：2026-08-12 fresh `security find-identity -v -p codesigning` 显示 `3 valid identities found`，其中包括 `Apple Distribution: ZHI LI`；通用 Debug-iphoneos build 已使用 Apple Development 签名。当前 HEAD 尚未 fresh 执行或验证 Apple Distribution Archive、App Store IPA export、`get-task-allow=false`、上传或 ASC processing；provisioning/App Store profile、export 配置、上传和 TestFlight 仍是独立 gate。
- `PASS（仓库离线验证）`：Worker 已实现 Apple ES256 JWS、固定 Apple roots/完整证书链、bundle/environment/product/到期与 payload 撤销字段校验；App Store Server Notifications V2 的续费、到期、退款和撤销幂等处理也已实现。
- `PASS（配置与 Worker 控制面）/ BLOCKED（端到端发布）`：当前 `Info.plist` / `Project.yml` 已配置 production `ManagedAIBaseURL`；production 与独立 Sandbox Worker 已有当前 deployment、KV、DO 及仅名称可见的 secrets 证据。App Store Connect Notifications V2 URL、Send Test Notification、Sandbox 真交易/通知以及指定 iPhone 上的 managed AI 交互仍未验证。离线验签不做 OCSP，发布负责人必须接受该边界或在上线前实现完整在线检查。
- `PASS（仓库）/ BLOCKED（生产）`：`DEVICE_PRIVACY` 强一致 lease/erasure、Entitlement DO mapping 清理、raw device ID 消除及 owner runbook 已实现并测试；真实 Cloudflare 环境尚未完成脱敏 active-lease retry → erase → replay → read-back 演练。
- `PASS`：依据用户此前明确的发布授权，当前法律页 source commit `a21b1b94327acc65963659e284c51d2f9c62fda3` 已部署为 Sites version 14。

### 1.1 2026-08-12 Worker 与设备补充证据（supersedes 2026-08-11 部署结论）

以下内容来自 Task 5 原始执行报告和 2026-08-12 fresh 的 Wrangler 只读 `deployments list`、`versions list`、`versions view`；输出已脱敏，不记录 secret 值、author ID 或 author email。部署和 secret 变更命令本次均未执行。

| 环境 | 当前 deployment / version | bindings（值已脱敏） | 只读路由检查 |
|---|---|---|---|
| Production `todo-quota-proxy` | deployment `7df8cd2a-3970-46bf-bbec-adb759fe5ac8`；version `5452a702-104d-4238-a8fc-accaa7709eaf`；`100%` | KV `QUOTA` (`7930375f712c4fb383fc6d424b0b733c`)；DO `ENTITLEMENTS` (`0513d124128c4477b971a3a7f6997a22`)；DO `DEVICE_PRIVACY` (`fab8ad3f426b44619a978de903ca72a2`)；secret names：`ALLOWED_ORIGINS`、`APP_STORE_APPLE_ID`、`APP_STORE_BUNDLE_ID`、`APP_STORE_ENVIRONMENT`、`DEEPSEEK_API_KEY`、`ERASURE_ADMIN_TOKEN` | `GET /proxy/quota` 未带 device ID：HTTP `401`，`application/json`，body code `missing_device_id` |
| Sandbox `todo-quota-proxy-sandbox` | deployment `acb0544d-3601-4a8b-a288-f030e40a3db1`；version `1d994964-0990-4464-bf83-2c29da0ed20d`；`100%` | KV `QUOTA` (`0e064308deb54c12adc5a5bb544e6d1f`)；DO `ENTITLEMENTS` (`a44baa62f4484a9a921ca14d21aebae0`)；DO `DEVICE_PRIVACY` (`1316b52c29114073b049afd19cb44324`)；secret names：`APP_STORE_BUNDLE_ID`、`APP_STORE_ENVIRONMENT`、`DEEPSEEK_API_KEY`、`ERASURE_ADMIN_TOKEN` | `GET /proxy/quota` 未带 device ID：HTTP `401`，`application/json`，body code `missing_device_id` |

Production 在 deployment `7df8cd2a-3970-46bf-bbec-adb759fe5ac8` 之前的精确 active baseline 已从连续 deployment history 恢复：deployment `2eed8a85-9752-4278-b2a9-0f5f7b396a29` 将 version `0cc40f76-4ecf-4fb6-b247-d645277dfc7f` 分配为 `100%`。因此历史流量基线可确定性还原，不是 unknown。需要注意：该旧 version 的只读详情不含 `DEEPSEEK_API_KEY` binding；稍后的 version `fde0b6a7-20b2-4f46-8549-59f724d5b52f` 虽包含该 secret，却未出现在 deployment history 中，不能替代“上线前 active baseline”。任何未来回退都必须由 owner 先评估 managed chat 失效风险，本次未执行回退。

匿名设备 A 在 Task 5 验证时为 `unavailable`：针对该设备的 destination build、install、launch 均失败或被阻塞，八步交互验收 **NOT OBSERVED**。复验时必须运行 `xcodebuild -showdestinations` 与 `xcrun devicectl list devices`，选择当时可用的已配对设备；不得把发现的 destination/CoreDevice 标识写入跟踪文件。通用签名 Debug-iphoneos build 成功仅是 fallback build evidence，不证明真机安装、启动、free-input、picker、Dark Mode、无障碍或 managed AI 行为。

## 2. 验证状态

| 层级 | 状态 | 命令 | 2026-08-11 真实结果 |
|---|---|---|---|
| Root tests | **PASS** | `node --test` | exit `0`；`135 passed, 0 failed` |
| Worker tests | **PASS** | `cd workers/quota-proxy && node --test test.mjs` | exit `0`；`66 passed, 0 failed` |
| Task 5 iOS focused tests | **PASS** | `xcodebuild ... -only-testing:TodoNativeTests/QuotaClientTests -only-testing:TodoNativeTests/PurchaseManagerTests test` | exit `0`；`15 passed, 0 failed` |
| Xcode project | **PASS** | `cd ios && xcodegen generate` | exit `0`；工程生成成功 |
| iOS tests | **PASS** | `xcodebuild -project TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test` | exit `0`；`342 passed, 0 failed`；`** TEST SUCCEEDED **` |
| Debug build | **PASS** | `xcodebuild ... -configuration Debug ... build` | exit `0`；`** BUILD SUCCEEDED **` |
| Code-signing identities | **PASS（身份可用性）** | `security find-identity -v -p codesigning` | 2026-08-12 fresh read-only check：exit `0`；`3 valid identities found`，包括 `Apple Distribution: ZHI LI`。不记录 identity hash、Team ID 或私钥材料。 |
| Unsigned static Archive | **PASS（仅静态）** | `xcodebuild ... -configuration Release -destination 'generic/platform=iOS' -archivePath /private/tmp/todo-archive.3UdF8w/TodoNative.xcarchive CODE_SIGNING_ALLOWED=NO archive` | exit `0`；`** ARCHIVE SUCCEEDED **`。该 Archive **未签名、不是 App Store 可上传 Archive** |
| Signed Archive/export/upload | **NOT RUN / BLOCKED** | Apple Distribution archive、`xcodebuild -exportArchive`、ASC upload | 当前 HEAD 尚未 fresh 执行或验证；identity 可用性不证明 provisioning/App Store profile、export options、上传、ASC processing 或 TestFlight。未虚构 Archive、IPA、上传或 processing 结果。 |
| Web production build | **PASS** | `npm run build` | exit `0`；production build 成功 |
| Root / Worker dependency audit | **PASS** | `npm audit` / `cd workers/quota-proxy && npm audit` | 两处均 `0 vulnerabilities` |
| Wrangler dry-run | **PASS（本地）** | `cd workers/quota-proxy && npx wrangler deploy --dry-run` | exit `0`；`536.02 KiB` / gzip `93.64 KiB`；bindings 为 `QUOTA`、`ENTITLEMENTS`、`DEVICE_PRIVACY` |

构建环境：Xcode `26.6`（build `17F113`）；无签名 Archive 使用 `iphoneos26.5` SDK（build `23F81a`），deployment target `17.0`，arm64。

旧无签名 Archive 曾出现 `All interface orientations must be supported unless the app requires full screen`。复审后工程和 fresh Archive 均确认 iPhone 与 iPad 声明 portrait、portrait upside-down、landscape left/right；过滤后的 Archive warning 输出中旧方向 warning 为 0。构建仍有 SwiftData `Sendable` 前瞻 warning，以及 `No AppIntents.framework dependency found` 的 metadata-skipped warning；两者与方向声明无关。

## 3. Archive 静态检查

检查对象：`/private/tmp/todo-archive.3UdF8w/TodoNative.xcarchive/Products/Applications/TodoNative.app`。

| 项目 | 状态 | 证据 |
|---|---|---|
| Archive 类型 | **PASS（仅静态）** | Release、arm64、iPhoneOS；Archive `SigningIdentity` 与 `Team` 均为空，app `codesign` 返回 `code object is not signed at all` |
| Bundle / version / build | **PASS** | `CFBundleIdentifier=com.zhili.todo-native`；`CFBundleShortVersionString=1.0.0`；`CFBundleVersion=1` |
| 法律 URL | **PASS** | `PrivacyPolicyURL`、`TermsOfUseURL`、`SupportURL` 均为 `https://todo-list-app.zhili1993.chatgpt.site/...` |
| Managed AI endpoint | **SUPERSEDED（该 Archive 仅为 2026-08-11 历史证据）** | 当时 Archive `Info.plist` 不含 `ManagedAIBaseURL`；当前 source/generated plist 已配置 production URL，但仍须在最终 Apple Distribution Archive 中重新读取确认 |
| Privacy Manifest | **PASS（内容仍需随最终生产数据流复核）** | `PrivacyInfo.xcprivacy` 已入包且 plist lint 通过；`NSPrivacyTracking=false`；UserDefaults reason `CA92.1`；Collected Data 数组为空 |
| 权限本地化 | **PASS** | `en.lproj/InfoPlist.strings` 与 `zh-Hans.lproj/InfoPlist.strings` 已入包，均包含 Microphone 与 Speech Recognition 文案 |
| 方向声明 | **PASS（静态）** | Archive `Info.plist` 中 iPhone/iPad 均包含 portrait、upside-down 与两个 landscape；旧方向 warning 在 fresh Archive 过滤输出中无命中 |
| StoreKit 测试配置 | **PASS** | Archive 内 `find ... -name '*.storekit'` 无结果 |
| App icons | **PASS** | AppIcon source 13/13 `hasAlpha: no`；Archive 导出的 iPhone/iPad icon 2/2 `hasAlpha: no` |
| DEBUG 通知测试入口 | **PASS** | Release Mach-O 对 `test-notification-` / `sendTestNotification` 的 raw、`strings` 和 symbol 检查均无命中；源码 UI/函数在 `#if DEBUG` 内 |
| Release signing | **NOT RUN / BLOCKED** | 本机 Apple Distribution identity 可用，但当前 HEAD 尚未 fresh 生成或验证 Apple Distribution 签名包；provisioning/App Store profile 仍待核验。 |
| `get-task-allow=false` | **NOT RUN / BLOCKED** | 该项必须从真实签名 app entitlement 读取；无签名 Archive 不能证明 |

## 4. Web 法律页

### 4.1 本地 production build

`npm run build` fresh 通过。`dist/privacy.html`、`dist/terms.html`、`dist/support.html` 均有真实 `<main>` / 双语 `<h1>` 正文、正确 title、互链与返回应用链接，且三页正文包含 `mailto:lz123321@live.com`。`dist/` 是生成物，不暂存、不提交。

### 4.2 真实线上只读验证

部署证据：依据用户此前明确的发布授权，法律页 source commit `a21b1b94327acc65963659e284c51d2f9c62fda3` 已成功部署为 Sites version 14，目标为 `https://todo-list-app.zhili1993.chatgpt.site`。

验证命令：对三条 URL 使用 `curl -L --max-time 15`；部署完成后主代理另用 `curl -sSL --compressed https://todo-list-app.zhili1993.chatgpt.site/terms.html` fresh 复核，Terms 正文第 46 行包含 `lz123321@live.com`。

| URL | HTTP | 标题 / 正文 | 状态 |
|---|---:|---|---|
| `https://todo-list-app.zhili1993.chatgpt.site/privacy.html` | `200`，`text/html; charset=utf-8` | `隐私政策 / Privacy Policy · AI-native Todo`；互链正常；正文含 `lz123321@live.com` | **PASS** |
| `https://todo-list-app.zhili1993.chatgpt.site/terms.html` | `200`，`text/html; charset=utf-8` | `服务条款 / Terms of Use · AI-native Todo`；互链正常；Sites version 14 正文第 46 行含 `lz123321@live.com` | **PASS** |
| `https://todo-list-app.zhili1993.chatgpt.site/support.html` | `200`，`text/html; charset=utf-8` | `支持 / Support · AI-native Todo`；互链正常；正文含 `lz123321@live.com` | **PASS** |

Sites version 14 已部署成功；部署后 Terms 已 fresh 复核支持邮箱。Terms 与 Support 当前为 **PASS**。仓库 Privacy 源码已新增删除后的有限哈希保留披露，但 version 14 尚未包含该修订，因此 Privacy 对 Path A 为 **BLOCKED — 重新发布并 live 复核**；Path B 不启用 managed Worker 数据路径，不受此项阻塞。

## 5. 仓库与生产阻塞

| 项目 | 当前 fresh 证据 | 状态 / 所需动作 |
|---|---|---|
| Managed endpoint | 当前 source/generated plist 已配置 production `ManagedAIBaseURL`，Task 5 route-isolation diagnosis 也确认 app bundle 可读取该 URL | **PASS（配置）/ BLOCKED（最终包与交互）** — 需从最终 Apple Distribution Archive 重新读取并在指定真机完成 managed AI 交互验收 |
| Worker bindings | 2026-08-12 Wrangler 只读 version view 见第 1.1 节：production / Sandbox 使用互相独立的 `QUOTA`、`ENTITLEMENTS`、`DEVICE_PRIVACY` namespace，当前版本均为 migration tag `v2` | **PASS（控制面存在性）/ BLOCKED（删除演练）** — namespace 与 bindings 已可 read-back；真实隔离环境的 active-lease / erase / replay 验收仍未执行 |
| Apple transaction verification | 产品验证 HEAD `3f38fb9f2e16221545f19eef839f04051ded74b7` 所含 Worker 树覆盖 Apple root pin、leaf→WWDR→root、ES256、bundle/environment、月/年产品、到期与 payload 撤销字段 | **PASS（仓库离线验签）/ BLOCKED（生产）** — 未用 Sandbox/Production 真 JWS 验证；不执行 OCSP |
| Notifications V2 | 同一产品验证树的 Entitlement DO 已实现外/内层 JWS 验签、app identity/environment/product 校验，以及 `SUBSCRIBED` / `DID_RENEW` / `EXPIRED` / `REFUND` / `REVOKE` 幂等状态更新 | **PASS（仓库）/ BLOCKED（外部）** — 生产 ASC URL、`APP_STORE_APPLE_ID`、Send Test Notification、Sandbox 续费/到期/退款/撤销验证均未执行 |
| Managed data deletion | 设置页提供 Support ID；首次部署统一 UUID identity 大小写；`DEVICE_PRIVACY` DO 在所有 device-bearing 操作前发强一致 lease 并预登记 hash-only resource catalog，erasure 以持久 catalog/phase 有界清理，KV 项需 65 秒 exact read-back，catalog 空后需两轮间隔 65 秒的 legacy 空验证；并发 owner retry、跨-colo 延迟、空身份 suppression 与注册指针故障顺序均有测试；操作见 `managed-data-deletion-runbook.md` | **PASS（仓库）/ BLOCKED（外部）** — 尚未在真实隔离环境完成 active-lease retry、KV propagation window、两轮空扫描、幂等 erase 与 read-back 演练 |
| Codesigning / export / upload | 2026-08-12 fresh check 有 `3 valid identities found`，包括 `Apple Distribution: ZHI LI`；通用 Debug-iphoneos build 使用 Apple Development 签名 | **BLOCKED** — 当前 HEAD 尚未 fresh 验证 Apple Distribution Archive；仍需核验 provisioning/App Store profile 与 export options，再完成 export、upload、ASC processing 和 TestFlight 验证。 |

## 6. 外部所有者操作（本次 NOT RUN）

以下项目没有当前控制面证据，均为 **NOT RUN / ACTION REQUIRED**：

- Apple Developer Identifier / Team / capabilities 与 App Store profile；
- App Store Connect app record、SKU、默认语言、build processing；
- Paid Apps Agreement、tax/banking、base app price、availability/territories；
- Subscription Group、monthly/yearly products、真实价格、地区、本地化与审核截图；
- Category、Age Rating、Content Rights、Export Compliance、DSA、copyright/controller；
- App Privacy 最终问卷、真实 review contact、可回复支持邮箱；
- TestFlight groups 与 iPhone/iPad 安装、启动、StoreKit Sandbox、通知/麦克风/语音权限、语言和 light/dark 矩阵；
- Version release method、最终提交人、时间、build/version 与回退方案。

## 7. 提交决策

当前结论：**材料准备中，不能据此宣布可提交。**

最终提交前必须关闭或由有权限 owner 明确选择：

- **Managed AI 上线后提交：** endpoint、KV、secrets、Apple JWS 验签、bundle/environment 校验、撤销同步、真实生产验证与隐私材料全部一致；或
- **Managed AI 暂不可用提交：** binary、元数据、截图和审核备注均诚实说明，商品不承诺托管额度，App Privacy 回答采用无 managed 传输的实际路径。

最终提交人：`ACTION REQUIRED`

最终提交时间：`ACTION REQUIRED`

ASC build/version：`ACTION REQUIRED`

提交决策与例外：`ACTION REQUIRED`
