# PromptShield — Windows PowerShell Installer
# Run in PowerShell (Admin recommended):
# iwr -useb https://raw.githubusercontent.com/YOUR_ORG/promptshield/main/install.ps1 | iex
# Or with args:
# & ([scriptblock]::Create((iwr https://...install.ps1).Content)) -DeviceId "DID-XXXX" -Name "My PC"

param(
    [string]$DeviceId = "",
    [string]$Name = "",
    [string]$Mode = "api",
    [switch]$SkipCursor,
    [switch]$SkipClaude
)

$REPO      = "YOUR_ORG/promptshield"
$GATEWAY   = "https://YOUR_GATEWAY_URL"
$PAGES     = "https://YOUR_ORG.github.io/promptshield"
$VERSION   = "1.0.0"
$INSTALL   = "$env:USERPROFILE\.devguard"
$RAW       = "https://raw.githubusercontent.com/$REPO/main"

function Write-Step { Write-Host "→ $args" -ForegroundColor Blue }
function Write-OK   { Write-Host "✓ $args" -ForegroundColor Green }
function Write-Warn { Write-Host "⚠ $args" -ForegroundColor Yellow }
function Write-Die  { Write-Host "✕ $args" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  ⬡  PromptShield — AI Developer Governance" -ForegroundColor Cyan
Write-Host "  v$VERSION · Windows"
Write-Host ""

# ── Check Node.js ─────────────────────────────────────────────────────────────
Write-Step "Checking dependencies..."
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "Node.js not found. Install it:" -ForegroundColor Red
    Write-Host "  winget install OpenJS.NodeJS.LTS"
    Write-Host "  — or — https://nodejs.org"
    Write-Host ""
    Write-Die "Install Node.js >=18 then re-run"
}
$nodeVer = (node --version).TrimStart('v').Split('.')[0] -as [int]
if ($nodeVer -lt 18) { Write-Die "Node.js >=18 required. Run: winget upgrade OpenJS.NodeJS.LTS" }
Write-OK "Node.js $(node --version)"

# ── Collect device info ───────────────────────────────────────────────────────
if (-not $DeviceId) {
    Write-Host ""
    Write-Host "? Paste your Device ID (from $PAGES/mode-b → My Devices → Add Device):" -ForegroundColor Yellow
    Write-Host "  It looks like: DID-XXXX-XXXX-XXXX" -ForegroundColor Gray
    $DeviceId = Read-Host
    if (-not $DeviceId) { Write-Die "Device ID required" }
}
if (-not $Name) {
    $defaultName = $env:COMPUTERNAME
    Write-Host "? Device name [$defaultName]:" -ForegroundColor Yellow
    $input = Read-Host
    $Name = if ($input) { $input } else { $defaultName }
}

Write-OK "Device: $Name"
Write-OK "Device ID: $DeviceId"

# ── Create directories ────────────────────────────────────────────────────────
Write-Step "Installing PromptShield core..."
New-Item -ItemType Directory -Force -Path "$INSTALL\bin", "$INSTALL\config", "$INSTALL\rules" | Out-Null

# Download hook scripts
foreach ($script in @("pre-tool-hook.js", "usage-reporter.js", "claude-md-sync.js", "review-logger.js", "generate-claude-md.js", "session-start.js")) {
    try {
        Invoke-WebRequest "$RAW/devguard/$script" -OutFile "$INSTALL\bin\$script" -UseBasicParsing -ErrorAction Stop
    } catch { Write-Warn "Could not download $script" }
}

# Write config
$config = @{
    version        = $VERSION
    developerToken = $DeviceId
    developerName  = $Name
    gatewayUrl     = $GATEWAY
    mode           = $Mode
    os             = "windows"
    installedAt    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json
Set-Content "$INSTALL\config\config.json" $config
Write-OK "Core installed at $INSTALL"

# ── Install team-claude CLI ───────────────────────────────────────────────────
Write-Step "Installing team-claude CLI..."
$cliDir = "$env:TEMP\ps-cli-install"
New-Item -ItemType Directory -Force -Path $cliDir | Out-Null
try {
    Invoke-WebRequest "$RAW/cli/package.json"   -OutFile "$cliDir\package.json"   -UseBasicParsing
    Invoke-WebRequest "$RAW/cli/team-claude.js" -OutFile "$cliDir\team-claude.js" -UseBasicParsing
    Set-Location $cliDir
    npm install --silent 2>$null
    npm install -g . --silent 2>$null
    Write-OK "team-claude CLI installed"
} catch {
    Write-Warn "npm install failed — copying manually"
    Copy-Item "$cliDir\team-claude.js" "$INSTALL\bin\team-claude.js"
    # Create .cmd wrapper for Windows
    Set-Content "$INSTALL\bin\team-claude.cmd" "@node `"%~dp0team-claude.js`" %*"
}
Set-Location $PSScriptRoot

# ── Sync CLAUDE.md ────────────────────────────────────────────────────────────
Write-Step "Syncing CLAUDE.md..."
node "$INSTALL\bin\claude-md-sync.js" --silent 2>$null
if ($LASTEXITCODE -eq 0) { Write-OK "CLAUDE.md synced" }
else { Write-Warn "Could not sync CLAUDE.md — will retry on first use" }

# ── Check for empty CLAUDE.md ─────────────────────────────────────────────────
$claudeMdPath = Join-Path (Get-Location) "CLAUDE.md"
if (-not (Test-Path $claudeMdPath) -or (Get-Item $claudeMdPath).Length -eq 0) {
    Write-Host ""
    Write-Host "⚠ CLAUDE.md not found in this directory." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Auto-generate using Claude API (~500 tokens)"
    Write-Host "  [2] Copy starter template (no tokens)"
    Write-Host "  [3] Skip"
    Write-Host ""
    $choice = Read-Host "Choose [1/2/3]"
    switch ($choice) {
        "1" {
            node "$INSTALL\bin\generate-claude-md.js" 2>$null
            if ($LASTEXITCODE -eq 0) { Write-OK "CLAUDE.md generated" }
            else { Write-Warn "Auto-generate failed — copying template"; $choice = "2" }
        }
        "2" {
            try {
                Invoke-WebRequest "$RAW/templates/CLAUDE.md.template" -OutFile $claudeMdPath -UseBasicParsing
                Write-OK "Starter CLAUDE.md copied — fill in your project details"
            } catch { Write-Warn "Could not download template" }
        }
        default { Write-Warn "Skipped — run 'team-claude init' later" }
    }
}

# ── Check deliberation ────────────────────────────────────────────────────────
$delibPath = Join-Path (Get-Location) ".deliberation"
if (-not (Test-Path $delibPath) -or (Get-ChildItem $delibPath -ErrorAction SilentlyContinue).Count -eq 0) {
    Write-Host ""
    Write-Host "⚠ No .deliberation/ directory found." -ForegroundColor Yellow
    Write-Host "  [1] Create empty structure   [2] Skip"
    $choice = Read-Host "Choose [1/2]"
    if ($choice -eq "1") {
        New-Item -ItemType Directory -Force -Path "$delibPath\.example" | Out-Null
        Write-OK ".deliberation/ structure created"
    } else { Write-Warn "Skipped — run /kickoff to start deliberation" }
}

# ── Register with gateway ─────────────────────────────────────────────────────
Write-Step "Registering with gateway..."
try {
    $body = @{ name=$Name; os="windows"; mode=$Mode; version=$VERSION } | ConvertTo-Json
    Invoke-RestMethod "$GATEWAY/api/v1/developers/register" -Method Post `
        -Headers @{ Authorization="Bearer $DeviceId"; "Content-Type"="application/json" } `
        -Body $body | Out-Null
    Write-OK "Registered with gateway"
} catch { Write-Warn "Gateway offline — will register when connected" }

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "✓ PromptShield installed!" -ForegroundColor Green
Write-Host ""
Write-Host "  Device:  $Name"
Write-Host "  Mode:    $Mode"
Write-Host ""
Write-Host "  Commands:"
Write-Host "  team-claude login    — verify your device ID"
Write-Host "  team-claude chat     — start a tracked session"
Write-Host "  team-claude status   — usage vs quota"
Write-Host ""
Write-Host "  Dashboard: $PAGES/mode-b.html" -ForegroundColor Cyan
Write-Host ""
