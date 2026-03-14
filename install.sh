#!/bin/bash
# mario-ping installer — sets up Claude Code hooks and downloads sounds
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks/mario-ping"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "🏎  mario-ping installer"
echo ""

# Create hooks directory
mkdir -p "$HOOKS_DIR/scripts" "$HOOKS_DIR/sounds"

# Copy core files
echo "Installing to $HOOKS_DIR ..."
cp "$SCRIPT_DIR/mario.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/scripts/mac-kart-overlay.js" "$HOOKS_DIR/scripts/"
cp "$SCRIPT_DIR/scripts/pack-download.sh" "$HOOKS_DIR/scripts/"
chmod +x "$HOOKS_DIR/mario.sh" "$HOOKS_DIR/scripts/pack-download.sh"

# Copy config only if not already present (preserve user customizations)
if [ ! -f "$HOOKS_DIR/config.json" ]; then
  cp "$SCRIPT_DIR/config.json" "$HOOKS_DIR/"
fi

# Create settings.json if missing
[ -f "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"

# Register Claude Code hooks
python3 - <<'PYEOF'
import json, os, sys

settings_path = os.environ.get('SETTINGS_FILE', os.path.expanduser('~/.claude/settings.json'))
hooks_dir = os.environ.get('HOOKS_DIR', os.path.expanduser('~/.claude/hooks/mario-ping'))
hook_script = os.path.join(hooks_dir, 'mario.sh')

try:
    with open(settings_path) as f:
        settings = json.load(f)
except Exception:
    settings = {}

hooks = settings.setdefault('hooks', {})

for event in ['Notification', 'Stop', 'SessionStart', 'UserPromptSubmit']:
    existing = hooks.get(event, [])
    if not isinstance(existing, list):
        existing = []
    # Remove old mario-ping entries
    existing = [h for h in existing
                if not (isinstance(h, dict) and 'mario-ping' in str(h.get('hooks', '')))]
    existing.append({
        'matcher': '',
        'hooks': [{'type': 'command', 'command': hook_script}]
    })
    hooks[event] = existing

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
print('✓ Claude Code hooks registered in', settings_path)
PYEOF

# Download sounds
echo ""
bash "$SCRIPT_DIR/scripts/pack-download.sh" "$HOOKS_DIR"

# Create mario CLI symlink
if [ -w /usr/local/bin ]; then
  ln -sf "$HOOKS_DIR/mario.sh" /usr/local/bin/mario
  echo "✓ mario CLI installed at /usr/local/bin/mario"
else
  echo "  Tip: add to your shell: alias mario='$HOOKS_DIR/mario.sh'"
fi

echo ""
echo "✅ mario-ping installed! Restart Claude Code to activate."
echo ""
echo "  mario test      — show kart + play sound"
echo "  mario toggle    — pause/unpause"
echo "  mario status    — check status"
