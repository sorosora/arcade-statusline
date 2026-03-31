#!/usr/bin/env bash
# Demo script for arcade-statusline — animated simulation
# Simulates a 10-hour Claude Code session (40 frames × 15 min/frame).
# Usage: bash demo.sh [--theme pacman|pikmin]
set -euo pipefail

# ── Parse arguments ─────────────────────────────────────────────────────────
THEME="pacman"
BIN="$HOME/.claude/arcade-statusline"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --theme) THEME="$2"; shift 2 ;;
    *) BIN="$1"; shift ;;
  esac
done

CHOMP="/tmp/.claude-pacman-chomp"
PIKMIN_ANIM="/tmp/.claude-pikmin-anim"
PIKMIN_STATE="/tmp/.claude-statusline-state.json"

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
  tput cnorm 2>/dev/null || true
}
trap cleanup EXIT

# ── Constants ───────────────────────────────────────────────────────────────
NOW=$(date +%s)
SLOT=$((NOW / 900))
TOTAL_FRAMES=40   # 40 × 15 min = 10 hours

# 5h rate limit resets at frame 20 (5 hours in) and frame 40 (10 hours)
# These are absolute epoch times; the binary's now_epoch() is shifted by
# --slot-offset, so the countdown will tick down naturally each frame.
FIVE_RESET_FRAME=20
FIVE_RESET_EPOCH=$((NOW + FIVE_RESET_FRAME * 900))
FIVE_RESET2_EPOCH=$((NOW + 40 * 900))
# 7d resets in 6 days from simulated start
SEVEN_RESET_EPOCH=$((NOW + 518400))

# ── Activity pattern ────────────────────────────────────────────────────────
# Per-frame data: context_used%, is_active (1=flower, 0=dot)
# Pattern: morning work → compact → lunch → afternoon → 5h reset → more work → break → evening
#
# Frame:  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40
CTX_USED=(  0 12 25 38 50 63 75 88  3  8 15 22 35 48 60 72 85 92 95 97  2 10 22 35 48 60 72 80 80 80 80 80  5 15 30 48 65 78 88 94 97)
ACTIVE=(    1  1  1  1  1  1  1  1  0  0  0  0  1  1  1  1  1  1  1  1  1  1  1  1  0  0  0  0  1  1  1  1  1  1  1  1  1  1  1  1  1)

# 5h rate limit %: builds up to 100% at frame 20 (reset), then builds again
five_for_frame() {
  local f=$1
  if (( f < FIVE_RESET_FRAME )); then
    echo $(( f * 100 / FIVE_RESET_FRAME ))
  else
    echo $(( (f - FIVE_RESET_FRAME) * 100 / FIVE_RESET_FRAME ))
  fi
}

# 7d rate limit %: slowly builds up
seven_for_frame() {
  local f=$1
  echo $(( f * 50 / TOTAL_FRAMES ))
}

# ── Rendering ───────────────────────────────────────────────────────────────
SAMPLE_JSON='{"model":"x","version":"1","context_window":{"used_percentage":50,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":'"$FIVE_RESET_EPOCH"'},"seven_day":{"used_percentage":50,"resets_at":'"$SEVEN_RESET_EPOCH"'}}}'
LINES=$(echo "$SAMPLE_JSON" | "$BIN" --theme "$THEME" | wc -l | tr -d ' ')

FIRST_RENDER=true

render() {
  local ctx_pct="$1" five_pct="$2" seven_pct="$3" five_reset="$4" seven_reset="$5" slot_offset="${6:-0}"

  local json='{"model":"Opus 4.6","version":"1.0.33","context_window":{"used_percentage":'"$ctx_pct"',"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":'"$five_pct"',"resets_at":'"$five_reset"'},"seven_day":{"used_percentage":'"$seven_pct"',"resets_at":'"$seven_reset"'}}}'

  if [ "$FIRST_RENDER" = false ]; then
    for _ in $(seq 1 "$LINES"); do
      printf '\033[A\033[2K'
    done
  fi
  FIRST_RENDER=false

  echo "$json" | "$BIN" --theme "$THEME" --slot-offset "$slot_offset"
}

# Build pikmin state based on activity pattern
write_pikmin_state() {
  local current_frame="$1"
  local virtual_slot=$((SLOT + current_frame))
  local out='{"slots":{'
  local first=true
  local s f offset consumed
  # Cover wide range
  for s in $(seq -f '%.0f' $((virtual_slot - 50)) $((virtual_slot + 10))); do
    offset=$((virtual_slot - s))
    consumed="false"
    # Map slot offset to frame: frame = current_frame - offset
    f=$((current_frame - offset))
    if (( f >= 0 && f <= TOTAL_FRAMES )); then
      if (( ${ACTIVE[$f]:-0} == 1 )); then consumed="true"; fi
    fi
    if [ "$first" = true ]; then first=false; else out+=","; fi
    out+="\"${s}\":{\"consumed\":${consumed}}"
  done
  out+='},"sessions":{}}'
  printf '%s' "$out" >| "$PIKMIN_STATE"
}

# ── Animation loop ──────────────────────────────────────────────────────────
tput civis 2>/dev/null || true

if [ "$THEME" = "pacman" ]; then
  # ── Pac-Man: fast chase, context 0→98%, ghosts close in, GAME OVER ──
  PAC_FRAMES=18

  # 5h hits 100% at frame 15 (out of 18), context freezes after that
  # 18 frames × 15 min = 4.5h, within 5h reset window
  GAME_OVER_FRAME=15

  # Pac-Man doesn't use slot-offset (no time axis scrolling),
  # so reset countdowns stay fixed — which is fine for a short chase demo
  PAC_FIVE_RESET=$((NOW + 18000))   # 5h
  PAC_SEVEN_RESET=$((NOW + 604800)) # 7d

  for frame in $(seq 0 $PAC_FRAMES); do
    progress=$(( frame * 100 / PAC_FRAMES ))

    if (( frame <= GAME_OVER_FRAME )); then
      # Before game over: everything ramps up
      ctx_pct=$(( frame * 75 / GAME_OVER_FRAME ))
      five_pct=$(( frame * 100 / GAME_OVER_FRAME ))
      seven_pct=$(( progress * 70 / 100 ))
    else
      # After game over: everything frozen
      five_pct=100
    fi

    # Speed: slow → fast → dramatic pause near end → hold game over
    if (( frame > GAME_OVER_FRAME )); then delay=0.5
    elif (( progress < 50 )); then delay=0.3
    elif (( progress < 85 )); then delay=0.15
    else delay=0.4
    fi

    render "$ctx_pct" "$five_pct" "$seven_pct" "$PAC_FIVE_RESET" "$PAC_SEVEN_RESET" "$frame"
    sleep "$delay"
  done

  # Hold GAME OVER
  sleep 3

else
  # ── Pikmin Bloom: 10-hour day simulation ──
  for frame in $(seq 0 $TOTAL_FRAMES); do
    ctx_pct=${CTX_USED[$frame]}
    five_pct=$(five_for_frame "$frame")
    seven_pct=$(seven_for_frame "$frame")

    if (( frame < FIVE_RESET_FRAME )); then
      five_reset=$FIVE_RESET_EPOCH
    else
      five_reset=$FIVE_RESET2_EPOCH
    fi

    write_pikmin_state "$frame"

    render "$ctx_pct" "$five_pct" "$seven_pct" "$five_reset" "$SEVEN_RESET_EPOCH" "$frame"
    sleep 0.3
  done

  # Hold final frame
  sleep 3
fi

tput cnorm 2>/dev/null || true
echo ""
