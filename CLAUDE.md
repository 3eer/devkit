# devkit — Claude Code プラグイン開発リポジトリ

このリポジトリは Claude Code マーケットプレイス `3eer` を提供する。
`origin`: `git@github.com:3eer/devkit.git`

## ⚠️ 最重要: 変更したら必ずバージョンを上げる

skill / agent / command / hook など **プラグインの中身を変更したら、
必ず `.claude-plugin/marketplace.json` の該当プラグインの `version` を上げる**こと。

**理由**: Claude Code はインストール済みプラグインを `version` 番号ごとに
`~/.claude/plugins/cache/3eer/devkit/<version>/` へ展開してキャッシュする。
version を据え置いたまま中身だけ変えても、Claude Code は「同じバージョン＝再展開不要」と
判断して古い cache を使い続けるため、skill の追加・リネームなどの変更がいくら update / reload
しても反映されない。reload は設定の再読込であって cache の再展開はしない。

**ルール**:
- 機能追加（skill 追加など）→ MINOR を上げる (例 2.0.x → 2.1.0)
- 修正・微調整 → PATCH を上げる (例 2.0.0 → 2.0.1)
- バージョンを上げ忘れると、利用者側に変更が一切届かない

変更 → commit の前に `marketplace.json` の `version` を更新したか必ず確認する。

## 反映の流れ

1. 中身を変更
2. `.claude-plugin/marketplace.json` の `version` を上げる
3. commit & push
4. 利用者側で `/plugin` から update（新バージョン番号で新しい cache へ展開される）
