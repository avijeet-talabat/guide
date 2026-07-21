#!/bin/sh
# Claude Code status line
# Displays: user@host  cwd  |  model  |  in:Xk out:Xk  |  $cost sess  [| 💰 CC:$X/$Yk · Mo:$X/$Y]  |  [====      ] ctx%
# Budget segment appears automatically when ~/.claude/budget-cache.txt exists (see budget-refresh.sh).

input=$(cat)

# Parse all Claude Code fields in one jq call
eval "$(echo "$input" | jq -r '
  "cwd="       + (.workspace.current_dir // .cwd // "" | @sh),
  "model="     + (.model.display_name // "" | @sh),
  "total_in="  + ((.context_window.total_input_tokens  // "") | tostring | @sh),
  "total_out=" + ((.context_window.total_output_tokens // "") | tostring | @sh),
  "used="      + ((.context_window.used_percentage     // "") | tostring | @sh),
  "cost="      + ((.cost.total_cost_usd               // "") | tostring | @sh)
')"

cwd="${cwd/#$HOME/~}"

# Read monthly budget from cache (optional)
BUDGET_CACHE="$HOME/.claude/budget-cache.txt"
cc_used="" cc_max="" mo_used="" mo_max=""
if [ -f "$BUDGET_CACHE" ] && [ -s "$BUDGET_CACHE" ]; then
  eval "$(jq -r '
    "cc_used=" + ((.cinder_cove.used_dollars  // "" | tostring) | @sh),
    "cc_max="  + ((.cinder_cove.limit_dollars // "" | tostring) | @sh),
    "mo_used=" + (((.spend.used.amount_minor  // 0) / 100 | tostring) | @sh),
    "mo_max="  + (((.spend.limit.amount_minor // 0) / 100 | tostring) | @sh)
  ' "$BUDGET_CACHE" 2>/dev/null)"
fi

# Token segment (grey)
token_seg=""
if [ -n "$total_in" ] && [ "$total_in" != "null" ] && [ -n "$total_out" ] && [ "$total_out" != "null" ]; then
  token_seg=$(awk -v i="$total_in" -v o="$total_out" 'BEGIN {
    if (i >= 1000) { printf " | \033[38;5;244min:%.1fk", i/1000 } else { printf " | \033[38;5;244min:%d", i }
    if (o >= 1000) { printf " out:%.1fk\033[0m", o/1000 } else { printf " out:%d\033[0m", o }
  }')
fi

# Cost + budget segment (amber)
cost_seg=""
if [ -n "$cost" ] && [ "$cost" != "null" ]; then
  cost_seg=$(awk -v c="$cost" -v cu="$cc_used" -v cm="$cc_max" -v mu="$mo_used" -v mm="$mo_max" 'BEGIN {
    printf " | \033[38;5;178m$%.4f sess\033[0m", c
    if (cm != "" && cm+0 > 0 && mm+0 > 0) {
      cc_used_str = (cu+0 >= 1000) ? sprintf("$%.0fk", cu/1000) : sprintf("$%.2f", cu)
      printf " | \xf0\x9f\x92\xb0 CC:%s/$%.0fk \xc2\xb7 Mo:$%.2f/$%.0f", cc_used_str, cm/1000, mu, mm
    }
  }')
fi

# Context progress bar (green → orange → red)
ctx_seg=""
if [ -n "$used" ] && [ "$used" != "null" ]; then
  ctx_seg=$(awk -v u="$used" 'BEGIN {
    filled = int(u * 10 / 100 + 0.5); empty = 10 - filled
    bar = ""; for (i=0;i<filled;i++) bar=bar"="; for (i=0;i<empty;i++) bar=bar" "
    pct = int(u + 0.5)
    if (pct >= 90) color="\033[38;5;196m"
    else if (pct >= 70) color="\033[38;5;214m"
    else color="\033[38;5;76m"
    printf " | %s[%s] %d%%\033[0m", color, bar, pct
  }')
fi

printf "\033[38;5;32m%s@%s\033[0m  \033[38;5;105m%s\033[0m  | %s%b%b%b\n" \
  "$(whoami)" "$(hostname -s)" "$cwd" "$model" "$token_seg" "$cost_seg" "$ctx_seg"
