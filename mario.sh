#!/bin/bash
# mario-ping: Mario Kart Wii sounds + animated kart overlay for Claude Code hooks
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
SCRIPTS_DIR="$MARIO_DIR/scripts"
SOUNDS_DIR="$MARIO_DIR/sounds"
ASSETS_DIR="$MARIO_DIR/assets"

# --- Platform ---
detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}
PLATFORM=$(detect_platform)

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

# --- TTS fallback (macOS) ---
say_fallback() {
  local text="$1"
  [ "$PLATFORM" = "mac" ] && say "$text" &>/dev/null &
}

# --- Get sound file for category ---
get_sound() {
  local category="$1"
  local f
  for ext in mp3 wav ogg; do
    f="$SOUNDS_DIR/${category}.${ext}"
    [ -f "$f" ] && { echo "$f"; return; }
  done
  echo ""
}

# --- Show kart overlay (async) ---
# sprite: kart, green-shell, red-shell (default: kart)
show_kart() {
  local sprite="${1:-kart}"
  local overlay="$SCRIPTS_DIR/mac-kart-overlay.js"
  [ ! -f "$overlay" ] && return 0
  [ "$PLATFORM" != "mac" ] && return 0
  local signal="/tmp/mario-ping-kart-signal-$$"
  touch "$signal"
  osascript -l JavaScript "$overlay" "$sprite" "$signal" "$ASSETS_DIR" &>/dev/null &
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

# --- CLI subcommands ---
if [ "${1:-}" != "" ]; then
  VOLUME=$(get_config "volume" "0.7")
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
        echo "  Character : $(get_config 'character' 'mario')"
        echo "  Volume    : $(get_config 'volume' '0.7')"
      fi
      exit 0
      ;;
    test)
      echo "Testing mario-ping..."
      sound=$(get_sound "input.required")
      if [ -n "$sound" ]; then
        play_sound "$sound" "$VOLUME"
        echo "  Playing sound: $sound"
      else
        say_fallback "Here we go"
        echo "  Playing TTS fallback: 'Here we go'"
      fi
      if [ "$PLATFORM" = "mac" ]; then
        overlay="$SCRIPTS_DIR/mac-kart-overlay.js"
        if [ -f "$overlay" ]; then
          sprite=$(get_config "sprite" "kart")
          signal="/tmp/mario-ping-test-$$"
          touch "$signal"
          echo "  Showing $sprite animation for 4 seconds..."
          osascript -l JavaScript "$overlay" "$sprite" "$signal" "$ASSETS_DIR" &>/dev/null &
          sleep 4
          rm -f "$signal"
          echo "  Done."
        else
          echo "  Overlay script not found: $overlay"
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

# --- Parse hook event from stdin ---
INPUT=$(cat)

EVENT=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    e = d.get('hook_event_name', '')
    ntype = d.get('notification_type', '')
    if e == 'Notification':            print('input.required')
    elif e == 'Stop':                  print('task.complete')
    elif e == 'SessionStart':          print('session.start')
    elif e == 'UserPromptSubmit':      print('user.submit')
    else:                              print('ignore')
except: print('ignore')
" 2>/dev/null)

# Check enabled
ENABLED=$(get_config "enabled" "true")
[ "$ENABLED" = "false" ] && exit 0

# Check paused
[ -f "$MARIO_DIR/.paused" ] && exit 0

VOLUME=$(get_config "volume" "0.7")

case "$EVENT" in
  input.required)
    sound=$(get_sound "input.required")
    if [ -n "$sound" ]; then
      play_sound "$sound" "$VOLUME"
    else
      say_fallback "Here we go"
    fi
    show_kart "$(get_config 'sprite' 'kart')"
    ;;
  task.complete)
    dismiss_kart
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
    dismiss_kart
    ;;
  *)
    exit 0
    ;;
esac

exit 0
