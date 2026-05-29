# 4型システム — 詳細定義・決定木・境界例

出典: ADR-0001（docs/adr/0001-skill-type-system.md）

---

## 設計の起点

型の境界を「**入力と出力の関係**」で定義する。副作用の有無ではなく、スキルが何を受け取り何を返すかが型を決める。

「他スキルを呼ぶかどうか」を独立した型の軸として設けることで、LLM が単一スキルとオーケストレーターを混同する問題を型レベルで防ぐ。

---

## 型の定義

| 型 | 入力 | 出力 | 他スキルを呼ぶか |
|---|---|---|---|
| `load` | — | コンテキスト提供 | なし |
| `do` | 入力 | 単一の成果物 | なし |
| `evaluate` | 入力 + 成果物 | 判定JSON | なし（評価専任） |
| `orchestrate` | 入力 | 複数ステップの実行結果 | あり |

---

## 決定木

```
他のスキルを呼び出して組み合わせるか？
  Yes → orchestrate 型
  No  → 何を出力するか？
          コンテキスト提供（出力なし）→ load 型
          判定JSON のみ             → evaluate 型
          成果物（ファイル・変換結果）→ do 型
```

---

## 各型の制約

### load 型

- `user-invocable: false` が既定（Claude が自動参照するもの）
- `Write` / `Edit` 禁止。`Read` のみ
- 副作用なしの保証が型の定義に含まれる

### do 型

- Input / Output を観測可能な形で定義する（「完了しました」は Output ではない）
- 500行を超える場合は `references/` に降ろす（Lost in the Middle 論文: compaction 対策）
- 最重要ルールは冒頭30行に集約する

### evaluate 型

- **別context 実行が型の定義に含まれる**（SycEval 論文の78.5%迎合率対策。ルールではなく型で強制）
  - frontmatter に `context: fork` を必須フィールドとして宣言する
- 成果物を直接編集しない。`Read` のみ
- 評価基準（rubric / ref）を自分では変更できない
- 出力形式: 評価JSON（`score` / `feedback_structured` / `passed`）

### orchestrate 型

- 呼び出すスキルを `dependencies:` で宣言する（Graph of Skills 論文: 依存チェーンの明示的宣言）
- 探索・評価の結果を親 context に積み上げない。subagent に消化させてサマリだけ受け取る（DACS 論文: context 汚染の隔離）
- ループの終了条件を明示する（無限ループ防止）

---

## frontmatter テンプレート

### load 型

```yaml
---
name: xxx
type: load
mutating: false
user-invocable: false
triggers:
  - 「...」
---
```

### do 型

```yaml
---
name: xxx
type: do
mutating: true
writes_to:
  - output/
tools:
  - Read
  - Write
  - Bash
user-invocable: true
argument-hint: "<引数の説明>"
triggers:
  - 「...」
---
```

### evaluate 型

```yaml
---
name: xxx
type: evaluate
mutating: false
context: fork
agent: general-purpose
tools:
  - Read
user-invocable: false
triggers:
  - 評価・採点・チェック系のトリガー
---
```

### orchestrate 型

```yaml
---
name: xxx
type: orchestrate
mutating: true
dependencies:
  - yyy
  - zzz
tools:
  - Agent
user-invocable: true
argument-hint: "<引数の説明>"
triggers:
  - 「...」
---
```

---

## フィールド定義

| フィールド | 型 | 必須 | 意味 |
|---|---|---|---|
| `type` | `load\|do\|evaluate\|orchestrate` | ○ | 4型のいずれか |
| `mutating` | boolean | ○ | 副作用の有無 |
| `dependencies` | string[] | `orchestrate` 型で必須 | 呼び出すスキル名の一覧 |
| `writes_to` | string[] | `do`/`orchestrate` 型で推奨 | 書き込み先ディレクトリ |
| `tools` | string[] | 推奨 | 使用するツール一覧 |
| `triggers` | string[] | 推奨 | トリガーとなるユーザー発話 |
| `context` | `fork` | `evaluate` 型で必須 | 別 context 実行の宣言 |
| `user-invocable` | boolean | ○ | `/` メニュー表示の制御 |
| `argument-hint` | string | `user-invocable: true` かつ `$ARGUMENTS` を読む場合 | タブ補完時のヒント |

---

## 型整合性ルール（lint で検出可能）

| ルール | 種別 |
|---|---|
| `type: load` かつ `mutating: true` | エラー |
| `type: evaluate` かつ `tools` に `Write`/`Edit` | エラー |
| `type: evaluate` かつ `context: fork` なし | エラー |
| `type: orchestrate` かつ `dependencies:` なし | エラー |
| `mutating` の値が `type` から導出される値と不一致 | 警告 |

---

## 境界例

| ケース | 型 | 理由 |
|---|---|---|
| コードレビュー結果をファイルに書く | `do` | 主目的が成果物（レポートファイル）の生成 |
| コードレビューして判定 JSON を返す | `evaluate` | 主目的が評価。ファイル書き込みは型違反 |
| qa-loop（テスト→修正→再テスト） | `orchestrate` | 複数ステップを制御。他スキルを呼ぶ |
| 外部 API を叩いて知識を返す | `load` | 出力がコンテキスト提供。副作用なし |
| 外部 API を叩いて状態を変える | `do` | 副作用あり。成果物（変更結果）を返す |

---

## devkit コンポーネントの型分類

| コンポーネント | 型 | 備考 |
|---|---|---|
| `coding-conventions` skill | `load` | 知識注入のみ |
| `pr-review` skill | `orchestrate` | 複数 agent を並列実行して結果を統合 |
| `qa-loop` skill | `orchestrate` | テスト→修正→再テストのループ制御 |
| `security-gate` skill | `orchestrate` | 複数チェックを順番に走らせる |
| `tech-debt` skill | `orchestrate` | 複数分析を組み合わせて実行 |
| `deep-research` skill | `orchestrate` | 収集・検証・執筆を並列 agent に委譲 |
| `make-skill` skill | `do` | 成果物（SKILL.md）を生成 |
| `quality-reviewer` agent | `evaluate` | 成果物評価専任 |
| `security-auditor` agent | `evaluate` | セキュリティ評価専任 |
| `ux-reviewer` agent | `evaluate` | UX 評価専任 |
| `type-checker` agent | `evaluate` | 型安全性評価専任 |
| `debt-analyzer` agent | `evaluate` | 技術負債評価専任 |
