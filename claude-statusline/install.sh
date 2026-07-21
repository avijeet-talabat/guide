#!/bin/sh
# install.sh — sets up Claude Code with opusplan[1m] model + statusline
#
# What this installs:
#   ~/.claude/statusline-command.sh   the statusline script
#   ~/.claude/settings.json           model + statusLine config (merged, non-destructive)
#
# Run: sh install.sh
# For monthly budget display, also follow the "Monthly budget" section in README.md.

set -e

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE="$CLAUDE_DIR/statusline-command.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Setting up Claude Code..."

# ── 1. Check dependencies ──────────────────────────────────────────────────────
if ! command -v jq > /dev/null 2>&1; then
  echo "Error: jq is required. Install it with: brew install jq"
  exit 1
fi

# ── 2. Create ~/.claude if needed ─────────────────────────────────────────────
mkdir -p "$CLAUDE_DIR"

# ── 3. Install statusline script ───────────────────────────────────────────────
cp "$SCRIPT_DIR/statusline-command.sh" "$STATUSLINE"
chmod +x "$STATUSLINE"
echo "    ✓ Installed $STATUSLINE"

# ── 4. Merge settings (preserves your existing config) ────────────────────────
NEW_SETTINGS='{
  "model": "opusplan[1m]",
  "statusLine": {
    "type": "command",
    "command": "sh ~/.claude/statusline-command.sh",
    "padding": 0,
    "refreshInterval": 300
  }
}'

if [ -f "$SETTINGS" ]; then
  MERGED=$(jq -s '.[0] * .[1]' "$SETTINGS" - <<EOF
$NEW_SETTINGS
EOF
)
  echo "$MERGED" > "$SETTINGS"
  echo "    ✓ Merged settings into existing $SETTINGS"
else
  echo "$NEW_SETTINGS" | jq '.' > "$SETTINGS"
  echo "    ✓ Created $SETTINGS"
fi

echo ""
echo "==> Done! Restart Claude Code or send any message to see the statusline."
echo ""
echo "    avijeet@mac  ~/project  | Claude Opus  | in:15k out:1.2k | \$0.08 sess | [=   ] 8%"
echo ""
echo "    To also show monthly budget (mo: \$732/\$1300), see README.md → Monthly budget setup."
