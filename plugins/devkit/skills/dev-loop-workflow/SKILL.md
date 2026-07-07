---
name: dev-loop-workflow
type: workflow
mutating: true
user-invocable: true
argument-hint: "<タスク説明>"
dependencies:
  - coding-conventions-reader
  - qa-workflow
  - pr-review-reader
  - implement-to-pr-workflow
writes_to:
  - .
description: |
  要件・設計 → 実装 → 検証 → コミット → レビュー → Live Proof → 要件トレース → PR →
  本人の受け入れテストまでを1依頼で回す開発ループ。dev-lead（Tech Lead/PM）を常駐させ、
  dev-developer / dev-qa / 独立レビューを連携する。本人が登場するのはエスカレーションと
  最終受け入れテスト＋マージ号令のみ。AI はマージしない。
  Use when the user wants full-cycle development from task description to merge-ready PR.
  Triggers on: dev-loop, 開発ループ, 設計からPRまで, 要件から実装まで, 受け入れテストまで回して.
  受け入れ条件が既に確定している実装-only 依頼は implement-to-pr-workflow を直接使うこと。
version: 1.0.0
tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Agent
  - Skill
  - Task
triggers:
  - dev-loop
  - 開発ループ
  - 設計からPRまで
  - 要件から実装まで
  - 受け入れテストまで回して
---

# dev-loop-workflow — 設計から受け入れテスト依頼まで

**Input:** タスク説明（ゴール・制約があれば含める）
**Output:** マージ可能な PR + 本人向け受け入れテストパッケージ + Decision Brief

## 3原則（implement-to-pr-workflow と共通）

1. **Decision-Ready** — 未整備のものを本人に判断させない
2. **Live Proof** — テスト緑だけで実物確認を省略しない
3. **push ≠ merge** — PR 作成まで。マージは本人のみ

## Harness（Claude Code / Cursor 両対応）

| 操作 | Claude Code | Cursor |
|------|-------------|--------|
| dev-lead 起動 | `Agent` → `devkit:dev-lead` | `Task` → `subagent_type="generalPurpose"`、prompt 先頭に `agents/dev-lead.md` 全文 |
| dev-lead 常駐 | 同一 Agent を `resume` / SendMessage で継続 | 同一 Task を `resume` で継続 |
| dev-developer / dev-qa | `Agent` → `devkit:dev-developer` / `devkit:dev-qa` | `Task` + 対応 agent md 全文を prompt に載せる |
| レビュー用 subagent | `Agent` → `devkit:quality-reviewer` 等 | `Task` → `subagent_type="quality-reviewer"` 等（devkit agents と同名） |
| スキル委譲 | `Skill` ツール | orchestrator が SKILL.md を `Read` し手順に従う |
| Live Proof（UI） | browser MCP / Bash curl | cursor-ide-browser MCP / Bash curl |

**ルール:** 環境で使えるツールを選ぶ。Claude Code では `Agent`/`Skill` を優先。Cursor では `Task`/`Read` で同等の手順を実行する。

---

## Phase 0: ブランチ

1. デフォルトブランチ上にいる場合、feature ブランチを切る
2. 共有ブランチ上では実装しない

## Phase 1: 設計・要件（dev-lead）

`dev-lead` を起動し `$ARGUMENTS` を渡す（Harness 表に従う）。

dev-lead の成果物:

- タスク宣言（一文）
- **番号付き受け入れ条件**（正常系＋異常系。implement-to-pr Step 0 品質基準を満たすこと）
- mermaid + 実装計画（今回 / 別 Issue 化）
- エスカレーション事項（あれば本人に選択肢＋推奨で確認 → 回答を dev-lead に返して確定）

**ゲート:** 受け入れ条件が1つもテスト可能な粒度でない場合は実装に入らず設計相談として停止。

## Phase 2: 実装（dev-developer）

1. 確定計画と番号付き AC を `dev-developer` に渡す
2. 実装中の確認は dev-lead に裁定 → 回答を dev-developer に返す
3. dev-developer は `coding-conventions-reader` に従う

## Phase 3: コミット（dev-lead 承認ゲート）

1. dev-developer がコミットメッセージ案を提出
2. dev-lead が承認ゲート（証拠・スコープ・粒度・衛生）を実行
3. 承認後、feature ブランチ上で `git add` + `git commit`
4. 未コミット変更が残っていれば Phase 3 を完了するまで次へ進まない

## Phase 4: 検証（dev-qa + qa-workflow）

1. `dev-qa` に実装内容・AC 一覧を渡し Live Proof 含む検証
2. Fail → dev-developer に差し戻し（同一問題2回まで）→ Phase 2-3 へ
3. Pass 後、`qa-workflow` スキルでテスト→修正ループ（最大5回）
4. dev-qa が「本人向け受け入れテスト項目」を出力（LLM/UI 等の自動検証不能項目）

## Phase 5: 独立レビュー（pr-review-reader）

`pr-review-reader` スキルの手順で diff を敵対的レビュー:

| 指摘 | 対応 |
|------|------|
| CRITICAL / HIGH | dev-developer で修正 → Phase 3-4 へ |
| MEDIUM / LOW | Decision Brief に回す |

**往復上限:** Phase 4↔5 は最大2周。

## Phase 6: Live Proof + 要件トレース

`implement-to-pr-workflow` の **Step 4（Live Proof）** と **Step 5（requirements-checker）** に従う:

- Phase 1 で確定した番号付き AC を基準に双方向トレース
- 未達が1つでもあれば BLOCK → Phase 2 へ（最大1回）

## Phase 7: PR 作成（dev-lead 最終承認）

1. dev-lead 最終承認ゲート
2. ベースブランチを `git log` / リモート HEAD から自動検出
3. AC・トレーサビリティ・マトリクス・Live Proof 証跡・レビュー結果を PR body に含め `gh pr create`
4. ブランチを push し canonical URL を取得
5. **`gh pr merge` は実行しない**

## Phase 8: 本人への受け入れテスト + Decision Brief

`implement-to-pr-workflow` **Step 8（Decision Brief）** の形式に、以下を追加:

```markdown
## 受け入れテスト依頼

**PR**: https://github.com/OWNER/REPO/pull/NN
**タスク宣言**: <一文>

### 自動で完了済み
- 設計 / 実装 / commit / QA / 独立レビュー / Live Proof / 要件トレース / PR 作成

### あなたに確認してほしいこと（自動検証不能な項目のみ）
1. <URL＋手順>

### dev-lead の裁定ログ
- 設計: … / 実装中裁定: N件 / 最終ゲート: 承認
- エスカレーション: なし（あれば経緯）

---
→ この PR を **マージ** しますか、**クローズ** しますか？（私はマージしません）
```

## 本人が登場する場面（この2つ以外はゼロ）

| 場面 | タイミング |
|------|-----------|
| エスカレーション | dev-lead が境界と判定した時のみ |
| 受け入れテスト＋マージ号令 | Phase 8 |

## 禁止事項

- 既存テストの改ざん・skip で通す
- Live Proof の省略（環境不足時は停止報告）
- マージ・本番反映・破壊的削除
- dev-lead なしにスコープ追加

## 学習ループ（任意）

本人の判断と dev-lead の裁定が食い違った場合、`~/Documents/brain/context/` の改訂候補として報告する。
