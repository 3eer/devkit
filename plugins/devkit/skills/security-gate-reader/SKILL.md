---
name: security-gate-reader
type: reader
mutating: false
user-invocable: true
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
version: 1.0.0
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

### パッケージ評価基準 (npm)

| 指標 | 警戒閾値 |
|------|---------|
| 週間ダウンロード数 | 100万未満は注意 |
| 最終更新 | 2年以上前は注意 |
| メンテナ数 | 1人のみはバスファクターリスク |
| ライセンス | GPL系はビジネス利用に注意 |

## シークレット・認証情報の取り扱い

### 禁止パターン (pre-writeフックが自動検出)

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
- `.env` → コミット禁止 (`.gitignore` に追加)
- `.env.example` → コミット可 (プレースホルダーのみ)
- `.env.local` → コミット禁止

## SAST スキャン (Semgrep)

```bash
# Semgrep がインストール済みの場合のみ実行
if command -v semgrep >/dev/null 2>&1; then
  semgrep scan --config auto --severity ERROR --quiet .
fi
```

`post-edit-semgrep.sh` フックが Edit/Write 後に自動実行する。
Critical severity のみブロック対象。Warning は情報提供のみ。

## OPA/Conftest によるポリシーチェック

```bash
# Conftest がインストール済みの場合のみ実行
if command -v conftest >/dev/null 2>&1; then
  conftest test --policy "${CLAUDE_PLUGIN_ROOT}/policies/devkit.rego" .
fi
```

`policies/devkit.rego` がチェックするポリシー:
- 未承認パッケージの使用禁止
- 機密パスへの変更の警告
- `.env` ファイルのコミット禁止

## インシデント対応フロー

シークレットが検出された場合 (pre-write フックが停止した場合):

1. **コミット前に検出できた場合:** `.env.example` にプレースホルダーとして記録
2. **コミット済みの可能性がある場合:** `git log --all -S "検出文字列"` で確認
3. **リモートにpush済みの場合:**
   - 即座にキーをローテートする (GitHub Secrets / Vault 等で新しいキーを発行)
   - `git filter-branch` または `git filter-repo` で履歴から削除
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

## test-runner エージェントとの連携

詳細なセキュリティスキャン結果の解析が必要な場合は `test-runner` エージェントを起動する。
`test-runner` は gitleaks / semgrep / trivy の結果を統合して標準化レポートを生成する。
