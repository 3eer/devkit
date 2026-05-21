#!/usr/bin/env bash
# devkit: Post-Edit quality check hook
# Fires after Write / Edit / MultiEdit tool calls.
# Detects the language of the edited file and runs the appropriate linter/typecheck.
# Sends feedback to Claude via additionalContext. Always exits 0.

set -uo pipefail

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

[ -z "$FILE_PATH" ] && { printf '{"continue":true}\n'; exit 0; }
[ -f "$FILE_PATH" ]  || { printf '{"continue":true}\n'; exit 0; }

EXT="${FILE_PATH##*.}"
FEEDBACK=""
ERRORS_FOUND=0

PROJECT_ROOT="$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null \
  || dirname "$FILE_PATH")"

case "$EXT" in
  ts|tsx|mts|cts)
    # ESLint
    ESLINT_BIN="$PROJECT_ROOT/node_modules/.bin/eslint"
    [ -f "$ESLINT_BIN" ] || ESLINT_BIN="$(command -v eslint 2>/dev/null || true)"
    if [ -n "$ESLINT_BIN" ] && [ -x "$ESLINT_BIN" ]; then
      if ! OUT=$("$ESLINT_BIN" "$FILE_PATH" --format compact 2>&1 | head -30); then
        FEEDBACK="${FEEDBACK}**ESLint エラー:**\n${OUT}\n\n"
        ERRORS_FOUND=1
      fi
    fi
    # TypeScript type check
    TSC_BIN="$PROJECT_ROOT/node_modules/.bin/tsc"
    [ -f "$TSC_BIN" ] || TSC_BIN="$(command -v tsc 2>/dev/null || true)"
    TSCONFIG="$PROJECT_ROOT/tsconfig.json"
    if [ -n "$TSC_BIN" ] && [ -x "$TSC_BIN" ] && [ -f "$TSCONFIG" ]; then
      if ! OUT=$("$TSC_BIN" --noEmit --project "$TSCONFIG" 2>&1 | head -30); then
        FEEDBACK="${FEEDBACK}**TypeScript 型エラー:**\n${OUT}\n\n"
        ERRORS_FOUND=1
      fi
    fi
    ;;

  js|jsx|mjs|cjs)
    ESLINT_BIN="$PROJECT_ROOT/node_modules/.bin/eslint"
    [ -f "$ESLINT_BIN" ] || ESLINT_BIN="$(command -v eslint 2>/dev/null || true)"
    if [ -n "$ESLINT_BIN" ] && [ -x "$ESLINT_BIN" ]; then
      if ! OUT=$("$ESLINT_BIN" "$FILE_PATH" --format compact 2>&1 | head -30); then
        FEEDBACK="${FEEDBACK}**ESLint エラー:**\n${OUT}\n\n"
        ERRORS_FOUND=1
      fi
    fi
    ;;

  py)
    if command -v ruff >/dev/null 2>&1; then
      if ! OUT=$(ruff check "$FILE_PATH" 2>&1 | head -30); then
        FEEDBACK="${FEEDBACK}**Ruff lint エラー:**\n${OUT}\n\n"
        ERRORS_FOUND=1
      fi
      if ! ruff format --check "$FILE_PATH" >/dev/null 2>&1; then
        FEEDBACK="${FEEDBACK}**Ruff format:** フォーマットが必要です。\`ruff format ${FILE_PATH}\` を実行してください。\n\n"
      fi
    fi
    if command -v mypy >/dev/null 2>&1; then
      if ! OUT=$(mypy "$FILE_PATH" --ignore-missing-imports 2>&1 | head -20); then
        FEEDBACK="${FEEDBACK}**mypy 型エラー:**\n${OUT}\n\n"
        ERRORS_FOUND=1
      fi
    fi
    ;;

  go)
    if command -v golangci-lint >/dev/null 2>&1; then
      if ! OUT=$(golangci-lint run "$FILE_PATH" 2>&1 | head -30); then
        FEEDBACK="${FEEDBACK}**golangci-lint エラー:**\n${OUT}\n\n"
        ERRORS_FOUND=1
      fi
    elif command -v go >/dev/null 2>&1; then
      if ! OUT=$(go vet "$(dirname "$FILE_PATH")" 2>&1); then
        FEEDBACK="${FEEDBACK}**go vet エラー:**\n${OUT}\n\n"
        ERRORS_FOUND=1
      fi
    fi
    ;;

  rs)
    if command -v cargo >/dev/null 2>&1 && [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
      if ! OUT=$(cd "$PROJECT_ROOT" && cargo check 2>&1 | head -30); then
        FEEDBACK="${FEEDBACK}**cargo check エラー:**\n${OUT}\n\n"
        ERRORS_FOUND=1
      fi
      if command -v cargo-clippy >/dev/null 2>&1 || cargo clippy --version >/dev/null 2>&1; then
        if ! OUT=$(cd "$PROJECT_ROOT" && cargo clippy -- -D warnings 2>&1 | head -30); then
          FEEDBACK="${FEEDBACK}**cargo clippy 警告:**\n${OUT}\n\n"
          ERRORS_FOUND=1
        fi
      fi
    fi
    ;;

  *)
    printf '{"continue":true}\n'
    exit 0
    ;;
esac

if [ "$ERRORS_FOUND" -eq 0 ]; then
  printf '{"continue":true}\n'
  exit 0
fi

# Send feedback to Claude as additionalContext
python3 -c "
import json, sys
feedback = sys.argv[1]
context = '[devkit quality-check] 編集後チェックでエラーが検出されました。次のファイルを編集する前にこれらを修正してください:\n\n' + feedback + '\n修正方針:\n1. 型エラー → 型アノテーションを追加/修正\n2. Lint エラー → ルールに従ってコードを修正\n3. フォーマットエラー → 指示されたコマンドを実行'
print(json.dumps({
  'hookSpecificOutput': {
    'hookEventName': 'PostToolUse',
    'additionalContext': context
  }
}))
" "$FEEDBACK"

exit 0
