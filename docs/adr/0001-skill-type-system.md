# ADR-0001: Skill 型システムの設計方針

- **Status**: Draft
- **Date**: 2026-05-29
- **Context**: devkit に skill 作成スキルを追加するにあたり、skill の型体系を0から設計した

---

## 背景

devkit は現在複数の skill/agent を持っているが、型の定義がなく「何を作るか」の判断基準が属人的だった。skill の設計者が増えるにつれて、同じ目的のスキルが異なる設計になる・LLMがどのスキルを呼ぶべきか判断できないという問題が生じた。

2025〜2026年のLLMエージェント研究を調査した結果、skill を「入力と出力の関係」で分類することが設計の一貫性と型の境界の明確さにつながるという結論に至った。具体的には以下の要求を型システムで満たす：

- **直感性**: Claude Code を使う全ユーザー（非エンジニア含む）が型名を見て何をするものか即座に分かる
- **境界の明確さ**: 「このスキルはどの型か」が入力と出力の関係だけで機械的に決まる
- **安全性**: sycophancy・context汚染・セキュリティリスクを型の定義に組み込み、運用ルールへの依存を減らす
- **形式性**: [SoK: Agentic Skills (2602.20867)](https://arxiv.org/abs/2602.20867) が提唱する形式定義 `S = (C, π, T, R)`（C: 適用条件, π: 実行ポリシー, T: 終了条件, R: 再利用インターフェース）を土台にし、型の判定を決定木で機械的に行える

---

## 論文的根拠

| 論文 | 採用した知見 |
|---|---|
| [SoK: Agentic Skills (2602.20867)](https://arxiv.org/abs/2602.20867) | Skill = `S = (C, π, T, R)` の形式定義。representation × scope の2軸タクソノミー。知識注入と行動実行の分離 |
| [Agent Skills Architecture (2602.12430)](https://arxiv.org/abs/2602.12430) | SKILL.md + scripts/ + references/ 構造。Progressive Disclosure（段階的コンテキスト読み込み） |
| [Comprehensive Survey on Agent Skills (2605.07358)](https://arxiv.org/html/2605.07358v1) | skill を「知識注入」と「行動実行」で分離することの有効性 |
| [SycEval (2502.08177)](https://arxiv.org/html/2502.08177v4) | 同一context自己評価の78.5%迎合率 → evaluate型は型レベルで別context実行を強制 |
| [Graph of Skills (2604.05333)](https://arxiv.org/abs/2604.05333) | 依存チェーンの明示的宣言。スキル間の依存関係を設計時に宣言することの重要性 |
| [DACS (2604.07911)](https://arxiv.org/abs/2604.07911) | context汚染の隔離 → 探索・評価は別contextに逃がす |
| [Skill-Inject (2602.20156)](https://arxiv.org/abs/2602.20156) | SKILL.md自体が攻撃面（実証済み脆弱性26.1%）→ セキュリティ確認をフロー必須ステップに |
| [Lost in the Middle (2307.03172)](https://arxiv.org/abs/2307.03172) | 重要情報は先頭30行に集約。末尾情報はcompaction後に消える |

---

## 決定: 4型システム

### 設計の起点

型の境界を「入力と出力の関係」で定義する。副作用の有無ではなく、**スキルが何を受け取り何を返すか**が型を決める。これにより「コードレビュー結果をファイルに書く」のような境界例も一意に決まる（主目的が評価なら `evaluate`、主目的が成果物生成なら `do`）。

また、「他スキルを呼ぶかどうか」を独立した型の軸として設ける。これにより、LLMが単一スキルとオーケストレーターを混同する問題を型レベルで防ぐ。

### 型の定義

| 型 | 入力 | 出力 | 他スキルを呼ぶか |
|---|---|---|---|
| `load` | — | コンテキスト提供 | なし |
| `do` | 入力 | 単一の成果物 | なし |
| `evaluate` | 入力 + 成果物 | 判定JSON | なし（評価専任） |
| `orchestrate` | 入力 | 複数ステップの実行結果 | あり |

### 決定木

```
他のスキルを呼び出して組み合わせるか？
  Yes → orchestrate 型
  No  → 何を出力するか？
          コンテキスト提供（出力なし）→ load 型
          判定JSON のみ             → evaluate 型  ※ 別context実行が型の定義に含まれる
          成果物（ファイル・変換結果）→ do 型
```

### 各型の制約

**load 型**
- `user-invocable: false` が既定（Claudeが自動参照するもの）
- Write 禁止。Read のみ
- 副作用なしの保証が型の定義に含まれる

**do 型**
- Input / Output を観測可能な形で定義する（「完了しました」は Output ではない）
- 500行を超える場合は `references/` に降ろす（Lost in the Middle論文: compaction対策）
- 最重要ルールは冒頭30行に集約する

**evaluate 型**
- **別context実行が型の定義に含まれる**（SycEval論文の78.5%迎合率対策。ルールではなく型で強制）
- 成果物を直接編集しない。Read のみ
- 評価基準（rubric / ref）を自分では変更できない
- 出力形式: 評価JSON（score / feedback_structured / passed）

**orchestrate 型**
- 呼び出すスキルを `dependencies:` で宣言する（Graph of Skills論文: 依存チェーンの明示的宣言）
- 探索・評価の結果を親contextに積み上げない。subagentに消化させてサマリだけ受け取る（DACS論文: context汚染の隔離）
- ループの終了条件を明示する（無限ループ防止）

### 境界例

| ケース | 型 | 理由 |
|---|---|---|
| コードレビュー結果をファイルに書く | `do` | 主目的が成果物（レポートファイル）の生成 |
| コードレビューして判定JSONを返す | `evaluate` | 主目的が評価。ファイル書き込みは型違反 |
| qa-loop（テスト→修正→再テスト） | `orchestrate` | 複数ステップを制御。他スキルを呼ぶ |
| 外部APIを叩いて知識を返す | `load` | 出力がコンテキスト提供。副作用なし |
| 外部APIを叩いて状態を変える | `do` | 副作用あり。成果物（変更結果）を返す |

---

## devkit との対応

devkit の既存コンポーネントを4型で再分類すると：

| コンポーネント | 型 | 備考 |
|---|---|---|
| `coding-conventions` skill | `load` | 知識注入のみ |
| `pr-review` skill | `orchestrate` | 複数agentを並列実行して結果を統合 |
| `qa-loop` skill | `orchestrate` | テスト→修正→再テストのループ制御 |
| `security-gate` skill | `orchestrate` | 複数チェックを順番に走らせる |
| `tech-debt` skill | `orchestrate` | 複数分析を組み合わせて実行 |
| `quality-reviewer` agent | `evaluate` | 成果物評価専任 |
| `security-auditor` agent | `evaluate` | セキュリティ評価専任 |
| `ux-reviewer` agent | `evaluate` | UX評価専任 |
| `type-checker` agent | `evaluate` | 型安全性評価専任 |
| `debt-analyzer` agent | `evaluate` | 技術負債評価専任 |

旧ADRでは `pr-review` / `qa-loop` / `security-gate` を `do` に分類していたが、これらは全て複数スキル・agentの組み合わせであるため `orchestrate` に再分類。

---

## skill 作成スキル（make-skill）の設計方針

この型システムを前提に、skill を0から作るための `do` 型スキル `make-skill` を devkit に追加する。

### ファイル構成

```
plugins/devkit/skills/make-skill/
├── SKILL.md
└── references/
    ├── type-system.md          # 4型の詳細定義・境界例・決定木
    ├── description-guide.md    # トリガー文の書き方
    └── security-checklist.md   # Skill固有の脅威タクソノミー（Skill-Inject論文ベース）
```

### フロー概要

| Step | 担当 | 手段 |
|---|---|---|
| 0 Skill適格性チェック | 親 | — |
| 1 gap の特定 | 親 | ユーザー対話 |
| 2 コードベース探索 + MECEチェック | **subagent** | `Agent(subagent_type="Explore")` |
| 3 型の決定 + 宣言 | 親 | 決定木を適用 |
| 4 SKILL.md 起草 | 親 | Write |
| 5 トリガー文最適化 | 親 | `references/description-guide.md` 参照 |
| 6 セキュリティ確認 | 親 | `references/security-checklist.md` 参照 |
| 7 セルフチェック | 親 | チェックリスト |
| 8 内部レビュー | **subagent** | `evaluate` 型スキルをfork実行（DACS論文: context汚染の隔離） |
| 9 ユーザーへの提示 | 親 | — |

**Step 2 MECEチェックの内容**

Explore subagent に以下を調べさせ、200語以内のサマリで返させる：

走査対象（実行環境の全スキルディレクトリ）:
- `~/.claude/skills/`
- `~/.claude/plugins/*/skills/`
- `.claude/skills/`（プロジェクトローカル）

確認内容:
1. 上記3箇所の全スキルの `triggers:` と `description` を走査し、今回作るスキルと意図が重複するものがないか
2. 重複が見つかった場合は「既存スキルを `orchestrate` 型で呼ぶ設計で済まないか」を親が判断
3. 重複なしの場合のみ Step 3 へ進む

---

## 未解決事項

- `evaluate` 型スキルの評価JSON スキーマを devkit として統一定義するか（現状は agent ごとにバラバラ）
- `make-skill` スキル自体の `evaluate` 型ペア（設計品質を評価する skill）をいつ作るか

---

## 関連論文

- [SoK: Agentic Skills — Beyond Tool Use in LLM Agents](https://arxiv.org/abs/2602.20867)
- [Agent Skills for Large Language Models: Architecture, Acquisition, Security](https://arxiv.org/abs/2602.12430)
- [A Comprehensive Survey on Agent Skills: Taxonomy, Techniques, and Applications](https://arxiv.org/html/2605.07358v1)
- [SkillOpt: Executive Strategy for Self-Evolving Agent Skills](https://arxiv.org/abs/2605.23904)
- [Graph of Skills: Dependency-Aware Structural Retrieval](https://arxiv.org/abs/2604.05333)
- [Dynamic Attentional Context Scoping (DACS)](https://arxiv.org/abs/2604.07911)
- [SycEval: Evaluating LLM Sycophancy](https://arxiv.org/html/2502.08177v4)
- [Skill-Inject: Measuring Agent Vulnerability to Skill File Attacks](https://arxiv.org/abs/2602.20156)
- [Lost in the Middle: How Language Models Use Long Contexts](https://arxiv.org/abs/2307.03172)

---

## frontmatter 仕様

4型の情報を機械可読な frontmatter として標準化する。

### 型別 frontmatter テンプレート

**load 型**
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

**do 型**
```yaml
---
name: xxx
type: do
mutating: true
writes_to:
  - output/        # 書き込み先のスコープを限定
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

**evaluate 型**
```yaml
---
name: xxx
type: evaluate
mutating: false
context: fork      # 別context実行。型の定義として必須
agent: general-purpose
tools:
  - Read           # Read のみ。Write を含めると型違反
user-invocable: false
triggers:
  - 評価・採点・チェック系のトリガー
---
```

**orchestrate 型**
```yaml
---
name: xxx
type: orchestrate
mutating: true
dependencies:
  - yyy            # 呼び出すスキルを列挙（Graph of Skills論文: 依存チェーンの明示）
  - zzz
tools:
  - Agent
user-invocable: true
argument-hint: "<引数の説明>"
triggers:
  - 「...」
---
```

### フィールド定義

| フィールド | 型 | 必須 | 意味 |
|---|---|---|---|
| `type` | `load\|do\|evaluate\|orchestrate` | ○ | 4型のいずれか。機械可読な型宣言 |
| `mutating` | boolean | ○ | 副作用の有無。`type` から自動導出できるが明示して lint に使う |
| `dependencies` | string[] | `orchestrate` 型で必須 | 呼び出すスキル名の一覧 |
| `writes_to` | string[] | `do`/`orchestrate` 型で推奨 | 書き込み先ディレクトリ。スコープの明示とセキュリティ審査に使う |
| `tools` | string[] | 推奨 | 使用するツール一覧。Skill-Inject脅威審査（脆弱性26.1%）に使う |
| `triggers` | string[] | 推奨 | トリガーとなるユーザー発話。`description` より機械的に扱える |
| `context` | `fork` | `evaluate` 型で必須 | 別context実行の宣言 |
| `user-invocable` | boolean | ○ | Claude Code 公式フィールド。`/` メニュー表示の制御 |
| `argument-hint` | string | `user-invocable: true` かつ `$ARGUMENTS` を読む場合 | タブ補完時のヒント表示 |

### 型整合性ルール（lint で検出可能）

- `type: load` かつ `mutating: true` → エラー
- `type: evaluate` かつ `tools` に `Write`/`Edit` → エラー
- `type: evaluate` かつ `context: fork` なし → エラー
- `type: orchestrate` かつ `dependencies:` なし → エラー
- `mutating` の値が `type` から導出される値と不一致 → 警告
