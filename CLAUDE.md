# devkit — Claude Code プラグイン開発リポジトリ

このリポジトリは Claude Code マーケットプレイス `3eer` を提供する。
`origin`: `git@github.com:3eer/devkit.git`

## ⚠️ 最重要: 変更したら必ずバージョンを上げる（2ファイル同時）

skill / agent / command / hook など **プラグインの中身を変更したら、
必ず version を上げる**こと。ただし version を持つファイルは **2つある**:

1. `.claude-plugin/marketplace.json` の該当プラグインの `version`（SSoT＝真実の源）
2. `.claude-plugin/plugin.json` の `version`

**この2つは常に一致させる。** 片方だけ上げると CI が落ちる（下記）。

**理由**: Claude Code はインストール済みプラグインを `version` 番号ごとに
`~/.claude/plugins/cache/3eer/devkit/<version>/` へ展開してキャッシュする。
version を据え置いたまま中身だけ変えても、Claude Code は「同じバージョン＝再展開不要」と
判断して古い cache を使い続けるため、skill の追加・リネームなどの変更がいくら update / reload
しても反映されない。reload は設定の再読込であって cache の再展開はしない。

**ルール**:
- 機能追加（skill 追加など）→ MINOR を上げる (例 2.0.x → 2.1.0)
- 修正・微調整 → PATCH を上げる (例 2.0.0 → 2.0.1)
- 破壊的変更（skill リネーム・呼び出し名変更など）→ MINOR を上げる
- バージョンを上げ忘れると、利用者側に変更が一切届かない

### ⛔ CI ゲート（`scripts/check-plugin-version.sh`）

CI は `marketplace.json`（SSoT）と `plugin.json` の version が **一致しているか**を検証する。
不一致だと `version mismatch` で **PR がブロックされる**。
→ **version を上げるときは必ず両方を同じ値にする。** push 前にローカルで
`bash scripts/check-plugin-version.sh` を実行して緑を確認するのが安全。

変更 → commit の前に、`marketplace.json` と `plugin.json` の `version` を
**両方**更新したか必ず確認する。

## 反映の流れ

1. 中身を変更
2. `.claude-plugin/marketplace.json` と `.claude-plugin/plugin.json` の `version` を
   **両方同じ値に**上げる
3. `bash scripts/check-plugin-version.sh` で一致を確認（CI と同じチェック）
4. commit & push
5. 利用者側で `/plugin` から update（新バージョン番号で新しい cache へ展開される）
