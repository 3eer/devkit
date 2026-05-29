---
name: qa-loop
type: orchestrate
mutating: true
user-invocable: true
argument-hint: "[テストコマンド or ファイルパス]"
dependencies:
  - test-runner
writes_to:
  - .
description: |
  Use this skill when the user asks to run tests, fix failing tests, set up a test loop,
  do test-driven development, or when Claude has just written code and should verify it works.
  Triggers on: "run the tests", "fix the tests", "TDD", "make tests pass", "autonomous testing",
  "QA", "test loop", テストを実行, テストを直して, テストが通るまで, 自律テスト, QA環境.
version: 1.0.0
tools:
  - Read
  - Bash
  - Glob
  - Grep
  - Edit
  - Write
  - Agent
triggers:
  - "run the tests"
  - "fix the tests"
  - "TDD"
  - "make tests pass"
  - "autonomous testing"
  - "test loop"
  - テストを実行
  - テストを直して
  - テストが通るまで
  - 自律テスト
---

# Autonomous QA Loop

## 原則

- **最大イテレーション:** 5回
- **停止条件:** 全テスト通過 / 同じエラーが2回連続で発生 / 最大イテレーション超過
- **禁止:** 失敗テストを削除・スキップで「通す」ことは禁止

## Step 1: テストコマンドを特定する

以下の優先順位で自動検出する:

```bash
# package.json の scripts.test を確認
python3 -c "
import json
with open('package.json') as f:
    d = json.load(f)
print(d.get('scripts', {}).get('test', ''))
" 2>/dev/null

# フレームワーク設定ファイルを検出
ls pytest.ini pyproject.toml setup.cfg Makefile go.mod Cargo.toml 2>/dev/null
```

| 検出パターン | 実行コマンド |
|-------------|-------------|
| `package.json` の `test` スクリプト | `npm test` / `pnpm test` / `yarn test` |
| `pytest.ini` / `pyproject.toml[tool.pytest]` | `python -m pytest -x --tb=short` |
| `go.mod` | `go test ./... -count=1` |
| `Cargo.toml` | `cargo test` |
| `Makefile` に `test` ターゲット | `make test` |

## Step 2: テストを実行して出力を解析する

```bash
# タイムアウト付きで実行 (デフォルト120秒)
# 失敗したテスト名・エラーメッセージ・スタックトレースを抽出
```

出力から抽出する情報:
- 失敗したテスト名
- エラーメッセージ
- 期待値 vs 実際値の差分

## Step 3: 失敗パターンを分類して修正する

| パターン | 推定原因 | 対応 |
|---------|---------|------|
| `AssertionError` / `expect(...).toBe` | ロジックの誤り | 実装コードを修正 |
| `TypeError` / `AttributeError` | 型の不一致 | 型定義・引数を修正 |
| `ModuleNotFoundError` / `Cannot find module` | インポートパス誤り | パスを確認・修正 |
| `ECONNREFUSED` / `ConnectionError` | 外部依存 (DB/API) | モックを確認 or 環境確認 |
| タイムアウト | 非同期処理の問題 | await/async を確認 |

### 修正の優先順位
1. コンパイル・インポートエラー (テスト実行不可)
2. 型エラー
3. ロジックエラー (期待値不一致)
4. 環境依存エラー

## Step 4: ループを回す

```
イテレーション 1:
  → テスト実行 → N件失敗 → 根本原因特定 → 修正
イテレーション 2:
  → テスト実行 → M件失敗 (M < N → 進捗あり, M = N → 別原因を探す)
  ...
全テスト通過 OR 最大5回 → 停止してレポート生成
```

### 停止ルール
- **同じエラーが2回連続:** 自動修正の限界。人間に報告して停止する
- **5イテレーション完了:** 残存問題を報告して停止する

## Step 5: 完了レポートを生成する

```markdown
## QA Loop 完了レポート

**結果:** [全テスト通過 / X件残存 / 手動確認が必要]
**イテレーション数:** N回
**修正したファイル:** [リスト]

### 残存する問題 (あれば)
- [テスト名]: [エラー内容] → [推定原因と推奨対応]

### 推奨次ステップ
- [ ] ...
```
