#!/bin/sh
# budget-refresh.sh — fetches Claude.ai org usage and caches it to
# ~/.claude/budget-cache.txt so the statusline can display CC credit + monthly spend.
#
# Run once manually, then add to cron (see README.md).
#
# SETUP: set your org ID below (claude.ai → Settings → Account → Organization ID)

CLAUDE_ORG_ID="${CLAUDE_ORG_ID:-YOUR_ORG_ID}"

if [ "$CLAUDE_ORG_ID" = "YOUR_ORG_ID" ]; then
  echo "Error: set CLAUDE_ORG_ID at the top of this script."
  exit 1
fi

BUDGET_CACHE="$HOME/.claude/budget-cache.txt"
NOW=$(date +%s)
CACHE_AGE=999999
if [ -f "$BUDGET_CACHE" ]; then
  CACHE_MOD=$(stat -f %m "$BUDGET_CACHE" 2>/dev/null || echo 0)
  CACHE_AGE=$((NOW - CACHE_MOD))
fi

# Skip if cache is fresh (< 5 minutes old)
[ "$CACHE_AGE" -lt 300 ] && exit 0

SESSION_KEY=$(security find-generic-password -s "claude.ai" -a "claude-session-key" -w 2>/dev/null)
if [ -z "$SESSION_KEY" ]; then
  echo "Error: no session key in Keychain. See README.md → Step 2."
  exit 1
fi

# Find a python3 that has curl_cffi (searches all python3* variants in PATH)
PYTHON_CMD=$(python3 -c "from curl_cffi import requests; import sys; print(sys.executable)" 2>/dev/null)
if [ -z "$PYTHON_CMD" ]; then
  PYTHON_CMD=$(IFS=:; for dir in $PATH; do
    for py in "$dir"/python3*; do
      [ -x "$py" ] && "$py" -c "from curl_cffi import requests; import sys; print(sys.executable)" 2>/dev/null && break 2
    done
  done)
fi
if [ -z "$PYTHON_CMD" ]; then
  echo "Error: curl_cffi not found. Run: pip install curl_cffi --upgrade"
  exit 1
fi

BUDGET_TMP=$(mktemp)
$PYTHON_CMD -c "
from curl_cffi import requests
r = requests.get(
    'https://claude.ai/api/organizations/${CLAUDE_ORG_ID}/usage',
    cookies={'sessionKey': '${SESSION_KEY}'},
    impersonate='chrome'
)
print(r.text)
" > "$BUDGET_TMP" 2>/dev/null

if jq -e '.spend' "$BUDGET_TMP" > /dev/null 2>&1; then
  mv "$BUDGET_TMP" "$BUDGET_CACHE"
  echo "Cache updated: $BUDGET_CACHE"
else
  rm -f "$BUDGET_TMP"
  echo "Error: unexpected API response. Check your session key and org ID."
  exit 1
fi
