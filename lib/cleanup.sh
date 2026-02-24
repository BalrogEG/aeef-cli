#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# cleanup.sh — Remove AEEF agent artifacts after a successful QC run
# ──────────────────────────────────────────────────────────────────────────────

# ── Color helpers (if not already defined) ────────────────────────────────────
declare -f info    &>/dev/null || info()    { printf '\033[0;34m[aeef]\033[0m %s\n' "$*"; }
declare -f success &>/dev/null || success() { printf '\033[0;32m[aeef]\033[0m %s\n' "$*"; }
declare -f warn    &>/dev/null || warn()    { printf '\033[0;33m[aeef]\033[0m %s\n' "$*" >&2; }
declare -f error   &>/dev/null || error()   { printf '\033[0;31m[aeef]\033[0m %s\n' "$*" >&2; }

# ──────────────────────────────────────────────────────────────────────────────
# aeef_cleanup — Remove .claude/ and .aeef/ directories and commit the removal.
#
# This function is called after a successful QC run to clean up all
# agent-specific artifacts so the final branch is free of AEEF scaffolding.
#
# Behavior:
#   - Removes the .claude/ directory (rules, skills, hooks)
#   - Removes the .aeef/ directory (handoffs, provenance, runs)
#   - Commits the removal with a descriptive message
#   - Prints confirmation of what was cleaned
#
# Returns:
#   0 on success, 1 if nothing to clean
# ──────────────────────────────────────────────────────────────────────────────
aeef_cleanup() {
    local cleaned=false

    # Remove .claude/ directory
    if [[ -d ".claude" ]]; then
        info "Removing .claude/ directory..."
        rm -rf ".claude"
        cleaned=true
    else
        info "No .claude/ directory found. Skipping."
    fi

    # Remove .aeef/ directory
    if [[ -d ".aeef" ]]; then
        info "Removing .aeef/ directory..."
        rm -rf ".aeef"
        cleaned=true
    else
        info "No .aeef/ directory found. Skipping."
    fi

    # Commit the cleanup if anything was removed
    if [[ "$cleaned" == true ]]; then
        # Stage removals
        git add -A

        # Only commit if there are staged changes
        if ! git diff --cached --quiet; then
            git commit -m "chore(aeef): remove agent artifacts

Cleaned up .claude/ and .aeef/ directories after successful QC pass.
These directories are scaffolding used by the AEEF CLI during agent runs
and are not needed in the final deliverable."

            info "Cleanup committed: $(git log -1 --oneline)"
            success "Agent artifacts removed and committed."
        else
            info "No staged changes after cleanup. Skipping commit."
        fi
    else
        info "Nothing to clean up."
        return 1
    fi

    return 0
}
