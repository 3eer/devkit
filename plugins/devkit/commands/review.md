---
description: Review code — self-review before push, GitHub PR review, or bulk quality audit
argument-hint: "[PR-number | branch-name | --base <branch> | --audit path]"
allowed-tools: Bash, Read, Glob, Grep, Task
---

# Review — マルチエージェント並列コードレビュー

引数: `$ARGUMENTS`

40観点を専門エージェントに割り当てて並列レビューを実行する。

---

## 引数パターンと実行フロー

| 引数 | ユースケース | 動作 |
|------|-----------|------|
| なし | push前の自己レビュー | git log等からベースブランチを自動検出して `git diff <BASE_BRANCH>...HEAD` を対象にレビュー |
| `--base <branch>` | ベースブランチ指定 | `git diff <branch>...HEAD` を対象にレビュー |
| `123` (数値) | GitHub PR レビュー | `gh pr diff 123` + PR の `baseRefName` でベースブランチを確認してレビュー |
| `feature/xxx` (ブランチ名) | ブランチレビュー | git log等からベースブランチを自動検出して `git diff <BASE_BRANCH>...feature/xxx` を対象にレビュー（`--base` で上書き可） |
| `--audit [path]` | 品質監査 | 既存コードをホットスポット優先でスキャン |

---

## 実行手順

### 0. プロジェクトのルール・AI設定を読む

diff を読む前に、レビュー基準となるファイルを収集する。

```bash
# CLAUDE.md / .claude/ 配下の設定（skills/ サブディレクトリは除く — 別途処理）
find . -maxdepth 4 \( -name "CLAUDE.md" -o -path "*/.claude/*.md" \) \
  -not -path "*/.claude/skills/*" \
  -not -path "*/node_modules/*" 2>/dev/null

# .agents/ 配下のエージェント定義・ルール
# -L: .claude/ が .agents/ へのシンボリックリンクの構成があるため、リンクを辿る
find -L . -maxdepth 4 -path "*/.agents/*" \
  -not -path "*/node_modules/*" 2>/dev/null

# コーディング規約・アーキテクチャ指針
find . -maxdepth 3 \( \
  -name "CONVENTIONS.md" -o -name "RULES.md" -o -name "CONTRIBUTING.md" \
  -o -name "ARCHITECTURE.md" -o -name ".eslintrc*" -o -name "biome.json" \
\) -not -path "*/node_modules/*" 2>/dev/null
```

見つかったファイルは全て `Read` する。ここで定義された禁止パターン・アーキテクチャ制約を
レビュー基準として使い、違反は HIGH 以上で報告する。

#### ドメインスキルの検出

```bash
# .claude/skills/ 配下の SKILL.md を列挙する。
# -L: .claude/skills/ が .agents/skills/ への symlink である構成（meo-agent 等）でも
#     リンク先の実体を辿るために必須。-L が無いと symlink 配下の skill が 0 件になる。
# SKILL.md のみ（references/*.md 等の補助ファイルは除外）に絞る。
find -L . -maxdepth 5 -path "*/.claude/skills/*/SKILL.md" \
  -not -path "*/node_modules/*" 2>/dev/null | sort
```

見つかったファイルを **SKILL_FILES** 候補リストとして記録する（内容はまだ読まない）。
このリストはステップ3でエージェントを追加起動する際に使用する。

**SKILL_FILES の選別（候補が多い場合）:**

skill が多数あるリポ（meo-agent は 40 件超）では全件を skill-reviewer に回すと並列数が爆発する。
**diff の変更内容に関連する skill を優先**して最大 8 件まで選ぶ。判断材料:

1. **常に優先**: silent-failure / docs-sync / error-handling / aggregate / race-condition 等、
   「本番事故・整合性・観測性・ドキュメント同期」に直結する横断 skill（diff の領域を問わず効く）
2. 変更ファイルのパス・ドメイン語と SKILL.md の `description` が一致する skill
3. 上記で 8 件に満たない場合のみ、残りをアルファベット順で補充

選別後の SKILL_FILES が空になることは避ける（横断 skill は最低限残す）。

### 1. 引数をパースして diff を取得する

#### STEP 1: `--audit` を最初に確認する

`$ARGUMENTS` が `--audit` で始まる場合はケース D へ進む。それ以外は STEP 2 へ。

#### STEP 2: `--base <branch>` を抽出する

`$ARGUMENTS` に `--base <branch>` が含まれる場合、そのブランチ名を BASE_BRANCH とし、`--base <branch>` 部分を除去した残りを REVIEW_TARGET とする。
`--base` が含まれない場合は REVIEW_TARGET = `$ARGUMENTS` のまま。

#### STEP 3: BASE_BRANCH を確定する（`--base` 未指定の場合のみ）

`--base` が指定されなかった場合、以下を順番に実行してベースブランチを特定する:

```bash
# 1. トラッキングブランチから merge 先を確認
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null

# 2. git log で分岐点の候補を確認（コミット数が少ない方が実際の分岐元）
git rev-list --count origin/develop...HEAD 2>/dev/null
git rev-list --count origin/main...HEAD 2>/dev/null

# 3. develop ブランチの存在確認
git show-ref --verify --quiet refs/remotes/origin/develop 2>/dev/null && echo "develop_exists"
git show-ref --verify --quiet refs/heads/develop 2>/dev/null && echo "develop_exists_local"
```

**判定ルール（優先順位順）:**
1. `git rev-parse @{u}` でトラッキングブランチが取得できた場合、そのブランチ名を BASE_BRANCH とする（例: `origin/develop` → `develop`）
2. `origin/develop...HEAD` と `origin/main...HEAD` の両方のコミット数を比較し、コミット数が少ない方を BASE_BRANCH とする（分岐が近い方が実際の親ブランチ）
3. `origin/develop` が存在すれば `develop`、存在しなければ `main`

#### STEP 4: REVIEW_TARGET に応じてコマンドを実行する

**ケース A: REVIEW_TARGET が空（引数なし）**

STEP 3 で確定した BASE_BRANCH を使って以下を実行する:

```bash
git status --short
git branch --show-current
# BASE_BRANCHが "develop" の場合:
git diff origin/develop...HEAD --name-only
git diff origin/develop...HEAD --stat
git diff origin/develop...HEAD --unified=80
# BASE_BRANCHが "main" の場合:
git diff origin/main...HEAD --name-only
git diff origin/main...HEAD --stat
git diff origin/main...HEAD --unified=80
```

**ケース B: REVIEW_TARGET が数値のみ（PR番号）**

```bash
gh pr view <PR番号> --json title,body,additions,deletions,changedFiles
gh pr diff <PR番号>
```

**ケース C: REVIEW_TARGET が非空かつ数値でない（ブランチ名）**

STEP 3 で確定した BASE_BRANCH を使って以下を実行する:

```bash
# BASE_BRANCHが "develop" の場合:
git diff origin/develop...<REVIEW_TARGET> --stat
git diff origin/develop...<REVIEW_TARGET> --unified=80
# BASE_BRANCHが "main" の場合:
git diff origin/main...<REVIEW_TARGET> --stat
git diff origin/main...<REVIEW_TARGET> --unified=80
```

**ケース D: `--audit [path]`**

```bash
# TARGETは "--audit " の後ろの部分。指定なしなら "."
git log --since="30 days ago" --name-only --format="" | sort | uniq -c | sort -rn | head -30
rg --files <TARGET> \
  -g '*.ts' -g '*.tsx' -g '*.js' -g '*.jsx' -g '*.py' -g '*.go' -g '*.rs' \
  -g '!node_modules' -g '!.git' | head -80
```

長い diff は途中で切れた内容だけで判断せず、変更ファイルを `Read` して変更ハンク周辺と呼び出し元/呼び出し先を確認する。

### 2. `pr-review` スキルでコンテキスト収集とリスクスコア計算を行う

スキルに従い、spec / ADR / cross-aggregate 参照 / API・イベント・公開 contract 変更 / 運用・リリース安全性 / CI・check状態を確認してから、
変更ファイルをカテゴリ分類しリスクスコアを算出する。

### 3. リスクレベルに応じてエージェントを並列起動する

**低リスク (0–20):**
- `quality-reviewer` と `requirements-checker` を**同時に**起動（並列）
  - quality-reviewer: 観点1-5（正確性）・19-20・22-24（信頼性・テスト）・40（リグレッション）
  - requirements-checker: 観点21（要件充足・仕様書照合）
- ただし以下に該当する場合は、該当エージェントを追加する:
  - 型/API・イベント・webhook contract/domain model 変更 → `type-checker`
  - セキュリティ/認証/依存関係変更 → `security-auditor`
  - DB migration/queue/job/cron/deploy/config 変更 → `debt-analyzer`
  - UIコンポーネント/ページ/フォーム変更 → `ux-reviewer`

**中リスク (21–50):**
- 以下のエージェントを**同時に**起動（並列）
  - `quality-reviewer`: 観点1-5・19-20・22-24・40
  - `requirements-checker`: 観点21（要件充足・仕様書照合）
  - `security-auditor`: 観点6-10（OWASP・セキュリティ）
  - `debt-analyzer`: 観点11-18・25-27・33-38（設計・保守性・運用・パフォーマンス）
    — **中リスク以上で常時起動**。観点25（不要な再計算/再アロケーション）と観点33-38
    （構造化ログ・トレーサビリティ）を担当する唯一のエージェントで、条件付きにすると
    通常の実装 PR でこれらが落ちる
- 型/API・イベント・webhook contract/domain model 変更がある場合は `type-checker` も追加する
- アプリ内の DI/配線コード（`server.ts` / composition root / DI container）に新依存を足す
  変更も `debt-analyzer` 対象（背後で新ロジック経路が増えているサイン）
- UIコンポーネント/ページ/フォーム変更がある場合は `ux-reviewer` も追加する

**高リスク (51+):**
- 以下のエージェントを**同時に**起動（並列）
  - `quality-reviewer`: 観点1-5・19-20・22-24・40（リグレッション）
  - `requirements-checker`: 観点21（要件充足・仕様書照合）
  - `security-auditor`: 観点6-10（セキュリティ Red Team）
  - `type-checker`: 観点28-32（型安全性・I/F設計）
  - `debt-analyzer`: 観点11-18・25-27・33-38（設計・保守性・運用・パフォーマンス）
  - UIコンポーネント/ページ/フォーム変更がある場合は `ux-reviewer` も追加する

**監査モード (--audit):**
- `debt-analyzer` と `quality-reviewer` を**同時に**起動（並列）

#### ドメインスキルレビュアーの追加起動

SKILL_FILES に1件以上のファイルがある場合、**スキルファイル1件につき1つの `skill-reviewer` エージェントを追加で並列起動する**（通常エージェントとは独立）。

各 `skill-reviewer` への指示:
```
あなたはドメイン固有ルール専門レビュアーです。

## あなたのタスク
以下のスキルファイルに定義されたルール・観点**のみ**を使って、渡された diff をレビューしてください。
このスキルファイルの外にある観点（型安全・セキュリティ・テスト等）は一切報告しないこと。

## スキルファイル
[スキルファイルのパスと内容をここに貼り付ける]

## レビュー対象 diff
[diff をここに貼り付ける]

## 出力ルール
- CRITICAL / HIGH / MEDIUM / LOW で分類する
- 確信度 80% 未満の指摘は報告しない
- diff の変更行またはその直接影響範囲に紐づく問題のみ報告する
- lint/tsc で検出可能な問題は報告しない
- 問題がなければ「スキル違反なし」と1行で返す

## フォーマット
### ドメインスキル違反 — [スキルファイル名]

| # | ファイル:行 | 違反ルール | 問題の要約 | 推奨修正 |
|---|-----------|----------|----------|--------|

（問題がなければこのセクション全体を省略）
```

**上限:** SKILL_FILES はステップ0の選別で最大 8 件に絞られている。各 1 件につき 1 つの `skill-reviewer` を起動する。

### 4. 各エージェントへのコンテキスト指示

各エージェントを起動する際、以下を伝える:
- diff の内容（または対象ファイルリスト）
- リスクスコアとその根拠（どのファイルがハイリスク判定か）
- PR description または変更の目的（把握できている場合）
- spec / cross-aggregate 参照 / API・イベント・公開 contract 変更 / 運用・リリース安全性 / CI・check状態の確認結果
- 担当する観点の番号と重点確認事項
- **重点はあくまで「先に見る」であって「だけ見る」ではない。担当観点はすべて独立に確認し、
  軽量な品質観点（ログ・トレーサビリティ、命名規約、不要な再計算/メモ化、文言）を重い
  バグ観点の陰で省略しないこと、と必ず伝える**（重点で絞ると本来カバーすべき観点が落ちる）
- CRITICAL / HIGH / MEDIUM / LOW の分類基準
- 確信度 80% 未満の推測は Findings に入れず Open Questions に分離すること

### 5. `/codex:review` を実行する

エージェントレビューと並行して、Codex による静的レビューを実行する。

```
/codex:review
```

- `--audit` モードの場合は対象パスを引数に渡す: `/codex:review --audit $TARGET`
- Codex のレビュー結果はステップ6の統合レポートにマージする

### 6. 結果を統合してレポートを出力する

`pr-review` スキルのレポートフォーマットに従い、エージェントと Codex の結果を統合する。

レポートヘッダ直後に**「観点カバレッジ」表**を置き、起動したエージェントとカバー観点、
および**未起動エージェントの担当観点を「今回未チェック」と明示**する（省略は「カバーした」と
誤読される）。詳細フォーマットは `pr-review` スキル Step 6 を参照。

`skill-reviewer` の結果がある場合は、通常セクションの後に**「ドメインスキル違反」セクション**として追記する。
スキルファイルごとに1サブセクション。違反なしのスキルはサブセクションごと省略する。

CRITICAL 問題がある場合はレポートの最上部に目立つ形で表示する。
高リスク判定の場合は人間レビューを強く推奨する旨を明示する。

---

## 使用例

```bash
# push前の自己レビュー（develop との差分、develop がなければ main）
/review

# ベースブランチを明示して自己レビュー
/review --base staging

# PR #142 のレビュー
/review 142

# feature ブランチのレビュー（develop との差分）
/review feature/add-payment

# feature ブランチを main との差分でレビュー
/review feature/add-payment --base main

# src/api ディレクトリの品質監査
/review --audit src/api
```
