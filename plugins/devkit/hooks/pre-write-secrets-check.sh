#!/usr/bin/env bash
# devkit: Pre-Write/Edit secret detection hook
# Fires before Write / Edit / MultiEdit tool calls.
# Blocks on detected secrets; always exits 0 to avoid crashing Claude Code.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/env-path-check.sh
source "${SCRIPT_DIR}/lib/env-path-check.sh"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)"

case "$TOOL_NAME" in
  Write|Edit|MultiEdit) ;;
  *) devkit_hook_allow; exit 0 ;;
esac

FILE_PATH="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('file_path', ti.get('path', '')))
" 2>/dev/null || true)"

if devkit_is_blocked_env_path "$FILE_PATH"; then
  devkit_hook_deny "[devkit] .env ファイルへの直接書き込みを検出しました。このファイルはコミットされる危険があります。.env.example を代わりに使用し、実際の値は環境変数として設定してください。意図的に書き込む場合はユーザーに「.envに書いてOK」と伝えてください。"
  exit 0
fi

CONTENT="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
tool = d.get('tool_name', '')
if tool == 'Write':
    print(ti.get('content', ''))
elif tool == 'Edit':
    print(ti.get('new_string', ''))
elif tool == 'MultiEdit':
    edits = ti.get('edits', [])
    print('\n'.join(e.get('new_string', '') for e in edits))
" 2>/dev/null || true)"

if [ -z "$CONTENT" ]; then
  devkit_hook_allow
  exit 0
fi

if command -v gitleaks >/dev/null 2>&1; then
  EMPTY_DIR="$(mktemp -d /tmp/devkit-gl-XXXXXX)"
  if ! printf '%s' "$CONTENT" | gitleaks detect --pipe --source "$EMPTY_DIR" 2>/dev/null; then
    rmdir "$EMPTY_DIR" 2>/dev/null
    devkit_hook_deny "[devkit] gitleaks がシークレットを検出しました。APIキー・トークン・パスワードをコードに直接書き込まないでください。環境変数 (process.env.KEY / os.environ[\"KEY\"]) を使用してください。"
    exit 0
  fi
  rmdir "$EMPTY_DIR" 2>/dev/null
  devkit_hook_allow
  exit 0
fi

DETECTED=""

printf '%s' "$CONTENT" | grep -qE 'sk-proj-[a-zA-Z0-9\-_]{20,}|sk-[a-zA-Z0-9]{20,}' && DETECTED="OpenAI API Key"
printf '%s' "$CONTENT" | grep -qE 'sk-ant-[a-zA-Z0-9\-]{20,}' && DETECTED="Anthropic API Key"
printf '%s' "$CONTENT" | grep -qE 'AKIA[0-9A-Z]{16}' && DETECTED="AWS Access Key ID"
printf '%s' "$CONTENT" | grep -qE 'ghp_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{82}' && DETECTED="GitHub Token"
printf '%s' "$CONTENT" | grep -qiE \
  '(password|passwd|secret|api_?key|access_?token|auth_?token)\s*=\s*["\x27][^"\x27${}]{8,}["\x27]' \
  && DETECTED="ハードコードされた認証情報"
printf '%s' "$CONTENT" | grep -q 'BEGIN.*PRIVATE KEY' && DETECTED="Private Key"

if [ -n "$DETECTED" ]; then
  devkit_hook_deny "[devkit] ${DETECTED} が検出されました。機密情報をソースコードに直接書き込まないでください。環境変数を使用し、値は .env ファイルに記載してください（.env はコミットしない）。"
  exit 0
fi

devkit_hook_allow
exit 0
