---
name: make-skill
type: do
mutating: true
user-invocable: true
argument-hint: "<スキル名または作りたいスキルの概要>"
writes_to:
  - plugins/devkit/skills/
  - .claude/skills/
tools:
  - Read
  - Write
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
triggers:
  - "make a skill"
  - "create a skill"
  - "新しいスキルを作って"
  - "スキルを作成して"
  - "make-skill"
  - "スキルを追加して"
---

# make-skill — Skill 作成ガイド

このスキルは新しい skill を0から作成する `do` 型スキルです。
作成対象の型決定・MECEチェック・セキュリティ確認まで一貫して行います。

詳細な型定義・決定木・セキュリティチェックリストは `references/` を参照してください。

---

## Step 0: Skill 適格性チェック

以下の条件をすべて満たす場合のみ続行する。1つでも満たさない場合は中断してユーザーに説明する。

- [ ] 繰り返し使う操作である（1回限りのタスクはスキルにしない）
- [ ] Claude Code のコンテキスト内で完結できる（外部サービスの手動操作を含まない）
- [ ] 既存スキルの組み合わせでは実現できない（Step 2 で確認）

---

## Step 1: gap の特定

ユーザーから以下を引き出す（AskUserQuestion で1回にまとめて聞く）:

- **何をしたいか**: 解決したい問題・自動化したい操作
- **入力と出力**: 何を渡して何が返ってくるほしいか
- **頻度**: どのくらいの頻度で使うか
- **他スキルとの関係**: 既存のスキルと組み合わせるか、独立して使うか

既に十分な情報が会話から取れている場合はスキップしてよい。

---

## Step 2: コードベース探索 + MECE チェック（subagent に委譲）

`Agent(subagent_type="Explore")` で以下を調べさせ、**200語以内のサマリ**で返させる:

```
以下のディレクトリにある全スキルの `triggers:` と `description` を走査してください。

走査対象:
- ~/.claude/skills/
- ~/.claude/plugins/*/skills/
- .claude/skills/（存在すれば）
- plugins/devkit/skills/

確認内容:
1. 今回作ろうとしているスキル「[スキル概要]」と意図が重複するスキルがないか
2. 類似スキルが見つかった場合はスキル名と重複理由を報告する
3. 走査できなかったディレクトリは「存在しない」と明記する

200語以内で報告してください。
```

**判定:**
- 重複あり → 既存スキルを `orchestrate` 型で呼ぶ設計で済まないかをユーザーに確認
- 重複なし → Step 3 へ進む

---

## Step 3: 型の決定 + 宣言

`references/type-system.md` の決定木を適用して型を決定する:

```
他のスキルを呼び出して組み合わせるか？
  Yes → orchestrate 型
  No  → 何を出力するか？
          コンテキスト提供（出力なし）→ load 型
          判定JSON のみ             → evaluate 型
          成果物（ファイル・変換結果）→ do 型
```

型を決定したら、その根拠をユーザーに1文で説明する。

---

## Step 4: SKILL.md 起草

ADR-0001 の frontmatter テンプレートを使って SKILL.md を起草する。

**必須ルール（Lost in the Middle 論文: 先頭30行に集約）:**
- frontmatter + 最重要ルール（禁止事項・停止条件）を冒頭30行以内に収める
- 500行を超える詳細内容は `references/` に降ろす

**型別の必須フィールド:**

| 型 | 必須フィールド |
|---|---|
| `load` | `type`, `mutating: false`, `user-invocable: false` |
| `do` | `type`, `mutating`, `writes_to`, `tools`, `user-invocable: true`, `argument-hint` |
| `evaluate` | `type`, `mutating: false`, `context: fork`, `tools`（Write禁止）, `user-invocable: false` |
| `orchestrate` | `type`, `mutating`, `dependencies`, `tools`（Agent必須）, `user-invocable: true` |

---

## Step 5: トリガー文最適化

`references/description-guide.md` を参照して `triggers:` と `description` を最適化する。

チェック:
- [ ] トリガーに日本語と英語の両方を含んでいるか
- [ ] 「〜してください」「〜を実行」などの動詞フレーズを含んでいるか
- [ ] 既存スキルのトリガーと重複していないか（Step 2 の結果を参照）

---

## Step 6: セキュリティ確認

`references/security-checklist.md` のチェックリストを適用する。

**高リスク項目（これが1つでも該当する場合はユーザーに確認する）:**
- [ ] `Write` / `Edit` ツールを使う（書き込み先の `writes_to` は限定されているか）
- [ ] `Bash` でシェルコマンドを実行する（ユーザー入力をシェルに渡すか）
- [ ] 外部 URL・API を呼び出す（WebFetch / WebSearch）
- [ ] 他スキルを呼び出す（呼び出し先スキルの権限が過剰でないか）
- [ ] SKILL.md 自体にユーザー入力を展開する（プロンプトインジェクション面）

---

## Step 7: セルフチェック

SKILL.md を起草した後、以下を機械的に確認する:

**frontmatter 整合性（lint ルール）:**
- [ ] `type: load` かつ `mutating: true` → エラー（修正必須）
- [ ] `type: evaluate` かつ `tools` に `Write`/`Edit` → エラー（修正必須）
- [ ] `type: evaluate` かつ `context: fork` なし → エラー（修正必須）
- [ ] `type: orchestrate` かつ `dependencies:` なし → エラー（修正必須）
- [ ] `mutating` の値が型から導出される値と不一致 → 警告

**内容チェック:**
- [ ] 最重要ルールが冒頭30行以内にあるか
- [ ] Input / Output が観測可能な形で定義されているか（「完了しました」は Output ではない）
- [ ] ループがある場合、終了条件が明示されているか

---

## Step 8: 内部レビュー（subagent に委譲）

`evaluate` 型スキルを fork 実行してレビューさせる（DACS 論文: context 汚染の隔離）。

```
Agent(subagent_type="general-purpose") に以下を伝える:

あなたは skill 設計レビュアーです。以下の SKILL.md を ADR-0001 の基準でレビューしてください。

[SKILL.md の内容]

チェックリスト:
□ frontmatter の型整合性（lint ルール違反がないか）
□ 型の決定が ADR-0001 の決定木に従っているか
□ トリガー文が既存スキルと重複していないか
□ セキュリティリスクが未対処のまま残っていないか
□ 冒頭30行に最重要ルールが集約されているか

出力: 修正必須項目 / 修正推奨項目 / 承認
```

レビュアーが「修正必須」を返した場合は Step 4 に戻って修正する（最大1回）。

---

## Step 9: ユーザーへの提示

以下の構造でユーザーに提示する:

```markdown
## 作成するスキル: [スキル名]

**型:** [load / do / evaluate / orchestrate]
**理由:** [決定木の適用結果を1文で]
**配置先:** [plugins/devkit/skills/<name>/SKILL.md]

### SKILL.md プレビュー
[SKILL.md の内容]

### セキュリティメモ
[高リスク項目があれば記載。なければ省略]

---
このまま作成してよいですか？ファイルを書き込む前に確認します。
```

ユーザーの承認を得てから `Write` でファイルを作成する。
