#!/bin/bash
# mario-ping sound pack downloader
# Downloads Mario Kart sound clips from GitHub releases
set -uo pipefail

MARIO_DIR="${1:-$HOME/.claude/hooks/mario-ping}"
SOUNDS_DIR="$MARIO_DIR/sounds"
REPO="darshangupta/mario-ping"
TAG="sounds-v1"

mkdir -p "$SOUNDS_DIR"

# Map: category name → release asset filename
declare -A SOUNDS
SOUNDS["input.required"]="here-we-go.mp3"
SOUNDS["task.complete"]="course-clear.mp3"
SOUNDS["task.error"]="wah.mp3"
SOUNDS["session.start"]="race-start.mp3"
SOUNDS["resource.limit"]="blue-shell.mp3"

BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"

echo "Downloading Mario Kart sounds..."
any_downloaded=false
for category in "${!SOUNDS[@]}"; do
  filename="${SOUNDS[$category]}"
  dest="$SOUNDS_DIR/${category}.mp3"
  if [ -f "$dest" ]; then
    echo "  ✓ ${category} (cached)"
    any_downloaded=true
    continue
  fi
  url="${BASE_URL}/${filename}"
  if curl -fsSL --connect-timeout 5 "$url" -o "$dest" 2>/dev/null; then
    echo "  ✓ ${category}"
    any_downloaded=true
  else
    echo "  ~ ${category} (will use TTS fallback — sounds release not yet published)"
    rm -f "$dest"
  fi
done

if [ "$any_downloaded" = false ]; then
  echo ""
  echo "  No sounds downloaded yet. mario-ping will use macOS TTS ('say' command) until"
  echo "  sounds are published at: https://github.com/${REPO}/releases/tag/${TAG}"
fi
echo ""
