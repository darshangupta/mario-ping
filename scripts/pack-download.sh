#!/bin/bash
# mario-ping sound pack downloader
# Downloads Mario Kart sound clips from GitHub releases
set -uo pipefail

MARIO_DIR="${1:-$HOME/.claude/hooks/mario-ping}"
SOUNDS_DIR="$MARIO_DIR/sounds"
REPO="darshangupta/mario-ping"
TAG="sounds-v1"

mkdir -p "$SOUNDS_DIR"

BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"

# category:filename pairs (bash 3.2 compatible — no associative arrays)
SOUND_PAIRS="
input.required:here-we-go.mp3
task.complete:course-clear.mp3
task.error:wah.mp3
session.start:race-start.mp3
resource.limit:blue-shell.mp3
"

echo "Downloading Mario Kart sounds..."
any_downloaded=false
while IFS=: read -r category filename; do
  [ -z "$category" ] && continue
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
done <<EOF
$SOUND_PAIRS
EOF

if [ "$any_downloaded" = false ]; then
  echo ""
  echo "  No sounds downloaded yet. mario-ping will use macOS TTS ('say' command) until"
  echo "  sounds are published at: https://github.com/${REPO}/releases/tag/${TAG}"
fi
echo ""
