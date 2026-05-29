# トリガー文・description の書き方ガイド

---

## 目的

`triggers:` と `description` は Claude がスキルを自動選択する際の唯一の判断材料になる。
曖昧なトリガーは誤起動を招き、狭すぎるトリガーは必要なときに起動されない。

---

## triggers: の書き方

### 原則

1. **動詞フレーズを含める** — 名詞だけのトリガーは他の文脈と衝突しやすい
2. **日本語と英語の両方を書く** — どちらの言語で話しかけられても起動するように
3. **ユーザーが実際に言いそうな言葉を使う** — 技術用語より口語表現を優先
4. **4〜8 語程度の短いフレーズ** — 長すぎると部分一致が難しくなる

### 良い例 / 悪い例

| NG | OK | 理由 |
|---|---|---|
| `"review"` | `"review this PR"` | 動詞フレーズにする |
| `"security"` | `"is this secure"`, `"scan for vulnerabilities"` | 文脈を含める |
| `"コード規約"` | `"コーディング規約に従って"`, `"コードを書く"` | 口語表現にする |
| `"テスト"` | `"テストが通るまで直して"`, `"テストを実行して"` | 操作の意図を含める |

### 既存スキルとの重複を避ける

triggers は devkit の全スキルを通じてユニークであることが望ましい。
Step 2 の MECE チェックで重複を確認すること。

重複が避けられない場合（例: 「セキュリティチェック」が複数スキルに関係する場合）は、
より具体的なフレーズに絞って区別する。

---

## description: の書き方

### 構造

```
[いつ使うか（条件）]. [何をするか（動作の概要）]. Triggers on: [トリガーフレーズのサンプル], [日本語フレーズ].
```

### 長さ

- 3〜5行（約100〜200文字）
- description は `allowed-tools` とともに Claude のスキル選択に使われる
- 長すぎると compaction でカットされる（Lost in the Middle 論文）

### 良い例

```yaml
description: |
  Use this skill when reviewing a pull request, self-reviewing before push, or scanning
  existing code for quality. Orchestrates parallel specialist agents based on risk level.
  Triggers on: "review this PR", "check the diff", "is this safe to merge", "before I push",
  PRのレビュー, マージ前確認, push前確認, 変更のリスク評価.
```

### 悪い例

```yaml
# 何をするかが不明
description: "PR review skill"

# 条件が曖昧
description: "Use when you want to review code"

# 長すぎる（compaction でカット対象）
description: |
  This skill performs comprehensive code review by orchestrating multiple specialist agents
  including quality-reviewer, security-auditor, type-checker, debt-analyzer, and ux-reviewer
  in parallel based on a risk scoring algorithm that considers file count, sensitive paths,
  breaking changes, and test coverage. It generates a structured report with CRITICAL, HIGH,
  MEDIUM, LOW categorized findings...
```

---

## argument-hint: の書き方

`user-invocable: true` かつ `$ARGUMENTS` を使うスキルは `argument-hint` を書く。

```yaml
# パターン1: 必須引数
argument-hint: "<PR番号 or ブランチ名>"

# パターン2: 省略可能な引数
argument-hint: "[対象パス]"

# パターン3: オプションフラグあり
argument-hint: "<調査トピック> [--mode quick|standard|deep]"

# パターン4: 複数の使い方
argument-hint: "[PR番号 or ブランチ名 or --base <branch>]"
```

`<>` は必須、`[]` は省略可能の慣例に従う。

---

## チェックリスト

SKILL.md を起草したら、以下を確認する:

- [ ] `triggers:` に日本語と英語の両方があるか
- [ ] 各トリガーが動詞フレーズを含んでいるか（名詞だけでない）
- [ ] `description` が3〜5行に収まっているか
- [ ] `description` に「いつ使うか」が明記されているか
- [ ] `user-invocable: true` の場合、`argument-hint` があるか
- [ ] 既存スキルのトリガーと明確に区別できるか（MECE チェック結果を参照）
