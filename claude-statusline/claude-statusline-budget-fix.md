# Claude Code Statusline — Budget Cache Fix

## Problem

The statusline shows a stale monthly spend (e.g. `Mo:$994.40/$1300`) because the budget cache file
`~/.claude/budget-cache.txt` hasn't been refreshed. The script auto-refreshes every 4 minutes
but requires a valid `claude.ai` session key stored in the macOS keychain.

## Diagnosis

Check if the cache is stale:
```sh
stat -f "%Sm" ~/.claude/budget-cache.txt
```

Check if the keychain entry exists:
```sh
security find-generic-password -s "claude.ai" -a "claude-session-key" -w
```

## Fix

### 1. Get a fresh session key
Open claude.ai in your browser → DevTools → Application → Cookies → copy the `sessionKey` value.

### 2. Save it to the keychain
```sh
security add-generic-password -s "claude.ai" -a "claude-session-key" -w "sk-ant-sid02-..." -U
```

### 3. Force a cache refresh
```sh
rm ~/.claude/budget-cache.txt && echo '{}' | sh ~/.claude/statusline-command.sh
```

The statusline will now show the correct spend on the next update.

## How the auto-refresh works

The script (`~/.claude/statusline-command.sh`) checks the cache age on every statusline render.
If the cache is older than 4 minutes, it:
1. Reads the session key from the macOS keychain
2. Fetches `https://claude.ai/api/organizations/<org-id>/usage` using `curl_cffi`
3. Saves the response to `~/.claude/budget-cache.txt`

If `curl_cffi` is not installed or the session key is missing/expired, the refresh silently fails
and the old cached value continues to be shown.

## Notes

- The org ID is hardcoded in the script: `17689280-b17d-4dbe-83e7-9e62144aab69`
- Session keys expire — repeat the fix whenever the displayed amount goes stale again
- Never share the session key in chat or commit it to git
