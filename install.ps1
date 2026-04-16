# SafeClaw Windows Installer
# Usage: iwr -useb https://safeclaw.sh/install.ps1 | iex

Write-Host ""
Write-Host "  SafeClaw" -ForegroundColor Cyan
Write-Host "  The safe version of OpenClaw" -ForegroundColor DarkGray
Write-Host ""

$containerCmd = ""
if (Get-Command podman -ErrorAction SilentlyContinue) {
    $containerCmd = "podman"
} elseif (Get-Command docker -ErrorAction SilentlyContinue) {
    $containerCmd = "docker"
}

Write-Host "  How do you want to run SafeClaw?"
Write-Host ""
Write-Host "  [1] Container ($($containerCmd if ($containerCmd) else "Podman/Docker")) - recommended" -ForegroundColor Cyan
Write-Host "  [2] pip install - runs on host, developer mode" -ForegroundColor Cyan
Write-Host ""
$choice = Read-Host "  Choice [1]"
if ($null -eq $choice -or $choice -eq "") { $choice = "1" }

if ($choice -eq "1") {
    if (-not $containerCmd) {
        Write-Host "  No container runtime found." -ForegroundColor Red
        Write-Host "  Install Podman: https://podman.io/docs/installation"
        Write-Host "  Or Docker Desktop: https://docs.docker.com/desktop/install/windows/"
        exit 1
    }

    Write-Host "  Pulling SafeClaw proxy image..." -ForegroundColor Cyan
    & $containerCmd pull ghcr.io/aceteam-ai/aep-proxy:latest

    $safePath = Join-Path $HOME "safeclaw"
    if (-not (Test-Path $safePath)) {
        New-Item -Path $safePath -ItemType Directory
    }

    Write-Host ""
    Write-Host "  Ready." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Start SafeClaw:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    $containerCmd run -p 8899:8899 -v ${safePath}:/workspace ghcr.io/aceteam-ai/aep-proxy"
    Write-Host ""
    Write-Host "  Dashboard:  http://localhost:8899/aep/"
    Write-Host "  API Keys:   Configure in Dashboard > Settings"
    Write-Host "  Workspace:  $safePath"
} elseif ($choice -eq "2") {
    Write-Host "  Installing aceteam-aep via pip..." -ForegroundColor Cyan
    # Try multiple ways to install pip packages on Windows, including user install and breaking system packages logic (less common on Windows but good for consistency)
    $pipArgs = @("install", "aceteam-aep[all]", "--quiet")

    # Check if we should try a user install
    try {
        & python -m pip $pipArgs --user
    } catch {
        & python -m pip $pipArgs
    }

    if (-not (Get-Command aceteam-aep -ErrorAction SilentlyContinue)) {
        Write-Host "  Installation failed. Please install aceteam-aep manually: pip install aceteam-aep[all]" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "  Ready." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Start SafeClaw:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    aceteam-aep proxy --port 8899"
}
