#!/usr/bin/env pwsh
# Installer for Pac-Man inspired Claude Code statusline (Windows / PowerShell 7+)

# ── version check ─────────────────────────────────────────────────────────────
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "[x] PowerShell 7+ is required." -ForegroundColor Red
    Write-Host "    Install from: https://github.com/PowerShell/PowerShell" -ForegroundColor Red
    exit 1
}

# ── variables ─────────────────────────────────────────────────────────────────
$ClaudeDir  = Join-Path $env:USERPROFILE '.claude'
$ScriptName = 'statusline.ps1'
$Target     = Join-Path $ClaudeDir $ScriptName
$Settings   = Join-Path $ClaudeDir 'settings.json'
$RawUrl     = 'https://github.com/sorosora/arcade-statusline/releases/latest/download/statusline.ps1'

# ── output helpers ────────────────────────────────────────────────────────────
function Write-Info  { param($msg) Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "[x] $msg" -ForegroundColor Red }

# ── create directory ──────────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

# ── backup existing script ────────────────────────────────────────────────────
if (Test-Path $Target) {
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $backup    = "${Target}.bak.${timestamp}"
    Copy-Item $Target $backup
    Write-Info "Backed up existing $ScriptName to $(Split-Path $backup -Leaf)"
}

# ── download statusline.ps1 ───────────────────────────────────────────────────
Write-Info "Downloading $ScriptName..."
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $RawUrl -OutFile $Target -UseBasicParsing
    Write-Info "Saved to $Target"
} catch {
    Write-Err "Failed to download ${ScriptName}: $_"
    exit 1
}

# ── configure settings.json ───────────────────────────────────────────────────
$StatusCmd = "pwsh -NoProfile -File `"$Target`""

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
Write-Host '  The Pac-Man statusline will appear automatically in Claude Code.'
Write-Host '  To preview it manually:'
Write-Host ''
Write-Host "    echo '{}' | pwsh -NoProfile -File `"$Target`""
Write-Host ''
