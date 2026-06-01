# 3型システム — 詳細定義・決定木・境界例

出典: ADR-0001（docs/adr/0001-skill-type-system.md）

---

## 設計の起点

型の境界を「**副作用の有無**」と「**スキル合成の有無**」の2軸で定義する。

| | 副作用なし | 副作用あり |
|---|---|---|
| **合成なし（atomic）** | `reader` | `command` |
| **合成あり（composite）** | `reader`（吸収） | `workflow` |

副作用なしの合成（複数 reader を並列実行して統合するだけ）は `reader` に吸収する。
関数型では純粋関数の合成は純粋関数であり、独立した型を設ける必要がないため。

### 関数型プログラミングとの対応

| 型 | 関数型の概念 |
|---|---|
| `reader` | Reader モナド / 純粋関数 — 参照透過性が保証される |
| `command` | IO アクション — 副作用を型レベルで明示する最小単位 |
| `workflow` | Kleisli 合成 (`>>=`) — IO アクションを連鎖・合成する |

---

## 型の定義

| 型 | 入力 | 出力 | 副作用 | 他スキルを呼ぶか |
|---|---|---|---|---|
| `reader` | 0個以上 | 情報・知識・判定・レポート | **禁止** | 任意（pure な合成は reader のまま） |
| `command` | 1個以上 | 単一の成果物 | **あり** | 基本なし（合成の最小単位） |
| `workflow` | 1個以上 | 複数ステップの実行結果 | **あり** | **必須** |

---

## スキル命名規則

型ごとにスキル名のパターンを統一する。

| 型 | 命名パターン | 例 |
|---|---|---|
| `reader` | `{topic}-reader` | `pr-review-reader`, `tech-debt-reader` |
| `workflow` | `{topic}-workflow` | `qa-workflow` |
| `command` | 動詞で始まるケバブケース | `make-skill`, `generate-report` |

**理由**: 型名がスキル名に現れることで、スキル一覧を見ただけで副作用の有無と合成の有無が分かる。
`command` 型は動詞ベースにすることで「何をするか」が名前から明確になり、副作用の存在を動詞が暗示する。

**lint ルール**:
- `type: reader` かつ名前が `-reader` で終わらない → 警告
- `type: workflow` かつ名前が `-workflow` で終わらない → 警告
- `type: command` かつ名前が動詞で始まらない（英数字動詞の判断は難しいため手動確認） → 注意

---

## 決定木

```
Q1: ファイル書き込み・状態変更・外部サービスへの書き込みをするか？
    ├─ NO  → reader
    └─ YES
         Q2: 他のスキルを呼び出して複数フェーズを合成するか？
             ├─ NO  → command
             └─ YES → workflow
```

決定木の特徴:
- Q1 の判断基準は「副作用の有無」— 迷いがない
- Q2 の判断基準は「合成の有無」— 迷いがない
- 2問で確定する

---

## 各型の制約

### reader 型

- **ファイルシステムへの書き込み禁止**（`Write` / `Edit` は型違反）
- 外部サービスの状態を変えるコマンドの実行禁止
- 読み取り専用の Bash（`grep`, `git log`, `cat` 等）は許可
- 複数の reader スキルを並列実行して統合することは許可（その結果も reader）
- 評価・判定を返す場合は `context: fork` を推奨（SycEval 論文: 78.5% 迎合率対策）
- `user-invocable: false`（自動参照用途）と `true`（ユーザー直接起動）どちらも可

### command 型

- Input / Output を観測可能な形で定義する（「完了しました」は Output ではない）
- 副作用は単一のドメインに限定することを推奨（スキルの単一責任）
- 500行を超える場合は `references/` に降ろす（Lost in the Middle 論文: compaction 対策）
- 最重要ルールは冒頭30行に集約する

### workflow 型

- 呼び出すスキルを `dependencies:` で宣言する（Graph of Skills 論文: 依存チェーンの明示的宣言）
- 探索・評価の結果を親 context に積み上げない。subagent に消化させてサマリだけ受け取る（DACS 論文: context 汚染の隔離）
- ループの終了条件を明示する（無限ループ防止）
- 内包するスキルが `mutating: true` なら `workflow` も `mutating: true` にする（エフェクト伝播）

---

## frontmatter テンプレート

### reader 型

```yaml
---
name: xxx
type: reader
mutating: false
user-invocable: false   # 自動参照の場合。ユーザー直接起動なら true
tools:
  - Read
  - Glob
  - Grep
triggers:
  - 「...」
---
```

判定結果を返す reader（旧 evaluate 相当）は `context: fork` を追加する:

```yaml
---
name: xxx
type: reader
mutating: false
context: fork           # 別 context 実行。迎合率対策に推奨
user-invocable: false
tools:
  - Read
triggers:
  - 評価・採点・チェック系のトリガー
---
```

### command 型

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

### workflow 型

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

---

## フィールド定義

| フィールド | 型 | 必須 | 意味 |
|---|---|---|---|
| `type` | `reader\|command\|workflow` | ○ | 3型のいずれか |
| `mutating` | boolean | ○ | 副作用の有無。`reader` は必ず false、`command`/`workflow` は必ず true |
| `dependencies` | string[] | `workflow` 型で必須 | 呼び出すスキル名の一覧 |
| `writes_to` | string[] | `command`/`workflow` 型で推奨 | 書き込み先ディレクトリ |
| `tools` | string[] | 推奨 | 使用するツール一覧 |
| `triggers` | string[] | 推奨 | トリガーとなるユーザー発話 |
| `context` | `fork` | `reader` 型で判定を返す場合に推奨 | 別 context 実行の宣言 |
| `user-invocable` | boolean | ○ | `/` メニュー表示の制御 |
| `argument-hint` | string | `user-invocable: true` かつ `$ARGUMENTS` を読む場合 | タブ補完時のヒント |

---

## 型整合性ルール（lint で検出可能）

| ルール | 種別 |
|---|---|
| `type: reader` かつ `mutating: true` | エラー |
| `type: reader` かつ `tools` に `Write`/`Edit` | エラー |
| `type: command` かつ `mutating: false` | エラー |
| `type: workflow` かつ `dependencies:` なし | エラー |
| `type: workflow` かつ `tools` に `Agent` なし | エラー |
| `type: workflow` で内包スキルが `mutating: true` なのに自身が `mutating: false` | 警告 |

---

## 境界例

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

## devkit コンポーネントの型分類

| コンポーネント | 型 | 備考 |
|---|---|---|
| `coding-conventions-reader` skill | `reader` | 知識注入のみ |
| `pr-review-reader` skill | `reader` | 複数 agent で読んで報告。書き込みなし |
| `security-gate-reader` skill | `reader` | 複数チェックを読んで報告。書き込みなし |
| `tech-debt-reader` skill | `reader` | 複数分析を読んで報告。書き込みなし |
| `deep-research-reader` skill | `reader` | 収集・検証・執筆を並列 agent に委譲。書き込みなし |
| `make-skill` skill | `command` | 成果物（SKILL.md）を生成 |
| `qa-workflow` skill | `workflow` | テスト→修正→再テストでコードを変更 |
| `quality-reviewer` agent | `reader` | 成果物評価専任（旧 evaluate 相当） |
| `security-auditor` agent | `reader` | セキュリティ評価専任 |
| `ux-reviewer` agent | `reader` | UX 評価専任 |
| `type-checker` agent | `reader` | 型安全性評価専任 |
| `debt-analyzer` agent | `reader` | 技術負債評価専任 |
