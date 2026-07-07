# ADR-0001: Skill 型システムの設計方針

- **Status**: Accepted
- **Date**: 2026-05-29
- **Updated**: 2026-06-01
- **Context**: devkit に skill 作成スキルを追加するにあたり、skill の型体系を0から設計した

---

## 背景

devkit は現在複数の skill/agent を持っているが、型の定義がなく「何を作るか」の判断基準が属人的だった。skill の設計者が増えるにつれて、同じ目的のスキルが異なる設計になる・LLMがどのスキルを呼ぶべきか判断できないという問題が生じた。

2025〜2026年のLLMエージェント研究を調査した結果、skill を「副作用の有無」と「スキル合成の有無」の2軸で分類することが設計の一貫性と型の境界の明確さにつながるという結論に至った。具体的には以下の要求を型システムで満たす：

- **直感性**: Claude Code を使う全ユーザー（非エンジニア含む）が型名を見て何をするものか即座に分かる
- **境界の明確さ**: 「このスキルはどの型か」が2問の決定木で機械的に決まる
- **安全性**: context汚染・セキュリティリスクを型の定義に組み込み、運用ルールへの依存を減らす
- **形式性**: [SoK: Agentic Skills (2602.20867)](https://arxiv.org/abs/2602.20867) が提唱する形式定義 `S = (C, π, T, R)` を土台にし、型の判定を決定木で機械的に行える
- **関数型との整合**: 型の意味論が関数型プログラミングの概念（純粋関数・IOアクション・Kleisli合成）と矛盾しない

---

## 論文的根拠

| 論文 | 採用した知見 |
|---|---|
| [SoK: Agentic Skills (2602.20867)](https://arxiv.org/abs/2602.20867) | Skill = `S = (C, π, T, R)` の形式定義。representation × scope の2軸タクソノミー。知識注入と行動実行の分離 |
| [Agent Skills Architecture (2602.12430)](https://arxiv.org/abs/2602.12430) | SKILL.md + scripts/ + references/ 構造。Progressive Disclosure（段階的コンテキスト読み込み） |
| [Comprehensive Survey on Agent Skills (2605.07358)](https://arxiv.org/html/2605.07358v1) | skill を「知識注入」と「行動実行」で分離することの有効性 |
| [SycEval (2502.08177)](https://arxiv.org/html/2502.08177v4) | 同一context自己評価の78.5%迎合率 → 判定を返す reader は `context: fork` を推奨 |
| [Graph of Skills (2604.05333)](https://arxiv.org/abs/2604.05333) | 依存チェーンの明示的宣言。スキル間の依存関係を設計時に宣言することの重要性 |
| [DACS (2604.07911)](https://arxiv.org/abs/2604.07911) | context汚染の隔離 → 探索・評価は別contextに逃がす |
| [Skill-Inject (2602.20156)](https://arxiv.org/abs/2602.20156) | SKILL.md自体が攻撃面（実証済み脆弱性26.1%）→ セキュリティ確認をフロー必須ステップに |
| [Lost in the Middle (2307.03172)](https://arxiv.org/abs/2307.03172) | 重要情報は先頭30行に集約。末尾情報はcompaction後に消える |

---

## 決定: 3型システム

### スキル命名規則

型ごとにスキル名のパターンを統一する。

| 型 | 命名パターン | 例 |
|---|---|---|
| `reader` | `{topic}-reader` | `pr-review-reader`, `tech-debt-reader` |
| `workflow` | `{topic}-workflow` | `qa-workflow` |
| `command` | 動詞で始まるケバブケース | `make-skill`, `generate-report` |

**理由**: 型名がスキル名に現れることで、スキル一覧を見ただけで副作用の有無と合成の有無が分かる。
`command` 型は動詞ベースにすることで「何をするか」が名前から明確になり、副作用の存在を動詞が暗示する。

### 設計の2軸

型の境界を「**副作用の有無**」と「**スキル合成の有無**」の2つの直交する軸で定義する。

```
              副作用なし (pure)    副作用あり (effectful)
              ─────────────────────────────────────────
atomic        │  reader           │  command
composite     │  reader（吸収）    │  workflow
```

副作用なしの合成（複数の reader を並列実行して統合）は `reader` に吸収する。
関数型では **純粋関数の合成は純粋関数** であり、独立した型を設ける必要がないため。

### 関数型プログラミングとの対応

| 型 | 関数型の概念 | 意味 |
|---|---|---|
| `reader` | Reader モナド / 純粋関数 | `Reader env a` — 環境から値を読むが状態を変えない。参照透過性が保証される |
| `command` | IO アクション（非合成） | `IO a` の単一インスタンス。副作用を型レベルで明示し、合成の最小単位として機能する |
| `workflow` | Kleisli 合成 (`>>=`) | `a -> IO b` を `>>=` で繋いだもの。`command` を Kleisli 矢として合成する |

### 型の定義

| 型 | 入力 | 出力 | 副作用 | 他スキルを呼ぶか |
|---|---|---|---|---|
| `reader` | 0個以上 | 情報・知識・判定・レポート | **禁止** | 任意（pure な合成は reader のまま） |
| `command` | 1個以上 | 単一の成果物 | **あり** | 基本なし（合成の最小単位） |
| `workflow` | 1個以上 | 複数ステップの実行結果 | **あり** | **必須** |

### 決定木

```
Q1: ファイル書き込み・状態変更・外部サービスへの書き込みをするか？
    ├─ NO  → reader
    └─ YES
         Q2: 他のスキルを呼び出して複数フェーズを合成するか？
             ├─ NO  → command
             └─ YES → workflow
```

### 各型の制約

**reader 型**
- **ファイルシステムへの書き込み禁止**（`Write` / `Edit` は型違反）
- 読み取り専用の Bash（`grep`, `git log`, `cat` 等）は許可
- 複数の reader スキルを並列実行して統合することは許可（その結果も reader）
- 判定結果を返す場合は `context: fork` を推奨（SycEval論文の78.5%迎合率対策）

**command 型**
- Input / Output を観測可能な形で定義する（「完了しました」は Output ではない）
- 副作用は単一のドメインに限定することを推奨
- 500行を超える場合は `references/` に降ろす（Lost in the Middle論文: compaction対策）

**workflow 型**
- 呼び出すスキルを `dependencies:` で宣言する（Graph of Skills論文: 依存チェーンの明示的宣言）
- 探索・評価の結果を親contextに積み上げない。subagentに消化させてサマリだけ受け取る（DACS論文: context汚染の隔離）
- ループの終了条件を明示する（無限ループ防止）
- 内包するスキルが `mutating: true` なら `workflow` も `mutating: true` にする（エフェクト伝播）

### 境界例

| ケース | 型 | 理由 |
|---|---|---|
| コードレビュー結果を報告する | `reader` | 書き込みなし。判定は reader の出力形のひとつ |
| SKILL.md ファイルを生成する | `command` | ファイルを書く。単一フェーズ |
| テスト→修正→再テストをループする | `workflow` | コードを変更する。複数フェーズを合成 |
| 複数 agent を並列でレビューさせて統合する | `reader` | 書き込みなし。pure な合成は reader のまま |
| 外部 API を叩いて知識を返す | `reader` | 状態を変えない読み取り |
| 外部 API を叩いて状態を変える | `command` | 副作用あり。単一フェーズ |
| テストを実行して合否判定を返す | `reader` | Bash 実行は許可。ファイルは書かない |

---

## devkit との対応

devkit の既存コンポーネントを3型で分類すると：

| コンポーネント | 型 | 旧型 | 備考 |
|---|---|---|---|
| `coding-conventions-reader` skill | `reader` | `load` | 知識注入のみ |
| `pr-review-reader` skill | `reader` | `orchestrate` | 複数agentで読んで報告。書き込みなし |
| `security-gate-reader` skill | `reader` | `orchestrate` | 複数チェックを読んで報告。書き込みなし |
| `tech-debt-reader` skill | `reader` | `orchestrate` | 複数分析を読んで報告。書き込みなし |
| `deep-research-reader` skill | `reader` | `orchestrate` | 収集・検証・執筆を並列 agent に委譲。書き込みなし |
| `make-skill` skill | `command` | `do` | 成果物（SKILL.md）を生成 |
| `qa-workflow` skill | `workflow` | `orchestrate` | テスト→修正→再テストでコードを変更 |
| `implement-to-pr-workflow` skill | `workflow` | — | AC ゲート→実装→QA→レビュー→Live Proof→トレース→commit→PR→Decision Brief |
| `dev-loop-workflow` skill | `workflow` | — | 設計(dev-lead)→実装→commit→QA→レビュー→Live Proof→トレース→PR→受け入れテスト依頼 |
| `dev-lead` agent | `reader` | — | 設計・裁定・承認。コードは書かない |
| `dev-developer` agent | `command` | — | dev-lead 計画に従う実装者 |
| `dev-qa` agent | `reader` | — | 実機検証・差し戻し |
| `quality-reviewer` agent | `reader` | `evaluate` | 成果物評価専任 |
| `security-auditor` agent | `reader` | `evaluate` | セキュリティ評価専任 |
| `ux-reviewer` agent | `reader` | `evaluate` | UX評価専任 |
| `type-checker` agent | `reader` | `evaluate` | 型安全性評価専任 |
| `debt-analyzer` agent | `reader` | `evaluate` | 技術負債評価専任 |

旧4型（`load` / `do` / `evaluate` / `orchestrate`）から新3型（`reader` / `command` / `workflow`）への移行理由:
- `load` と `evaluate` と `orchestrate(mutating=false)` は関数型では全て「純粋関数」。3つを別の型に分けていたのは矛盾だった
- `orchestrate` が副作用ありとなしを混在させていた問題を、`reader`（pure）と `workflow`（effectful）の分離で解消

---

## skill 作成スキル（make-skill）の設計方針

この型システムを前提に、skill を0から作るための `command` 型スキル `make-skill` を devkit に追加する。

### ファイル構成

```
plugins/devkit/skills/make-skill/
├── SKILL.md
└── references/
    ├── type-system.md          # 3型の詳細定義・境界例・決定木
    ├── description-guide.md    # トリガー文の書き方
    └── security-checklist.md   # Skill固有の脅威タクソノミー（Skill-Inject論文ベース）
```

### フロー概要

| Step | 担当 | 手段 |
|---|---|---|
| 0 Skill適格性チェック | 親 | — |
| 1 gap の特定 | 親 | ユーザー対話 |
| 2 コードベース探索 + MECEチェック | **subagent** | `Agent(subagent_type="Explore")` |
| 3 型の決定 + 宣言 | 親 | 決定木を適用（2問で確定） |
| 4 SKILL.md 起草 | 親 | Write |
| 5 トリガー文最適化 | 親 | `references/description-guide.md` 参照 |
| 6 セキュリティ確認 | 親 | `references/security-checklist.md` 参照 |
| 7 セルフチェック | 親 | チェックリスト |
| 8 内部レビュー | **subagent** | reader スキルをfork実行（DACS論文: context汚染の隔離） |
| 9 ユーザーへの提示 | 親 | — |

---

## frontmatter 仕様

3型の情報を機械可読な frontmatter として標準化する。

### 型別 frontmatter テンプレート

**reader 型**
```yaml
---
name: xxx
type: reader
mutating: false
user-invocable: false
tools:
  - Read
triggers:
  - 「...」
---
```

判定結果を返す reader（旧 evaluate 相当）:
```yaml
---
name: xxx
type: reader
mutating: false
context: fork
user-invocable: false
tools:
  - Read
triggers:
  - 評価・採点・チェック系のトリガー
---
```

**command 型**
```yaml
---
name: xxx
type: command
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

**workflow 型**
```yaml
---
name: xxx
type: workflow
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

### フィールド定義

| フィールド | 型 | 必須 | 意味 |
|---|---|---|---|
| `type` | `reader\|command\|workflow` | ○ | 3型のいずれか |
| `mutating` | boolean | ○ | 副作用の有無。`reader` は必ず false、`command`/`workflow` は必ず true |
| `dependencies` | string[] | `workflow` 型で必須 | 呼び出すスキル名の一覧 |
| `writes_to` | string[] | `command`/`workflow` 型で推奨 | 書き込み先ディレクトリ。スコープの明示とセキュリティ審査に使う |
| `tools` | string[] | 推奨 | 使用するツール一覧。Skill-Inject脅威審査に使う |
| `triggers` | string[] | 推奨 | トリガーとなるユーザー発話 |
| `context` | `fork` | 判定を返す `reader` 型で推奨 | 別context実行の宣言 |
| `user-invocable` | boolean | ○ | Claude Code 公式フィールド。`/` メニュー表示の制御 |
| `argument-hint` | string | `user-invocable: true` かつ `$ARGUMENTS` を読む場合 | タブ補完時のヒント表示 |

### 型整合性ルール（lint で検出可能）

- `type: reader` かつ `mutating: true` → エラー
- `type: reader` かつ `tools` に `Write`/`Edit` → エラー
- `type: command` かつ `mutating: false` → エラー
- `type: workflow` かつ `dependencies:` なし → エラー
- `type: workflow` かつ `tools` に `Agent` なし → エラー
- `type: workflow` で内包スキルが `mutating: true` なのに自身が `mutating: false` → 警告

---

## 未解決事項

- `reader` 型スキルの `context: fork` の適用基準を統一定義するか（現状は推奨止まり）
- `make-skill` スキル自体の `reader` 型ペア（設計品質を評価する skill）をいつ作るか

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
