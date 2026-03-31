#!/usr/bin/env pwsh
# Installer for arcade-statusline (Rust binary) — Windows / PowerShell 7+

# ── variables ─────────────────────────────────────────────────────────────────
$ClaudeDir = Join-Path $env:USERPROFILE '.claude'
$BinName   = 'arcade-statusline.exe'
$Target    = Join-Path $ClaudeDir $BinName
$Settings  = Join-Path $ClaudeDir 'settings.json'
$BaseUrl   = 'https://github.com/sorosora/arcade-statusline/releases/latest/download'

# ── output helpers ────────────────────────────────────────────────────────────
function Write-Info  { param($msg) Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "[x] $msg" -ForegroundColor Red }

# ── detect architecture ───────────────────────────────────────────────────────
$Arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') {
    'aarch64'
} else {
    'x86_64'
}

$Archive = "arcade-statusline-${Arch}-pc-windows-msvc.zip"
$DownloadUrl = "${BaseUrl}/${Archive}"

Write-Info "Detected platform: ${Arch}-pc-windows-msvc"

# ── create directory ──────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

# ── backup existing binary ────────────────────────────────────────────────────
if (Test-Path $Target) {
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $backup    = "${Target}.bak.${timestamp}"
    Copy-Item $Target $backup
    Write-Info "Backed up existing $BinName to $(Split-Path $backup -Leaf)"
}

# ── download binary ───────────────────────────────────────────────────────────
Write-Info "Downloading $Archive..."
$TmpDir = Join-Path $env:TEMP "arcade-statusline-install"
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
$ZipPath = Join-Path $TmpDir $Archive
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing
    Expand-Archive -Path $ZipPath -DestinationPath $TmpDir -Force
    Copy-Item (Join-Path $TmpDir $BinName) $Target -Force
    Remove-Item $TmpDir -Recurse -Force
    Write-Info "Saved to $Target"
} catch {
    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Err "Failed to download ${Archive}: $_"
    Write-Err "URL: $DownloadUrl"
    exit 1
}

# ── theme selection ────────────────────────────────────────────────────────────
$NowEpoch = [int][double]::Parse((Get-Date -UFormat %s))
$Sample = @"
{"model":"Claude Opus 4.6","version":"1.0.0","context_window":{"used_percentage":35,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":28,"resets_at":$($NowEpoch + 7200)},"seven_day":{"used_percentage":15,"resets_at":$($NowEpoch + 259200)}}}
"@

Write-Host ''
Write-Host '  Choose a theme:'
Write-Host ''
Write-Host '  +-------------------------------------------------------------------+'
Write-Host '  |  1) Pac-Man                                                       |'
Write-Host '  +-------------------------------------------------------------------+'
Write-Host ''
$Sample | & $Target --theme pacman
Write-Host ''
Write-Host '  +-------------------------------------------------------------------+'
Write-Host '  |  2) Pikmin Bloom                                                  |'
Write-Host '  +-------------------------------------------------------------------+'
Write-Host ''
$Sample | & $Target --theme pikmin
Write-Host ''

$choice = Read-Host '  Enter choice [1/2] (default: 1)'
$Theme = if ($choice -eq '2') { 'pikmin' } else { 'pacman' }

Write-Info "Selected theme: $Theme"

# ── configure settings.json ───────────────────────────────────────────────────
$StatusCmd = "`"$Target`" --theme $Theme"

if (Test-Path $Settings) {
    $raw = Get-Content $Settings -Raw -ErrorAction SilentlyContinue
    $json = if ($raw) {
        try { $raw | ConvertFrom-Json -ErrorAction Stop } catch { [PSCustomObject]@{} }
    } else { [PSCustomObject]@{} }

    $currentCmd = $json.statusLine.command
    if ($currentCmd -eq $StatusCmd) {
        Write-Info "settings.json already configured (no changes needed)"
    } else {
        $statusLineObj = [PSCustomObject]@{ type = 'command'; command = $StatusCmd }
        if ($null -ne $json.statusLine) {
            $json.statusLine = $statusLineObj
        } else {
            $json | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $statusLineObj
        }
        $json | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding UTF8
        Write-Info "Updated statusLine command in $Settings"
    }
} else {
    [PSCustomObject]@{
        statusLine = [PSCustomObject]@{ type = 'command'; command = $StatusCmd }
    } | ConvertTo-Json -Depth 10 | Set-Content $Settings -Encoding UTF8
    Write-Info "Created $Settings with statusLine config"
}

# ── done ──────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Info 'Installation complete!'
Write-Host ''
Write-Host '  The statusline will appear automatically in Claude Code.'
Write-Host "  To change theme later, edit $Settings"
Write-Host '  and set --theme to pacman or pikmin.'
Write-Host ''
