---
name: tech-debt
type: orchestrate
mutating: false
user-invocable: true
argument-hint: "[対象パス or --days <日数>]"
dependencies:
  - debt-analyzer
description: |
  Use this skill when the user asks about technical debt, code quality metrics, hotspot
  analysis, refactoring opportunities, architectural issues, or wants to understand where
  the codebase needs attention. Triggers on: "tech debt", "hotspots", "refactor candidates",
  "code quality report", "what needs cleanup", "complexity analysis", "where is the mess",
  技術負債, ホットスポット, リファクタ候補, コード品質, 複雑度分析, 整理が必要な箇所.
version: 1.0.0
tools:
  - Read
  - Bash
  - Glob
  - Grep
  - Agent
triggers:
  - "tech debt"
  - "hotspots"
  - "refactor candidates"
  - "code quality report"
  - "what needs cleanup"
  - "complexity analysis"
  - "where is the mess"
  - 技術負債
  - ホットスポット
  - リファクタ候補
  - コード品質
  - 複雑度分析
  - 整理が必要な箇所
---

# Tech Debt Analysis & Visualization

## Step 1: ホットスポットを検出する

「変更頻度 × 複雑度」の積でリスクの高いファイルを特定する。

```bash
# 過去90日で最も変更されたファイル Top 20
git log --since="90 days ago" --name-only --format="" 2>/dev/null | \
  sort | uniq -c | sort -rn | head -20

# ファイルサイズ (複雑度の代理指標) Top 20
find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.py" \
  -o -name "*.go" -o -name "*.js" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" | \
  xargs wc -l 2>/dev/null | sort -rn | head -20

# TODO/FIXME/HACK の密度
grep -r "TODO\|FIXME\|HACK\|XXX\|BUG" \
  --include="*.ts" --include="*.tsx" --include="*.py" \
  --include="*.go" --include="*.js" \
  --exclude-dir=node_modules --exclude-dir=.git \
  -l . 2>/dev/null | \
  xargs grep -c "TODO\|FIXME\|HACK\|XXX\|BUG" 2>/dev/null | \
  sort -t: -k2 -rn | head -20
```

## Step 2: ホットスポットスコアを計算する

各ファイルに以下のスコアを付けて合計を算出:

```
変更頻度スコア = (90日の変更回数 / 全ファイル平均) × 50
サイズスコア   = 行数 > 500 → 25 / > 300 → 15 / > 100 → 5
TODO密度スコア = (TODO/FIXME数 per 100行) × 25
```

**合計スコア > 60 → ホットスポット (優先リファクタ対象)**

## Step 3: 依存関係の健全性を確認する

```bash
# npm: 古い依存関係
npm outdated 2>/dev/null | head -20 || true

# Python: 古い依存関係
pip list --outdated 2>/dev/null | head -20 || true

# Go: 古い依存関係
go list -u -m all 2>/dev/null | grep '\[' | head -20 || true
```

## Step 4: テストカバレッジを確認する (あれば)

```bash
# カバレッジレポートが存在するか確認
ls coverage/ .coverage coverage.xml lcov.info 2>/dev/null || true
```

## Step 5: Tech Debt レポートを生成する

```markdown
## Tech Debt Report — [YYYY-MM-DD]

### ホットスポット Top 5

| ファイル | 変更頻度/90日 | 行数 | TODO数 | スコア | 推奨アクション |
|---------|-------------|------|--------|--------|---------------|
| src/api/handler.ts | 23回 | 847 | 8 | 82 | 分割リファクタ |

### 技術負債カテゴリ

**コード複雑度**
- 500行超のファイル: [リスト]
- TODO/FIXME が5件以上: [リスト]

**依存関係**
- メジャーバージョンが古いパッケージ: [リスト]

**テスト**
- テストカバレッジ: [数値があれば]
- テストなしのファイル: [ある場合のリスト]

### リファクタリングロードマップ

**短期 (1-2週間):**
- [ ] [ファイル名]: [具体的なアクション]

**中期 (1-2ヶ月):**
- [ ] [ファイル名]: [具体的なアクション]

**長期 (判断待ち):**
- [ ] [ファイル名]: [依存関係が多く慎重に判断が必要な箇所]
```

## SonarQube / CodeScene 連携 (任意)

環境変数が設定されている場合、外部プラットフォームのデータを取得して補完する:

```bash
# SonarQube
if [ -n "${SONARQUBE_URL:-}" ] && [ -n "${SONARQUBE_TOKEN:-}" ]; then
  curl -s -u "${SONARQUBE_TOKEN}:" \
    "${SONARQUBE_URL}/api/measures/component?component=PROJECT_KEY&metricKeys=code_smells,technical_debt,coverage"
fi
```

## debt-analyzer エージェントとの連携

詳細なアーキテクチャ分析が必要な場合は `debt-analyzer` エージェントを起動する。
上記のホットスポット分析結果をコンテキストとして渡し、具体的なリファクタリング戦略と
ROI評価 (修正コスト vs 得られる価値) を含むロードマップを生成してもらう。
