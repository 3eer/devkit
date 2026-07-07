#!/usr/bin/env bash
# devkit: Pre-Read .env block hook
# Fires before Read tool calls. Blocks reading secret-bearing .env files.
# Always exits 0 (never crashes Claude Code).

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
  Read) ;;
  *) devkit_hook_allow; exit 0 ;;
esac

FILE_PATH="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('file_path', ti.get('path', '')))
" 2>/dev/null || true)"

if devkit_is_blocked_env_path "$FILE_PATH"; then
  devkit_hook_deny "[devkit] .env ファイルの読み取りは禁止です（${FILE_PATH}）。シークレットがコンテキストに混入する恐れがあります。.env.example のプレースホルダーを参照するか、必要な変数名だけをユーザーに確認してください。意図的に読む場合はユーザーに「.envを読んでOK」と明示的に依頼してもらってください。"
  exit 0
fi

devkit_hook_allow
exit 0
