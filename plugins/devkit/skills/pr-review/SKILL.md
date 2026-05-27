---
name: pr-review
description: |
  Use this skill when reviewing a pull request, self-reviewing before push, scanning existing
  code for quality, or when Claude has finished implementing a feature. Orchestrates parallel
  specialist agents based on risk level. Triggers on: "review this PR", "check the diff",
  "is this safe to merge", "before I push", "pre-merge check", "scan this directory",
  PRのレビュー, マージ前確認, push前確認, 変更のリスク評価, コード品質チェック.
version: 2.1.0
allowed-tools: Read, Bash, Glob, Grep, Task
---

# PR Review — 40観点・専門エージェント並列オーケストレーション

このスキルはレビューの「交通整理役」です。レビュー対象を確定し、diff と周辺仕様を読んでリスクを評価し、
担当エージェントを選定して並列で起動します。最終出力は「見つかった問題」を先に並べ、
エージェント名や内部の実行詳細は出しません。

---

## Step 0: レビュー対象を確定する

まずレビュー対象を一つに決める。対象が曖昧なまま広くスキャンしない。

```bash
# 現在のブランチ・変更概要
git status --short
git branch --show-current 2>/dev/null
git diff HEAD --name-only
git diff HEAD --stat

# PR番号が渡された場合
gh pr view "$PR_NUMBER" --json title,body,additions,deletions,changedFiles 2>/dev/null
```

対象が PR の場合は title/body を読む。自己レビューの場合は、ブランチ名・コミットメッセージ・変更ファイルから目的を推定する。
目的が推定できない場合は「目的不明」を前提にレビューし、仕様判断が必要な指摘は Open Questions に回す。

---

## Step 1: ベースブランチを確定してから diff を取得する

### ベースブランチの自動検出（`--base` 未指定時）

ハードコードせず、以下の優先順位でベースブランチを決定する:

```bash
# 1. ブランチの追跡設定から merge 先を確認
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null

# 2. git log で分岐点を探し、develop / main / master のどれから切られたか確認
git log --oneline --decorate origin/develop...HEAD 2>/dev/null | tail -1
git log --oneline --decorate origin/main...HEAD 2>/dev/null | tail -1

# 3. develop ブランチの存在確認
git show-ref --verify --quiet refs/remotes/origin/develop 2>/dev/null && echo "develop exists"
git show-ref --verify --quiet refs/heads/develop 2>/dev/null && echo "develop exists (local)"
```

**判定ルール（優先順位順）:**
1. `--base <branch>` が明示指定されていればそれを使う
2. `git rev-parse @{u}` でトラッキングブランチが取れればそのリモート名（`origin/develop` → `develop`）を使う
3. `git log` で `origin/develop...HEAD` のコミット数が `origin/main...HEAD` より少なければ `develop` を、そうでなければ `main` を使う
4. `origin/develop` が存在すれば `develop`、存在しなければ `main`

確定したベースブランチを **BASE_BRANCH** として以降で使用する。

---

### ユースケース A: 自己レビュー（push 前）

```bash
git diff HEAD --name-only
git diff HEAD --stat
git diff HEAD --unified=80
```

### ユースケース B: GitHub PR レビュー

```bash
# PR番号 $PR_NUMBER が渡された場合
gh pr view "$PR_NUMBER" --json title,body,additions,deletions,changedFiles,baseRefName 2>/dev/null
# baseRefName フィールドで PR のベースブランチを確認し、BASE_BRANCH を上書きする
gh pr diff "$PR_NUMBER" 2>/dev/null

# ブランチ名が渡された場合: 上記で確定した BASE_BRANCH を使う
git diff origin/$BASE_BRANCH..."$BRANCH" --stat
git diff origin/$BASE_BRANCH..."$BRANCH" --unified=80
```

### ユースケース C: 既存コード一括スキャン（品質監査）

```bash
rg --files "$TARGET_PATH" \
  -g '*.ts' -g '*.tsx' -g '*.js' -g '*.jsx' -g '*.py' -g '*.go' -g '*.rs' \
  -g '!node_modules' -g '!.git' | head -80

git log --since="30 days ago" --name-only --format="" 2>/dev/null | sort | uniq -c | sort -rn | head -30
```

**重要:** `head` で切った diff だけを根拠に最終判断しない。diff が長い場合は、変更ファイル一覧から対象ファイルを `Read` し、
変更ハンク周辺と呼び出し元/呼び出し先を確認する。

---

## Step 2: 事前コンテキスト収集（必須）

### 2-0: プロジェクトのルール・AI設定を読む

レビュー対象リポジトリのコーディング規約・AIエージェント向け指示を最初に読む。
これらはレビュー基準そのものになるため、**diff を読む前に必ず収集する**。

```bash
# CLAUDE.md / .claude/ 配下の設定
find . -maxdepth 4 \( -name "CLAUDE.md" -o -path "*/.claude/*.md" \) \
  -not -path "*/node_modules/*" 2>/dev/null | head -20

# .agents/ 配下のエージェント定義・ルール
find . -maxdepth 4 -path "*/.agents/*" \
  -not -path "*/node_modules/*" 2>/dev/null | head -20

# コーディング規約・リントルール
find . -maxdepth 3 \( \
  -name ".eslintrc*" -o -name "biome.json" -o -name ".prettierrc*" \
  -o -name "CONVENTIONS.md" -o -name "RULES.md" -o -name "CONTRIBUTING.md" \
  -o -name "ARCHITECTURE.md" \
\) -not -path "*/node_modules/*" 2>/dev/null | head -20
```

見つかったファイルは全て読む。ここで定義された禁止パターン・命名規則・アーキテクチャ制約は
レビューで HIGH 以上の根拠として使う。

### 2-A: spec / ADR / 設計ドキュメントを探して読む

```bash
# PRに関連するspec/設計ドキュメントを検索（実装前提の仕様乖離を防ぐ）
rg --files \
  -g 'proposal.md' -g 'design.md' -g 'spec.md' -g 'ADR-*.md' \
  -g 'docs/**' -g 'openspec/**' -g 'specs/**' | head -40

# ブランチ名・PR title・変更ファイル名由来のキーワードで絞り込む
rg -l "$FEATURE_KEYWORD" docs openspec specs . 2>/dev/null | head -20
```

**見つかったspec/設計ドキュメントは必ず読む。** 実装とspecの明確な乖離は CRITICAL 扱いとする。

### 2-B: ドメインキーワードのコンテキストを把握する

変更ファイルに登場するフラグ・ステータス値・Enumは、定義元を必ず読む:

```bash
# フラグ・ステータスの定義元を探す（例: Source, isConfirmed, Status等）
rg -l "isConfirmed|Source|Status" -g '*.ts' -g '*.tsx' -g '*.py' -g '*.go' | head -20
```

意味が不明なフラグは「AIが提案した未承認データ」等の重大なドメイン意味を持つ場合がある。
コードから読み解けない場合はPR descriptionまたはspecを参照する。

### 2-C: Cross-aggregate参照を確認する

削除・変更されるEntityのIDが他集約から参照されているかを必ず検索する:

```bash
# 削除・変更対象のEntityID型名を特定してgrep（例: SEOKeywordId, ProductId等）
rg -l "$ENTITY_ID_TYPE" -g '*.ts' -g '*.tsx' -g '*.py' -g '*.go' | head -40
```

参照が見つかった場合、その集約への影響（Task/PostingPlan/Post等）を確認する。
参照されているEntityを削除するコードはHIGH〜CRITICAL扱いとする。

### 2-D: API・イベント・公開contractの互換性変更（BREAKING change）を検出する

```bash
# ステータス値・フィールド名の変更をdiffで検索（例: "skipped" → "deleted"）
git diff HEAD --unified=20 | rg "[-+].*(status|state|type|enum).*[\"']" | head -50

# API/公開contractの変更を確認
git diff HEAD --name-only | rg "(handler|controller|route|api|schema|contract|openapi|graphql|proto|sdk|webhook|event)" | head -50
```

ステータス値・フィールド名・型の変更に加え、request body / query params / route path / pagination / sort / filter /
webhook payload / event payload / GraphQL schema / SDK・public export の変更は frontend・外部クライアント・非同期consumerへの影響を必ず確認する。
後方互換性や移行計画を確認できない場合は「contract互換性要確認」としてHIGH以上で報告する。

### 2-E: 運用・リリース安全性を確認する

```bash
# リリース・運用・非同期処理に関わる変更を検索
git diff HEAD --name-only | rg "(migration|schema|seed|backfill|queue|job|worker|cron|scheduler|feature|flag|env|config|deploy|docker|helm|k8s|terraform|workflow)" | head -50
```

以下に該当する場合は、ロールバック・段階リリース・既存データ/既存consumerとの互換性を確認する:
- DB migration / backfill / seed の追加・変更
- env/config/feature flag の追加・削除・意味変更
- queue/job/worker/cron/scheduler の処理内容・payload・実行頻度変更
- Docker/Kubernetes/Terraform/GitHub Actions 等のdeploy経路変更
- 監視・ログ・メトリクス・アラートに影響する変更

### 2-F: CI/check 状態を確認する

```bash
# GitHub PRの場合。失敗してもレビュー自体は継続する
gh pr checks "$PR_NUMBER" 2>/dev/null

# ローカルで利用可能な代表的チェックを確認
rg '"(typecheck|lint|test|check)"' package.json pyproject.toml Cargo.toml Makefile justfile 2>/dev/null | head -40
```

CI/check が未実行・不明の場合は、最終レポートに「機械検出項目は未確認」と明記する。
CIで検出可能としてスキップするのは、対象のcheckが実際に存在し、実行済みまたは実行予定であることを確認できた場合に限る。

---

## Step 3: リスクスコアを計算してエージェント構成を決定する

### スコアリング（合計で判定）

```
変更規模:
  1–5   ファイル → +0
  6–20  ファイル → +10
  21+   ファイル → +25

機密・インフラパス:
  *.env*, *secret*, infra/, terraform/, k8s/, .github/workflows/ → +40
  migrations/, *production*, *prod.* → +30

破壊的変更の指標:
  DBマイグレーション (DROP/ALTER)             → +30
  APIシグネチャ削除・リネーム                  → +20
  API/イベント/公開contractの非互換変更        → +25  ← BREAKING change（client/consumer影響必須確認）
  env変数の追加・削除                          → +15
  依存関係の major バージョンアップ             → +20
  webpack/vite/tsconfig 等のビルド設定変更     → +10
  queue/job/cron/scheduler のpayload・頻度変更  → +20
  deploy/CI/CD/infra 設定変更                   → +20

spec/設計整合性:
  specドキュメントが存在 & 実装との乖離あり    → +40  ← CRITICAL格上げ必須
  cross-aggregate参照のあるEntityを削除        → +30  ← HIGH〜CRITICAL
  PR bodyのACが不完全に実装されている疑い      → +20

テスト・品質状況:
  ロジック変更あり & テスト変更なし            → +20
  認証・認可コードの変更                       → +25
  外部 API・DB アクセスコードの変更            → +15
  個人情報/機微データ/監査ログに関わる変更     → +25

UI/UX:
  UIコンポーネント・ページ・フォームの変更     → +10  ← ux-reviewer 追加トリガー
  ユーザーフロー・ナビゲーション変更           → +15  ← ux-reviewer 追加トリガー
```

スコアは加算する。ただし、CRITICAL 格上げ条件（spec乖離、データ破壊、認証認可バイパス、silent failure）がある場合は、
合計点に関係なくマージブロックとして扱う。

### リスクレベルとエージェント構成

| スコア | リスクレベル | 起動するエージェント |
|--------|------------|------------------|
| 0–20   | 低リスク   | quality-reviewer + requirements-checker（並列） |
| 21–50  | 中リスク   | quality-reviewer + requirements-checker + security-auditor（並列） |
| 51+    | 高リスク   | quality-reviewer + requirements-checker + security-auditor + type-checker + debt-analyzer（5並列） |
| 品質監査 | 監査モード | debt-analyzer + quality-reviewer（並列） |

### 条件付きエージェント追加

スコアに関わらず、以下に該当する場合は該当エージェントを追加する:

- 認証・認可、入力検証、依存関係、機密情報、外部公開APIを変更 → `security-auditor`
- TypeScript の型定義、API/event/webhook contract、domain model、schema/parser、SDK/public export を変更 → `type-checker`
- DB migration、module boundary、依存方向、巨大ファイル、循環参照、queue/job/cron、deploy/infra/config の疑い → `debt-analyzer`
- UIコンポーネント・ページ・フォーム・ユーザーフロー・ナビゲーションを変更 → `ux-reviewer`

---

## Step 4: 担当エージェントと観点の割り当て

### 観点割り当てマップ

| エージェント | 担当観点 | 確認事項 |
|------------|--------|--------|
| **quality-reviewer** | 1-5（正確性）, 19-20・22-24（信頼性・テスト）, 40（リグレッション） | ロジック・エッジケース・状態遷移・副作用・冪等性・エラー処理・テスト・既存機能への影響 |
| **requirements-checker** | 21（要件充足） | 仕様書照合・AC充足・実装漏れ・実装過剰・スコープ逸脱 |
| **security-auditor** | 6-10（セキュリティ） | OWASP Top10・インジェクション・認証認可・機密情報・入力検証・依存安全性 |
| **type-checker** | 28-32（型・インターフェース） | any/as/!使用・ランタイム型安全・zod解析・関数インターフェース設計 |
| **debt-analyzer** | 11-18, 25-27, 33-38（設計・保守性・運用・パフォーマンス） | 層境界・DDD・複雑度・命名・N+1クエリ・キャッシュ・インデックス・マイグレーション・リリース安全性 |
| **ux-reviewer** | 39（UX整合性・アクセシビリティ） | エラーメッセージ・ローディング/空/エラー状態・ユーザージャーニー・フォーム・文言・a11y基本要件 |

### 観点の優先度（CIで自動検出可能なものは各エージェントがスキップ）

CIで検出済み（報告不要）:
- tsc --noEmit による型エラー
- ESLint / Biome による lint エラー
- フォーマット違反

CI/check が存在しない、または状態不明の場合:
- 型・lint・formatの「明らかな未実行リスク」は Findings ではなく Open Questions / 推奨アクションに記録する
- 手元で実行できる軽量checkが明確な場合は、レビュー前後に実行を提案または実行する

---

## Step 5: エージェントを並列起動する

コンテキストとして各エージェントに渡す情報:
1. diff の内容（または対象ファイルリスト）
2. リスクスコアとその根拠
3. PR の目的・背景（PR description があれば）
4. Step 2 で収集した spec / cross-aggregate 参照の結果

**`ux-reviewer` を起動する場合、追加で以下を伝える:**
- UIに関係するファイル（コンポーネント・ページ・フォーム）のリスト
- PR bodyに記載されたユーザー向けの変更概要（あれば）
- 「エンジニアリング上の正確性は他エージェントが担当しているため、ユーザー体験の観点のみ報告すること」

**`requirements-checker` を起動する場合、以下も伝える:**
- PR bodyの全文（要件充足チェックに使用）
- Step 2-A で収集した spec / AC の内容（あれば）

**全エージェント共通: 以下を必ず含める:**
- 「何を確認するか」を明確に記述する（例: 「観点3（状態遷移）の idempotent return アンチパターンを特に確認してください」）
- 「各問題を CRITICAL / HIGH / MEDIUM / LOW で分類して報告すること」
- 「CRITICAL の基準: spec/設計との乖離、データ破壊・消失リスク、認証認可バイパス、silent failure でユーザーが気づけない不整合」
- 「確信度 80% 未満の推測は Findings に入れず、必要なら Open Questions に回すこと」
- 「lint/format/typecheck で機械検出できる問題は報告しないこと」
- 「報告にエージェント自身の名前を含めないこと。観点カテゴリ・ファイル:行・問題・推奨修正のみ返すこと」

---

## Step 6: 結果を統合してレポートを生成する

各エージェントのレポートを以下の構造にまとめる:

```markdown
## PR Review Report — [PR番号 or ブランチ名 or 監査対象]

**日時:** [YYYY-MM-DD]
**対象:** [変更ファイル数] ファイル (+[追加行] / -[削除行])
**リスクレベル:** [低/中/高] (スコア: [XX])
**マージ推奨:** [Yes / No / 修正後OK / 人間レビュー必須]

---

### CRITICAL — 即時修正必須（マージブロック）

| # | 観点 | ファイル:行 | 問題の要約 |
|---|------|-----------|----------|
| 1 | [観点カテゴリ] | `path/to/file.ts:42` | 一行の問題サマリ |

**1. [問題タイトル]**

[問題の詳細説明。なぜ問題なのか、どのような影響があるか、コードの具体的な箇所を引用しながら説明する。]

→ [推奨する修正方針を具体的に記述する。]

---

### HIGH — マージ前に修正推奨

| # | 観点 | ファイル:行 | 問題の要約 |
|---|------|-----------|----------|
| 1 | [観点カテゴリ] | `path/to/file.ts:42` | 一行の問題サマリ |

**1. [問題タイトル]**

[問題の詳細説明。]

→ [推奨する修正方針。]

---

### MEDIUM — 次のPRで対応推奨

| # | 観点 | ファイル:行 | 問題の要約 |
|---|------|-----------|----------|
| 1 | [観点カテゴリ] | `path/to/file.ts:42` | 一行の問題サマリ |

**1. [問題タイトル]**

[問題の詳細説明。]

→ [推奨する修正方針。]

---

### LOW — 観察・改善提案

| # | 観点 | ファイル:行 | 問題の要約 |
|---|------|-----------|----------|
| 1 | [観点カテゴリ] | `path/to/file.ts:42` | 一行の問題サマリ |

**1. [問題タイトル]**

[問題の詳細説明。]

→ [推奨する修正方針。]

---

### 推奨アクション
- [ ] [Critical問題の修正]
- [ ] [High問題の修正]
- [ ] [人間レビューが必要な場合: その理由]

### Open Questions
- [仕様や運用確認が必要な点。なければ省略]
```

**フォーマットのルール:**
- 各セクションの冒頭に「表（一覧）」を置き、全問題を一目で把握できるようにする
- 表の直後に各問題の「詳細説明」を番号付きで展開する
- 詳細説明では問題のWHY（なぜ問題か）・影響範囲・コード引用を含める
- 修正方針は `→` で始める
- エージェント名はレポートに含めない（読者に不要な実装詳細）
- 問題がないセクションは省略する
- Findings には「変更行または変更の直接影響範囲」に紐づく問題だけを書く
- 仕様確認だけで確定できない内容は Open Questions に分離する

---

## Step 7: 高リスク時のユーザーへの警告

スコア 51+ の場合、レポート冒頭に以下を追加する:

```
⚠️  このPRは高リスク判定です。人間によるレビューを強く推奨します。

確認が必要な事項:
- [ ] 機密パス変更の意図は正しいか
- [ ] DBマイグレーションはロールバック可能か（.down.sql が存在するか）
- [ ] API変更は後方互換か、非互換なら移行計画はあるか
- [ ] 環境変数変更はすべての環境に反映されるか
- [ ] migration/backfill/queue/job/cron変更は既存versionと互換か
- [ ] rollback・feature flag・監視/アラートの計画はあるか
- [ ] セキュリティレビューを受けたか
```

---

## gitStream 連携

`.cm/gitstream.cm` がある場合、リスクレベルに対応するラベルが自動付与される:
- `low-risk` → 自動続行
- `medium-risk` → security-auditor + quality-reviewer + requirements-checker の結果を PR コメントに投稿
- `high-risk` → 人間レビュー待ちをユーザーに通知
