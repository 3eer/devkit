#!/usr/bin/env bash
# Shared JSON helpers for devkit PreToolUse hooks.

devkit_hook_allow() {
  printf '{"continue":true}\n'
}

devkit_hook_deny() {
  local reason="$1"
  python3 -c "
import json, sys
print(json.dumps({
  'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'permissionDecision': 'deny',
    'permissionDecisionReason': sys.argv[1]
  }
}))
" "$reason"
}
