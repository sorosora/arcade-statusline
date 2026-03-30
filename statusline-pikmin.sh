#!/usr/bin/env bash
# Claude Code status line — Pikmin Bloom style (flower planting trail)
# Pikmin squad walks in place, background scrolls left, flowers planted over time.

input=$(cat)

# ── colours ──────────────────────────────────────────────────────────────────
B='\033[38;5;34m'   # green (border — garden theme)
Y='\033[1;33m'      # yellow
R='\033[1;31m'      # red
P='\033[1;35m'      # purple
O='\033[38;5;208m'  # orange (CLAUDE title)
W='\033[0;37m'      # white
DIM='\033[2m'       # dim
NC='\033[0m'        # reset

# ── extract fields ───────────────────────────────────────────────────────────
ctx_pct=$(echo "$input"    | jq -r '.context_window.used_percentage // "0"')
five_pct=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input"   | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
model=$(echo "$input"      | jq -r 'if .model | type == "object" then (.model.display_name // .model.id // empty) | gsub("\\s*\\(.*\\)"; "") else .model // empty end')
ctx_total=$(echo "$input"  | jq -r '.context_window.context_window_size // .context_window.total_tokens // empty')
version=$(echo "$input"    | jq -r '.version // empty')

ctx_int=$(printf "%.0f" "$ctx_pct" 2>/dev/null || echo 0)
five_int=$(printf "%.0f" "${five_pct:-0}" 2>/dev/null || echo 0)
week_int=$(printf "%.0f" "${week_pct:-0}" 2>/dev/null || echo 0)

# ── helpers ──────────────────────────────────────────────────────────────────
fmt_reset() {
  local ts="$1"; [ -z "$ts" ] && return
  local now; now=$(date +%s); local diff=$(( ts - now ))
  if (( diff <= 0 )); then printf "now"; return; fi
  local d=$(( diff / 86400 )) h=$(( (diff % 86400) / 3600 )) m=$(( (diff % 3600) / 60 ))
  if (( d > 0 )); then printf "%dd%dh" "$d" "$h"
  elif (( h > 0 )); then printf "%dh%dm" "$h" "$m"
  else printf "%dm" "$m"; fi
}

colour_remain() {
  local remain="$1"
  if   (( remain <= 20 )); then printf "\033[1;31m%d%%\033[0m" "$remain"
  elif (( remain <= 50 )); then printf "\033[1;33m%d%%\033[0m" "$remain"
  else printf "\033[0;37m%d%%\033[0m" "$remain"; fi
}

fmt_tokens() {
  local t="$1"; [ -z "$t" ] && return
  if (( t >= 1000000 )); then printf "%dM" $(( t / 1000000 ))
  elif (( t >= 1000 )); then printf "%dk" $(( t / 1000 ))
  else printf "%d" "$t"; fi
}

# ── state management ─────────────────────────────────────────────────────────
STATE_FILE="/tmp/.claude-pikmin-state.json"
SESSION_ID="$$"  # PID as session identifier
SLOT_MINUTES=15
TRAIL_SLOTS=36   # 36 slots × 15 min = 9 hours (behind pikmin)
FUTURE_SLOTS=4   # 4 slots × 15 min = 1 hour (ahead of pikmin)

now_epoch=$(date +%s)
current_slot=$(( now_epoch / (SLOT_MINUTES * 60) ))
current_minute=$(date +%M | sed 's/^0//')
current_hour_minute=$(( current_minute % 60 ))

# Determine if this is a big flower slot: pos = (slot + 1) % 8, pos 0 = big
is_hour_slot=0
if (( (current_slot + 1) % 8 == 0 )); then
  is_hour_slot=1
fi

# Random flower picker
small_flowers=("🌸" "🌺" "🌼")
big_flowers=("🪻" "🌻" "🌷")
fruits=("🍎" "🍊" "🍋" "🍇" "🍓" "🍑" "🫐")

pick_small_flower() {
  echo "${small_flowers[$(( $1 % 3 ))]}"
}

pick_big_flower() {
  echo "${big_flowers[$(( $1 % 3 ))]}"
}

pick_fruit() {
  echo "${fruits[$(( $1 % ${#fruits[@]} ))]}"
}

# Rate limit check — if any rate limit is 100%, can't plant
rate_limit_hit=0
if [ -n "$five_pct" ] && (( five_int >= 100 )); then rate_limit_hit=1; fi
if [ -n "$week_pct" ] && (( week_int >= 100 )); then rate_limit_hit=1; fi

# Compute reset time slots (for fruit display in future)
five_reset_slot=""
week_reset_slot=""
fruit_char=""  # computed per slot
if [ -n "$five_reset" ]; then
  five_reset_slot=$(( five_reset / (SLOT_MINUTES * 60) ))
fi
if [ -n "$week_reset" ]; then
  week_reset_slot=$(( week_reset / (SLOT_MINUTES * 60) ))
fi

# Next flower for footer label
cur_pos=$(( (current_slot + 1) % 8 ))
if (( cur_pos == 0 )); then
  next_flower=$(pick_big_flower "$current_slot")
else
  next_flower=$(pick_small_flower "$current_slot")
fi

# Read state
if [ -f "$STATE_FILE" ]; then
  state=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')
  # Validate JSON
  echo "$state" | jq empty 2>/dev/null || state='{}'
else
  state='{}'
fi

trail=$(echo "$state" | jq -r '.trail // {}')
sessions=$(echo "$state" | jq -r '.sessions // {}')

# Get last context % for this session
last_ctx=$(echo "$sessions" | jq -r --arg sid "$SESSION_ID" '.[$sid] // empty')

# Determine if context was consumed
ctx_consumed=0
if [ -n "$last_ctx" ]; then
  last_ctx_int=$(printf "%.0f" "$last_ctx" 2>/dev/null || echo 0)
  if (( ctx_int != last_ctx_int )); then
    ctx_consumed=1
  fi
else
  # First time this session — if context > 0, assume consuming
  if (( ctx_int > 0 )); then
    ctx_consumed=1
  fi
fi

# Check what's already in this slot
slot_key="$current_slot"
existing=$(echo "$trail" | jq -r --arg k "$slot_key" '.[$k] // empty')

# Decide what to plant
if [ -n "$existing" ] && [ "$existing" != "·" ] && [ "$existing" != "🌱" ]; then
  # Already a flower — don't overwrite. Remove session tracking.
  sessions=$(echo "$sessions" | jq --arg sid "$SESSION_ID" 'del(.[$sid])')
elif (( rate_limit_hit )); then
  # Rate limit hit — can't plant
  if [ -z "$existing" ]; then
    trail=$(echo "$trail" | jq --arg k "$slot_key" --arg v "·" '. + {($k): $v}')
  fi
  sessions=$(echo "$sessions" | jq --arg sid "$SESSION_ID" --argjson v "$ctx_int" '. + {($sid): $v}')
elif (( ctx_consumed )); then
  # Plant a flower!
  if (( is_hour_slot )); then
    flower=$(pick_big_flower "$current_slot")
  else
    flower=$(pick_small_flower "$current_slot")
  fi
  trail=$(echo "$trail" | jq --arg k "$slot_key" --arg v "$flower" '. + {($k): $v}')
  # Flower planted — remove session tracking
  sessions=$(echo "$sessions" | jq --arg sid "$SESSION_ID" 'del(.[$sid])')
else
  # No consumption — seedling if hour slot, dot otherwise
  if [ -z "$existing" ]; then
    if (( is_hour_slot )); then
      trail=$(echo "$trail" | jq --arg k "$slot_key" --arg v "🌱" '. + {($k): $v}')
    else
      trail=$(echo "$trail" | jq --arg k "$slot_key" --arg v "·" '. + {($k): $v}')
    fi
  fi
  sessions=$(echo "$sessions" | jq --arg sid "$SESSION_ID" --argjson v "$ctx_int" '. + {($sid): $v}')
fi

# Prune old slots (keep only last TRAIL_SLOTS worth)
oldest_slot=$(( current_slot - TRAIL_SLOTS ))
trail=$(echo "$trail" | jq --argjson oldest "$oldest_slot" 'to_entries | map(select((.key | tonumber) >= $oldest)) | from_entries')

# Prune stale sessions (no update in 30 min = 3 slots)
# Simple approach: just keep sessions, they're small

# Write state back
new_state=$(jq -n --argjson trail "$trail" --argjson sessions "$sessions" \
  '{trail: $trail, sessions: $sessions}')
echo "$new_state" > "$STATE_FILE"

# ── animation state ──────────────────────────────────────────────────────────
ANIM_FILE="/tmp/.claude-pikmin-anim"
if [ -f "$ANIM_FILE" ] && [ "$(cat "$ANIM_FILE")" = "1" ]; then
  PIKMIN_ORDER="🔴🟡🔵"
  echo "0" > "$ANIM_FILE"
else
  PIKMIN_ORDER="🟡🔵🔴"
  echo "1" > "$ANIM_FILE"
fi

# ── build game line ──────────────────────────────────────────────────────────
# Fixed layout: per 2h block = big(1+1pad) + small×6(6) + 7th small(1+1pad) = 10 cols
# total = 10×(10h/2) + spacer(1) + pikmin(4) = 10×5 + 5 = 55 cols
MAP_W=54

HS="\033[8m.\033[0m"  # hidden spacer: 1 invisible col

is_big() {
  case "$1" in 🌱|🪻|🌻|🌷) return 0 ;; *) return 1 ;; esac
}

# Slot position in 2h block: pos = (s + 1) % 8
# pos 0 = big flower slot (crosses even-hour boundary)
# pos 1-6 = normal small flower slots
# pos 7 = 7th small flower (last in block, 1h45m-2h0m)
slot_pos_in_block() {
  echo $(( ($1 + 1) % 8 ))
}

# Render a slot: returns the display string
# Position 0 = big flower/seedling (2 cols: emoji + pad after)
# Position 7 = last small flower (2 cols: pad before + emoji)
# Position 1-6 = small flower/dot (1 col)
render_slot() {
  local val="$1" pos="$2"
  if (( pos == 0 || pos == 7 )); then
    # Big flower (pos 0) or 7th small (pos 7): emoji + pad after
    # Emoji: pad with hidden spacer. No emoji: pad with visible dot.
    if [ -z "$val" ] || [ "$val" = "·" ]; then
      printf "${DIM}·${NC}${DIM}·${NC}"
    else
      printf "%s${HS}" "$val"
    fi
  else
    # Normal slot: 1 col
    if [ -z "$val" ] || [ "$val" = "·" ]; then
      printf "${DIM}·${NC}"
    else
      printf "%s" "$val"
    fi
  fi
}

# Build game line
game=""

# Trail (past 9 hours + current slot, oldest on left)
for (( s = current_slot - TRAIL_SLOTS + 1; s <= current_slot; s++ )); do
  sk="$s"
  val=$(echo "$trail" | jq -r --arg k "$sk" '.[$k] // empty')
  pos=$(slot_pos_in_block "$s")
  # pos 0: seedling if no flower
  if (( pos == 0 )) && { [ -z "$val" ] || [ "$val" = "·" ] || [ "$val" = "🌱" ]; }; then
    val="🌱"
  fi
  game+="$(render_slot "$val" "$pos")"
done

# Pikmin squad (3 emoji + pad after)
game+="${PIKMIN_ORDER}${HS}"

# Future (next 1 hour)
# Priority for pos 0: big flower > fruit > seedling
# Priority for pos 1-7: fruit > dot/seedling
for (( s = current_slot + 1; s <= current_slot + FUTURE_SLOTS; s++ )); do
  pos=$(slot_pos_in_block "$s")
  is_fruit=0
  if [ -n "$five_reset_slot" ] && (( s == five_reset_slot )); then is_fruit=1; fi
  if [ -n "$week_reset_slot" ] && (( s == week_reset_slot )); then is_fruit=1; fi

  if (( pos == 0 )); then
    # pos 0: seedling by default, fruit if reset, (big flower can't happen in future)
    if (( is_fruit )); then
      game+="$(render_slot "$(pick_fruit "$s")" "$pos")"
    else
      game+="$(render_slot "🌱" "$pos")"
    fi
  else
    # pos 1-7: fruit if reset, dot otherwise
    if (( is_fruit )); then
      game+="$(render_slot "$(pick_fruit "$s")" "$pos")"
    else
      game+="$(render_slot "·" "$pos")"
    fi
  fi
done

# ── remaining values ─────────────────────────────────────────────────────────
ctx_remain=$(( 100 - ctx_int )); (( ctx_remain < 0 )) && ctx_remain=0
five_remain=$(( 100 - five_int )); (( five_remain < 0 )) && five_remain=0
week_remain=$(( 100 - week_int )); (( week_remain < 0 )) && week_remain=0
five_rs=$(fmt_reset "$five_reset")
week_rs=$(fmt_reset "$week_reset")

# ── build sky + grass lines ───────────────────────────────────────────────────
SKY='\033[38;5;39m'  # sky blue
sky=""
for (( i=0; i<MAP_W; i++ )); do sky+="${SKY}█${NC}"; done
grass=""
for (( i=0; i<MAP_W; i++ )); do grass+="${B}▀${NC}"; done

# ── header ───────────────────────────────────────────────────────────────────
ctx_size=$(fmt_tokens "$ctx_total")
ctx_c=$(colour_remain "$ctx_remain")

left_plain="CLAUDE"
[ -n "$version" ] && left_plain+=" v${version}"
left_len=${#left_plain}

right_plain=""
[ -n "$model" ] && right_plain+="${model} "
[ -n "$ctx_size" ] && right_plain+="${ctx_size} "
right_plain+="Context ${ctx_remain}% left"
right_len=$(( ${#right_plain} + 1 ))  # 🌸 replaces "o": net +1 visual col

gap=$(( MAP_W - left_len - right_len ))
(( gap < 2 )) && gap=2

left_colored="${O}CLAUDE${NC}"
[ -n "$version" ] && left_colored+=" ${DIM}v${version}${NC}"

right_colored=""
[ -n "$model" ] && right_colored+="\033[2m${model}\033[0m "
[ -n "$ctx_size" ] && right_colored+="\033[2m${ctx_size}\033[0m "
right_colored+="\033[2mC\033[0m${next_flower}\033[8m.\033[0m\033[2mntext\033[0m ${ctx_c} \033[2mleft\033[0m"

# ── footer ────────────────────────────────────────────────────────────────────
# Left: rate limit info with fruit for reset time
footer_left=""
footer_left_plain=""
if [ -n "$week_pct" ]; then
  week_c=$(colour_remain "$week_remain")
  footer_left+="\033[2m7d\033[0m ${week_c}"
  footer_left_plain+="7d ${week_remain}%"
  if [ -n "$week_rs" ]; then
    week_fruit=$(pick_fruit "${week_reset_slot:-0}")
    footer_left+=" ${week_fruit}${HS}${DIM}${week_rs}${NC}"
    footer_left_plain+=" XX${week_rs}"
  fi
fi
if [ -n "$five_pct" ]; then
  [ -n "$footer_left" ] && { footer_left+="  "; footer_left_plain+="  "; }
  five_c=$(colour_remain "$five_remain")
  footer_left+="\033[2m5h\033[0m ${five_c}"
  footer_left_plain+="5h ${five_remain}%"
  if [ -n "$five_rs" ]; then
    five_fruit=$(pick_fruit "${five_reset_slot:-0}")
    footer_left+=" ${five_fruit}${HS}${DIM}${five_rs}${NC}"
    footer_left_plain+=" XX${five_rs}"
  fi
fi

# Right: status indicator
if (( rate_limit_hit )); then
  footer_right="Ha! ▶️"
  footer_right_vcols=7   # Ha!(3) + space(1) + ▶️(2) + overflow(1)
else
  footer_right="✨Bloom!⏹️"
  footer_right_vcols=10  # ✨(2) + Bloom!(6) + ⏹️(2)
fi

# Combine with gap
footer_gap=$(( MAP_W - ${#footer_left_plain} - footer_right_vcols ))
(( footer_gap < 2 )) && footer_gap=2
footer_pad=$(printf "%*s" "$footer_gap" "")
limit_line="${footer_left}${footer_pad}${footer_right}"

# ── output ───────────────────────────────────────────────────────────────────
gap_pad=$(printf "%*s" "$gap" "")
echo -e "${left_colored}${gap_pad}${right_colored}"
echo -e "${sky}"
echo -e "${game}"
echo -e "${grass}"
[ -n "$limit_line" ] && echo -e "$limit_line"
