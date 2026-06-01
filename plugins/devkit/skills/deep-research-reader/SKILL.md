---
name: deep-research-reader
type: reader
mutating: false
user-invocable: true
argument-hint: "<調査トピック> [--mode quick|standard|deep]"
dependencies:
  - fact-collector
  - fact-verifier
  - report-writer
description: |
  Use this skill when the user asks to research, investigate, compare, or analyze any topic
  deeply. Orchestrates parallel sub-agents across fact collection, verification, and report
  writing phases. Triggers on: "research", "investigate", "compare", "analyze", "deep dive",
  "調べて", "リサーチ", "調査して", "比較して", "詳しく教えて", "深掘り".
version: 1.0.0
tools:
  - Read
  - Bash
  - Glob
  - Grep
  - WebSearch
  - WebFetch
  - Agent
  - AskUserQuestion
triggers:
  - "research"
  - "investigate"
  - "compare"
  - "analyze"
  - "deep dive"
  - 調べて
  - リサーチ
  - 調査して
  - 比較して
  - 詳しく教えて
  - 深掘り
---

# Deep Research — 並列サブエージェント・オーケストレーション

このスキルは調査の「交通整理役」です。要件を精緻化し、収集・検証・執筆を
独立したエージェントに並列委譲して、偏りのないレポートを生成します。

---

## Step 1: 事前インタビューでスコープを確定する

AskUserQuestion ツールで以下を確認する（1回のまとめ質問で聞く）:

- **調査トピック**: 何を知りたいか（まだ曖昧なら具体化する）
- **調査の目的**: 意思決定のため / 学習のため / 技術選定のため
- **深さ**: 概要レベル(Quick) / 標準(Standard) / 徹底調査(Deep)
- **除外領域**: 調べなくていいこと・期間・対象外の技術スタック

既に十分な情報が会話から取れている場合はこのステップをスキップしてよい。

---

## Step 2: 調査設計（中立クエリの構築）

確証バイアスを排除するため、クエリを以下のルールで組み立てる:

| NG（バイアスあり） | OK（中立） |
|---|---|
| 「なぜXは優れているか」 | 「Xの特性・制約・ユースケースは何か」 |
| 「Xの利点」 | 「X のトレードオフ」 |

### 調査クエリセットを生成する

```
通常クエリ (3件):
  1. [トピック] [対象期間] site:公式ドキュメント or 専門ブログ
  2. [トピック] comparison benchmark [年]
  3. [トピック] use cases production examples

反証クエリ (2件) — 確証バイアス対抗:
  4. [トピック] problems limitations production
  5. switching away from [トピック] OR [トピック] vs alternative
```

### 深さ別エージェント構成

| モード | エージェント構成 |
|--------|----------------|
| Quick  | collector × 1、report-writer × 1（直列） |
| Standard | collector × 2（並列）、verifier × 1、report-writer × 1 |
| Deep   | collector × 3（並列）、verifier × 2（並列）、report-writer × 1、reviewer × 1 |

---

## Step 3: 情報収集フェーズ（並列実行）

**使用エージェント**: `fact-collector`（`agents/fact-collector.md` で定義）

**Standard / Deep モード**: 複数の `fact-collector` を Agent ツールで並列起動する。
1つのメッセージに複数の Agent ツール呼び出しを並べることで並列実行される。

各エージェントへの指示テンプレート（Agent ツールの prompt に渡す）:

```
agents/fact-collector.md の指示に従って動作してください。

担当クエリ: [クエリA] / [クエリB]
対象期間: [YYYY年以降]
トピック: [調査トピック]

収集情報を Tier 分類・循環引用チェック付きで報告してください。
```

**反証担当 collector への追加指示**（必ず1インスタンスに担当させる）:

```
agents/fact-collector.md の指示に従って動作してください。

担当クエリ（反証）:
- "[トピック] problems limitations production"
- "switching away from [トピック]"

批判・失敗事例を重点収集してください。確証バイアス排除が目的です。
```

---

## Step 4: 検証フェーズ（Deep モードのみ並列実行）

**使用エージェント**: `fact-verifier`（`agents/fact-verifier.md` で定義）

**Standard モード**: verifier × 1 で全収集情報を検証。
**Deep モード**: verifier × 2 を並列で起動し、担当情報を分割する。

各 verifier への指示テンプレート（Agent ツールの prompt に渡す）:

```
agents/fact-verifier.md の指示に従って動作してください。

以下の collector 出力を検証してください:
[collector-A の出力] / [collector-B の出力（Deep モード）]

独立ソース確認・循環引用検出・矛盾フラグ・信頼度付与を行ってください。
```

---

## Step 5: レポート生成フェーズ

**使用エージェント**: `report-writer`（`agents/report-writer.md` で定義）

report-writer への指示テンプレート（Agent ツールの prompt に渡す）:

```
agents/report-writer.md の指示に従って動作してください。

以下の検証済み情報からレポートを生成してください:
[verifier の出力全文]

トピック: [調査トピック]
調査モード: [Quick / Standard / Deep]
スコープ: [対象・除外・対象期間]
```

---

## Step 6: 品質チェック（Deep モードのみ）

**使用エージェント**: 汎用エージェント（report-writer とは独立したコンテキストで起動する）

reviewer への指示テンプレート（Agent ツールの prompt に渡す）:

```
あなたはリサーチレポートの独立レビュアーです。
report-writer とは完全に独立したコンテキストでレビューしてください。

以下のレポートをレビューしてください:
[report-writer の出力]

チェックリスト:
□ 事実確認: Tier 1/2 のみで裏付けられた主張が「確認済み」と書かれているか
□ バイアス確認: 結論が特定の技術・選択肢に偏っていないか、相反するエビデンスが等しく扱われているか
□ 構造確認: Executive Summary だけで意思決定できるか、調査限界が正直に記載されているか
□ 循環引用: 独立ソースが実際に独立しているか

出力: 修正必須項目 / 修正推奨項目 / 承認
```

reviewer が「修正必須」を返した場合は report-writer に差し戻す（最大1回）。

---

## Step 7: 最終レポートを出力する

```markdown
# Deep Research Report — [トピック]

**調査日:** [YYYY-MM-DD]
**調査モード:** [Quick / Standard / Deep]
**調査スコープ:** [対象・除外・対象期間]

---

## Executive Summary
[2〜3文。結論・推奨・留意点を含む]

---

## 主要発見

### 確認済み（Tier 1/2）
- ...

### 有力だが要確認（Tier 3）
- ...

---

## 詳細分析
[各観点の詳細]

---

## 相反情報・批判的見解
[反証クエリで得た情報。省略禁止]

---

## 調査限界
- 未調査領域: ...
- Tier 4 のみの主張: ...
- 情報の鮮度リスク: ...

---

## 証拠品質マトリクス

| 主張 | 信頼度 | ソース数 | 最強証拠 | 未確定リスク |
|------|--------|---------|---------|------------|
```

---

## 並列実行の優先ルール

1. **fact-collector は常に並列で起動する**（依存関係なし）
2. **fact-verifier は collector 完了後に並列で起動する**（Deep モード）
3. **report-writer は verifier 完了後**（Sequential）
4. **reviewer は report-writer とは独立したコンテキストで起動する**

```
[Standard モード]
collector-A ──┐
collector-B ──┴──► verifier ──► report-writer

[Deep モード]
collector-A ──┐
collector-B ──┼──► verifier-A ──┐
collector-C ──┘    verifier-B ──┴──► report-writer ──► reviewer
```

---

## 中断・リセット条件

- 同じ検索クエリで有効な情報が2回連続で得られない → クエリを変えて再試行（1回まで）
- コンテキストが50%に達したら中間サマリーを作成してから続行する
- 調査結果が「情報なし」に終わった場合は、その旨を正直に報告する（推測で補わない）
