---
description: Analyze technical debt and generate a prioritized hotspot report with refactoring roadmap
argument-hint: "[path-or-module]"
allowed-tools: Bash, Read, Glob, Grep
---

# Debt — Tech Debt Analysis

引数: `$ARGUMENTS` (省略時はプロジェクト全体)

技術負債を分析してホットスポットレポートとリファクタリングロードマップを生成する。

## 実行手順

`tech-debt` スキルに従って以下を実行する:

1. 対象パス: `$ARGUMENTS` (省略時は `.`)
2. git 変更頻度・ファイルサイズ・TODO密度 でホットスポットスコアを算出する
3. 依存関係の健全性 (`npm outdated` 等) を確認する
4. `debt-analyzer` エージェントを起動して詳細なアーキテクチャ分析を依頼する
5. 優先度付きリファクタリングロードマップ (Quick wins / Middle-term / Strategic) を提示する

ROI (修正コスト vs 得られる価値) を考慮した現実的な提案を生成する。
