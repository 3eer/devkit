---
description: Run autonomous test loop — iterate test→fix→test until all tests pass (max 5 iterations)
argument-hint: "[custom-test-command]"
allowed-tools: Bash, Read, Edit, Glob, Grep
---

# Test-Loop — Autonomous QA Loop

引数: `$ARGUMENTS` (省略時はテストコマンドを自動検出)

テストが全て通過するまで自律的にテスト→修正→再テストを繰り返す。

## 実行手順

`qa-workflow` スキル（`plugins/devkit/skills/qa-workflow/SKILL.md`）を読み、
Step 1 から順に実行する。引数 `$ARGUMENTS` をスキルのテストコマンド指定として渡す。
