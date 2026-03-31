#!/usr/bin/env bash
# Installer for Pac-Man inspired Claude Code statusline
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SCRIPT_NAME="statusline.sh"
TARGET="$CLAUDE_DIR/$SCRIPT_NAME"
SETTINGS="$CLAUDE_DIR/settings.json"
RAW_URL="https://github.com/sorosora/arcade-statusline/releases/latest/download/statusline.sh"

# Colours for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { printf "${GREEN}[+]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$1"; }
error() { printf "${RED}[x]${NC} %s\n" "$1"; }

# ── Check dependencies ──────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  warn "jq is not installed. The statusline requires jq to function."
  warn "Install it with: brew install jq (macOS) or apt install jq (Linux)"
fi

if ! command -v curl &>/dev/null; then
  error "curl is required but not installed. Aborting."
  exit 1
fi

# ── Create directory ────────────────────────────────────────────────────────
mkdir -p "$CLAUDE_DIR"

# ── Backup existing script ──────────────────────────────────────────────────
if [ -f "$TARGET" ]; then
  backup="$TARGET.bak.$(date +%Y%m%d%H%M%S)"
  cp "$TARGET" "$backup"
  info "Backed up existing $SCRIPT_NAME to $(basename "$backup")"
fi

# ── Download statusline.sh ──────────────────────────────────────────────────
info "Downloading $SCRIPT_NAME..."
if curl -fsSL "$RAW_URL" -o "$TARGET"; then
  chmod +x "$TARGET"
  info "Saved to $TARGET"
else
  error "Failed to download $SCRIPT_NAME"
  exit 1
fi

# ── Configure settings.json ─────────────────────────────────────────────────
STATUS_CMD="bash $TARGET"

if command -v jq &>/dev/null; then
  # Use jq to safely merge settings
  if [ -f "$SETTINGS" ]; then
    existing=$(cat "$SETTINGS")
    current_cmd=$(echo "$existing" | jq -r '.statusLine.command // empty')
    if [ "$current_cmd" = "$STATUS_CMD" ]; then
      info "settings.json already configured (no changes needed)"
    else
      merged=$(echo "$existing" | jq --arg cmd "$STATUS_CMD" '.statusLine = {"type": "command", "command": $cmd}')
      echo "$merged" > "$SETTINGS"
      info "Updated statusLine command in $SETTINGS"
    fi
  else
    jq -n --arg cmd "$STATUS_CMD" '{"statusLine": {"type": "command", "command": $cmd}}' > "$SETTINGS"
    info "Created $SETTINGS with statusLine config"
  fi
else
  # Fallback without jq: manual check and write
  if [ -f "$SETTINGS" ]; then
    if grep -q "statusLine" "$SETTINGS" 2>/dev/null; then
      warn "settings.json exists and already has statusLine config."
      warn "Please manually set statusLine.command to: $STATUS_CMD"
    else
      warn "settings.json exists but jq is not available to safely merge."
      warn "Please manually add to $SETTINGS:"
      echo "  \"statusLine\": { \"command\": \"$STATUS_CMD\" }"
    fi
  else
    cat > "$SETTINGS" <<JSONEOF
{
  "statusLine": {
    "type": "command",
    "command": "$STATUS_CMD"
  }
}
JSONEOF
    info "Created $SETTINGS with statusLine config"
  fi
fi

# ── Generate default config ─────────────────────────────────────────────────
CONF_FILE="$CLAUDE_DIR/arcade-statusline.conf"
if [ ! -f "$CONF_FILE" ]; then
  cat > "$CONF_FILE" <<'CONFEOF'
# Arcade Statusline Configuration
# DISPLAY_MODE: "remaining" (default) or "used"
DISPLAY_MODE=remaining
# MAX_WIDTH: maximum header line width (default: 54)
MAX_WIDTH=54
CONFEOF
  info "Created default config at $CONF_FILE"
else
  info "Config file already exists (no changes needed)"
fi

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
info "Installation complete!"
echo ""
echo "  The Pac-Man statusline will appear automatically in Claude Code."
echo "  To preview it manually:"
echo ""
echo "    echo '{}' | bash $TARGET"
echo ""
