#!/usr/bin/env bash
# Demo script for arcade-statusline — shows all states side by side
# Useful for debugging and verifying different scenarios.
set -euo pipefail

BIN="${1:-$HOME/.claude/arcade-statusline}"
CHOMP="/tmp/.claude-pacman-chomp"
PIKMIN_ANIM="/tmp/.claude-pikmin-anim"
PIKMIN_STATE="/tmp/.claude-statusline-state.json"
NOW=$(date +%s)
SLOT_SEC=$((15 * 60))
SLOT=$((NOW / SLOT_SEC))

DIM='\033[2m'
NC='\033[0m'

# ── Backup real state ───────────────────────────────────────────────────────
backup_file() { [ -f "$1" ] && cp "$1" "$1.demo-bak"; }
restore_file() { [ -f "$1.demo-bak" ] && mv "$1.demo-bak" "$1" || rm -f "$1"; }

backup_file "$CHOMP"
backup_file "$PIKMIN_ANIM"
backup_file "$PIKMIN_STATE"

cleanup() {
  restore_file "$CHOMP"
  restore_file "$PIKMIN_ANIM"
  restore_file "$PIKMIN_STATE"
}
trap cleanup EXIT

show() {
  local title="$1" theme="$2" json="$3" anim="${4:-}"
  echo ""
  echo -e "  ${DIM}── ${title} ──${NC}"
  echo ""
  if [ -n "$anim" ]; then
    printf '%s' "$anim" >| "$CHOMP" 2>/dev/null || true
    printf '%s' "$anim" >| "$PIKMIN_ANIM" 2>/dev/null || true
  fi
  echo "$json" | "$BIN" --theme "$theme"
  echo ""
}

# ── Pac-Man scenarios ───────────────────────────────────────────────────────

TITLE="\033[1;33m  === Pac-Man Theme ===\033[0m"
echo ""
echo -e "$TITLE"

show "Fresh start (ctx 5%, ghost caged)" pacman \
  '{"model":"Opus 4.6","version":"1.0.33","context_window":{"used_percentage":5,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'"$((NOW+7200))"'},"seven_day":{"used_percentage":8,"resets_at":'"$((NOW+259200))"'}}}' \
  "0"

show "Mid session (ctx 55%, 7d ghost released)" pacman \
  '{"model":"Opus 4.6","version":"1.0.33","context_window":{"used_percentage":55,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":38,"resets_at":'"$((NOW+5400))"'},"seven_day":{"used_percentage":62,"resets_at":'"$((NOW+172800))"'}}}' \
  "1"

show "Heavy usage (ctx 90%, ghosts closing in)" pacman \
  '{"model":"Opus 4.6","version":"1.0.33","context_window":{"used_percentage":90,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":85,"resets_at":'"$((NOW+1800))"'},"seven_day":{"used_percentage":72,"resets_at":'"$((NOW+86400))"'}}}' \
  "0"

show "GAME OVER (5h rate limit hit 100%)" pacman \
  '{"model":"Opus 4.6","version":"1.0.33","context_window":{"used_percentage":75,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":'"$((NOW+3600))"'},"seven_day":{"used_percentage":60,"resets_at":'"$((NOW+172800))"'}}}' \
  "0"

# ── Pikmin Bloom scenarios ──────────────────────────────────────────────────

TITLE="\033[1;32m  === Pikmin Bloom Theme ===\033[0m"
echo ""
echo -e "$TITLE"

build_pikmin_state() {
  local slots="{"
  local first=true
  for offset in $(seq 36 -1 0); do
    local s=$((SLOT - offset))
    local consumed="false"
    if (( offset < 8 )); then consumed="true"
    elif (( offset < 16 && offset % 2 == 0 )); then consumed="true"
    elif (( offset < 24 && offset % 3 == 0 )); then consumed="true"
    fi
    if [ "$first" = true ]; then first=false; else slots+=","; fi
    slots+="\"$s\":{\"consumed\":$consumed}"
  done
  slots+="}"
  echo "{\"slots\":$slots,\"sessions\":{}}"
}

build_pikmin_state >| "$PIKMIN_STATE" 2>/dev/null || true

show "Blooming trail (active session)" pikmin \
  '{"model":"Opus 4.6","version":"1.0.33","context_window":{"used_percentage":35,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":28,"resets_at":'"$((NOW+1800))"'},"seven_day":{"used_percentage":15,"resets_at":'"$((NOW+259200))"'}}}' \
  "0"

build_idle_state() {
  local slots="{"
  local first=true
  for offset in $(seq 36 -1 0); do
    local s=$((SLOT - offset))
    local consumed="false"
    if (( offset == 32 || offset == 24 || offset == 16 )); then consumed="true"; fi
    if [ "$first" = true ]; then first=false; else slots+=","; fi
    slots+="\"$s\":{\"consumed\":$consumed}"
  done
  slots+="}"
  echo "{\"slots\":$slots,\"sessions\":{}}"
}

build_idle_state >| "$PIKMIN_STATE" 2>/dev/null || true

show "Sparse trail (mostly idle)" pikmin \
  '{"model":"Opus 4.6","version":"1.0.33","context_window":{"used_percentage":12,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":8,"resets_at":'"$((NOW+14400))"'},"seven_day":{"used_percentage":5,"resets_at":'"$((NOW+518400))"'}}}' \
  "1"

build_ratelimit_state() {
  local slots="{"
  local first=true
  for offset in $(seq 36 -1 0); do
    local s=$((SLOT - offset))
    local consumed="false"
    if (( offset > 3 )); then consumed="true"; fi
    if [ "$first" = true ]; then first=false; else slots+=","; fi
    slots+="\"$s\":{\"consumed\":$consumed}"
  done
  slots+="}"
  echo "{\"slots\":$slots,\"sessions\":{}}"
}

build_ratelimit_state >| "$PIKMIN_STATE" 2>/dev/null || true

show "Rate limit hit (flowers blocked)" pikmin \
  '{"model":"Opus 4.6","version":"1.0.33","context_window":{"used_percentage":60,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":'"$((NOW+2700))"'},"seven_day":{"used_percentage":72,"resets_at":'"$((NOW+86400))"'}}}' \
  "0"

echo ""
