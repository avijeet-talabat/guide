# Claude Code Statusline

Shows Claude usage directly in your Claude Code statusline.

```
avijeet@mac  ~/project  | Claude Opus 4.6  | in:36.8k out:24.2k  | $1.70 sess  | 💰 CC:$3.99/$1k · Mo:$0.00/$200  | [=         ] 6%
```

- **CC** — Claude Code & Cowork quarterly credit (used first)
- **Mo** — Monthly personal spend limit (kicks in after credit runs out)

---

## Install

Requirements: `jq` (`brew install jq`)

```sh
sh install.sh
```

Restarts automatically on next Claude message.

---

## Add monthly budget (💰 CC · Mo)

### 1. Install curl_cffi

```sh
pip install curl_cffi --upgrade
```

> On macOS with Homebrew Python: `pip install --break-system-packages --user curl_cffi`

### 2. Store your session key in Keychain

1. Open [claude.ai](https://claude.ai) → DevTools → Application → Cookies → `sessionKey`
2. Copy the value (starts with `sk-ant-...`)

```sh
security add-generic-password -a "claude-session-key" -s "claude.ai" -w "YOUR_SESSION_KEY"
```

### 3. Set your org ID and run

Edit `budget-refresh.sh`, set `CLAUDE_ORG_ID` (find it at claude.ai → Settings → Account), then:

```sh
sh budget-refresh.sh
```

### 4. Keep it fresh with cron

```sh
(crontab -l 2>/dev/null; echo "*/5 * * * * CLAUDE_ORG_ID=your-uuid sh ~/budget-refresh.sh > /dev/null 2>&1") | crontab -
```

---

## Session key expired? (~every 28 days)

```sh
security add-generic-password -U -a "claude-session-key" -s "claude.ai" -w "NEW_KEY"
rm -f ~/.claude/budget-cache.txt
```
