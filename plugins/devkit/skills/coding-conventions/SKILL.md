---
name: coding-conventions
description: |
  Use this skill when starting a new feature, creating files, asking about code style or
  architecture patterns, or when Claude is about to write substantial code. Also activates
  when the user says "follow our conventions", "write idiomatic code", "check the style",
  "make it consistent", or when working in a project that has CLAUDE.md or a linter config.
  Ensures PostToolUse hooks run lint/format/typecheck after every edit.
  コーディング規約, アーキテクチャ方針, スタイルガイド, コードを書く, 実装する.
version: 1.0.0
allowed-tools: Read, Glob, Grep, Bash
---

# Coding Conventions & Output Quality

## 起動時の必須アクション (並行実行)

スキル起動時に以下を並行して実行してプロジェクト固有の規約を把握する:

1. `Read ./CLAUDE.md` — プロジェクト固有ルール (存在すれば)
2. `Glob ["**/.eslintrc*", "**/eslint.config.*", "**/biome.json"]` — JS/TS linter設定
3. `Glob ["**/pyproject.toml", "**/ruff.toml", "**/.ruff.toml"]` — Python設定
4. `Glob ["**/.golangci.yml", "**/.golangci.yaml"]` — Go設定

## コードを書く前のチェックリスト

- [ ] 同じ機能の既存実装を `Grep` で検索して重複を避ける
- [ ] 隣接ファイルを `Read` して命名・スタイルのパターンを確認する
- [ ] テストが存在するか確認し、ロジック変更時はテストも更新する
- [ ] 新しい外部ライブラリは `security-gate` スキルで評価する

## 普遍的な原則

### 命名
- 意図が明確な完全な単語を使う (略語より `calculateTotalPrice` > `calcTotPrc`)
- 既存のファイルの命名パターンに必ず合わせる
- ブール値は `is`, `has`, `can`, `should` で始める

### コード構造
- 関数は単一責任 — 1関数が1つのことをする
- 深いネスト (4層以上) はアーリーリターンで解消する
- コメントは WHY を書く。WHAT はコード自体が語る

### エラーハンドリング
- サイレントに失敗させない (`catch` して何もしない = 禁止)
- エラーは呼び出し元に伝播させるか、ログ + ユーザー通知を行う
- ユーザー入力・外部API・ファイルI/O の境界でのみバリデーションする

## 言語別チェックリスト

### TypeScript / JavaScript
- `any` 型を使う場合は必ず理由コメントを付ける
- `console.log` をデバッグ用に残さない (logger を使う)
- 非同期エラーは `try/catch` またはチェーンで必ず処理する
- `interface` > `type` (拡張可能性のため)

### Python
- 型ヒントは必須 (Python 3.10+ では `X | Y` 記法)
- `# type: ignore` は理由コメントとセット
- `except Exception` より具体的な例外クラスを先に捕捉する

### Go
- エラーを必ずチェックする (`_, _ = ...` は禁止)
- `defer cancel()` を忘れない (goroutineリーク防止)
- `context.Context` は第1引数として受け渡す

### Rust
- `unwrap()` / `expect()` はテストコードのみ許可
- プロダクションでは `?` 演算子か適切なエラー型を使う

## PostToolUse フック (自動実行)

このスキルをサポートする `post-edit-quality-check.sh` フックが Edit/Write 後に自動で
linter・typecheck を実行する。フックがエラーを報告したら **次のファイルを修正する前に** 解消する。

修正の優先順位:
1. **型エラー** — コンパイルを壊す → 最優先
2. **Lint エラー** — ルール違反 → コミット前に修正
3. **フォーマット** — 指示されたコマンドで修正

## アーキテクチャ判断の原則

| 状況 | 推奨アクション |
|------|----------------|
| 新しい抽象化が必要か迷う | 同じパターンが3回以上出現したら検討 |
| 外部ライブラリを追加 | `security-gate` スキルを通す |
| DBスキーマ変更 | マイグレーションファイルを必ず作成 |
| API追加 | 型定義・OpenAPIを先に書いてから実装 |
| 設定ファイル変更 | `pr-review` スキルで高リスク判定 |
