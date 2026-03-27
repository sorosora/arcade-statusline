#!/usr/bin/env pwsh
# Claude Code status line — Pac-Man style (single line chase)
# PowerShell 7+ version for Windows

# ── encoding ──────────────────────────────────────────────────────────────────
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)

# ── read stdin ────────────────────────────────────────────────────────────────
$raw  = [Console]::In.ReadToEnd()
$data = if ($raw.Trim()) {
    try { $raw | ConvertFrom-Json -ErrorAction Stop } catch { [PSCustomObject]@{} }
} else { [PSCustomObject]@{} }

# ── chomp state (toggle between open/closed mouth each update) ────────────────
$CHOMP_FILE = Join-Path $env:TEMP '.claude-pacman-chomp'
if ((Test-Path $CHOMP_FILE) -and ([System.IO.File]::ReadAllText($CHOMP_FILE).Trim() -eq '1')) {
    $PAC_CHAR = '●'; $G1_CHAR = 'ᗩ'; $G2_CHAR = 'ᗣ'
    [System.IO.File]::WriteAllText($CHOMP_FILE, '0')
} else {
    $PAC_CHAR = 'ᗧ'; $G1_CHAR = 'ᗣ'; $G2_CHAR = 'ᗩ'
    [System.IO.File]::WriteAllText($CHOMP_FILE, '1')
}

# ── colours ───────────────────────────────────────────────────────────────────
$B   = "`e[38;5;27m"   # neon blue (border)
$Y   = "`e[1;33m"      # yellow (Pac-Man)
$R   = "`e[1;31m"      # red (5h ghost)
$P   = "`e[1;35m"      # purple (7d ghost)
$O   = "`e[38;5;208m"  # orange (CLAUDE title)
$W   = "`e[0;37m"      # white (model)
$DIM = "`e[2m"         # dim (version, size)
$NC  = "`e[0m"         # reset

# ── extract fields ────────────────────────────────────────────────────────────
$ctx_pct    = $data.context_window.used_percentage
$five_pct   = $data.rate_limits.five_hour.used_percentage
$five_reset = $data.rate_limits.five_hour.resets_at
$week_pct   = $data.rate_limits.seven_day.used_percentage
$week_reset = $data.rate_limits.seven_day.resets_at
$ctx_total  = if ($null -ne $data.context_window.context_window_size) {
    $data.context_window.context_window_size
} else {
    $data.context_window.total_tokens
}
$version = $data.version

# model: support object or string
$model_raw = $data.model
if ($null -eq $model_raw) {
    $model = $null
} elseif ($model_raw -isnot [string]) {
    $m = if ($null -ne $model_raw.display_name) { [string]$model_raw.display_name }
         elseif ($null -ne $model_raw.id)       { [string]$model_raw.id }
         else                                    { $null }
    $model = if ($m) { $m -replace '\s*\(.*\)', '' } else { $null }
} else {
    $model = if ($model_raw) { $model_raw } else { $null }
}

# parse percentages to int
$ctx_int  = if ($null -ne $ctx_pct)  { [int][Math]::Round([double]$ctx_pct)  } else { 0 }
$five_int = if ($null -ne $five_pct) { [int][Math]::Round([double]$five_pct) } else { 0 }
$week_int = if ($null -ne $week_pct) { [int][Math]::Round([double]$week_pct) } else { 0 }

# ── helpers ───────────────────────────────────────────────────────────────────
function fmt_reset {
    param([object]$ts)
    if ($null -eq $ts) { return '' }
    $now  = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $diff = [long]$ts - $now
    if ($diff -le 0) { return 'now' }
    $d = [int]($diff / 86400)
    $h = [int](($diff % 86400) / 3600)
    $m = [int](($diff % 3600) / 60)
    if ($d -gt 0)     { return "${d}d${h}h" }
    elseif ($h -gt 0) { return "${h}h${m}m" }
    else              { return "${m}m" }
}

function colour_remain([int]$remain) {
    if     ($remain -le 20) { return "`e[1;31m${remain}%`e[0m" }
    elseif ($remain -le 50) { return "`e[1;33m${remain}%`e[0m" }
    else                     { return "`e[0;37m${remain}%`e[0m" }
}

function fmt_tokens {
    param([object]$t)
    if ($null -eq $t) { return '' }
    $n = [long]$t
    if ($n -ge 1000000) { return "$([int]($n / 1000000))M" }
    if ($n -ge 1000)    { return "$([int]($n / 1000))k" }
    return "$n"
}

function rep_hline([int]$n) {
    $s = ''
    for ($i = 0; $i -lt $n; $i++) { $s += "`e[38;5;27m═`e[0m" }
    return $s
}

# ── map config ────────────────────────────────────────────────────────────────
$MAP_W   = 50
$PAD     = 1
$TOTAL_W = $MAP_W + 2 + $PAD * 2  # 54

# ── remaining values ──────────────────────────────────────────────────────────
$ctx_remain  = [Math]::Max(0, 100 - $ctx_int)
$five_remain = [Math]::Max(0, 100 - $five_int)
$week_remain = [Math]::Max(0, 100 - $week_int)
$five_rs = fmt_reset $five_reset
$week_rs = fmt_reset $week_reset

# ── positions ─────────────────────────────────────────────────────────────────
$PAC_MIN = 12
$pac_pos = $PAC_MIN + [int]($ctx_int * ($MAP_W - 1 - $PAC_MIN) / 100)
if ($pac_pos -lt $PAC_MIN) { $pac_pos = $PAC_MIN }
if ($pac_pos -ge $MAP_W)   { $pac_pos = $MAP_W - 1 }

[int]$g1 = -1; [int]$g2 = -1; $game_over = $false; $g2_caged = $false
$g1_pending = $null; $g2_pending = $null

if ($null -ne $five_pct) {
    if ($five_int -ge 100) { $g1 = $pac_pos; $game_over = $true }
    else { $g1_pending = $five_int }
}

if ($null -ne $week_pct) {
    if ($week_remain -gt 50) { $g2_caged = $true }
    if (-not $g2_caged) {
        if ($week_int -ge 100) { $g2 = $pac_pos; $game_over = $true }
        else { $g2_pending = $week_int }
    }
}

# ── room offset (caged ghost takes positions 0-4) ─────────────────────────────
$ROOM_W = 0
if ($g2_caged) {
    $ROOM_W = 5
    if ($pac_pos -lt $ROOM_W) { $pac_pos = $ROOM_W }
}

# ── resolve pending ghost positions ───────────────────────────────────────────
if ($null -ne $g1_pending) {
    $g1_start = $ROOM_W
    $g1 = $g1_start + [int]($g1_pending * ($pac_pos - $g1_start) / 100)
}
if ($null -ne $g2_pending) {
    $g2 = [int]($week_int * $pac_pos / 100)
}

# ── resolve overlaps ──────────────────────────────────────────────────────────
if (-not $game_over) {
    if ($g1 -ge 0 -and $g1 -ge $pac_pos -and $pac_pos -gt 0) { $g1 = $pac_pos - 1 }
    if ($g2 -ge 0 -and $g2 -ge $pac_pos -and $pac_pos -gt 0) { $g2 = $pac_pos - 1 }
}
if ($g1 -ge 0 -and $g2 -ge 0 -and $g1 -eq $g2) {
    if ($five_int -le $week_int) { if ($g1 -gt 0) { $g1-- } }
    else                          { if ($g2 -gt 0) { $g2-- } }
}
if (-not $game_over) {
    if ($g1 -ge 0 -and $g1 -eq $pac_pos -and $pac_pos -gt 0) { $g1 = $pac_pos - 1 }
    if ($g2 -ge 0 -and $g2 -eq $pac_pos -and $pac_pos -gt 0) { $g2 = $pac_pos - 1 }
}

# ── build game line ───────────────────────────────────────────────────────────
$go_text  = ' GAME OVER'
$go_start = -1
if ($game_over) {
    $go_start = $pac_pos + 1
    if ($go_start + $go_text.Length -gt $MAP_W) {
        $go_start = $MAP_W - $go_text.Length
        if ($go_start -le $pac_pos) { $go_start = $pac_pos + 1 }
    }
}

$game = ''
if ($g2_caged) {
    if ($PAC_CHAR -eq 'ᗧ') { $game += "${P}${G2_CHAR}${NC}  ${B}▌${NC} " }
    else                     { $game += "  ${P}${G2_CHAR}${NC}${B}▌${NC} " }
}

$cherry_pos = $PAC_MIN + [int](95 * ($MAP_W - 1 - $PAC_MIN) / 100)

for ($i = $ROOM_W; $i -lt $MAP_W; $i++) {
    if ($game_over -and $go_start -ge 0 -and $i -ge $go_start -and $i -lt ($go_start + $go_text.Length)) {
        $ci = $i - $go_start
        $ch = $go_text[$ci]
        if ($ch -eq [char]' ') { $game += ' ' }
        else { $game += "${R}${ch}${NC}" }
    } elseif ($game_over -and $i -eq $pac_pos) {
        if ($g1 -ge 0 -and $g1 -eq $pac_pos) { $game += "${R}${G1_CHAR}${NC}" }
        else { $game += "${P}${G2_CHAR}${NC}" }
    } elseif ((-not $game_over) -and $i -eq $pac_pos) {
        $game += "${Y}${PAC_CHAR}${NC}"
    } elseif ($g1 -ge 0 -and $i -eq $g1 -and -not ($game_over -and $g1 -eq $pac_pos)) {
        $game += "${R}${G1_CHAR}${NC}"
    } elseif ($g2 -ge 0 -and $i -eq $g2 -and -not ($game_over -and $g2 -eq $pac_pos)) {
        $game += "${P}${G2_CHAR}${NC}"
    } elseif ($i -gt $pac_pos -and $i -eq $cherry_pos) {
        $game += "${R}ᐝ${NC}"
    } elseif ($i -gt $pac_pos) {
        $game += "${W}·${NC}"
    } else {
        $game += ' '
    }
}

# ── build border lines ────────────────────────────────────────────────────────
$hline_w    = $MAP_W + $PAD * 2
$top_border = "${B}╭${NC}$(rep_hline $hline_w)${B}╮${NC}"
$bot_border = "${B}╰${NC}$(rep_hline $hline_w)${B}╯${NC}"

# ── header ────────────────────────────────────────────────────────────────────
$ctx_size = fmt_tokens $ctx_total
$ctx_c    = colour_remain $ctx_remain

$right_plain = ''
if ($model)    { $right_plain += "$model " }
if ($ctx_size) { $right_plain += "$ctx_size " }
$right_plain += "Xontext ${ctx_remain}% left"
$right_len = $right_plain.Length

$left_plain = 'CLAUDE'
if ($version) { $left_plain += " v$version" }
$left_len = $left_plain.Length
$gap = [Math]::Max(2, $TOTAL_W - $left_len - $right_len)

$left_colored = "${O}CLAUDE${NC}"
if ($version) { $left_colored += " ${DIM}v${version}${NC}" }

$right_colored = ''
if ($model)    { $right_colored += "${W}${model}${NC} " }
if ($ctx_size) { $right_colored += "${DIM}${ctx_size}${NC} " }
$right_colored += "${Y}ᗧ${NC}${DIM}ontext${NC} ${ctx_c} ${DIM}left${NC}"

# ── rate limit line ───────────────────────────────────────────────────────────
$limit_line = ''
if ($null -ne $week_pct) {
    $week_c = colour_remain $week_remain
    $limit_line += "${P}ᗩ${NC} ${DIM}7d${NC} ${week_c}"
    if ($week_rs) { $limit_line += " ${DIM}↓${week_rs}${NC}" }
}
if ($null -ne $five_pct) {
    if ($limit_line) { $limit_line += '  ' }
    $five_c = colour_remain $five_remain
    $limit_line += "${R}ᗩ${NC} ${DIM}5h${NC} ${five_c}"
    if ($five_rs) { $limit_line += " ${DIM}↓${five_rs}${NC}" }
}

# ── output ────────────────────────────────────────────────────────────────────
$gap_pad = ' ' * $gap
[Console]::WriteLine("${left_colored}${gap_pad}${right_colored}")
[Console]::WriteLine($top_border)
[Console]::WriteLine("${B}║${NC} ${game} ${B}║${NC}")
[Console]::WriteLine($bot_border)
if ($limit_line) { [Console]::WriteLine($limit_line) }
