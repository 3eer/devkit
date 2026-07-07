---
description: Implement with acceptance criteria through test loop, review, Live Proof, commit, and PR creation
argument-hint: "<task with acceptance criteria>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Skill, Task
---

# Implement-to-PR — Ship It Workflow

引数: `$ARGUMENTS`

受け入れ条件付きの実装依頼を、`implement-to-pr-workflow` スキルに従って PR 作成まで完結させる。

## 実行手順

1. `$ARGUMENTS` からゴール・受け入れ条件・制約を抽出する（Step 0）
2. Step 1〜8 を順に実行する（Harness 表に従い Claude Code / Cursor 両対応）
3. Step 8 の Decision Brief を提出して停止する（マージはしない）

設計フェーズが必要な場合は `/devkit:dev-loop` を使うこと。
