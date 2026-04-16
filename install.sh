#!/usr/bin/env bash
# SafeClaw Installer — https://safeclaw.sh
#
# Usage: curl -fsSL https://safeclaw.sh/install.sh | bash
#
# SafeClaw = OpenClaw + AEP safety proxy.
# This script installs everything you need to run AI agents safely.
# Safe to run multiple times — existing config is preserved.

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}${CYAN}  SafeClaw${NC}"
echo -e "${DIM}  Run AI agents safely — OpenClaw + AEP safety proxy${NC}"
echo ""

# ---------------------------------------------------------------------------
# Detect container runtime: prefer Podman, fall back to Docker
# Verify daemon is actually running, not just that the CLI exists
# ---------------------------------------------------------------------------
CONTAINER_CMD=""
if command -v podman &>/dev/null && podman info &>/dev/null; then
    CONTAINER_CMD="podman"
elif command -v docker &>/dev/null && docker info &>/dev/null; then
    CONTAINER_CMD="docker"
elif command -v podman &>/dev/null; then
    # Podman CLI installed but not running
    echo -e "  ${YELLOW}Podman is installed but not running.${NC}"
    echo -e "  ${DIM}Starting Podman...${NC}"
    if podman machine start 2>/dev/null && podman info &>/dev/null; then
        CONTAINER_CMD="podman"
        echo -e "  ${GREEN}Podman started.${NC}"
    else
        echo -e "  ${DIM}Could not auto-start. Try manually:${NC}"
        echo "    podman machine start"
        echo ""
        # Don't exit — fall through to install_container_runtime if needed
    fi
elif command -v docker &>/dev/null; then
    # Docker CLI installed but daemon not running — suggest Podman instead
    echo -e "  ${YELLOW}Docker is installed but the daemon is not running.${NC}"
    echo -e "  ${DIM}We recommend Podman (no daemon needed, no Docker Desktop license).${NC}"
    echo ""
    # Don't exit — fall through to install_container_runtime which installs Podman
fi

# ---------------------------------------------------------------------------
# Auto-install Docker/Podman if missing
# ---------------------------------------------------------------------------
install_container_runtime() {
    echo ""
    echo -e "  ${YELLOW}No container runtime (Docker/Podman) detected.${NC}"
    echo ""

    local os
    os="$(uname -s)"

    case "$os" in
        Darwin)
            if command -v brew &>/dev/null; then
                echo -e "  ${CYAN}Installing Podman via Homebrew...${NC}"
                echo -e "  ${DIM}(Free, no Docker Desktop license required)${NC}"
                brew install podman
                echo ""
                echo -e "  ${CYAN}Initializing Podman machine...${NC}"
                podman machine init 2>/dev/null || true
                podman machine start 2>/dev/null || true
                if podman info &>/dev/null; then
                    CONTAINER_CMD="podman"
                    echo -e "  ${GREEN}Podman is ready.${NC}"
                else
                    echo -e "  ${YELLOW}Podman installed. Start it manually, then re-run:${NC}"
                    echo "    podman machine init && podman machine start"
                    exit 0
                fi
            else
                echo -e "  ${RED}Homebrew not found.${NC} Install Podman manually:"
                echo "    https://podman.io/docs/installation"
                echo "  Or install Docker:"
                echo "    https://docs.docker.com/desktop/install/mac/"
                exit 1
            fi
            ;;
        Linux)
            if command -v apt-get &>/dev/null; then
                echo -e "  ${CYAN}Installing Podman via apt...${NC}"
                sudo apt-get update -qq && sudo apt-get install -y -qq podman
            elif command -v dnf &>/dev/null; then
                echo -e "  ${CYAN}Installing Podman via dnf...${NC}"
                sudo dnf install -y podman
            elif command -v pacman &>/dev/null; then
                echo -e "  ${CYAN}Installing Podman via pacman...${NC}"
                sudo pacman -S --noconfirm podman
            elif command -v zypper &>/dev/null; then
                echo -e "  ${CYAN}Installing Podman via zypper...${NC}"
                sudo zypper install -y podman
            else
                echo -e "  ${RED}Could not detect package manager.${NC}"
                echo "  Install Podman: https://podman.io/docs/installation"
                echo "  Or Docker: https://docs.docker.com/engine/install/"
                exit 1
            fi

            # Re-detect after install
            if command -v podman &>/dev/null && podman info &>/dev/null; then
                CONTAINER_CMD="podman"
            elif command -v docker &>/dev/null && docker info &>/dev/null; then
                CONTAINER_CMD="docker"
            else
                echo -e "  ${RED}Installation succeeded but daemon not running.${NC}"
                echo "  Try: sudo systemctl start podman"
                exit 1
            fi
            echo -e "  ${GREEN}Installed ${CONTAINER_CMD}.${NC}"
            ;;
        *)
            echo -e "  ${RED}Unsupported OS: $os${NC}"
            echo "  Install Docker: https://docs.docker.com/get-docker/"
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Interactive preference selector
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    echo -e "  ${BOLD}What is SafeClaw?${NC}"
    echo -e "  ${DIM}SafeClaw = OpenClaw (AI agent platform) + AEP (safety proxy).${NC}"
    echo -e "  ${DIM}The agent runs in a container. The proxy blocks dangerous actions,${NC}"
    echo -e "  ${DIM}tracks cost, and signs every decision. Your files stay safe.${NC}"
    echo ""
    echo -e "  ${BOLD}What do you want to install?${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} ${BOLD}Full SafeClaw${NC} ${GREEN}(recommended)${NC}"
    echo -e "      ${DIM}OpenClaw agent + AEP safety proxy, all in containers${NC}"
    echo ""
    echo -e "  ${CYAN}[2]${NC} ${BOLD}Safety proxy only${NC}"
    echo -e "      ${DIM}For existing agents (Claude Code, CrewAI, LangChain, etc.)${NC}"
    echo ""
    echo -e "  ${CYAN}[3]${NC} ${BOLD}pip install (developer mode)${NC}"
    echo -e "      ${DIM}Runs on host, no container — for development/hacking${NC}"
    echo ""
    echo -e "  ${CYAN}[4]${NC} ${BOLD}I already have it installed${NC}"
    echo ""
    printf "  Choice [1]: "
    read -r choice </dev/tty
    choice=${choice:-1}
else
    # Non-interactive (piped) — default to full SafeClaw if container available, else proxy
    if [ -n "$CONTAINER_CMD" ]; then
        choice=1
    else
        choice=3
    fi
fi

case "$choice" in
    1)
        # Full SafeClaw: OpenClaw + AEP proxy
        if [ -z "$CONTAINER_CMD" ]; then
            if [ -t 1 ]; then
                echo ""
                printf "  Container runtime required. Install one now? [Y/n]: "
                read -r yn </dev/tty
                yn=${yn:-Y}
                if [[ "$yn" =~ ^[Yy] ]]; then
                    install_container_runtime
                else
                    echo ""
                    echo "  Install Podman: https://podman.io/docs/installation"
                    echo "  Or Docker: https://docs.docker.com/get-docker/"
                    exit 1
                fi
            else
                install_container_runtime
            fi
        fi

        SAFECLAW_DIR="$HOME/safeclaw"
        mkdir -p "$SAFECLAW_DIR"

        echo ""
        echo -e "  ${CYAN}Pulling SafeClaw images in parallel via ${CONTAINER_CMD}...${NC}"
        echo -e "  ${DIM}  AEP safety proxy (smaller, demo-ready first)${NC}"
        echo -e "  ${DIM}  OpenClaw agent${NC}"
        echo ""

        PROXY_LOG=$(mktemp)
        SAFECLAW_LOG=$(mktemp)

        # Proxy first (smaller, primary demo target)
        $CONTAINER_CMD pull ghcr.io/aceteam-ai/aep-proxy:latest >"$PROXY_LOG" 2>&1 &
        PROXY_PID=$!
        $CONTAINER_CMD pull ghcr.io/aceteam-ai/safeclaw:latest >"$SAFECLAW_LOG" 2>&1 &
        SAFECLAW_PID=$!

        # Report proxy first since it should finish first
        if wait "$PROXY_PID"; then
            echo -e "  ${GREEN}AEP safety proxy pulled.${NC}"
        else
            echo -e "  ${RED}AEP safety proxy pull failed.${NC}"
            tail -5 "$PROXY_LOG" | sed 's/^/    /'
        fi

        if wait "$SAFECLAW_PID"; then
            echo -e "  ${GREEN}OpenClaw agent pulled.${NC}"
        else
            echo -e "  ${RED}OpenClaw agent pull failed.${NC}"
            tail -5 "$SAFECLAW_LOG" | sed 's/^/    /'
        fi

        rm -f "$PROXY_LOG" "$SAFECLAW_LOG"

        # Always download/update compose files (idempotent)
        echo -e "  ${DIM}  Downloading compose files...${NC}"
        curl -fsSL "https://raw.githubusercontent.com/aceteam-ai/safeclaw/main/docker-compose.yml" \
            -o "$SAFECLAW_DIR/docker-compose.yml"
        curl -fsSL "https://raw.githubusercontent.com/aceteam-ai/safeclaw/main/docker-compose.safe.yml" \
            -o "$SAFECLAW_DIR/docker-compose.safe.yml"
        curl -fsSL "https://raw.githubusercontent.com/aceteam-ai/safeclaw/main/.env.example" \
            -o "$SAFECLAW_DIR/.env.example" 2>/dev/null || true

        # Create .env if missing
        if [ ! -f "$SAFECLAW_DIR/.env" ]; then
            if [ -f "$SAFECLAW_DIR/.env.example" ]; then
                cp "$SAFECLAW_DIR/.env.example" "$SAFECLAW_DIR/.env"
            else
                cat > "$SAFECLAW_DIR/.env" <<'ENVEOF'
# SafeClaw environment — add your API keys here
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
OPENCLAW_IMAGE=ghcr.io/aceteam-ai/safeclaw:latest
OPENCLAW_CONFIG_DIR=./config
OPENCLAW_WORKSPACE_DIR=./workspace
ENVEOF
            fi
            mkdir -p "$SAFECLAW_DIR/config" "$SAFECLAW_DIR/workspace"
        fi

        echo ""
        echo -e "  ${GREEN}${BOLD}Ready.${NC}"
        echo ""
        echo -e "  ${BOLD}SafeClaw = OpenClaw + AEP safety proxy${NC}"
        echo -e "  ${DIM}The agent runs in a container. It cannot access your files,${NC}"
        echo -e "  ${DIM}email, or credentials. The safety proxy blocks dangerous${NC}"
        echo -e "  ${DIM}actions before they execute.${NC}"
        echo ""
        echo -e "  ${CYAN}Start SafeClaw:${NC}"
        echo ""
        echo "    cd ~/safeclaw"
        echo "    # Add your API keys to .env first"
        echo "    $CONTAINER_CMD compose -f docker-compose.yml -f docker-compose.safe.yml up"
        echo ""
        echo -e "  ${CYAN}Dashboard:${NC}       http://localhost:8899/dashboard/"
        echo -e "  ${CYAN}Agent UI:${NC}        http://localhost:18789/"
        echo -e "  ${CYAN}API Keys:${NC}        Edit ~/safeclaw/.env"
        echo -e "  ${CYAN}Workspace:${NC}       ~/safeclaw/workspace"
        ;;
    2)
        # Safety proxy only — for existing agents
        if [ -z "$CONTAINER_CMD" ]; then
            if [ -t 1 ]; then
                echo ""
                printf "  Container runtime required. Install one now? [Y/n]: "
                read -r yn </dev/tty
                yn=${yn:-Y}
                if [[ "$yn" =~ ^[Yy] ]]; then
                    install_container_runtime
                else
                    echo ""
                    echo "  Install Podman: https://podman.io/docs/installation"
                    echo "  Or Docker: https://docs.docker.com/get-docker/"
                    exit 1
                fi
            else
                install_container_runtime
            fi
        fi

        echo -e "  ${CYAN}Pulling AEP safety proxy image via ${CONTAINER_CMD}...${NC}"
        $CONTAINER_CMD pull ghcr.io/aceteam-ai/aep-proxy:latest 2>&1 | tail -3

        mkdir -p "$HOME/safeclaw"

        echo ""
        echo -e "  ${GREEN}${BOLD}Ready.${NC}"
        echo ""
        echo -e "  ${BOLD}Safety proxy installed.${NC}"
        echo -e "  ${DIM}This adds safety to any existing agent (Claude Code, CrewAI,${NC}"
        echo -e "  ${DIM}LangChain, etc.) — it sits between your agent and the LLM.${NC}"
        echo ""
        echo -e "  ${CYAN}Start the safety proxy:${NC}"
        echo ""
        echo "    $CONTAINER_CMD run -p 8899:8899 -v ~/safeclaw:/workspace ghcr.io/aceteam-ai/aep-proxy"
        echo ""
        echo -e "  ${CYAN}Then point your agent at the proxy:${NC}"
        echo ""
        echo "    export OPENAI_BASE_URL=http://localhost:8899/v1"
        echo ""
        echo -e "  ${CYAN}Dashboard:${NC}  http://localhost:8899/dashboard/"
        echo -e "  ${CYAN}API Keys:${NC}   Configure in Dashboard > Settings"
        echo -e "  ${CYAN}Workspace:${NC}  ~/safeclaw"
        echo ""
        echo -e "  ${DIM}Want the full agent too? Re-run this installer and choose option 1.${NC}"
        ;;
    3)
        # pip path — isolated venv via `uv tool install`
        if ! command -v uv &>/dev/null; then
            echo -e "  ${CYAN}Installing uv...${NC}"
            curl -LsSf https://astral.sh/uv/install.sh | sh
            export PATH="$HOME/.local/bin:$PATH"
        fi

        echo -e "  ${CYAN}Installing aceteam-aep (isolated tool venv)...${NC}"
        if command -v uv &>/dev/null; then
            # --force lets re-runs upgrade cleanly; do NOT silence errors
            uv tool install --force "aceteam-aep[all]"
            uv tool update-shell || true
            # Add tool bin dir to PATH for this session (piped curl|bash shell)
            UV_TOOL_BIN="$(uv tool dir --bin 2>/dev/null || echo "$HOME/.local/bin")"
            export PATH="$UV_TOOL_BIN:$PATH"
        else
            echo -e "  ${YELLOW}uv not available — falling back to pip --user${NC}"
            if command -v pip3 &>/dev/null; then
                pip3 install --user "aceteam-aep[all]"
            elif command -v pip &>/dev/null; then
                pip install --user "aceteam-aep[all]"
            elif command -v python3 &>/dev/null; then
                python3 -m pip install --user "aceteam-aep[all]"
            else
                echo -e "  ${RED}No Python package manager found (uv, pip, pip3, python3).${NC}"
                exit 1
            fi
            export PATH="$HOME/.local/bin:$PATH"
        fi

        # Verify the install actually works end-to-end (not just that the bin exists)
        if ! aceteam-aep --help >/dev/null 2>&1; then
            echo ""
            echo -e "  ${RED}Installation completed but verification failed.${NC}"
            echo -e "  ${DIM}Running 'aceteam-aep --help' to show the error:${NC}"
            echo ""
            aceteam-aep --help || true
            echo ""
            echo -e "  ${YELLOW}Add the tool bin dir to your PATH, then re-run:${NC}"
            echo "    export PATH=\"${UV_TOOL_BIN:-$HOME/.local/bin}:\$PATH\""
            exit 1
        fi

        echo ""
        echo -e "  ${GREEN}${BOLD}Ready.${NC}"
        echo ""
        echo -e "  ${BOLD}AEP safety proxy installed (pip / developer mode).${NC}"
        echo -e "  ${DIM}This installs only the safety proxy, not the full OpenClaw agent.${NC}"
        echo -e "  ${DIM}For the full SafeClaw stack, re-run and choose option 1.${NC}"
        echo ""
        echo -e "  ${CYAN}Start the safety proxy:${NC}"
        echo ""
        echo "    aceteam-aep proxy --port 8899"
        echo ""
        echo -e "  ${CYAN}Or wrap any agent:${NC}"
        echo ""
        echo "    aceteam-aep wrap -- python my_agent.py"
        echo ""
        echo -e "  ${CYAN}Dashboard:${NC} http://localhost:8899/dashboard/"
        ;;
    4)
        echo -e "  ${GREEN}Great.${NC}"
        echo ""
        echo -e "  ${CYAN}Full SafeClaw (recommended):${NC}"
        echo "    cd ~/safeclaw && podman compose -f docker-compose.yml -f docker-compose.safe.yml up"
        echo ""
        echo -e "  ${CYAN}Safety proxy only:${NC}"
        echo "    podman run -p 8899:8899 ghcr.io/aceteam-ai/aep-proxy"
        echo ""
        echo -e "  ${CYAN}pip (developer mode):${NC}"
        echo "    aceteam-aep proxy --port 8899"
        echo ""
        echo -e "  Dashboard: http://localhost:8899/dashboard/"
        ;;
    *)
        echo -e "  ${RED}Invalid choice.${NC} Run this script again."
        exit 1
        ;;
esac

echo ""
echo -e "${DIM}  SafeClaw: github.com/aceteam-ai/safeclaw${NC}"
echo -e "${DIM}  Workshop: github.com/aceteam-ai/aep-quickstart/blob/main/workshop/bootcamp.html${NC}"
echo ""

# ---------------------------------------------------------------------------
# Workshop outro — QR codes + coupon prompt
# ---------------------------------------------------------------------------
if [ -t 1 ] && command -v qrencode &>/dev/null; then
    echo -e "  ${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}Connect with me on LinkedIn${NC}        ${BOLD}Star SafeClaw on GitHub${NC}"
    echo ""

    LI_QR=$(qrencode -t UTF8 -m 1 "https://www.linkedin.com/in/sunapi386/" 2>/dev/null)
    GH_QR=$(qrencode -t UTF8 -m 1 "https://github.com/aceteam-ai/safeclaw" 2>/dev/null)

    if [ -n "$LI_QR" ] && [ -n "$GH_QR" ]; then
        paste <(echo "$LI_QR") <(echo "$GH_QR") | while IFS=$'\t' read -r left right; do
            printf "  %-36s  %s\n" "$left" "$right"
        done
    fi

    echo ""
    echo -e "  ${CYAN}linkedin.com/in/sunapi386${NC}          ${CYAN}github.com/aceteam-ai/safeclaw${NC}"
    echo ""
    echo -e "  ${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}Partner offer: Pale Blue Dot × SafeClaw${NC}"
    echo -e "  ${DIM}palebluedot.ai is partnered with us.${NC}"
    echo ""
    echo -e "  ${BOLD}\$200${NC} ${BOLD}in AceTeam credits${NC} — ${BOLD}50 vouchers${NC} available."
    echo ""
    echo -e "  ${CYAN}To claim:${NC}"
    echo "    1. Sign up at aceteam.ai"
    echo "    2. Star github.com/aceteam-ai/safeclaw"
    echo "    3. DM linkedin.com/in/sunapi386 (mention TokenRouter)"
    echo ""
    echo -e "  ${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
elif [ -t 1 ]; then
    echo -e "  ${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}Connect:${NC}  ${CYAN}linkedin.com/in/sunapi386${NC}"
    echo -e "  ${BOLD}Star:${NC}     ${CYAN}github.com/aceteam-ai/safeclaw${NC}"
    echo ""
    echo -e "  ${BOLD}Partner offer: Pale Blue Dot × SafeClaw${NC}"
    echo -e "  ${BOLD}\$200${NC} AceTeam credits, ${BOLD}50 vouchers${NC} available."
    echo -e "  ${DIM}Sign up at aceteam.ai, star this repo, then DM Jason on LinkedIn (mention TokenRouter).${NC}"
    echo ""
fi
