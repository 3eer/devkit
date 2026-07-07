---
name: gate-workflow
argument-hint: "[quick|full|report]"
dependencies:
  - coding-conventions
  - security-gate
  - tech-debt
  - test-runner
  - debt-analyzer
description: |
  Run the full devkit quality gate on the current project — lint, secrets, dependency
  vulnerabilities, tests, optional SAST and tech-debt score, optional Markdown report.
  Triggers on: "quality gate", "run the gate", "gate full", "gate quick", "gate report",
  品質ゲート, ゲート実行, フル品質チェック, 品質チェック full.
version: 1.0.0
tools:
  - Read
  - Bash
  - Glob
  - Grep
  - Agent
  - Skill
  - Task
triggers:
  - "quality gate"
  - "run the gate"
  - "gate full"
  - "gate quick"
  - "gate report"
  - 品質ゲート
  - ゲート実行
  - フル品質チェック
  - 品質チェック
---

# Gate — Full Quality Gate

引数: `$ARGUMENTS`（省略時 `quick`）

モードに応じて devkit の品質ゲートを実行する。

## モード

| モード | 内容 |
|--------|------|
| `quick` (デフォルト) | lint + secrets check (gitleaks) + 依存関係脆弱性 (trivy/npm audit) + テスト実行 |
| `full` | quick + **semgrep SAST** + 技術負債スコア（`tech-debt` / `debt-analyzer`） |
| `report` | full + Markdown レポートファイル生成 |

**SAST (semgrep) は `full` / `report` モードでのみ実行する。** 編集後フックは lint のみ（軽量）。

## 実行手順

### 0. セキュリティ bootstrap の確認（初回または未設定時）

プロジェクトに pre-commit / CI セキュリティ設定がない場合、`security-gate` スキルの「プロジェクトへの展開」に従い雛形をコピーする:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/templates/pre-commit-config.yaml" .pre-commit-config.yaml
pip install pre-commit && pre-commit install

mkdir -p .github/workflows
cp "${CLAUDE_PLUGIN_ROOT}/templates/github-workflows-devkit-security.yml" .github/workflows/devkit-security.yml
```

既に `.pre-commit-config.yaml` または `.github/workflows/devkit-security.yml` がある場合はスキップする。

### 1. プロジェクト設定を読む

`coding-conventions` スキルに従い linter 設定・CLAUDE.md を読み込む。

### 2. `test-runner` エージェントを起動する

起動時に **ゲートモード** を必ず伝える:

| モード | test-runner への指示 |
|--------|---------------------|
| `quick` | `GATE_MODE=quick` — gitleaks + trivy/npm audit/pip-audit。**semgrep は実行しない** |
| `full` / `report` | `GATE_MODE=full` — quick の内容 + semgrep SAST |

### 3. 技術負債（full/report のみ）

`full` または `report` モードの場合は `debt-analyzer` エージェントで技術負債スコアを計測する。

### 4. 結果を統合してサマリーを報告する

### 5. レポート生成（report のみ）

`devkit-report-[YYYY-MM-DD].md` を生成する。
