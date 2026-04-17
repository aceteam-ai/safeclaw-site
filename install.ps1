# SafeClaw Windows Installer
# Usage: iwr -useb https://safeclaw.sh/install.ps1 | iex
# Safe to run multiple times — existing config is preserved.

Write-Host ""
Write-Host "  SafeClaw" -ForegroundColor Cyan
Write-Host "  Run AI agents safely - OpenClaw + Agent Safety Net" -ForegroundColor DarkGray
Write-Host ""

$containerCmd = ""
if ((Get-Command podman -ErrorAction SilentlyContinue) -and (podman info 2>$null)) {
    $containerCmd = "podman"
} elseif ((Get-Command docker -ErrorAction SilentlyContinue) -and (docker info 2>$null)) {
    $containerCmd = "docker"
}

function Install-ContainerRuntime {
    Write-Host ""
    Write-Host "  No container runtime (Docker/Podman) detected." -ForegroundColor Yellow
    Write-Host ""

    # Try winget first, then choco
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "  Installing Docker Desktop via winget..." -ForegroundColor Cyan
        winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
        Write-Host ""
        Write-Host "  Docker Desktop installed. Please launch it from the Start menu," -ForegroundColor Yellow
        Write-Host "  then re-run this installer." -ForegroundColor Yellow
        exit 0
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "  Installing Docker Desktop via Chocolatey..." -ForegroundColor Cyan
        choco install docker-desktop -y
        Write-Host ""
        Write-Host "  Docker Desktop installed. Please launch it from the Start menu," -ForegroundColor Yellow
        Write-Host "  then re-run this installer." -ForegroundColor Yellow
        exit 0
    } else {
        Write-Host "  Install Docker Desktop manually:" -ForegroundColor Red
        Write-Host "    https://docs.docker.com/desktop/install/windows/"
        Write-Host "  Or install Podman:"
        Write-Host "    https://podman.io/docs/installation"
        exit 1
    }
}

Write-Host "  What is SafeClaw?" -ForegroundColor White
Write-Host "  SafeClaw = OpenClaw (AI agent platform) + AEP (safety proxy)." -ForegroundColor DarkGray
Write-Host "  The agent runs in a container. The proxy blocks dangerous actions," -ForegroundColor DarkGray
Write-Host "  tracks cost, and signs every decision. Your files stay safe." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  What do you want to install?" -ForegroundColor White
Write-Host ""
Write-Host "  [1] Full SafeClaw (recommended)" -ForegroundColor Cyan
Write-Host "      OpenClaw agent + Agent Safety Net, all in containers" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [2] Safety proxy only" -ForegroundColor Cyan
Write-Host "      For existing agents (Claude Code, CrewAI, LangChain, etc.)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [3] Developer mode (git clone + uv sync)" -ForegroundColor Cyan
Write-Host "      Clone aceteam-aep and run from source - for hacking on the proxy" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [4] I already have it installed" -ForegroundColor Cyan
Write-Host ""
$choice = Read-Host "  Choice [1]"
if ($null -eq $choice -or $choice -eq "") { $choice = "1" }

if ($choice -eq "1") {
    # Full SafeClaw
    if (-not $containerCmd) {
        $yn = Read-Host "  Container runtime required. Install one now? [Y/n]"
        if ($null -eq $yn -or $yn -eq "" -or $yn -match "^[Yy]") {
            Install-ContainerRuntime
        } else {
            Write-Host "  Install Docker Desktop: https://docs.docker.com/desktop/install/windows/"
            exit 1
        }
    }

    $safePath = Join-Path $HOME "safeclaw"
    if (-not (Test-Path $safePath)) { New-Item -Path $safePath -ItemType Directory | Out-Null }

    Write-Host ""
    Write-Host "  Pulling SafeClaw images via $containerCmd..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    [1/2] OpenClaw agent image" -ForegroundColor DarkGray
    & $containerCmd pull ghcr.io/aceteam-ai/safeclaw:latest
    Write-Host "    [2/2] Agent Safety Net image" -ForegroundColor DarkGray
    & $containerCmd pull ghcr.io/aceteam-ai/aep-proxy:latest

    # Always download/update compose files (idempotent)
    $composeFile = Join-Path $safePath "docker-compose.yml"
    $safeComposeFile = Join-Path $safePath "docker-compose.safe.yml"
    Write-Host "    Downloading compose files..." -ForegroundColor DarkGray
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/aceteam-ai/safeclaw/main/docker-compose.yml" -OutFile $composeFile -UseBasicParsing
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/aceteam-ai/safeclaw/main/docker-compose.safe.yml" -OutFile $safeComposeFile -UseBasicParsing
    try {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/aceteam-ai/safeclaw/main/.env.example" -OutFile (Join-Path $safePath ".env.example") -UseBasicParsing
    } catch {}

    # Create .env if missing
    $envFile = Join-Path $safePath ".env"
    if (-not (Test-Path $envFile)) {
        $envExample = Join-Path $safePath ".env.example"
        if (Test-Path $envExample) {
            Copy-Item $envExample $envFile
        } else {
            @"
# SafeClaw environment - add your API keys here
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
OPENCLAW_IMAGE=ghcr.io/aceteam-ai/safeclaw:latest
OPENCLAW_CONFIG_DIR=./config
OPENCLAW_WORKSPACE_DIR=./workspace
"@ | Out-File -FilePath $envFile -Encoding utf8
        }
        New-Item -Path (Join-Path $safePath "config") -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $safePath "workspace") -ItemType Directory -Force | Out-Null
    }

    Write-Host ""
    Write-Host "  Ready." -ForegroundColor Green
    Write-Host ""
    Write-Host "  SafeClaw = OpenClaw + Agent Safety Net" -ForegroundColor White
    Write-Host "  The agent runs in a container. It cannot access your files," -ForegroundColor DarkGray
    Write-Host "  email, or credentials. The safety proxy blocks dangerous" -ForegroundColor DarkGray
    Write-Host "  actions before they execute." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Start SafeClaw:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    cd $safePath"
    Write-Host "    # Add your API keys to .env first"
    Write-Host "    $containerCmd compose -f docker-compose.yml -f docker-compose.safe.yml up"
    Write-Host ""
    Write-Host "  Dashboard:  http://localhost:8899/dashboard/"
    Write-Host "  Agent UI:   http://localhost:18789/"
    Write-Host "  API Keys:   Edit $safePath\.env"
    Write-Host "  Workspace:  $safePath\workspace"

} elseif ($choice -eq "2") {
    # Safety proxy only
    if (-not $containerCmd) {
        $yn = Read-Host "  Container runtime required. Install one now? [Y/n]"
        if ($null -eq $yn -or $yn -eq "" -or $yn -match "^[Yy]") {
            Install-ContainerRuntime
        } else {
            Write-Host "  Install Docker Desktop: https://docs.docker.com/desktop/install/windows/"
            exit 1
        }
    }

    Write-Host "  Pulling Agent Safety Net image..." -ForegroundColor Cyan
    & $containerCmd pull ghcr.io/aceteam-ai/aep-proxy:latest

    $safePath = Join-Path $HOME "safeclaw"
    if (-not (Test-Path $safePath)) { New-Item -Path $safePath -ItemType Directory | Out-Null }

    Write-Host ""
    Write-Host "  Ready." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Safety proxy installed." -ForegroundColor White
    Write-Host "  This adds safety to any existing agent (Claude Code, CrewAI," -ForegroundColor DarkGray
    Write-Host "  LangChain, etc.) - it sits between your agent and the LLM." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Start the safety proxy:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    $containerCmd run -p 8899:8899 -v ${safePath}:/workspace ghcr.io/aceteam-ai/aep-proxy"
    Write-Host ""
    Write-Host "  Then point your agent at the proxy:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    `$env:OPENAI_BASE_URL = 'http://localhost:8899/v1'"
    Write-Host ""
    Write-Host "  Dashboard:  http://localhost:8899/dashboard/"
    Write-Host "  API Keys:   Configure in Dashboard > Settings"
    Write-Host "  Workspace:  $safePath"
    Write-Host ""
    Write-Host "  Want the full agent too? Re-run this installer and choose option 1." -ForegroundColor DarkGray

} elseif ($choice -eq "3") {
    # Developer mode: clone aceteam-aep and run via uv sync --extra proxy
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "  git not found. Install git first, then re-run." -ForegroundColor Red
        exit 1
    }

    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Host "  Installing uv..." -ForegroundColor Cyan
        Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
        $env:Path = "$HOME\.local\bin;$env:Path"
    }

    $repoDir = if ($env:ACETEAM_AEP_DIR) { $env:ACETEAM_AEP_DIR } else { Join-Path $HOME "aceteam-aep" }

    if (Test-Path (Join-Path $repoDir ".git")) {
        Write-Host "  Updating existing clone at $repoDir..." -ForegroundColor Cyan
        git -C $repoDir pull --ff-only
    } else {
        Write-Host "  Cloning aceteam-aep into $repoDir..." -ForegroundColor Cyan
        git clone https://github.com/aceteam-ai/aceteam-aep.git $repoDir
    }

    Write-Host "  Installing proxy dependencies via uv sync --extra proxy..." -ForegroundColor Cyan
    Push-Location $repoDir
    try {
        uv sync --extra proxy
    } finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "  Ready." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Agent Safety Net cloned to $repoDir." -ForegroundColor White
    Write-Host "  Run commands from the repo with 'uv run'. Edit the source and re-run to iterate." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Start the safety proxy:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    cd $repoDir"
    Write-Host "    uv run aceteam-aep proxy --port 8899"
    Write-Host ""
    Write-Host "  Or wrap any agent:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    cd $repoDir; uv run aceteam-aep wrap -- python my_agent.py"
    Write-Host ""
    Write-Host "  Dashboard: http://localhost:8899/dashboard/"

} elseif ($choice -eq "4") {
    Write-Host "  Great." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Full SafeClaw (recommended):" -ForegroundColor Cyan
    Write-Host "    cd ~/safeclaw"
    Write-Host "    docker compose -f docker-compose.yml -f docker-compose.safe.yml up"
    Write-Host ""
    Write-Host "  Safety proxy only:" -ForegroundColor Cyan
    Write-Host "    docker run -p 8899:8899 ghcr.io/aceteam-ai/aep-proxy"
    Write-Host ""
    Write-Host "  Developer mode (from source):" -ForegroundColor Cyan
    Write-Host "    cd ~/aceteam-aep; uv run aceteam-aep proxy --port 8899"
    Write-Host ""
    Write-Host "  Dashboard: http://localhost:8899/dashboard/"
} else {
    Write-Host "  Invalid choice. Run this script again." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  SafeClaw: github.com/aceteam-ai/safeclaw" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Connect:  " -NoNewline; Write-Host "linkedin.com/in/sunapi386" -ForegroundColor Cyan
Write-Host "  Star:     " -NoNewline; Write-Host "github.com/aceteam-ai/safeclaw" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Reply " -NoNewline; Write-Host "a" -ForegroundColor Green -NoNewline; Write-Host " to get a free SafeClaw hosted instance coupon!"
Write-Host ""
