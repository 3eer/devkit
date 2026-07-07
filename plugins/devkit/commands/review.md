---
description: Review code — self-review before push, GitHub PR review, or bulk quality audit
argument-hint: "[PR-number | branch-name | --base <branch> | --audit path]"
allowed-tools: Read, Bash, Glob, Grep, Task, Skill
---

# Review — マルチエージェント並列コードレビュー

引数: `$ARGUMENTS`

`pr-review-reader` スキルに従い、40観点の専門エージェント並列レビューを実行する。
オーケストレーション・リスクスコア・レポート形式の正典はスキル側のみ（このコマンドに重複ロジックを書かない）。

## 実行

1. **`pr-review-reader` スキル**（`plugins/devkit/skills/pr-review-reader/SKILL.md`）を読む
2. スキルの **Step 0 から順に**実行する
3. 引数 `$ARGUMENTS` をレビュー対象としてスキルに渡す

## 引数パターン

| 引数 | ユースケース |
|------|-------------|
| なし | push 前の自己レビュー（ベースブランチ自動検出） |
| `--base <branch>` | ベースブランチ指定 |
| `123` (数値) | GitHub PR レビュー |
| `feature/xxx` | ブランチレビュー |
| `--audit [path]` | 品質監査（path 省略時 `.`） |

## 使用例

```bash
/review
/review --base staging
/review 142
/review feature/add-payment
/review feature/add-payment --base main
/review --audit src/api
```
