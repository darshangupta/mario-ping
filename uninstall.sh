#!/bin/bash
set -euo pipefail
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks/mario-ping"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "Uninstalling mario-ping..."

# Remove hook entries from settings.json
if [ -f "$SETTINGS_FILE" ]; then
  python3 - <<'PYEOF'
import json, os

settings_path = os.environ.get('SETTINGS_FILE', os.path.expanduser('~/.claude/settings.json'))
try:
    with open(settings_path) as f:
        settings = json.load(f)
    hooks = settings.get('hooks', {})
    for event in list(hooks.keys()):
        if isinstance(hooks[event], list):
            hooks[event] = [h for h in hooks[event]
                            if not (isinstance(h, dict) and 'mario-ping' in str(h.get('hooks', '')))]
            if not hooks[event]:
                del hooks[event]
    if not hooks:
        del settings['hooks']
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
    print('✓ Hooks removed from', settings_path)
except Exception as e:
    print(f'Warning: {e}')
PYEOF
fi

# Remove hooks dir
rm -rf "$HOOKS_DIR"
echo "✓ Removed $HOOKS_DIR"

# Remove symlink
rm -f /usr/local/bin/mario
echo "✓ mario-ping uninstalled."
