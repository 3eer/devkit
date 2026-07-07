---
description: Run security scan — secrets detection, SAST, and dependency vulnerabilities
argument-hint: "[path]"
allowed-tools: Bash, Read, Glob, Grep, Agent
---

# Scan — Security Scan

引数: `$ARGUMENTS` (省略時は `.`)

明示的なセキュリティスキャンを実行する（編集フックとは独立。SAST 含むフルスキャン）。

## 実行手順

`security-gate-reader` スキルに従い、以下を順次実行する:

1. **シークレット検出** — gitleaks (インストール済みなら) / regex fallback
2. **SAST** — semgrep `--config p/security-audit --metrics=off` (インストール済みなら)
3. **依存関係脆弱性** — trivy / npm audit / pip-audit (インストール済みなら)
4. **OPA ポリシー** — conftest `--combine` (インストール済みなら) で `policies/devkit.rego` を適用

`test-runner` エージェントを **`GATE_MODE=full`** で起動し、スキャン結果を解析・標準化レポートを生成する。

各ツールが未インストールの場合はスキップして続行する。

プロジェクトに pre-commit / CI 設定がない場合は、スキルの「プロジェクトへの展開」も案内する。
