#!/usr/bin/env bash
# Verify marketplace.json (SSoT) and plugin.json versions match.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE="${ROOT}/.claude-plugin/marketplace.json"
PLUGIN="${ROOT}/.claude-plugin/plugin.json"

for f in "$MARKETPLACE" "$PLUGIN"; do
  if [[ ! -f "$f" ]]; then
    echo "check-plugin-version: missing $f" >&2
    exit 1
  fi
done

MARKETPLACE_VERSION="$(python3 -c "
import json
from pathlib import Path
print(json.loads(Path('${MARKETPLACE}').read_text())['plugins'][0]['version'])
")"

PLUGIN_VERSION="$(python3 -c "
import json
from pathlib import Path
print(json.loads(Path('${PLUGIN}').read_text())['version'])
")"

if [[ "$MARKETPLACE_VERSION" != "$PLUGIN_VERSION" ]]; then
  echo "check-plugin-version: version mismatch" >&2
  echo "  marketplace.json (SSoT): ${MARKETPLACE_VERSION}" >&2
  echo "  plugin.json:             ${PLUGIN_VERSION}" >&2
  exit 1
fi

echo "check-plugin-version: OK (${MARKETPLACE_VERSION})"
