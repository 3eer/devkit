---
description: Run autonomous test loop — iterate test→fix→test until all tests pass (max 5 iterations)
argument-hint: "[custom-test-command]"
allowed-tools: Bash, Read, Edit, Glob, Grep
---

# Test-Loop — Autonomous QA Loop

引数: `$ARGUMENTS` (省略時はテストコマンドを自動検出)

テストが全て通過するまで自律的にテスト→修正→再テストを繰り返す。

## 実行手順

`qa-loop` スキルに従って以下を実行する:

1. `$ARGUMENTS` が指定された場合はそのコマンドを使用する
2. 引数なしの場合は `package.json` / `pytest.ini` / `go.mod` / `Cargo.toml` から
   テストコマンドを自動検出する
3. 最大 5 イテレーションのループを実行する:
   - テスト実行 → 失敗を解析 → 根本原因を特定 → 修正 → 再テスト
4. 同じエラーが 2 回連続で発生した場合は自動修正の限界と判断して停止し、
   人間に状況を報告する
5. 完了レポートを生成する

**禁止:** 失敗テストの削除・スキップで「通す」ことは行わない。
