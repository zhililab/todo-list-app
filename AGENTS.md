# AGENTS.md

## 提交规范（强制）

- 提交必须合并规整：一次功能迭代的多个零散 commit 合并为**少量逻辑提交**再推送，禁止一次性推送大量小 commit。
- 提交分组按主题：功能（feat）、修复（fix）、文档（docs），可带 scope（如 `feat(companion)`）。
- 禁止 `--no-ff` 空合并提交；rebase/squash 保持线性历史。
- push 前先 `git fetch` 确认远程无领先提交，有则先 rebase。
- 重写已推送历史必须用 `--force-with-lease`，并先备份分支（`git branch backup_* SHA`）验证树一致（`git rev-parse A^{tree} B^{tree}`）。

## 测试与验证

- Web 单测：`node --test`（companion-*.test.js，全绿再提交）
- iOS：`xcodebuild -project ios/TodoNative.xcodeproj -scheme TodoNative -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' test`