#!/usr/bin/env bash
# devkit: Post-Edit Semgrep SAST hook
# Fires after Write / Edit / MultiEdit tool calls.
# Graceful degradation: silently skips if semgrep is not installed.
# Only reports ERROR/CRITICAL severity findings. Always exits 0.

set -uo pipefail

# Skip entirely if semgrep is not installed
command -v semgrep >/dev/null 2>&1 || { printf '{"continue":true}\n'; exit 0; }

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)"

case "$TOOL_NAME" in
  Write|Edit|MultiEdit) ;;
  *) printf '{"continue":true}\n'; exit 0 ;;
esac

FILE_PATH="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('file_path', ti.get('path', '')))
" 2>/dev/null || true)"

[ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ] && { printf '{"continue":true}\n'; exit 0; }

# Run semgrep with 30s timeout; ignore failures
SEMGREP_OUT="$(timeout 30 semgrep scan \
  --config auto \
  --severity ERROR \
  --json \
  --quiet \
  "$FILE_PATH" 2>/dev/null || true)"

[ -z "$SEMGREP_OUT" ] && { printf '{"continue":true}\n'; exit 0; }

CRITICAL_COUNT="$(printf '%s' "$SEMGREP_OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    results = [r for r in d.get('results', [])
               if r.get('extra', {}).get('severity', '') in ('ERROR', 'CRITICAL')]
    print(len(results))
except:
    print(0)
" 2>/dev/null || echo 0)"

[ "$CRITICAL_COUNT" -eq 0 ] && { printf '{"continue":true}\n'; exit 0; }

FINDINGS="$(printf '%s' "$SEMGREP_OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    results = [r for r in d.get('results', [])
               if r.get('extra', {}).get('severity', '') in ('ERROR', 'CRITICAL')]
    lines = []
    for r in results[:5]:
        rule = r.get('check_id', 'unknown')
        msg  = r.get('extra', {}).get('message', '')
        line = r.get('start', {}).get('line', '?')
        lines.append(f'  - [{rule}] Line {line}: {msg}')
    print('\n'.join(lines))
except Exception as e:
    print(f'  (parse error: {e})')
" 2>/dev/null || true)"

python3 -c "
import json, sys
count    = int(sys.argv[1])
findings = sys.argv[2]
context  = f'[devkit semgrep] {count}件のセキュリティ問題が検出されました:\n\n{findings}\n\nこれらを修正してからコミットしてください。詳細は https://semgrep.dev でルールIDを検索できます。'
print(json.dumps({
  'hookSpecificOutput': {
    'hookEventName': 'PostToolUse',
    'additionalContext': context
  }
}))
" "$CRITICAL_COUNT" "$FINDINGS"

exit 0
