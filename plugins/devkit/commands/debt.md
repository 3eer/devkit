---
description: Analyze technical debt and generate a prioritized hotspot report with refactoring roadmap
argument-hint: "[path-or-module]"
allowed-tools: Bash, Read, Glob, Grep
---

# Debt — Tech Debt Analysis

引数: `$ARGUMENTS` (省略時はプロジェクト全体)

技術負債を分析してホットスポットレポートとリファクタリングロードマップを生成する。

## 実行手順

`tech-debt-reader` スキル（`plugins/devkit/skills/tech-debt-reader/SKILL.md`）を読み、
Step 1 から順に実行する。引数 `$ARGUMENTS` を対象パス（省略時 `.`）として渡す。
