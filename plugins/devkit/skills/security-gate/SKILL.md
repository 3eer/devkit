---
name: security-gate
argument-hint: "[スキャン対象パス or パッケージ名]"
dependencies:
  - security-auditor
  - test-runner
description: |
  Use this skill when adding dependencies, writing authentication or authorization code,
  handling user input, creating API endpoints, working with environment variables or secrets,
  reviewing infrastructure code, or when the user asks about security. Triggers on:
  "add this package", "install dependency", "handle auth", "is this secure",
  "scan for vulnerabilities", "check secrets", "security review",
  依存関係を追加, セキュリティチェック, 脆弱性スキャン, 認証, 認可, シークレット.
version: 1.1.0
tools:
  - Read
  - Bash
  - Glob
  - Grep
  - Agent
triggers:
  - "add this package"
  - "install dependency"
  - "handle auth"
  - "is this secure"
  - "scan for vulnerabilities"
  - "check secrets"
  - "security review"
  - 依存関係を追加
  - セキュリティチェック
  - 脆弱性スキャン
  - 認証
  - 認可
  - シークレット
---

# Security Gate

## 防御の3層

| 層 | 仕組み | 役割 |
|----|--------|------|
| セッション内フック | pre-read / pre-write / post-edit-quality | 早期検知・UX（迂回可能） |
| pre-commit | `templates/pre-commit-config.yaml` | コミット境界の検査 |
| CI | `templates/github-workflows-devkit-security.yml` | push/PR 境界の保証 |

フックだけでは Bash 経由の書き込み等を塞げない。**pre-commit と CI の展開は devkit の責務**。

## プロジェクトへの展開

プロジェクトに以下がない場合、雛形をコピーして案内する:

```bash
# pre-commit（gitleaks + semgrep + private key 検出）
cp "${CLAUDE_PLUGIN_ROOT}/templates/pre-commit-config.yaml" .pre-commit-config.yaml
pip install pre-commit && pre-commit install

# GitHub Actions（gitleaks + semgrep + trivy）
mkdir -p .github/workflows
cp "${CLAUDE_PLUGIN_ROOT}/templates/github-workflows-devkit-security.yml" .github/workflows/devkit-security.yml
```

`.gitignore` に `.env` / `.env.local` が無ければ追加する。

## 依存関係を追加する前のチェック

新しいパッケージを追加する前に以下を確認する:

```bash
# npm audit (Node.js)
npm audit --audit-level=high 2>/dev/null || true

# Trivy による脆弱性スキャン (インストール済みの場合)
if command -v trivy >/dev/null 2>&1; then
  trivy fs --scanners vuln --severity HIGH,CRITICAL .
fi

# pip-audit (Python, インストール済みの場合)
if command -v pip-audit >/dev/null 2>&1; then
  pip-audit
fi
```

追加の推奨:
- lockfile を固定する
- インストールスクリプトを無効化する (`npm ci --ignore-scripts`, pnpm `onlyBuiltDependencies`)
- 公開直後のバージョンを避ける (pnpm `minimumReleaseAge` 等)

### パッケージ評価基準 (npm)

| 指標 | 警戒閾値 |
|------|---------|
| 週間ダウンロード数 | 100万未満は注意 |
| 最終更新 | 2年以上前は注意 |
| メンテナ数 | 1人のみはバスファクターリスク |
| ライセンス | GPL系はビジネス利用に注意 |

## シークレット・認証情報の取り扱い

### フックによる保護

| フック | 対象 | 動作 |
|--------|------|------|
| `pre-read-env-block.sh` | Read | `.env` / `.env.local` 等の**読み取りを拒否** |
| `pre-write-secrets-check.sh` | Write/Edit | `.env` への書き込み・ハードコードシークレットを拒否 |
| `post-edit-quality-check.sh` | Write/Edit 後 | lint / 型チェックのみ（軽量） |

### 禁止パターン (pre-write フックが自動検出)

```typescript
// NG: ハードコードされたAPIキー
const apiKey = "sk-xxxxxxxxxxxx";

// OK: 環境変数から読み込む
const apiKey = process.env.API_KEY;
if (!apiKey) throw new Error("API_KEY is required");
```

```python
# NG
password = "hardcoded_password"

# OK
password = os.environ["DB_PASSWORD"]
```

### .env ファイルの取り扱い
- `.env` / `.env.local` → **Read も Write も禁止**（フック）。コミット禁止 (`.gitignore` に追加)
- `.env.example` → コミット可 (プレースホルダーのみ)。Read 可
- 必要な変数名は `.env.example` から確認する。実値はユーザーに確認

## SAST スキャン (Semgrep)

**SAST は `/gate full`・`/scan`・pre-commit/CI で実行する。編集後フックでは走らない。**

```bash
# Semgrep がインストール済みの場合のみ実行
# --config auto は使わない（メトリクス送信・遅延を避ける）
if command -v semgrep >/dev/null 2>&1; then
  semgrep scan --config p/security-audit --severity ERROR --metrics=off --quiet .
fi
```

## OPA/Conftest によるポリシーチェック

```bash
# Conftest がインストール済みの場合のみ実行（--combine 必須）
if command -v conftest >/dev/null 2>&1; then
  conftest test --combine --policy "${CLAUDE_PLUGIN_ROOT}/policies/devkit.rego" .
fi
```

`policies/devkit.rego` がチェックするポリシー:
- 未承認パッケージの使用禁止
- 機密パスへの変更の警告
- `.env` ファイルのコミット禁止

## インシデント対応フロー

シークレットが検出された場合 (pre-write フックが拒否した場合):

1. **コミット前に検出できた場合:** `.env.example` にプレースホルダーとして記録
2. **コミット済みの可能性がある場合:** `git log --all -S "検出文字列"` で確認
3. **リモートにpush済みの場合:**
   - 即座にキーをローテートする (GitHub Secrets / Vault 等で新しいキーを発行)
   - `git filter-repo` で履歴から削除
   - チームに通知する

## OWASP Top 10 の主要チェック

コード生成時に以下を意識して確認する:

| 脆弱性 | チェック観点 |
|--------|------------|
| A01 アクセス制御の不備 | 認証チェックがすべてのエンドポイントに存在するか |
| A02 暗号化の失敗 | 機密データが平文で保存・転送されていないか |
| A03 インジェクション | ユーザー入力がSQLやシェルコマンドに渡されていないか |
| A05 セキュリティの設定ミス | デフォルト認証情報・デバッグモードが本番で有効になっていないか |
| A09 セキュリティロギングの不備 | 認証失敗・異常アクセスがログに記録されるか |

## test-runner / security-auditor との連携

| 用途 | 起動先 | モード |
|------|--------|--------|
| `/gate quick` | test-runner | `GATE_MODE=quick` — gitleaks + trivy。semgrep なし |
| `/gate full` | test-runner | `GATE_MODE=full` — + semgrep SAST |
| `/scan` | test-runner | `GATE_MODE=full` |
| PR レビュー (Red Team) | security-auditor | diff ベースの悪用シナリオ分析 |
