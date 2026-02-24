#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# install.sh — Install the AEEF CLI wrapper
#
# Creates a symlink from bin/aeef into ~/.local/bin/ so the `aeef` command
# is available system-wide. Also checks for required dependencies.
# ──────────────────────────────────────────────────────────────────────────────

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[0;33m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

info()    { printf "${BLUE}[install]${RESET} %s\n" "$*"; }
success() { printf "${GREEN}[install]${RESET} %s\n" "$*"; }
warn()    { printf "${YELLOW}[install]${RESET} %s\n" "$*" >&2; }
error()   { printf "${RED}[install]${RESET} %s\n" "$*" >&2; }

# ── Detect AEEF CLI root ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
AEEF_BIN="${SCRIPT_DIR}/bin/aeef"

if [[ ! -f "$AEEF_BIN" ]]; then
    error "Could not find bin/aeef at: ${AEEF_BIN}"
    error "Please run this script from the aeef-cli root directory."
    exit 1
fi

info "Detected AEEF CLI root: ${SCRIPT_DIR}"

# ── Create ~/.local/bin/ if needed ────────────────────────────────────────────
LOCAL_BIN="${HOME}/.local/bin"

if [[ ! -d "$LOCAL_BIN" ]]; then
    info "Creating ${LOCAL_BIN}/..."
    mkdir -p "$LOCAL_BIN"
fi

# ── Make bin/aeef executable ──────────────────────────────────────────────────
info "Ensuring bin/aeef is executable..."
chmod +x "$AEEF_BIN"

# ── Create symlink ────────────────────────────────────────────────────────────
SYMLINK_PATH="${LOCAL_BIN}/aeef"

if [[ -L "$SYMLINK_PATH" ]]; then
    info "Removing existing symlink at ${SYMLINK_PATH}..."
    rm "$SYMLINK_PATH"
elif [[ -f "$SYMLINK_PATH" ]]; then
    warn "A file (not a symlink) already exists at ${SYMLINK_PATH}."
    warn "Please remove it manually and re-run this script."
    exit 1
fi

info "Creating symlink: ${SYMLINK_PATH} -> ${AEEF_BIN}"
ln -s "$AEEF_BIN" "$SYMLINK_PATH"

# ── Check if ~/.local/bin is in PATH ─────────────────────────────────────────
if [[ ":${PATH}:" != *":${LOCAL_BIN}:"* ]]; then
    warn ""
    warn "~/.local/bin is NOT in your PATH."
    warn "Add the following line to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    warn ""
    warn "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    warn ""
    warn "Then restart your shell or run: source ~/.bashrc"
    warn ""
fi

# ── Check required dependencies ──────────────────────────────────────────────
printf "\n"
info "Checking required dependencies..."

DEPS_OK=true

check_dep() {
    local name="$1"
    local purpose="$2"
    if command -v "$name" &>/dev/null; then
        local version
        version="$("$name" --version 2>/dev/null | head -1 || echo "installed")"
        success "  ${name} — ${version}"
    else
        error "  ${name} — NOT FOUND (${purpose})"
        DEPS_OK=false
    fi
}

check_dep "claude" "Claude Code CLI — the AI backend"
check_dep "gh"     "GitHub CLI — for creating pull requests"
check_dep "git"    "Git — for branch management"
check_dep "jq"     "jq — for JSON parsing in CI mode"

printf "\n"

if [[ "$DEPS_OK" == false ]]; then
    warn "Some dependencies are missing. AEEF CLI may not function correctly."
    warn "Install missing dependencies before running 'aeef'."
else
    success "All dependencies found."
fi

# ── Success message ───────────────────────────────────────────────────────────
printf "\n"
printf "${GREEN}${BOLD}  AEEF CLI installed successfully!${RESET}\n"
printf "\n"
info "Usage:"
info "  aeef doctor --project ./my-app"
info "  aeef bootstrap --project ./my-app --role product"
info "  aeef --role product --project ./my-app"
info "  aeef --role developer --ci --prompt \"Build the feature\""
info "  aeef --help"
printf "\n"
info "Quickstart: ./GETTING-STARTED.md"
info "Documentation: https://aeef.dev"
printf "\n"

exit 0
