---
name: make-skill
type: command
mutating: true
user-invocable: true
argument-hint: "<スキル名または作りたいスキルの概要>"
writes_to:
  - plugins/devkit/skills/
  - .claude/skills/
  - /tmp/output/make-skill/
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

**Input:** スキル名または作りたいスキルの概要（自然言語）
**Output:** `plugins/devkit/skills/<name>/SKILL.md`（またはユーザー指定パス）に生成された SKILL.md ファイル

**禁止事項・停止条件（最重要）:**
- ユーザーの承認を得る前に `Write` でファイルを作成してはならない（Step 9 で確認）
- Step 0 の適格性チェックが1つでも未達なら即中断してユーザーに説明する
- 既存スキルと重複する場合は作成せず、既存スキルの利用を提案する

**型選択の根拠（command を選んだ理由）:**
`Agent` ツールを使うが、探索（Step 2）とレビュー（Step 8）はどちらも単一のファイル生成という主目的の補助であり、複数スキルを合成する workflow ではない。主成果物は1つの SKILL.md ファイルなので `command` が正しい型。

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
- 重複あり → 既存スキルを `workflow` 型で呼ぶ設計で済まないかをユーザーに確認
- 重複なし → Step 3 へ進む

---

## Step 3: 型の決定 + 宣言

`references/type-system.md` の決定木を適用して型を決定する:

```
Q1: ファイル書き込み・状態変更・外部サービスへの書き込みをするか？
  No  → reader 型
  Yes → Q2: 他のスキルを呼び出して複数フェーズを合成するか？
              No  → command 型
              Yes → workflow 型
```

**命名規則（型決定後に適用）:**
- `reader` 型 → `{topic}-reader` 形式（例: `pr-review-reader`）
- `workflow` 型 → `{topic}-workflow` 形式（例: `qa-workflow`）
- `command` 型 → 動詞で始まるケバブケース（例: `make-skill`, `generate-report`）

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
| `reader` | `type`, `mutating: false`, `user-invocable`（自動参照なら false） |
| `command` | `type`, `mutating: true`, `writes_to`, `tools`, `user-invocable: true`, `argument-hint` |
| `workflow` | `type`, `mutating: true`, `dependencies`, `tools`（Agent必須）, `user-invocable: true` |

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
- [ ] Step 2 のサブエージェントプロンプトにユーザー入力（スキル概要）を直接展開している（インジェクション経路）

---

## Step 7: セルフチェック

SKILL.md を起草した後、以下を機械的に確認する:

**frontmatter 整合性（lint ルール）:**
- [ ] `type: reader` かつ `mutating: true` → エラー（修正必須）
- [ ] `type: reader` かつ `tools` に `Write`/`Edit` → エラー（修正必須）
- [ ] `type: command` かつ `mutating: false` → エラー（修正必須）
- [ ] `type: workflow` かつ `dependencies:` なし → エラー（修正必須）
- [ ] `type: workflow` かつ `tools` に `Agent` なし → エラー（修正必須）

**命名規則チェック:**
- [ ] `type: reader` かつ `name` が `-reader` で終わらない → 警告（修正推奨）
- [ ] `type: workflow` かつ `name` が `-workflow` で終わらない → 警告（修正推奨）
- [ ] `type: command` かつ `name` が動詞で始まらない → 注意（手動確認）

**内容チェック:**
- [ ] 最重要ルールが冒頭30行以内にあるか
- [ ] Input / Output が観測可能な形で定義されているか（「完了しました」は Output ではない）
- [ ] ループがある場合、終了条件が明示されているか

---

## Step 8: 内部レビュー（subagent に委譲）

`reader` 型スキル（`context: fork`）を fork 実行してレビューさせる（DACS 論文: context 汚染の隔離）。

```
Agent(subagent_type="general-purpose") に以下を伝える:

あなたは skill 設計レビュアーです。以下の SKILL.md を ADR-0001 の基準でレビューしてください。

[SKILL.md の内容]

チェックリスト:
□ frontmatter の型整合性（lint ルール違反がないか）
□ 型の決定が ADR-0001 の決定木に従っているか
□ スキル名が命名規則に従っているか（reader: `-reader` 末尾 / workflow: `-workflow` 末尾 / command: 動詞始まり）
□ トリガー文が既存スキルと重複していないか
□ セキュリティリスクが未対処のまま残っていないか
□ 冒頭30行に最重要ルールが集約されているか

出力: 修正必須項目 / 修正推奨項目 / 承認
```

レビュアーが「修正必須」を返した場合は Step 4 に戻って修正する（最大1回）。
2回目のレビューでも「修正必須」が返った場合はユーザーに判断を委ねて停止する。

---

## Step 9: ユーザーへの提示

以下の構造でユーザーに提示する:

```markdown
## 作成するスキル: [スキル名]

**型:** [reader / command / workflow]
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

---

## Step 10: 成果物のアーカイブ保存（保存先をユーザーに確認）

スキルを正規の配置先（`plugins/devkit/skills/<name>/` または `.claude/skills/<name>/`）に
`Write` した後、**完成版の SKILL.md（と references/）をアーカイブ保存する**。

**保存先のデフォルトは `/tmp/output/make-skill/<name>/`**（スキル名でサブディレクトリを切る）だが、
**書き込む前に必ず `AskUserQuestion` で保存先を確認する**。デフォルトを推奨として提示し、変更・スキップも選べるようにする。

```
AskUserQuestion:
  question: "生成した成果物のアーカイブ保存先はどこにしますか？"
  options:
    - "/tmp/output/make-skill/<name>/ (デフォルト・推奨)"   # 推奨。スキル名でサブディレクトリを切る
    - "別のパスを指定する"                                  # ユーザーが任意パスを入力
    - "アーカイブしない（正規配置先のみ）"                    # コピーを作らない
```

確認で得た保存先 `<archive_dir>` に対して:

```bash
# <name> は作成したスキル名、<archive_dir> はユーザーが確認した保存先に置換する
mkdir -p "<archive_dir>"
cp "<配置先>/SKILL.md" "<archive_dir>/SKILL.md"
# references/ がある場合はそれもコピー
[ -d "<配置先>/references" ] && cp -R "<配置先>/references" "<archive_dir>/"
```

保存後、実際のアーカイブパスをユーザーに報告する（例: `アーカイブ: /tmp/output/make-skill/<name>/`）。
「アーカイブしない」が選ばれた場合はコピーをスキップし、正規配置先のみ報告する。

> 注意: アーカイブ先（`/tmp/output/` 等）はあくまで控え。**正規の配置先のコピーを消すとスキルは動かない**。
> `/tmp` は再起動で消える可能性があるため、アーカイブを唯一の保存先にしない。
