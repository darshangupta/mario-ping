# 🏎 mario-ping

**Mario Kart Wii sounds + animated kart overlay for your AI coding agent.**

When Claude Code (or any AI agent) needs your attention, a **Mario Kart character drives across the middle of your screen** and Mario Kart sounds blast. Stop babysitting your terminal. Let Mario ping you.

Inspired by [peon-ping](https://github.com/PeonPing/peon-ping).

---

## What it does

```
[ agent goes idle — needs your input ]

                    MARIO
          ━━━━━━━━━━━━━🏎━━━━━━━━━━━━━━━━━━━━━━━▶
```

1. Plays a Mario Kart sound (falls back to macOS TTS if sounds not downloaded)
2. Shows an animated kart driving across the **center** of your screen
3. Kart disappears the moment you submit your next message to Claude

---

## Install

```bash
git clone https://github.com/darshangupta/mario-ping
cd mario-ping
bash install.sh
```

Restart Claude Code to activate hooks.

---

## Characters

Set `"character"` in `~/.claude/hooks/mario-ping/config.json`:

| Character     | Value      |
|---------------|------------|
| Mario         | `mario`    |
| Luigi         | `luigi`    |
| Toad          | `toad`     |
| Yoshi         | `yoshi`    |
| Princess Peach| `peach`    |
| Bowser        | `bowser`   |
| Waluigi       | `waluigi`  |
| Rosalina      | `rosalina` |
| Donkey Kong   | `donkey`   |

---

## Commands

```bash
mario test      # play sound + show kart animation for 4s
mario toggle    # pause / unpause mario-ping
mario status    # show current status, character, volume
```

---

## Config

`~/.claude/hooks/mario-ping/config.json`:

```json
{
  "volume": 0.7,
  "enabled": true,
  "character": "mario",
  "kart_speed": 10,
  "categories": {
    "session.start": true,
    "task.complete": true,
    "task.error": true,
    "input.required": true,
    "resource.limit": true
  }
}
```

---

## Sounds

Sounds download automatically from the [GitHub releases](https://github.com/darshangupta/mario-ping/releases). Without sounds, mario-ping falls back to macOS `say` command (TTS).

**Sound events:**

| Event | Sound |
|-------|-------|
| Agent needs input | "Here We Go!" |
| Task complete | Course clear jingle |
| Error | "Wah!" |
| Session start | Race countdown |
| Resource limit | Blue shell incoming |

---

## Platform

| Platform | Sounds | Kart Animation |
|----------|--------|----------------|
| macOS    | ✅     | ✅             |
| Linux    | ✅     | ❌ (coming soon)|
| Windows  | ❌     | ❌             |

---

## How it works

mario-ping registers itself as a **Claude Code hook** for these events:

- `Notification` (agent idle / needs input) → plays sound + shows kart
- `UserPromptSubmit` (you replied) → dismisses kart
- `Stop` (task complete) → plays completion sound
- `SessionStart` → plays race start sound

The kart animation runs as a background `osascript` process. It polls for a signal file every frame — when `UserPromptSubmit` fires, mario.sh deletes the signal file and the kart process exits cleanly.

---

## Uninstall

```bash
bash uninstall.sh
```

---

## License

MIT
