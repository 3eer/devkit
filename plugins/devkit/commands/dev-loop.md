---
description: Run full dev loop — design through implementation, QA, review, commit, PR, and acceptance test handoff
argument-hint: "<task description>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Skill, Task
---

# Dev-Loop — Full Development Workflow

引数: `$ARGUMENTS`

`dev-loop-workflow` スキルに従い、設計 → 実装 → 検証 → コミット → レビュー → PR → 受け入れテスト依頼まで実行する。

## 実行手順

1. `$ARGUMENTS` をタスク説明として `dev-loop-workflow` スキルの Phase 0 から順に実行する
2. Harness（Claude Code / Cursor）に従い dev-lead / dev-developer / dev-qa を起動する
3. エスカレーション事項のみ本人に確認する
4. Phase 8 で Decision Brief + 受け入れテスト依頼を提出して停止する（マージはしない）
