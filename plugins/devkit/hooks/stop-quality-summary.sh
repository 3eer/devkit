#!/usr/bin/env bash
# devkit: Stop hook — post-session quick quality summary
# Fires when Claude finishes a response (Stop event).
# Only runs when files were edited in this session to avoid noise.
# Always exits 0.

set -uo pipefail

INPUT="$(cat)"

# Only fire on Stop events
EVENT="$(printf '%s' "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('hook_event_name',''))" 2>/dev/null || true)"

[ "$EVENT" = "Stop" ] || { printf '{"continue":true}\n'; exit 0; }

# Check if there are any staged or unstaged changes
if ! command -v git >/dev/null 2>&1; then
  printf '{"continue":true}\n'; exit 0
fi

CHANGED="$(git diff --name-only HEAD 2>/dev/null; git diff --name-only 2>/dev/null)"
[ -z "$CHANGED" ] && { printf '{"continue":true}\n'; exit 0; }

# Count changed files
CHANGED_COUNT="$(printf '%s' "$CHANGED" | grep -c '.' 2>/dev/null || echo 0)"

# Run secrets check on changed files
SECRETS_MSG=""
if command -v gitleaks >/dev/null 2>&1; then
  EMPTY_DIR="$(mktemp -d /tmp/devkit-stop-gl-XXXXXX)"
  if ! git diff HEAD 2>/dev/null | gitleaks detect --pipe --source "$EMPTY_DIR" 2>/dev/null; then
    SECRETS_MSG="- シークレット検出: gitleaks が問題を発見しました。`security-gate` スキルで確認してください。"
  else
    SECRETS_MSG="- シークレット検出: クリーン"
  fi
  rmdir "$EMPTY_DIR" 2>/dev/null || true
fi

python3 -c "
import json, sys
count = int(sys.argv[1])
secrets = sys.argv[2]

lines = [f'[devkit] セッション終了サマリー — {count}ファイルが変更されました。']
if secrets:
    lines.append(secrets)
lines.append('フル品質チェックを行うには `gate-workflow` スキルを実行してください。')

msg = '\n'.join(lines)
print(json.dumps({'terminalSequence': msg + '\n'}))
" "$CHANGED_COUNT" "$SECRETS_MSG"

exit 0
