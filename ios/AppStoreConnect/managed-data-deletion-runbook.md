# 托管服务数据删除 Runbook

更新日期：2026-08-11
适用范围：未来启用 Path A 托管 AI 后，处理用户主动发起的 Worker/KV 数据删除请求。
仓库基线：Worker 提交 `5ee3606`；Worker `66/66`、Wrangler dry-run 及 bindings `QUOTA` / `ENTITLEMENTS` / `DEVICE_PRIVACY` 通过。这些只是仓库证据，不是生产删除演练。

> **仓库实现 PASS / 生产操作 BLOCKED。** Worker 已实现强一致 `DEVICE_PRIVACY` Durable Object lease/erasure，且不提供公开删除端点（也不是公开自助删除）；但尚未在真实 Cloudflare 环境完成脱敏 create → erase → retry/read-back 演练。演练成功前不能回复用户“生产数据已删除”。

## 用户入口与 Support ID

1. 用户在 iOS“设置 → 隐私”复制 Support ID，并通过 `lz123321@live.com` 私密提交删除请求。
2. Support ID 格式为 `TD-<UUID>`，直接派生自 app 已使用的匿名 `deviceId`；它不创建第二个标识。操作员必须使用 app 的复制按钮原样粘贴，不得手输或修改大小写。首次部署契约会把 UUID device ID 统一为大写，使历史全小写与当前全大写 UUID 指向同一 identity；非 UUID opaque ID 保持原样。
3. 不要求用户提供 API Key、Apple ID、完整交易 JWS 或支付资料。不得把 Support ID 写入应用日志、公开截图、发布证据、聊天记录或代码提交。
4. 本产品没有账号体系，因此 Support ID 是设备范围删除请求的定位凭据。支持人员应提醒用户从自己的设备复制，并避免在公开渠道发送。

## 删除范围

对目标 `deviceId` 删除以下 KV 记录：

- `free:{deviceId}`；
- 兼容旧记录 `pro:{deviceId}`；
- 以 `daily:{deviceId}:` 开头的全部分页结果；
- 以 `appstore-device-subscription:{deviceId}:` 开头的全部当前设备指针；
- 若上线前审计发现旧开发 schema，再删除 `appstore-entitlement:{deviceId}:` 及其精确关联的 `appstore-original:*` 索引；不得假设旧 key 存在，也不得用无界前缀扫描代替精确匹配。

当前 Durable Object 不保存 raw device ID，只保存 domain-separated device hash、交易/通知 hash 与订阅强一致状态。删除后仅在 Device Privacy DO 保留 hashed erased state，并保留不指向 raw device 的交易级 hash，用于阻止自动重注册、维持退款/撤销顺序并避免影响另一台设备；公开隐私材料必须披露这项有限保留。当前契约不保存完整 JWS、原始 transaction ID 或 notification UUID。

## 已实现的 suppression 契约

仓库测试已覆盖：

1. `SHA-256("todo-erased-device:v1\\0" + deviceId)` 命名 Device Privacy DO；持久状态不含原始 device ID。
2. quota、chat、register-pro 在任何 device-bearing read/write/upstream 前取得强一致 lease，`finally` 释放；erased 后新 lease 统一 `410 device_erased`。
3. owner-only route 需独立 Bearer secret 与精确 Support ID；原子 erase 发现 active lease 时只返回 `202 retry`，不清理。
4. lease 内先把 free/current-daily/original-hash 资源登记到不含 raw device ID 的强 catalog；lease 为 0 后，每次 owner 重试只处理一个有界 catalog/legacy phase。KV 删除后至少等待 65 秒做 exact read-back，仍存在则重删并重新等待，`null` 才 ack；Entitlement mapping 由强 DO 删除。
5. catalog 为空后还要完成至少两轮相隔 65 秒的 legacy 空扫描/精确 read-back；只有 catalog 清空、mapping 删除且两轮均空才返回 `200 erased`。并发 owner 重试按 revision/phase 跟随已提交进度；Notifications V2 永不创建设备 mapping。
6. 自动 register 无法重建已删除记录；即使此前没有服务端数据，有效 Support ID 也会建立 suppression 并通过两轮空验证后返回 `200`。重复删除幂等。`scripts/erase-device.mjs` 从 stdin 接收 token/Support ID，输出不回显二者。

孤儿 lease 永久 fail closed：route 持续 `202`，不会通过 TTL/force 清除。必须停止并调查部署，不能冒险物理删除。生产演练尚未完成时，支持人员只能接收请求并说明托管功能尚未上线，不能回复“已持久删除”。

## 授权操作流程

1. 在受控环境使用复制按钮原样取得 Support ID：必须有精确 `TD-` 前缀，后半段必须是全大写或全小写规范 UUID；mixed-case 会被拒绝。不要把值输出到共享日志。
2. 确认 Cloudflare account、Worker environment 与 namespace，先以精确前缀分页列举数量。记录类别与条数，不记录完整 key 或 Support ID。
3. 依据 [`workers/quota-proxy/Runbook/production-deployment.md`](../../workers/quota-proxy/Runbook/production-deployment.md)，把 token 与 Support ID 通过 stdin 交给 helper；不得放入 argv、shell history 或日志。
4. `202 retry` 可能表示已有 lease、一个有界 phase 已完成、KV 正处于 65 秒传播验证窗口，或正在等待第二轮 legacy 空扫描。活动请求结束后继续；pending/read-back 与两轮空扫描之间必须等待至少 65 秒，其他 phase 可立即继续。若超过批准次数/时间仍不收敛，按孤儿 lease/存储故障处理并停止，禁止强制删除。
5. `200 erased` 已代表 strong catalog 为空、cataloged KV exact read-back 为 null、Entitlement mapping 已强删除，且至少两轮相隔 65 秒的 legacy 验证均空；随后仍按 `free`、`pro`、`daily`、当前 pointer、original-index 与 legacy 前缀做 operator read-back，并重放 quota/chat/register，三路必须都是 `410 device_erased`。
6. 通过支持邮箱回复“Worker/KV 设备范围记录已删除”，同时说明 Apple 与第三方提供商的数据边界。按支持保留政策清理工单中的 Support ID，不在发布报告中复述该值。

## 生产演练与审计

- 上线 Path A 前，用专用合成 Support ID 在隔离环境完成一次 create → active lease → erase/retry → finish → erase → automatic register replay → read-back 演练；演练只记录命令类别、数量、时间、操作者和结果，不记录实际 ID/JWS/token。
- Notifications V2 或交易注册在删除过程中可能并发更新交易级 hash 状态；它们不能创建设备 pointer，但删除完成后的 read-back 仍必须覆盖所有分页，并确认没有新的 raw-device key。任何生产写/delete/replay 均需单独审批。
- 此 Worker 从未部署，最低首次部署/回滚基线必须包含 `DEVICE_PRIVACY` migration `v2`；禁止回滚到更早版本。若未来发现已存在旧 raw DO schema，删除上线保持 **BLOCKED**，先完成迁移审计。
- 若未来加入账号、公开自助删除或新的 KV schema，必须同步更新 app 文案、隐私政策、App Privacy 问卷和本 runbook，并补回归测试。
