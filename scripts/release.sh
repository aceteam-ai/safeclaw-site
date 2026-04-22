#!/usr/bin/env bash
# Release the SafeClaw installer.
#
# Bumps INSTALLER_VERSION in install.sh, commits, tags vX.Y.Z, pushes, and
# (optionally) creates a GitHub release with install.sh attached as an asset.
# That release artifact is a pinnable copy — safeclaw.sh always serves HEAD,
# but a user can `curl ...releases/download/v1.2.3/install.sh | bash` to pin.
#
# Usage:
#   scripts/release.sh                        # bump patch, commit+tag+push+release
#   scripts/release.sh --minor                # bump minor
#   scripts/release.sh --major                # bump major
#   scripts/release.sh --set 1.2.3            # explicit version
#   scripts/release.sh --dry-run              # print plan, change nothing
#   scripts/release.sh --no-release           # commit+tag+push, skip `gh release`

set -euo pipefail

BUMP="patch"
EXPLICIT=""
DRY_RUN=0
NO_RELEASE=0

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --major) BUMP="major"; shift ;;
        --minor) BUMP="minor"; shift ;;
        --patch) BUMP="patch"; shift ;;
        --set) EXPLICIT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --no-release) NO_RELEASE=1; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown arg: $1"; usage ;;
    esac
done

cd "$(git rev-parse --show-toplevel)"

if [ ! -f install.sh ]; then
    echo "error: install.sh not found at repo root ($(pwd))" >&2
    exit 1
fi

CURRENT="$(grep -E '^INSTALLER_VERSION=' install.sh | head -1 | cut -d'"' -f2)"
if [ -z "$CURRENT" ]; then
    echo 'error: could not find INSTALLER_VERSION="..." in install.sh' >&2
    exit 1
fi

if [ -n "$EXPLICIT" ]; then
    NEW="$EXPLICIT"
else
    IFS='.' read -r maj min pat <<< "$CURRENT"
    case "$BUMP" in
        major) maj=$((maj+1)); min=0; pat=0 ;;
        minor) min=$((min+1)); pat=0 ;;
        patch) pat=$((pat+1)) ;;
    esac
    NEW="${maj}.${min}.${pat}"
fi

if ! [[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid version: $NEW (expected X.Y.Z)" >&2
    exit 1
fi

echo "Current: $CURRENT"
echo "New:     $NEW"
echo ""

# Preconditions (skipped in dry-run so you can preview from any state)
if [ "$DRY_RUN" = 0 ]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "error: working tree has uncommitted changes — commit or stash first" >&2
        exit 1
    fi
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    if [ "$BRANCH" != "main" ]; then
        echo "error: not on main (on $BRANCH) — switch first" >&2
        exit 1
    fi
    if git rev-parse "v$NEW" >/dev/null 2>&1; then
        echo "error: tag v$NEW already exists" >&2
        exit 1
    fi
fi

run() {
    if [ "$DRY_RUN" = 1 ]; then
        echo "[dry-run] $*"
    else
        echo "  $*"
        eval "$@"
    fi
}

# BSD sed (macOS) needs `-i ''`, GNU sed needs `-i`. Detect.
if sed --version >/dev/null 2>&1; then
    SED_I=(sed -i)
else
    SED_I=(sed -i '')
fi

if [ "$DRY_RUN" = 1 ]; then
    echo "[dry-run] ${SED_I[*]} 's/^INSTALLER_VERSION=.*/INSTALLER_VERSION=\"$NEW\"/' install.sh"
else
    "${SED_I[@]}" "s/^INSTALLER_VERSION=.*/INSTALLER_VERSION=\"$NEW\"/" install.sh
    # Confirm the edit took
    if [ "$(grep -c "^INSTALLER_VERSION=\"$NEW\"$" install.sh)" != "1" ]; then
        echo "error: INSTALLER_VERSION did not update cleanly" >&2
        exit 1
    fi
fi

run "git add install.sh"
run "git commit -m 'release: installer v$NEW'"
run "git tag -a 'v$NEW' -m 'installer v$NEW'"
run "git push origin main 'v$NEW'"

if [ "$NO_RELEASE" = 0 ]; then
    if ! command -v gh >/dev/null 2>&1; then
        echo "warning: gh CLI not found; skipping GitHub Release creation" >&2
    else
        run "gh release create 'v$NEW' install.sh --title 'installer v$NEW' --generate-notes"
    fi
fi

echo ""
if [ "$DRY_RUN" = 1 ]; then
    echo "✓ Dry run — no changes made."
else
    echo "✓ Released installer v$NEW"
    if [ "$NO_RELEASE" = 0 ] && command -v gh >/dev/null 2>&1; then
        repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
        [ -n "$repo" ] && echo "  https://github.com/$repo/releases/tag/v$NEW"
    fi
    echo ""
    echo "  Pinned install (users who want a specific version):"
    echo "    curl -fsSL https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo 'OWNER/REPO')/releases/download/v$NEW/install.sh | bash"
    echo ""
    echo "  Latest (HEAD of safeclaw.sh, unchanged) still:"
    echo "    curl -fsSL https://safeclaw.sh/install.sh | bash"
fi
