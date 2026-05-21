---
description: Run the full devkit quality gate on the current project
argument-hint: "[quick|full|report]"
allowed-tools: Read, Bash, Glob, Grep
---

# Gate — Full Quality Gate

引数: `$ARGUMENTS`

モードに応じて devkit の品質ゲートを実行する。

## モード

| モード | 内容 |
|--------|------|
| `quick` (デフォルト) | lint + secrets check + テスト実行 |
| `full` | quick + semgrep SAST + tech-debt スコア |
| `report` | full + Markdown レポートファイル生成 |

## 実行手順

1. `coding-conventions` スキルに従いプロジェクト設定 (linter設定、CLAUDE.md) を読み込む
2. `test-runner` エージェントを起動してテストとセキュリティスキャンを実行する
3. `full` または `report` モードの場合は `debt-analyzer` エージェントで技術負債スコアを計測する
4. 結果を統合してサマリーを報告する
5. `report` モードの場合は `devkit-report-[YYYY-MM-DD].md` を生成する

引数が指定されない場合は `quick` モードで実行する。
