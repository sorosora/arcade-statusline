#!/usr/bin/env bash
# Claude Code status line — Pac-Man style (single line chase)
# Top: model/size | CLAUDE | context remain. Map below. Limits underneath.

input=$(cat)

# ── chomp state (toggle between open/closed mouth each update) ───────────────
CHOMP_FILE="/tmp/.claude-pacman-chomp"
if [ -f "$CHOMP_FILE" ] && [ "$(cat "$CHOMP_FILE")" = "1" ]; then
  PAC_CHAR="●"; G1_CHAR="ᗩ"; G2_CHAR="ᗣ"; echo "0" > "$CHOMP_FILE"
else
  PAC_CHAR="ᗧ"; G1_CHAR="ᗣ"; G2_CHAR="ᗩ"; echo "1" > "$CHOMP_FILE"
fi

# ── config ──────────────────────────────────────────────────────────────────
CONF_FILE="${HOME}/.claude/arcade-statusline.conf"
[ -f "$CONF_FILE" ] && . "$CONF_FILE"
DISPLAY_MODE="${ARCADE_DISPLAY_MODE:-${DISPLAY_MODE:-remaining}}"
MAX_WIDTH="${ARCADE_MAX_WIDTH:-${MAX_WIDTH:-54}}"

# ── colours ──────────────────────────────────────────────────────────────────
B='\033[38;5;27m'; Y='\033[1;33m'; R='\033[1;31m'; P='\033[1;35m'
O='\033[38;5;208m'; W='\033[0;37m'; DIM='\033[2m'; NC='\033[0m'

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

colour_used() {
  local used="$1"
  if   (( used >= 80 )); then printf "\033[1;31m%d%%\033[0m" "$used"
  elif (( used >= 50 )); then printf "\033[1;33m%d%%\033[0m" "$used"
  else printf "\033[0;37m%d%%\033[0m" "$used"; fi
}

fmt_tokens() {
  local t="$1"; [ -z "$t" ] && return
  if (( t >= 1000000 )); then printf "%dM" $(( t / 1000000 ))
  elif (( t >= 1000 )); then printf "%dk" $(( t / 1000 ))
  else printf "%d" "$t"; fi
}

rep_hline() {
  local n=$1 s=""
  for (( i=0; i<n; i++ )); do s+="\033[38;5;27m═\033[0m"; done
  printf "%s" "$s"
}

# ── map config ───────────────────────────────────────────────────────────────
PAD=1  # padding between border and content
MAP_W=$(( MAX_WIDTH - 2 - PAD * 2 ))  # inner game width derived from MAX_WIDTH
TOTAL_W=$MAX_WIDTH

# ── remaining values ─────────────────────────────────────────────────────────
ctx_remain=$(( 100 - ctx_int )); (( ctx_remain < 0 )) && ctx_remain=0
five_remain=$(( 100 - five_int )); (( five_remain < 0 )) && five_remain=0
week_remain=$(( 100 - week_int )); (( week_remain < 0 )) && week_remain=0
five_rs=$(fmt_reset "$five_reset")
week_rs=$(fmt_reset "$week_reset")

# ── positions ────────────────────────────────────────────────────────────────
PAC_MIN=12  # minimum start position — leaves room for ghosts to chase
pac_pos=$(( PAC_MIN + ctx_int * (MAP_W - 1 - PAC_MIN) / 100 ))
(( pac_pos < PAC_MIN )) && pac_pos=$PAC_MIN
(( pac_pos >= MAP_W )) && pac_pos=$(( MAP_W - 1 ))

g1=-1; g2=-1; game_over=0
g2_caged=0  # 1 = 7d ghost locked in room

if [ -n "$five_pct" ]; then
  if (( five_int >= 100 )); then g1=$pac_pos; game_over=1
  else
    # Ghost range: ROOM_W..pac_pos (calculated after room offset is set)
    g1_pending=$five_int
  fi
fi

if [ -n "$week_pct" ]; then
  # Cage ghost when 7d usage < 50% (remaining > 50%)
  if (( week_remain > 50 )); then
    g2_caged=1
  fi

  if (( g2_caged == 0 )); then
    if (( week_int >= 100 )); then g2=$pac_pos; game_over=1
    else
      g2_pending=$week_int
    fi
  fi
fi

# ── room offset (caged ghost takes positions 0-4) ─────────────────────────────
ROOM_W=0
if (( g2_caged )); then
  ROOM_W=5  # 3 interior + 1 wall + 1 gap
  (( pac_pos < ROOM_W )) && pac_pos=$ROOM_W
fi

# ── resolve pending ghost positions (relative to their start..pac_pos range) ──
if [ -n "${g1_pending:-}" ]; then
  g1_start=$ROOM_W
  g1=$(( g1_start + g1_pending * (pac_pos - g1_start) / 100 ))
fi
if [ -n "${g2_pending:-}" ]; then
  g2=$(( week_int * pac_pos / 100 ))
fi

# ── resolve overlaps ────────────────────────────────────────────────────────
if (( game_over == 0 )); then
  (( g1 >= 0 && g1 >= pac_pos && pac_pos > 0 )) && g1=$(( pac_pos - 1 ))
  (( g2 >= 0 && g2 >= pac_pos && pac_pos > 0 )) && g2=$(( pac_pos - 1 ))
fi
if (( g1 >= 0 && g2 >= 0 && g1 == g2 )); then
  if (( five_int <= week_int )); then (( g1 > 0 )) && ((g1--))
  else (( g2 > 0 )) && ((g2--)); fi
fi
if (( game_over == 0 )); then
  (( g1 >= 0 && g1 == pac_pos && pac_pos > 0 )) && g1=$(( pac_pos - 1 ))
  (( g2 >= 0 && g2 == pac_pos && pac_pos > 0 )) && g2=$(( pac_pos - 1 ))
fi

# ── build game line ──────────────────────────────────────────────────────────
go_text=" GAME OVER"
go_start=-1
if (( game_over )); then
  go_start=$(( pac_pos + 1 ))
  if (( go_start + ${#go_text} > MAP_W )); then
    go_start=$(( MAP_W - ${#go_text} ))
    (( go_start <= pac_pos )) && go_start=$(( pac_pos + 1 ))
  fi
fi

game=""
# Prepend room if ghost is caged (ghost bounces in 3-cell room + wall + gap)
if (( g2_caged )); then
  if [ "$PAC_CHAR" = "ᗧ" ]; then
    game+="\033[1;35m${G2_CHAR}\033[0m  ${B}▌${NC} "
  else
    game+="  \033[1;35m${G2_CHAR}\033[0m${B}▌${NC} "
  fi
fi
# Cherry position at ~80% context (auto compact threshold)
cherry_pos=$(( PAC_MIN + 95 * (MAP_W - 1 - PAC_MIN) / 100 ))

for (( i=ROOM_W; i<MAP_W; i++ )); do
  if (( game_over && go_start >= 0 && i >= go_start && i < go_start + ${#go_text} )); then
    ci=$(( i - go_start ))
    ch="${go_text:$ci:1}"
    if [[ "$ch" == " " ]]; then game+=" "
    else game+="\033[1;31m${ch}\033[0m"; fi
  elif (( game_over && i == pac_pos )); then
    if (( g1 >= 0 && g1 == pac_pos )); then game+="\033[1;31m${G1_CHAR}\033[0m"
    else game+="\033[1;35m${G2_CHAR}\033[0m"; fi
  elif (( !game_over && i == pac_pos )); then
    game+="\033[1;33m${PAC_CHAR}\033[0m"
  elif (( g1 >= 0 && i == g1 && !(game_over && g1 == pac_pos) )); then
    game+="\033[1;31m${G1_CHAR}\033[0m"
  elif (( g2 >= 0 && i == g2 && !(game_over && g2 == pac_pos) )); then
    game+="\033[1;35m${G2_CHAR}\033[0m"
  elif (( i > pac_pos && i == cherry_pos )); then
    game+="\033[1;31mᐝ\033[0m"
  elif (( i > pac_pos )); then
    game+="\033[0;37m·\033[0m"
  else
    game+=" "
  fi
done

# ── build border lines ────────────────────────────────────────────────────────
hline_w=$(( MAP_W + PAD * 2 ))
top_border="${B}╭${NC}$(rep_hline $hline_w)${B}╮${NC}"
bot_border="${B}╰${NC}$(rep_hline $hline_w)${B}╯${NC}"

# ── header: CLAUDE (left)    model size ᗧontext XX% left (right) ─────────────
ctx_size=$(fmt_tokens "$ctx_total")
if [ "$DISPLAY_MODE" = "used" ]; then
  ctx_c=$(colour_used "$ctx_int")
else
  ctx_c=$(colour_remain "$ctx_remain")
fi

# Right text (plain, for length calculation)
right_plain=""
[ -n "$model" ] && right_plain+="${model} "
[ -n "$ctx_size" ] && right_plain+="${ctx_size} "
if [ "$DISPLAY_MODE" = "used" ]; then
  right_plain+="Xontext ${ctx_int}% used"
else
  right_plain+="Xontext ${ctx_remain}% left"
fi
right_len=${#right_plain}

# Left = "CLAUDE vX.X.X"
left_plain="CLAUDE"
[ -n "$version" ] && left_plain+=" v${version}"
left_len=${#left_plain}

# Header width fixed to TOTAL_W; drop mode suffix if content is too wide
header_w=$TOTAL_W
needed=$(( left_len + 2 + right_len ))
if (( needed > header_w )); then
  right_plain=""
  [ -n "$model" ] && right_plain+="${model} "
  [ -n "$ctx_size" ] && right_plain+="${ctx_size} "
  if [ "$DISPLAY_MODE" = "used" ]; then
    right_plain+="Xontext ${ctx_int}%"
  else
    right_plain+="Xontext ${ctx_remain}%"
  fi
  right_len=${#right_plain}
  show_left_suffix=0
else
  show_left_suffix=1
fi

gap=$(( header_w - left_len - right_len ))
(( gap < 2 )) && gap=2

# Colored left
left_colored="${O}CLAUDE${NC}"
[ -n "$version" ] && left_colored+=" ${DIM}v${version}${NC}"

# Colored right
right_colored=""
[ -n "$model" ] && right_colored+="${W}${model}${NC} "
[ -n "$ctx_size" ] && right_colored+="\033[2m${ctx_size}\033[0m "
right_colored+="\033[1;33mᗧ\033[0m\033[2montext\033[0m ${ctx_c}"
if (( show_left_suffix )); then
  if [ "$DISPLAY_MODE" = "used" ]; then
    right_colored+=" \033[2mused\033[0m"
  else
    right_colored+=" \033[2mleft\033[0m"
  fi
fi

# ── rate limit line (below map) ──────────────────────────────────────────────
limit_line=""
if [ -n "$week_pct" ]; then
  if [ "$DISPLAY_MODE" = "used" ]; then
    week_c=$(colour_used "$week_int")
  else
    week_c=$(colour_remain "$week_remain")
  fi
  limit_line+="\033[1;35mᗩ\033[0m \033[2m7d\033[0m ${week_c}"
  if [ "$DISPLAY_MODE" = "used" ]; then
    limit_line+=" \033[2mused\033[0m"
  else
    limit_line+=" \033[2mleft\033[0m"
  fi
  [ -n "$week_rs" ] && limit_line+=" \033[2m↓${week_rs}\033[0m"
fi
if [ -n "$five_pct" ]; then
  [ -n "$limit_line" ] && limit_line+="  "
  if [ "$DISPLAY_MODE" = "used" ]; then
    five_c=$(colour_used "$five_int")
  else
    five_c=$(colour_remain "$five_remain")
  fi
  limit_line+="\033[1;31mᗩ\033[0m \033[2m5h\033[0m ${five_c}"
  if [ "$DISPLAY_MODE" = "used" ]; then
    limit_line+=" \033[2mused\033[0m"
  else
    limit_line+=" \033[2mleft\033[0m"
  fi
  [ -n "$five_rs" ] && limit_line+=" \033[2m↓${five_rs}\033[0m"
fi

# ── output ───────────────────────────────────────────────────────────────────
gap_pad=$(printf "%*s" "$gap" "")
# Single line: CLAUDE version (left) + gap + right info
echo -e "${left_colored}${gap_pad}${right_colored}"
# Map
echo -e "$top_border"
echo -e "${B}║${NC} ${game} ${B}║${NC}"
echo -e "$bot_border"
# Limits
[ -n "$limit_line" ] && echo -e "$limit_line"
