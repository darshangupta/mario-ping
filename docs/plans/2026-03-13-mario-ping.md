# mario-ping Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Mario Kart-themed notification tool for AI coding agents (Claude Code etc.) that plays Mario Kart sounds and shows an animated kart driving across the screen whenever the agent needs your attention.

**Architecture:** Shell-script based (modeled after peon-ping). Main hook script `mario.sh` hooks into Claude Code's event system via `~/.claude/hooks/`. A JXA overlay script (`scripts/mac-kart-overlay.js`) creates an animated Mario Kart kart that drives across the middle of the screen using `NSTimer` + `ObjC.registerSubclass`. Sounds are downloaded from the GitHub releases of this repo and played via `afplay` on macOS.

**Tech Stack:** Bash, JXA (JavaScript for Automation / osascript), Python 3 (inline in bash for event parsing), afplay (macOS sound), GitHub Releases (sound hosting)

---

### Task 1: Initialize repo + CLAUDE.md

**Files:**
- Create: `CLAUDE.md`
- Create: `config.json`
- Create: `.gitignore`

**Step 1: Create CLAUDE.md with Drakeo the Ruler persona**

Write `/Users/darshangupta/mario-ping/CLAUDE.md`:
```markdown
# mario-ping

You are Drakeo the Claude. Talk like Drakeo the Ruler — LA slang, South Central energy, ice cold delivery, effortlessly smooth. You from the 9, not Chicago, keep it correct foenem. Fresh up out the slammer, flu flammer, Mr. LA, Mr. South Central.

## Project
mario-ping — Mario Kart Wii sounds + animated kart overlay for Claude Code hooks. When the AI needs you, a kart drives across your screen and Mario sounds blast.

## Stack
- Bash (main hook script mario.sh)
- JXA / osascript (kart animation overlay)
- Python 3 inline (event parsing)
- afplay (macOS sound playback)
- Claude Code hooks (PreToolUse, PostToolUse, Stop, Notification, SessionStart)

## Key Files
- `mario.sh` — main hook entry point
- `scripts/mac-kart-overlay.js` — animated kart overlay (JXA)
- `scripts/pack-download.sh` — sound downloader
- `install.sh` — one-line installer
- `adapters/claude.sh` — Claude Code hook adapter
- `config.json` — user config

## Commands
- `mario toggle` — pause/unpause
- `mario status` — check if active
- `mario test` — play a test sound + show kart
- `mario install` — install/reinstall

## Vibe
Keep it clean, keep it tuff. No unnecessary complexity. Every sound choice is intentional. The kart animation is the showstopper.
```

**Step 2: Create config.json**

Write `/Users/darshangupta/mario-ping/config.json`:
```json
{
  "volume": 0.7,
  "enabled": true,
  "desktop_notifications": true,
  "character": "mario",
  "kart_speed": 10,
  "kart_size": 64,
  "categories": {
    "session.start": true,
    "task.complete": true,
    "task.error": true,
    "input.required": true,
    "resource.limit": true
  },
  "suppress_sound_when_tab_focused": false,
  "notification_dismiss_seconds": 4
}
```

**Step 3: Create .gitignore**
```
sounds/*/
*.mp3
*.wav
*.ogg
.DS_Store
/tmp/
state.json
.paused
```

**Step 4: Init git and first commit**
```bash
cd /Users/darshangupta/mario-ping
git init && git add CLAUDE.md config.json .gitignore
git commit -m "feat: init mario-ping with config and CLAUDE.md"
```

---

### Task 2: Core mario.sh hook script

**Files:**
- Create: `mario.sh`

This is the main hook. It reads Claude Code hook events from stdin (JSON), parses the event type, plays the appropriate sound, and triggers the kart overlay.

**Step 1: Write mario.sh**

```bash
#!/bin/bash
# mario-ping: Mario Kart Wii voice/sound notifications for Claude Code hooks
# Hooks into: Notification, Stop, SessionStart, UserPromptSubmit
set -uo pipefail

# --- Locate mario-ping dir ---
MARIO_DIR=""
_hooks_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/mario-ping"
if [ -d "$_hooks_dir" ]; then
  MARIO_DIR="$_hooks_dir"
else
  MARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

CONFIG_FILE="$MARIO_DIR/config.json"
STATE_FILE="$MARIO_DIR/state.json"
SIGNAL_FILE="/tmp/mario-ping-active-$$"
SCRIPTS_DIR="$MARIO_DIR/scripts"
SOUNDS_DIR="$MARIO_DIR/sounds"

# --- Platform ---
detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}
PLATFORM=$(detect_platform)

# --- Play sound ---
play_sound() {
  local file="$1"
  local volume="${2:-0.7}"
  [ ! -f "$file" ] && return 0
  case "$PLATFORM" in
    mac) afplay "$file" --volume "$volume" &>/dev/null & ;;
    linux)
      if command -v paplay &>/dev/null; then
        paplay "$file" &>/dev/null &
      elif command -v aplay &>/dev/null; then
        aplay "$file" &>/dev/null &
      fi ;;
  esac
}

# --- Say fallback (macOS TTS) ---
say_fallback() {
  local text="$1"
  [ "$PLATFORM" = "mac" ] && say -v "Organ" "$text" &>/dev/null &
}

# --- Get config value via python ---
get_config() {
  local key="$1" default="$2"
  python3 -c "
import json, sys
try:
    cfg = json.load(open('$CONFIG_FILE'))
    val = cfg
    for k in '$key'.split('.'):
        val = val[k]
    print(str(val).lower() if isinstance(val, bool) else val)
except:
    print('$default')
" 2>/dev/null
}

# --- Show kart overlay (async) ---
show_kart() {
  local event="$1"
  local overlay="$SCRIPTS_DIR/mac-kart-overlay.js"
  [ ! -f "$overlay" ] && return 0
  [ "$PLATFORM" != "mac" ] && return 0
  local character
  character=$(get_config "character" "mario")
  local signal="/tmp/mario-ping-kart-signal-$$"
  touch "$signal"
  osascript -l JavaScript "$overlay" "$character" "$signal" "$event" &>/dev/null &
  # Store PID and signal file so UserPromptSubmit can kill it
  echo "$!" > "/tmp/mario-ping-kart-pid"
  echo "$signal" > "/tmp/mario-ping-kart-signal-path"
}

# --- Dismiss kart overlay ---
dismiss_kart() {
  local sig_path
  sig_path=$(cat /tmp/mario-ping-kart-signal-path 2>/dev/null || echo "")
  [ -n "$sig_path" ] && rm -f "$sig_path"
  local pid
  pid=$(cat /tmp/mario-ping-kart-pid 2>/dev/null || echo "")
  [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  rm -f /tmp/mario-ping-kart-pid /tmp/mario-ping-kart-signal-path
}

# --- Get sound file for category ---
get_sound() {
  local category="$1"
  local pack_dir="$SOUNDS_DIR"
  local character
  character=$(get_config "character" "mario")
  # Try category-specific sounds first
  local f
  for ext in mp3 wav ogg; do
    f="$pack_dir/${category}.${ext}"
    [ -f "$f" ] && { echo "$f"; return; }
  done
  echo ""
}

# --- Parse hook event from stdin ---
INPUT=$(cat)
EVENT=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    e = d.get('hook_event_name', '')
    ntype = d.get('notification_type', '')
    # Map to categories
    if e == 'Notification' and ntype == 'idle': print('input.required')
    elif e == 'Notification': print('input.required')
    elif e == 'Stop': print('task.complete')
    elif e == 'SessionStart': print('session.start')
    elif e == 'UserPromptSubmit': print('user.submit')
    elif e == 'PreToolUse' or e == 'PostToolUse': print('ignore')
    else: print('ignore')
except: print('ignore')
" 2>/dev/null)

# Check if enabled
ENABLED=$(get_config "enabled" "true")
[ "$ENABLED" = "false" ] && exit 0

# Check paused
[ -f "$MARIO_DIR/.paused" ] && exit 0

VOLUME=$(get_config "volume" "0.7")

case "$EVENT" in
  input.required)
    # THE SHOWSTOPPER: play sound + show kart
    sound=$(get_sound "input.required")
    if [ -n "$sound" ]; then
      play_sound "$sound" "$VOLUME"
    else
      say_fallback "Here we go"
    fi
    show_kart "input.required"
    ;;
  task.complete)
    sound=$(get_sound "task.complete")
    if [ -n "$sound" ]; then
      play_sound "$sound" "$VOLUME"
    else
      say_fallback "Course clear"
    fi
    ;;
  task.error)
    sound=$(get_sound "task.error")
    if [ -n "$sound" ]; then
      play_sound "$sound" "$VOLUME"
    else
      say_fallback "Wah"
    fi
    ;;
  session.start)
    sound=$(get_sound "session.start")
    if [ -n "$sound" ]; then
      play_sound "$sound" "$VOLUME"
    else
      say_fallback "3 2 1 Go"
    fi
    ;;
  user.submit)
    # User responded to Claude — dismiss the kart
    dismiss_kart
    ;;
  *)
    exit 0
    ;;
esac

exit 0
```

**Step 2: Make executable and commit**
```bash
chmod +x /Users/darshangupta/mario-ping/mario.sh
cd /Users/darshangupta/mario-ping
git add mario.sh
git commit -m "feat: add mario.sh main hook script"
```

---

### Task 3: Animated kart overlay (JXA)

**Files:**
- Create: `scripts/mac-kart-overlay.js`

This is the crown jewel. A Mario Kart kart drives across the middle of your screen using NSTimer animation in JXA (JavaScript for Automation). It stays until the user submits input (signal file deleted).

**Step 1: Write scripts/mac-kart-overlay.js**

```javascript
#!/usr/bin/env osascript -l JavaScript
// mac-kart-overlay.js — animated Mario Kart kart overlay for macOS
// Usage: osascript -l JavaScript mac-kart-overlay.js <character> <signal_file> <event_type>
// character: mario, luigi, toad, yoshi, peach, bowser, waluigi, rosalina, donkey
// signal_file: path to temp file; overlay exits when file is deleted
// event_type: input.required, task.complete, etc.

ObjC.import('Cocoa');
ObjC.import('QuartzCore');

function run(argv) {
  var character  = argv[0] || 'mario';
  var signalFile = argv[1] || '/tmp/mario-ping-kart-signal';
  var eventType  = argv[2] || 'input.required';

  // Character display: [emoji kart, name color r, g, b]
  var chars = {
    mario:    { kart: '🏎',  label: 'MARIO',    r: 0.9, g: 0.1, b: 0.1 },
    luigi:    { kart: '🏎',  label: 'LUIGI',    r: 0.1, g: 0.7, b: 0.1 },
    toad:     { kart: '🏎',  label: 'TOAD',     r: 0.4, g: 0.4, b: 1.0 },
    yoshi:    { kart: '🏎',  label: 'YOSHI',    r: 0.1, g: 0.8, b: 0.3 },
    peach:    { kart: '🏎',  label: 'PEACH',    r: 1.0, g: 0.5, b: 0.7 },
    bowser:   { kart: '🏎',  label: 'BOWSER',   r: 0.8, g: 0.5, b: 0.0 },
    waluigi:  { kart: '🏎',  label: 'WALUIGI',  r: 0.5, g: 0.0, b: 0.8 },
    rosalina: { kart: '🏎',  label: 'ROSALINA', r: 0.2, g: 0.6, b: 0.9 },
    donkey:   { kart: '🏎',  label: 'DK',       r: 0.6, g: 0.3, b: 0.0 },
  };
  var ch = chars[character] || chars['mario'];

  $.NSApplication.sharedApplication;
  $.NSApp.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var screens = $.NSScreen.screens;
  var screenCount = screens.count;
  var windows = [];
  var labels  = [];
  var namelbs = [];

  // Create one overlay window per screen
  for (var i = 0; i < screenCount; i++) {
    var screen = screens.objectAtIndex(i);
    var sf = screen.frame;
    var sw = sf.size.width;
    var sh = sf.size.height;
    var sx = sf.origin.x;
    var sy = sf.origin.y;

    var winH = 120;
    var winY = sy + sh / 2 - winH / 2; // vertical center of screen

    var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
      $.NSMakeRect(sx, winY, sw, winH),
      $.NSWindowStyleMaskBorderless,
      $.NSBackingStoreBuffered,
      false
    );
    win.setBackgroundColor($.NSColor.clearColor);
    win.setOpaque(false);
    win.setHasShadow(false);
    win.setAlphaValue(1.0);
    win.setLevel($.NSStatusWindowLevel + 1);
    win.setIgnoresMouseEvents(true);
    win.setCollectionBehavior(
      $.NSWindowCollectionBehaviorCanJoinAllSpaces |
      $.NSWindowCollectionBehaviorStationary
    );
    win.contentView.wantsLayer = true;

    // Kart emoji label
    var kartLabel = $.NSTextField.alloc.initWithFrame(
      $.NSMakeRect(-120, 10, 100, 90)
    );
    kartLabel.setStringValue($('🏎'));
    kartLabel.setBezeled(false);
    kartLabel.setDrawsBackground(false);
    kartLabel.setEditable(false);
    kartLabel.setSelectable(false);
    kartLabel.setFont($.NSFont.systemFontOfSize(72));
    kartLabel.cell.setWraps(false);
    win.contentView.addSubview(kartLabel);

    // Character name label (above kart)
    var nameLabel = $.NSTextField.alloc.initWithFrame(
      $.NSMakeRect(-120, 82, 120, 20)
    );
    nameLabel.setStringValue($(ch.label));
    nameLabel.setBezeled(false);
    nameLabel.setDrawsBackground(false);
    nameLabel.setEditable(false);
    nameLabel.setSelectable(false);
    nameLabel.setTextColor(
      $.NSColor.colorWithSRGBRedGreenBlueAlpha(ch.r, ch.g, ch.b, 1.0)
    );
    nameLabel.setFont($.NSFont.boldSystemFontOfSize(13));
    nameLabel.setAlignment($.NSTextAlignmentCenter);
    win.contentView.addSubview(nameLabel);

    // Speed lines behind kart (3 horizontal streaks)
    for (var line = 0; line < 3; line++) {
      var lineY = 20 + line * 28;
      var streakView = $.NSView.alloc.initWithFrame(
        $.NSMakeRect(-300, lineY, 200, 4)
      );
      streakView.setWantsLayer(true);
      var streakLayer = streakView.layer;
      streakLayer.setBackgroundColor(
        $.NSColor.colorWithSRGBRedGreenBlueAlpha(ch.r, ch.g, ch.b, 0.4 - line * 0.1).CGColor
      );
      streakLayer.setCornerRadius(2);
      win.contentView.addSubview(streakView);
    }

    win.makeKeyAndOrderFront(null);
    windows.push(win);
    labels.push(kartLabel);
    namelbs.push(nameLabel);
  }

  // Animation state (mutable object accessible from ObjC timer callback)
  var state = {
    x: -150,
    speed: 10,
    frameCount: 0,
    screenWidths: []
  };
  for (var si = 0; si < screenCount; si++) {
    var sf2 = screens.objectAtIndex(si).frame;
    state.screenWidths.push(sf2.size.width);
  }

  ObjC.registerSubclass({
    name: 'MarioKartAnimator',
    superclass: 'NSObject',
    methods: {
      'tick:': {
        types: ['void', ['id']],
        implementation: function(timer) {
          // Check dismiss signal file
          if (!$.NSFileManager.defaultManager.fileExistsAtPath($(signalFile))) {
            timer.invalidate();
            $.NSApp.terminate(null);
            return;
          }

          state.x += state.speed;
          state.frameCount++;

          // Reset when fully off screen (use first screen width as reference)
          var maxW = state.screenWidths[0] || 1920;
          if (state.x > maxW + 150) {
            state.x = -150;
          }

          // Slight speed wobble for feel
          if (state.frameCount % 30 === 0) {
            state.speed = 9 + Math.random() * 3;
          }

          // Update all screen overlays
          for (var wi = 0; wi < labels.length; wi++) {
            var lbl = labels[wi];
            var nlbl = namelbs[wi];
            lbl.setFrame($.NSMakeRect(state.x, 10, 100, 90));
            nlbl.setFrame($.NSMakeRect(state.x - 10, 82, 120, 20));
          }
        }
      }
    }
  });

  var animator = $.MarioKartAnimator.alloc.init;
  $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
    1/60,       // 60fps
    animator,
    'tick:',
    null,
    true
  );

  $.NSApp.run;
}
```

**Step 2: Make executable and test**
```bash
chmod +x /Users/darshangupta/mario-ping/scripts/mac-kart-overlay.js
# Quick test (will show kart until you delete the signal file)
touch /tmp/mario-test-signal
osascript -l JavaScript /Users/darshangupta/mario-ping/scripts/mac-kart-overlay.js mario /tmp/mario-test-signal input.required &
sleep 4
rm /tmp/mario-test-signal
```

**Step 3: Commit**
```bash
cd /Users/darshangupta/mario-ping
git add scripts/mac-kart-overlay.js
git commit -m "feat: add animated Mario Kart kart overlay (JXA, 60fps NSTimer)"
```

---

### Task 4: Sound pack downloader + pack structure

**Files:**
- Create: `scripts/pack-download.sh`
- Create: `sounds/README.md`

The installer downloads Mario Kart Wii sound clips from GitHub releases. Fallback: macOS `say` command.

**Step 1: Write scripts/pack-download.sh**

```bash
#!/bin/bash
# mario-ping sound pack downloader
# Downloads Mario Kart sound files from GitHub releases
set -euo pipefail

MARIO_DIR="${1:-$HOME/.claude/hooks/mario-ping}"
SOUNDS_DIR="$MARIO_DIR/sounds"
REPO="darshangupta/mario-ping"
TAG="sounds-v1"

mkdir -p "$SOUNDS_DIR"

# Sound files to download (category → filename)
declare -A SOUNDS=(
  ["input.required"]="here-we-go.mp3"
  ["task.complete"]="course-clear.mp3"
  ["task.error"]="wah.mp3"
  ["session.start"]="race-start.mp3"
  ["resource.limit"]="blue-shell.mp3"
)

BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"

echo "Downloading Mario Kart sounds..."
for category in "${!SOUNDS[@]}"; do
  filename="${SOUNDS[$category]}"
  dest="$SOUNDS_DIR/$category.mp3"
  if [ -f "$dest" ]; then
    echo "  ✓ $category (already downloaded)"
    continue
  fi
  url="${BASE_URL}/${filename}"
  if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
    echo "  ✓ $category"
  else
    echo "  ⚠ $category (download failed, will use TTS fallback)"
    rm -f "$dest"
  fi
done
echo "Done."
```

**Step 2: Commit**
```bash
chmod +x /Users/darshangupta/mario-ping/scripts/pack-download.sh
cd /Users/darshangupta/mario-ping
git add scripts/pack-download.sh sounds/
git commit -m "feat: add sound pack downloader"
```

---

### Task 5: install.sh + uninstall.sh

**Files:**
- Create: `install.sh`
- Create: `uninstall.sh`

**Step 1: Write install.sh**

```bash
#!/bin/bash
# mario-ping installer — one-liner setup for Claude Code hooks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks/mario-ping"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "🏎  mario-ping installer"
echo ""

# Create hooks directory
mkdir -p "$HOOKS_DIR/scripts"

# Copy files
echo "Installing mario-ping to $HOOKS_DIR..."
cp "$SCRIPT_DIR/mario.sh" "$HOOKS_DIR/"
cp -r "$SCRIPT_DIR/scripts/"* "$HOOKS_DIR/scripts/"
[ -f "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"
# Copy config if not already there
if [ ! -f "$HOOKS_DIR/config.json" ]; then
  cp "$SCRIPT_DIR/config.json" "$HOOKS_DIR/"
fi
chmod +x "$HOOKS_DIR/mario.sh"

# Register Claude Code hooks in settings.json
python3 - <<PYEOF
import json, os

settings_path = '$SETTINGS_FILE'
hook_script = '$HOOKS_DIR/mario.sh'

try:
    with open(settings_path) as f:
        settings = json.load(f)
except:
    settings = {}

hooks = settings.setdefault('hooks', {})

# Events to hook
hook_events = ['Notification', 'Stop', 'SessionStart', 'UserPromptSubmit']
for event in hook_events:
    existing = hooks.get(event, [])
    # Remove old mario-ping entries
    existing = [h for h in existing if isinstance(h, dict) and 'mario-ping' not in str(h.get('command', ''))]
    # Add new
    existing.append({
        'matcher': '',
        'hooks': [{'type': 'command', 'command': hook_script}]
    })
    hooks[event] = existing

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
print('✓ Claude Code hooks registered')
PYEOF

# Download sounds
echo ""
bash "$SCRIPT_DIR/scripts/pack-download.sh" "$HOOKS_DIR"

echo ""
echo "✅ mario-ping installed!"
echo ""
echo "Commands:"
echo "  mario test     — test sounds + kart animation"
echo "  mario toggle   — pause/unpause"
echo "  mario status   — check status"
echo ""
echo "Restart Claude Code to activate hooks."
```

**Step 2: Write uninstall.sh**

```bash
#!/bin/bash
set -euo pipefail
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks/mario-ping"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "Uninstalling mario-ping..."

# Remove hook entries from settings.json
python3 - <<PYEOF
import json
try:
    with open('$SETTINGS_FILE') as f:
        settings = json.load(f)
    hooks = settings.get('hooks', {})
    for event in list(hooks.keys()):
        hooks[event] = [h for h in hooks[event]
                        if isinstance(h, dict) and 'mario-ping' not in str(h)]
        if not hooks[event]:
            del hooks[event]
    with open('$SETTINGS_FILE', 'w') as f:
        json.dump(settings, f, indent=2)
    print('✓ Hooks removed from settings.json')
except Exception as e:
    print(f'Warning: {e}')
PYEOF

rm -rf "$HOOKS_DIR"
echo "✓ mario-ping uninstalled."
```

**Step 3: Commit**
```bash
chmod +x /Users/darshangupta/mario-ping/install.sh /Users/darshangupta/mario-ping/uninstall.sh
cd /Users/darshangupta/mario-ping
git add install.sh uninstall.sh
git commit -m "feat: add install/uninstall scripts with Claude Code hook registration"
```

---

### Task 6: CLI commands (mario toggle/test/status)

**Files:**
- Modify: `mario.sh` (add CLI subcommand handling at top)

**Step 1: Add CLI block to mario.sh (before the hook event parsing)**

Add after the function definitions, before `INPUT=$(cat)`:

```bash
# --- CLI subcommands ---
if [ "${1:-}" != "" ]; then
  case "${1:-}" in
    toggle)
      if [ -f "$MARIO_DIR/.paused" ]; then
        rm "$MARIO_DIR/.paused"
        echo "mario-ping: ON — Here we go! 🏎"
      else
        touch "$MARIO_DIR/.paused"
        echo "mario-ping: paused"
      fi
      exit 0
      ;;
    status)
      if [ -f "$MARIO_DIR/.paused" ]; then
        echo "mario-ping: PAUSED"
      else
        echo "mario-ping: ACTIVE"
        echo "Character: $(get_config 'character' 'mario')"
        echo "Volume: $(get_config 'volume' '0.7')"
      fi
      exit 0
      ;;
    test)
      echo "Testing mario-ping..."
      # Play a sound
      sound=$(get_sound "input.required")
      if [ -n "$sound" ]; then
        play_sound "$sound" "$VOLUME"
        echo "Playing sound: $sound"
      else
        say_fallback "Here we go"
        echo "Playing TTS fallback: 'Here we go'"
      fi
      # Show kart for 4 seconds
      if [ "$PLATFORM" = "mac" ]; then
        overlay="$SCRIPTS_DIR/mac-kart-overlay.js"
        if [ -f "$overlay" ]; then
          signal="/tmp/mario-ping-test-$$"
          touch "$signal"
          echo "Showing kart animation for 4 seconds..."
          osascript -l JavaScript "$overlay" "$(get_config 'character' 'mario')" "$signal" "test" &>/dev/null &
          sleep 4
          rm -f "$signal"
          echo "Done."
        fi
      fi
      exit 0
      ;;
    install)
      bash "$(dirname "${BASH_SOURCE[0]}")/install.sh"
      exit 0
      ;;
    *)
      echo "Usage: mario [toggle|status|test|install]"
      exit 1
      ;;
  esac
fi
```

**Step 2: Create mario symlink for CLI use**
```bash
# In install.sh, add: ln -sf "$HOOKS_DIR/mario.sh" /usr/local/bin/mario
# For now, users can alias it
```

**Step 3: Commit**
```bash
cd /Users/darshangupta/mario-ping
git add mario.sh
git commit -m "feat: add CLI subcommands (toggle, status, test, install)"
```

---

### Task 7: README.md

**Files:**
- Create: `README.md`

**Step 1: Write README.md**

```markdown
# 🏎 mario-ping

**Mario Kart Wii sounds + animated kart overlay for your AI coding agent.**

When Claude Code (or any AI agent) needs your attention, a Mario Kart character drives across the middle of your screen and Mario Kart sounds blast. Inspired by [peon-ping](https://github.com/PeonPing/peon-ping).

## Demo

```
[kart animation: Mario drives across screen]
🏎 MARIO ═══════════════════════════════════════════►
```

## Install

```bash
git clone https://github.com/darshangupta/mario-ping
cd mario-ping
bash install.sh
```

Then restart Claude Code.

## How it works

mario-ping hooks into Claude Code's event system. When the agent goes idle and needs your input, it:
1. Plays a Mario Kart sound (or uses macOS TTS fallback)
2. Shows an animated kart driving across the middle of your screen
3. Kart disappears when you submit your next message

## Characters

Set `"character"` in `~/.claude/hooks/mario-ping/config.json`:

| Character | Value |
|-----------|-------|
| Mario | `mario` |
| Luigi | `luigi` |
| Toad | `toad` |
| Yoshi | `yoshi` |
| Princess Peach | `peach` |
| Bowser | `bowser` |
| Waluigi | `waluigi` |
| Rosalina | `rosalina` |
| Donkey Kong | `donkey` |

## Commands

```bash
mario toggle    # pause/unpause
mario status    # check status
mario test      # test sound + kart animation
```

## Config

`~/.claude/hooks/mario-ping/config.json`:

```json
{
  "volume": 0.7,
  "character": "mario",
  "kart_speed": 10
}
```

## Sounds

Sounds download automatically from GitHub releases. Without sounds, falls back to macOS TTS (`say` command).

## Platform

- macOS: full support (sounds + kart animation)
- Linux: sounds only (no JXA overlay)
- Windows: not yet

## License

MIT
```

**Step 2: Commit**
```bash
cd /Users/darshangupta/mario-ping
git add README.md
git commit -m "docs: add README"
```

---

### Task 8: Create GitHub repo + push

**Step 1: Create GitHub repo**
```bash
cd /Users/darshangupta/mario-ping
gh repo create mario-ping --public --description "Mario Kart Wii sounds + animated kart overlay for Claude Code and AI coding agents" --source . --push
```

**Step 2: Verify**
```bash
gh repo view darshangupta/mario-ping
```

---

### Task 9: Test end-to-end

**Step 1: Run install**
```bash
cd /Users/darshangupta/mario-ping
bash install.sh
```

**Step 2: Test kart**
```bash
mario test
# Should show kart animation for 4s + play sound or TTS
```

**Step 3: Simulate hook event**
```bash
echo '{"hook_event_name":"Notification","notification_type":"idle","session_id":"test"}' | bash ~/.claude/hooks/mario-ping/mario.sh
```

**Step 4: Verify hooks in settings.json**
```bash
cat ~/.claude/settings.json | python3 -m json.tool | grep -A5 mario
```

---

## Notes

- The kart animation uses `ObjC.registerSubclass` in JXA with a mutable state object (`var state = { x: -150, ... }`) that the NSTimer callback closes over — this is the key to making 60fps animation work in JXA without needing real ObjC properties
- Signal file mechanism: kart overlay polls for signal file deletion every frame; when `UserPromptSubmit` hook fires, mario.sh deletes the signal file and the kart exits
- Sound files are named by category (`input.required.mp3`, `task.complete.mp3`, etc.) for easy customization
