#!/usr/bin/env bash
# Installer for arcade-statusline (Rust binary)
# Usage: bash install.sh [--theme pacman|pikmin]
set -euo pipefail

# ── Parse arguments ─────────────────────────────────────────────────────────
ARG_THEME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --theme) ARG_THEME="$2"; shift 2 ;;
    *) shift ;;
  esac
done

CLAUDE_DIR="$HOME/.claude"
BIN_NAME="arcade-statusline"
TARGET="$CLAUDE_DIR/$BIN_NAME"
SETTINGS="$CLAUDE_DIR/settings.json"
BASE_URL="https://github.com/sorosora/arcade-statusline/releases/latest/download"

# Colours for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { printf "${GREEN}[+]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$1"; }
error() { printf "${RED}[x]${NC} %s\n" "$1"; }

# ── Check dependencies ──────────────────────────────────────────────────────
if ! command -v curl &>/dev/null; then
  error "curl is required but not installed. Aborting."
  exit 1
fi

# ── Detect platform ─────────────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin) OS_TAG="apple-darwin" ;;
  Linux)  OS_TAG="unknown-linux-gnu" ;;
  *)      error "Unsupported OS: $OS"; exit 1 ;;
esac

case "$ARCH" in
  arm64|aarch64) ARCH_TAG="aarch64" ;;
  x86_64)        ARCH_TAG="x86_64" ;;
  *)             error "Unsupported architecture: $ARCH"; exit 1 ;;
esac

ARCHIVE="${BIN_NAME}-${ARCH_TAG}-${OS_TAG}.tar.xz"
DOWNLOAD_URL="${BASE_URL}/${ARCHIVE}"

info "Detected platform: ${ARCH_TAG}-${OS_TAG}"

# ── Create directory ────────────────────────────────────────────────────────
mkdir -p "$CLAUDE_DIR"

# ── Backup existing binary ──────────────────────────────────────────────────
if [ -f "$TARGET" ]; then
  backup="$TARGET.bak.$(date +%Y%m%d%H%M%S)"
  cp "$TARGET" "$backup"
  info "Backed up existing $BIN_NAME to $(basename "$backup")"
fi

# ── Install binary ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_BIN="$SCRIPT_DIR/target/release/$BIN_NAME"

if [ -f "$LOCAL_BIN" ]; then
  info "Found local build: $LOCAL_BIN"
  cp "$LOCAL_BIN" "$TARGET"
  chmod +x "$TARGET"
  info "Copied to $TARGET"
else
  info "Downloading $ARCHIVE..."
  TMPDIR=$(mktemp -d)
  if curl -fsSL -L "$DOWNLOAD_URL" -o "$TMPDIR/$ARCHIVE"; then
    tar -xf "$TMPDIR/$ARCHIVE" -C "$TMPDIR"
    cp "$TMPDIR/$BIN_NAME" "$TARGET"
    chmod +x "$TARGET"
    rm -rf "$TMPDIR"
    info "Saved to $TARGET"
  else
    rm -rf "$TMPDIR"
    error "Failed to download $ARCHIVE"
    error "URL: $DOWNLOAD_URL"
    exit 1
  fi
fi

# ── Theme selection ─────────────────────────────────────────────────────────
SAMPLE='{"model":"Claude Opus 4.6","version":"1.0.0","context_window":{"used_percentage":35,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":28,"resets_at":'"$(( $(date +%s) + 7200 ))"'},"seven_day":{"used_percentage":15,"resets_at":'"$(( $(date +%s) + 259200 ))"'}}}'

echo ""
echo "  Choose a theme:"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │  1) Pac-Man                                                     │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""
echo "$SAMPLE" | "$TARGET" --theme pacman
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────┐"
echo "  │  2) Pikmin Bloom                                                │"
echo "  └─────────────────────────────────────────────────────────────────┘"
echo ""
echo "$SAMPLE" | "$TARGET" --theme pikmin
echo ""

if [ -n "$ARG_THEME" ]; then
  THEME="$ARG_THEME"
else
  printf "  Enter choice [1/2] (default: 1): "
  read -r choice </dev/tty
  case "$choice" in
    2) THEME="pikmin" ;;
    *) THEME="pacman" ;;
  esac
fi

info "Selected theme: $THEME"

# ── Configure settings.json ─────────────────────────────────────────────────
STATUS_CMD="$TARGET --theme $THEME"

if command -v jq &>/dev/null; then
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

# ── Done ────────────────────────────────────────────────────────────────────
echo ""
info "Installation complete!"
echo ""
echo "  The statusline will appear automatically in Claude Code."
echo "  To change theme later, run the installer again or edit"
echo "  --theme in $SETTINGS"
echo ""
