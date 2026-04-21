#!/usr/bin/env bash
# SafeClaw Installer — https://safeclaw.sh
#
# Usage: curl -fsSL https://safeclaw.sh/install.sh | bash
#
# SafeClaw = OpenClaw + Agent Safety Net.
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
echo -e "${DIM}  Run AI agents safely — OpenClaw + Agent Safety Net${NC}"
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
            if ! command -v brew &>/dev/null; then
                echo -e "  ${YELLOW}Homebrew not installed on this Mac.${NC}"
                echo -e "  ${DIM}Homebrew is the cleanest way to install Podman (no Docker Desktop license).${NC}"
                echo ""

                local install_brew="Y"
                if [ -t 1 ]; then
                    printf "  Install Homebrew now? Runs the official installer from brew.sh [Y/n]: "
                    read -r install_brew </dev/tty
                    install_brew=${install_brew:-Y}
                fi

                if [[ "$install_brew" =~ ^[Yy] ]]; then
                    echo -e "  ${CYAN}Installing Homebrew...${NC}"
                    echo -e "  ${DIM}(You'll be prompted for your password. First run may also install Xcode Command Line Tools.)${NC}"
                    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
                        echo -e "  ${RED}Homebrew installer failed.${NC} Install it manually from https://brew.sh then re-run."
                        exit 1
                    }

                    # Homebrew doesn't add itself to PATH in the current shell — source it explicitly
                    if [ -x "/opt/homebrew/bin/brew" ]; then
                        eval "$(/opt/homebrew/bin/brew shellenv)"
                    elif [ -x "/usr/local/bin/brew" ]; then
                        eval "$(/usr/local/bin/brew shellenv)"
                    fi

                    if ! command -v brew &>/dev/null; then
                        echo -e "  ${RED}Homebrew installed but 'brew' isn't on PATH in this shell.${NC}"
                        echo -e "  ${DIM}Open a new terminal and re-run this installer.${NC}"
                        exit 1
                    fi
                    echo -e "  ${GREEN}Homebrew installed.${NC}"
                    echo ""
                else
                    echo "  Install Homebrew yourself: https://brew.sh"
                    echo "  Or install Podman manually: https://podman.io/docs/installation"
                    echo "  Or install Docker: https://docs.docker.com/desktop/install/mac/"
                    exit 1
                fi
            fi

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
# Already installed? Short-circuit the menu and offer to start it directly.
# The .env + docker-compose.yml pair is the install marker (written by cases 1/3).
# ---------------------------------------------------------------------------
SAFECLAW_DIR="$HOME/safeclaw"

if [ -f "$SAFECLAW_DIR/.env" ] && [ -f "$SAFECLAW_DIR/docker-compose.yml" ] && [ -t 1 ]; then
    if [ -f "$SAFECLAW_DIR/docker-compose.safe.yml" ]; then
        COMPOSE_ARGS="-f docker-compose.yml -f docker-compose.safe.yml"
        VARIANT="Full SafeClaw (OpenClaw + Agent Safety Net)"
    else
        COMPOSE_ARGS="-f docker-compose.yml"
        VARIANT="OpenClaw only"
    fi
    RUNTIME="${CONTAINER_CMD:-podman}"

    # Self-heal pre-2df0cf2 installs: those .env files lacked OPENCLAW_IMAGE /
    # _CONFIG_DIR / _WORKSPACE_DIR, so docker-compose.yml substitutes them to
    # empty and bails with "invalid spec: :/home/node/.openclaw".
    for kv in "OPENCLAW_IMAGE=ghcr.io/aceteam-ai/safeclaw:latest" \
              "OPENCLAW_CONFIG_DIR=./config" \
              "OPENCLAW_WORKSPACE_DIR=./workspace"; do
        key="${kv%%=*}"
        if ! grep -qE "^${key}=" "$SAFECLAW_DIR/.env"; then
            echo "$kv" >> "$SAFECLAW_DIR/.env"
        fi
    done
    mkdir -p "$SAFECLAW_DIR/config" "$SAFECLAW_DIR/workspace"
    if [ ! -f "$SAFECLAW_DIR/config/openclaw.json" ]; then
        echo '{ "gateway": { "mode": "local" } }' > "$SAFECLAW_DIR/config/openclaw.json"
    fi
    chmod -R a+rwX "$SAFECLAW_DIR/config" "$SAFECLAW_DIR/workspace" 2>/dev/null || true

    # Self-heal missing / placeholder / too-short OPENCLAW_GATEWAY_TOKEN.
    # Without a real value OpenClaw's Control UI rejects the websocket with
    # "unauthorized: gateway token missing". OpenClaw's upstream .env.example
    # ships "change-me-to-a-long-random-token" as a hint, which naive copies
    # of .env.example inherit — treat that placeholder as empty.
    current_token="$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$SAFECLAW_DIR/.env" | head -1 | cut -d= -f2-)"
    if [ -z "$current_token" ] || \
       [ "$current_token" = "change-me-to-a-long-random-token" ] || \
       [ "${#current_token}" -lt 16 ]; then
        # Strip any existing line (empty or placeholder) and append a fresh one.
        grep -v '^OPENCLAW_GATEWAY_TOKEN=' "$SAFECLAW_DIR/.env" > "$SAFECLAW_DIR/.env.tmp" && mv "$SAFECLAW_DIR/.env.tmp" "$SAFECLAW_DIR/.env"
        gateway_token="$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p 2>/dev/null || date +%s%N | sha256sum | head -c 32)"
        echo "OPENCLAW_GATEWAY_TOKEN=$gateway_token" >> "$SAFECLAW_DIR/.env"
    fi
    GATEWAY_TOKEN="$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$SAFECLAW_DIR/.env" | head -1 | cut -d= -f2-)"

    echo -e "  ${GREEN}✓ Already installed${NC} at ${CYAN}~/safeclaw${NC} ${DIM}— ${VARIANT}${NC}"
    echo ""
    echo -e "  ${BOLD}Start it:${NC}"
    echo ""
    echo "    cd ~/safeclaw && $RUNTIME compose $COMPOSE_ARGS up"
    echo ""
    if [ -n "$GATEWAY_TOKEN" ]; then
        echo -e "  ${BOLD}${YELLOW}→ Agent UI Gateway Token${NC} ${DIM}(paste on first visit to http://localhost:18789/):${NC}"
        echo ""
        echo -e "      ${BOLD}${CYAN}$GATEWAY_TOKEN${NC}"
        echo ""
    fi
    printf "  Start now? [${BOLD}Y${NC}/n/r=reinstall]: "
    read -r existing </dev/tty || existing=""
    case "${existing:-Y}" in
        [Yy]*)
            echo ""
            # Guard: when using podman, always drop any inherited DOCKER_HOST.
            # `podman compose` on macOS delegates to `docker-compose`, which
            # honors DOCKER_HOST; if the user's shell exports one (nix-shell /
            # direnv leaks are common, and the socket may be stale-but-present
            # so a `-S` check isn't enough), docker-compose talks to the wrong
            # daemon. Unsetting lets podman re-export its own machine socket.
            if [ "$RUNTIME" = "podman" ] && [ -n "${DOCKER_HOST:-}" ]; then
                echo -e "  ${DIM}Unsetting inherited DOCKER_HOST${NC} ${DIM}($DOCKER_HOST)${NC}"
                unset DOCKER_HOST
            fi

            # Pre-flight: verify the runtime can actually serve containers.
            # Podman on macOS can have a stale machine socket (e.g. left over
            # from a nix-shell TMPDIR) that passes `podman info` but fails when
            # docker-compose — which podman delegates to — tries to connect.
            # Stop+start regenerates the socket at the current TMPDIR.
            if ! $RUNTIME ps >/dev/null 2>&1; then
                echo -e "  ${YELLOW}$RUNTIME isn't responding. Restarting the machine...${NC}"
                if [ "$RUNTIME" = "podman" ]; then
                    podman machine stop >/dev/null 2>&1 || true
                    podman machine start >/dev/null 2>&1 || true
                fi
                if ! $RUNTIME ps >/dev/null 2>&1; then
                    echo -e "  ${RED}Still can't reach $RUNTIME.${NC} Try:"
                    echo "    podman machine rm -f podman-machine-default && podman machine init && podman machine start"
                    exit 1
                fi
                echo -e "  ${GREEN}$RUNTIME back online.${NC}"
            fi
            echo -e "  ${CYAN}Starting SafeClaw...${NC} ${DIM}(Ctrl+C to stop)${NC}"
            echo ""
            cd "$SAFECLAW_DIR"
            # Ensure a clean slate: remove any stopped/orphaned containers
            # first. This sidesteps "container already exists" / dependency
            # errors that compose hits when .env changed since the last run
            # (old container exists with stale env; new one can't take its
            # place until the old one is removed, which compose can't do if
            # something depends on it).
            $RUNTIME compose $COMPOSE_ARGS down --remove-orphans >/dev/null 2>&1 || true
            exec $RUNTIME compose $COMPOSE_ARGS up
            ;;
        [Rr]*)
            echo ""
            echo -e "  ${DIM}Continuing to installer menu...${NC}"
            echo ""
            ;;
        *)
            exit 0
            ;;
    esac
fi

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
    echo -e "      ${DIM}OpenClaw agent + Agent Safety Net, all in containers${NC}"
    echo ""
    echo -e "  ${CYAN}[2]${NC} ${BOLD}Safety proxy only${NC}"
    echo -e "      ${DIM}For existing agents (Claude Code, CrewAI, LangChain, etc.)${NC}"
    echo ""
    echo -e "  ${CYAN}[3]${NC} ${BOLD}OpenClaw only${NC} ${YELLOW}(no local proxy)${NC}"
    echo -e "      ${DIM}Agent only — choose hosted AceTeam gateway or truly raw LLM calls${NC}"
    echo ""
    echo -e "  ${CYAN}[4]${NC} ${BOLD}Developer mode (git clone + uv sync)${NC}"
    echo -e "      ${DIM}Clone aceteam-aep and run from source — for hacking on the proxy${NC}"
    echo ""
    echo -e "  ${CYAN}[5]${NC} ${BOLD}I already have it installed${NC}"
    echo ""
    printf "  Choice [1]: "
    read -r choice </dev/tty
    choice=${choice:-1}
else
    # Non-interactive (piped) — default to full SafeClaw if container available, else dev mode
    if [ -n "$CONTAINER_CMD" ]; then
        choice=1
    else
        choice=4
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
        echo -e "  ${DIM}  Agent Safety Net (smaller, demo-ready first)${NC}"
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
            echo -e "  ${GREEN}Agent Safety Net pulled.${NC}"
        else
            echo -e "  ${RED}Agent Safety Net pull failed.${NC}"
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

        # Create .env if missing.
        # Don't copy .env.example from the safeclaw repo — it's OpenClaw-only
        # and lacks OPENCLAW_IMAGE / OPENCLAW_CONFIG_DIR / OPENCLAW_WORKSPACE_DIR
        # which docker-compose.yml requires (no defaults), so compose fails.
        mkdir -p "$SAFECLAW_DIR/config" "$SAFECLAW_DIR/workspace"
        if [ ! -f "$SAFECLAW_DIR/.env" ]; then
            # Generate a per-install gateway token so the Control UI at
            # http://localhost:18789/ can connect without manual token setup.
            gateway_token="$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p 2>/dev/null || date +%s%N | sha256sum | head -c 32)"
            cat > "$SAFECLAW_DIR/.env" <<ENVEOF
# SafeClaw environment — add your API keys here
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
OPENCLAW_IMAGE=ghcr.io/aceteam-ai/safeclaw:latest
OPENCLAW_CONFIG_DIR=./config
OPENCLAW_WORKSPACE_DIR=./workspace
OPENCLAW_GATEWAY_TOKEN=$gateway_token
ENVEOF
        fi

        # Drop a minimal OpenClaw config so the gateway boots without `openclaw setup`.
        if [ ! -f "$SAFECLAW_DIR/config/openclaw.json" ]; then
            echo '{ "gateway": { "mode": "local" } }' > "$SAFECLAW_DIR/config/openclaw.json"
        fi

        # Container runs as UID 1000 (node user); host UID varies. On Linux the
        # mismatch blocks the container from rewriting openclaw.json atomically.
        # Docker Desktop on macOS handles this transparently, but chmod is
        # harmless there and necessary on Linux.
        chmod -R a+rwX "$SAFECLAW_DIR/config" "$SAFECLAW_DIR/workspace" 2>/dev/null || true

        GATEWAY_TOKEN="$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$SAFECLAW_DIR/.env" | head -1 | cut -d= -f2-)"

        echo ""
        echo -e "  ${GREEN}${BOLD}✓ Installed Full SafeClaw${NC} ${DIM}— OpenClaw + Agent Safety Net${NC}"
        echo ""
        echo -e "  ${BOLD}Start it:${NC}"
        echo ""
        echo "    cd ~/safeclaw && $CONTAINER_CMD compose -f docker-compose.yml -f docker-compose.safe.yml up"
        echo ""
        echo -e "  ${DIM}First, add your API keys:${NC} ${CYAN}\$EDITOR ~/safeclaw/.env${NC}"
        echo -e "  ${DIM}Dashboard:${NC} ${CYAN}http://localhost:8899/dashboard/${NC}  ${DIM}· Agent:${NC} ${CYAN}http://localhost:18789/${NC}"
        if [ -n "$GATEWAY_TOKEN" ]; then
            echo ""
            echo -e "  ${BOLD}${YELLOW}→ Agent UI Gateway Token${NC} ${DIM}(paste on first visit to http://localhost:18789/):${NC}"
            echo ""
            echo -e "      ${BOLD}${CYAN}$GATEWAY_TOKEN${NC}"
        fi
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

        echo -e "  ${CYAN}Pulling Agent Safety Net image via ${CONTAINER_CMD}...${NC}"
        $CONTAINER_CMD pull ghcr.io/aceteam-ai/aep-proxy:latest 2>&1 | tail -3

        mkdir -p "$HOME/safeclaw"

        echo ""
        echo -e "  ${GREEN}${BOLD}✓ Installed Safety Proxy${NC} ${DIM}— for existing agents${NC}"
        echo ""
        echo -e "  ${BOLD}Start it:${NC}"
        echo ""
        echo "    $CONTAINER_CMD run -p 8899:8899 -v ~/safeclaw:/workspace ghcr.io/aceteam-ai/aep-proxy"
        echo ""
        echo -e "  ${DIM}Then point your agent at it:${NC} ${CYAN}export OPENAI_BASE_URL=http://localhost:8899/v1${NC}"
        echo -e "  ${DIM}Dashboard:${NC} ${CYAN}http://localhost:8899/dashboard/${NC}"
        ;;
    3)
        # OpenClaw only (no local proxy). Sub-prompt lets the user route through
        # AceTeam's hosted safety gateway instead of running a local proxy
        # container — trade-off is calls leave the machine, but zero local setup.
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
        mkdir -p "$SAFECLAW_DIR/config" "$SAFECLAW_DIR/workspace"

        echo ""
        echo -e "  ${BOLD}Choose a safety option:${NC}"
        echo ""
        echo -e "  ${CYAN}[a]${NC} ${BOLD}AceTeam hosted gateway${NC} ${GREEN}(recommended)${NC}"
        echo -e "      ${DIM}Zero local setup. PII detection, cost tracking, signed audit${NC}"
        echo -e "      ${DIM}handled at https://aceteam.ai/api/gateway/v1${NC}"
        echo -e "      ${DIM}Get a gateway key: https://aceteam.ai/gateways${NC}"
        echo ""
        echo -e "  ${CYAN}[b]${NC} ${BOLD}Raw LLM calls${NC} ${YELLOW}(no safety)${NC}"
        echo -e "      ${DIM}Agent talks directly to OpenAI/Anthropic — for before/after demos${NC}"
        echo ""

        use_aceteam_gateway="a"
        if [ -t 1 ]; then
            printf "  Choice [a]: "
            read -r use_aceteam_gateway </dev/tty
            use_aceteam_gateway=${use_aceteam_gateway:-a}
        fi

        echo ""
        echo -e "  ${CYAN}Pulling OpenClaw agent via ${CONTAINER_CMD}...${NC}"
        $CONTAINER_CMD pull ghcr.io/aceteam-ai/safeclaw:latest 2>&1 | tail -3

        echo -e "  ${DIM}  Downloading docker-compose.yml...${NC}"
        curl -fsSL "https://raw.githubusercontent.com/aceteam-ai/safeclaw/main/docker-compose.yml" \
            -o "$SAFECLAW_DIR/docker-compose.yml"

        # Drop a minimal OpenClaw config so the gateway boots without `openclaw setup`.
        # Without this, the container crash-loops complaining about missing config.
        if [ ! -f "$SAFECLAW_DIR/config/openclaw.json" ]; then
            echo '{ "gateway": { "mode": "local" } }' > "$SAFECLAW_DIR/config/openclaw.json"
        fi

        # See case 1 for the UID mismatch rationale — required on Linux hosts.
        chmod -R a+rwX "$SAFECLAW_DIR/config" "$SAFECLAW_DIR/workspace" 2>/dev/null || true

        # Per-install gateway token for OpenClaw's Control UI; shared between 3a/3b.
        gateway_token="$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p 2>/dev/null || date +%s%N | sha256sum | head -c 32)"

        if [[ "$use_aceteam_gateway" =~ ^[Aa] ]]; then
            # Wire LLM calls through the hosted AceTeam safety gateway.
            if [ ! -f "$SAFECLAW_DIR/.env" ]; then
                cat > "$SAFECLAW_DIR/.env" <<ENVEOF
# OpenClaw + AceTeam hosted gateway
# Get your gateway API key at https://aceteam.ai/gateways and paste it below.
# The same key works for OpenAI- and Anthropic-compatible requests.
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
OPENAI_BASE_URL=https://aceteam.ai/api/gateway/v1
ANTHROPIC_BASE_URL=https://aceteam.ai/api/gateway/v1
OPENCLAW_IMAGE=ghcr.io/aceteam-ai/safeclaw:latest
OPENCLAW_CONFIG_DIR=./config
OPENCLAW_WORKSPACE_DIR=./workspace
OPENCLAW_GATEWAY_TOKEN=$gateway_token
ENVEOF
            fi
            GATEWAY_TOKEN="$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$SAFECLAW_DIR/.env" | head -1 | cut -d= -f2-)"

            echo ""
            echo -e "  ${GREEN}${BOLD}✓ Installed OpenClaw → AceTeam hosted gateway${NC}"
            echo ""
            echo -e "  ${BOLD}Start it:${NC}"
            echo ""
            echo "    cd ~/safeclaw && $CONTAINER_CMD compose -f docker-compose.yml up"
            echo ""
            echo -e "  ${DIM}First, get a gateway key at${NC} ${CYAN}https://aceteam.ai/gateways${NC} ${DIM}and paste into${NC} ${CYAN}~/safeclaw/.env${NC}"
            echo -e "  ${DIM}Agent:${NC} ${CYAN}http://localhost:18789/${NC}"
            if [ -n "$GATEWAY_TOKEN" ]; then
                echo ""
                echo -e "  ${DIM}Agent UI Gateway Token (paste into Control UI on first visit):${NC}"
                echo -e "    ${CYAN}$GATEWAY_TOKEN${NC}"
            fi
        else
            # Pure raw — no safety layer at all.
            if [ ! -f "$SAFECLAW_DIR/.env" ]; then
                cat > "$SAFECLAW_DIR/.env" <<ENVEOF
# OpenClaw — raw mode (no safety)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
OPENCLAW_IMAGE=ghcr.io/aceteam-ai/safeclaw:latest
OPENCLAW_CONFIG_DIR=./config
OPENCLAW_WORKSPACE_DIR=./workspace
OPENCLAW_GATEWAY_TOKEN=$gateway_token
ENVEOF
            fi
            GATEWAY_TOKEN="$(grep -E '^OPENCLAW_GATEWAY_TOKEN=' "$SAFECLAW_DIR/.env" | head -1 | cut -d= -f2-)"

            echo ""
            echo -e "  ${GREEN}${BOLD}✓ Installed OpenClaw${NC} ${YELLOW}— raw, no safety${NC}"
            echo ""
            echo -e "  ${BOLD}Start it:${NC}"
            echo ""
            echo "    cd ~/safeclaw && $CONTAINER_CMD compose -f docker-compose.yml up"
            echo ""
            echo -e "  ${DIM}First, add your API keys:${NC} ${CYAN}\$EDITOR ~/safeclaw/.env${NC}"
            echo -e "  ${DIM}Agent:${NC} ${CYAN}http://localhost:18789/${NC}  ${DIM}· Want safety? Re-run and pick [1] or [3a].${NC}"
            if [ -n "$GATEWAY_TOKEN" ]; then
                echo ""
                echo -e "  ${DIM}Agent UI Gateway Token (paste into Control UI on first visit):${NC}"
                echo -e "    ${CYAN}$GATEWAY_TOKEN${NC}"
            fi
        fi
        ;;
    4)
        # Developer mode: clone aceteam-aep source and run via `uv sync --extra proxy`.
        # More reliable than PyPI (which has been flaky) and gives you an editable source tree.
        if ! command -v git &>/dev/null; then
            echo -e "  ${RED}git not found.${NC} Install git first, then re-run."
            exit 1
        fi

        if ! command -v uv &>/dev/null; then
            echo -e "  ${CYAN}Installing uv...${NC}"
            curl -LsSf https://astral.sh/uv/install.sh | sh
            export PATH="$HOME/.local/bin:$PATH"
        fi

        REPO_DIR="${ACETEAM_AEP_DIR:-$HOME/aceteam-aep}"
        if [ -d "$REPO_DIR/.git" ]; then
            echo -e "  ${CYAN}Updating existing clone at ${REPO_DIR}...${NC}"
            git -C "$REPO_DIR" pull --ff-only || {
                echo -e "  ${YELLOW}Couldn't fast-forward ${REPO_DIR}. Fix manually or delete it and re-run.${NC}"
                exit 1
            }
        else
            echo -e "  ${CYAN}Cloning aceteam-aep into ${REPO_DIR}...${NC}"
            git clone https://github.com/aceteam-ai/aceteam-aep.git "$REPO_DIR"
        fi

        echo -e "  ${CYAN}Installing proxy dependencies via uv sync --extra proxy...${NC}"
        (cd "$REPO_DIR" && uv sync --extra proxy)

        # Verify the editable install works
        if ! (cd "$REPO_DIR" && uv run aceteam-aep --help >/dev/null 2>&1); then
            echo ""
            echo -e "  ${RED}uv sync completed but verification failed.${NC}"
            echo -e "  ${DIM}Running 'uv run aceteam-aep --help' to show the error:${NC}"
            (cd "$REPO_DIR" && uv run aceteam-aep --help) || true
            exit 1
        fi

        echo ""
        echo -e "  ${GREEN}${BOLD}Ready.${NC}"
        echo ""
        echo -e "  ${BOLD}Agent Safety Net cloned to ${REPO_DIR}.${NC}"
        echo -e "  ${DIM}Run commands from the repo with 'uv run'. Edit the source and re-run to iterate.${NC}"
        echo ""
        echo -e "  ${CYAN}Start the safety proxy:${NC}"
        echo ""
        echo "    cd $REPO_DIR"
        echo "    uv run aceteam-aep proxy --port 8899"
        echo ""
        echo -e "  ${CYAN}Or wrap any agent:${NC}"
        echo ""
        echo "    cd $REPO_DIR && uv run aceteam-aep wrap -- python my_agent.py"
        echo ""
        echo -e "  ${CYAN}Dashboard:${NC} http://localhost:8899/dashboard/"
        ;;
    5)
        echo -e "  ${GREEN}Great.${NC}"
        echo ""
        echo -e "  ${CYAN}Full SafeClaw (recommended):${NC}"
        echo "    cd ~/safeclaw && podman compose -f docker-compose.yml -f docker-compose.safe.yml up"
        echo ""
        echo -e "  ${CYAN}Safety proxy only:${NC}"
        echo "    podman run -p 8899:8899 ghcr.io/aceteam-ai/aep-proxy"
        echo ""
        echo -e "  ${CYAN}OpenClaw only (no safety net):${NC}"
        echo "    cd ~/safeclaw && podman compose -f docker-compose.yml up"
        echo ""
        echo -e "  ${CYAN}Developer mode (from source):${NC}"
        echo "    cd ~/aceteam-aep && uv run aceteam-aep proxy --port 8899"
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
