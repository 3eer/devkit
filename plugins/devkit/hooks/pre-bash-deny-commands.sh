#!/usr/bin/env bash
# devkit: Pre-Bash dangerous-command denylist hook
# Fires before every Bash tool call. Denies a fixed set of irreversible /
# destructive commands at the HARNESS level — Claude cannot bypass this, unlike
# a prompt-level instruction in a SKILL.md. Always exits 0 (never crashes Claude).
#
# Denied commands:
#   - gh pr merge / GitHub merge REST API   (push≠merge: マージは人間が判断する)
#   - git push --force / -f / --force-with-lease
#   - git push to main/master              (explicit refspec, or bare push while on main/master)
#   - rm -rf against CATASTROPHIC targets   ( / ~ $HOME * . .. system dirs, $VAR/ footgun )
#
# rm -rf policy: by default only catastrophic targets are blocked, so scoped
# cleanups like `rm -rf node_modules` / `rm -rf dist` still work. To block ALL
# recursive-force deletes, set the env var DEVKIT_RM_BLOCK_MODE=all (e.g. in the
# hook entry's env, or export it) — flip "catastrophic" → "all".

set -uo pipefail

INPUT="$(cat)"
export DEVKIT_HOOK_INPUT="$INPUT"
export ON_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
export RM_BLOCK_MODE="${DEVKIT_RM_BLOCK_MODE:-catastrophic}"

python3 - <<'PY'
import os, sys, json, re, shlex

def allow():
    print('{"continue":true}')
    sys.exit(0)

def deny(rule, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": f"[devkit] {reason} (rule: {rule})",
    }}))
    sys.exit(0)

try:
    data = json.loads(os.environ.get("DEVKIT_HOOK_INPUT", "") or "{}")
except Exception:
    allow()

if data.get("tool_name") != "Bash":
    allow()

cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""
on_branch = os.environ.get("ON_BRANCH", "")
rm_mode = os.environ.get("RM_BLOCK_MODE", "catastrophic")

norm = re.sub(r"\s+", " ", cmd.replace("\n", " ")).strip()
low = norm.lower()
# split into sub-commands so each segment (git push / rm / gh) is inspected on its own
segments = [s for s in re.split(r"(?:&&|\|\||[;|])", norm) if s.strip()]

# --- 1) PR merge (CLI + REST API) ------------------------------------------
if re.search(r"(^|\s)gh\s+pr\s+merge\b", low):
    deny("gh-pr-merge",
         "PR のマージは禁止です。PR 作成までで止め、マージは人間が判断します。")
if re.search(r"/pulls/\d+/merge\b", low) or re.search(r"gh\s+api\b.*pulls/\S+/merge", low):
    deny("api-pr-merge",
         "GitHub マージ API の呼び出しは禁止です。マージは人間が判断します。")

# --- 2) force push & 3) push to main/master --------------------------------
for seg in segments:
    sl = seg.strip().lower()
    if not re.search(r"\bgit\s+push\b", sl):
        continue
    # force push (--force / --force-with-lease / -f / combined short flags)
    if re.search(r"--force(-with-lease)?\b", sl) or re.search(r"\s-[a-z]*f[a-z]*\b", sl):
        deny("force-push",
             "force push は禁止です。コミット履歴を破壊する可能性があります。")
    try:
        toks = shlex.split(seg.strip())
    except Exception:
        toks = seg.strip().split()
    after = toks[toks.index("push") + 1:] if "push" in toks else []
    positum = [t for t in after if not t.startswith("-")]   # [remote] [refspec...]
    # explicit refspec targeting main/master (origin main, HEAD:main, +main, ...)
    if any(re.search(r"(^|:|\+)(main|master)$", p) for p in positum):
        deny("push-main",
             "main/master への直接 push は禁止です。ブランチを切って PR を作成してください。")
    # bare push (no refspec; at most a remote) while currently on main/master
    if on_branch in ("main", "master") and len(positum) <= 1:
        deny("push-main",
             f"現在 {on_branch} ブランチです。main/master への直接 push は禁止です。"
             "ブランチを切って PR を作成してください。")

# --- 4) rm -rf -------------------------------------------------------------
DANGER_EXACT = {"/", "~", "~/", ".", "..", "*", "/*", "~/*", "$HOME", "${HOME}",
                "$home", "${home}"}
DANGER_ROOT = re.compile(
    r"^/(usr|etc|var|bin|sbin|lib|opt|root|boot|dev|sys|System|Library|Applications|Users)\b")
EMPTY_VAR = re.compile(r'^["\']?\$\{?\w+\}?/?["\']?$')  # target is just $VAR or ${VAR}/ (empty-var footgun)

for seg in segments:
    s = seg.strip()
    sl = s.lower()
    if not re.search(r"\brm\b", sl):
        continue
    has_r = bool(re.search(r"\s-[a-z]*r[a-z]*\b", sl) or re.search(r"--recursive\b", sl))
    has_f = bool(re.search(r"\s-[a-z]*f[a-z]*\b", sl) or re.search(r"--force\b", sl))
    if not (has_r and has_f):
        continue
    if rm_mode == "all":
        deny("rm-rf-all",
             "rm -rf は禁止です（再帰・強制削除を全面ブロックする設定です）。")
    try:
        toks = shlex.split(s)
    except Exception:
        toks = s.split()
    targets = [t for t in toks if not t.startswith("-") and t != "rm" and t != "sudo"]
    for t in targets:
        tt = t.strip().strip('"').strip("'")
        if tt in DANGER_EXACT or DANGER_ROOT.match(tt) or EMPTY_VAR.match(tt) \
           or (tt.startswith("~/") and tt.count("/") <= 1):
            deny("rm-rf-catastrophic",
                 "致命的なパスに対する rm -rf を検出しました "
                 "（/・~・$HOME・*・.・システムディレクトリ・空になりうる変数展開 等）。")

allow()
PY
exit 0
