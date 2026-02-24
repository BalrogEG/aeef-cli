#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# git-workflow.sh — AEEF branch management, commit, PR, and revert functions
# ──────────────────────────────────────────────────────────────────────────────

# ── Color helpers (if not already defined) ────────────────────────────────────
declare -f info    &>/dev/null || info()    { printf '\033[0;34m[aeef]\033[0m %s\n' "$*"; }
declare -f success &>/dev/null || success() { printf '\033[0;32m[aeef]\033[0m %s\n' "$*"; }
declare -f warn    &>/dev/null || warn()    { printf '\033[0;33m[aeef]\033[0m %s\n' "$*" >&2; }
declare -f error   &>/dev/null || error()   { printf '\033[0;31m[aeef]\033[0m %s\n' "$*" >&2; }

# ──────────────────────────────────────────────────────────────────────────────
# aeef_run_id — Generate a unique run identifier.
#
# Arguments:
#   $1 — role name
#
# Prints:
#   A run ID in the form YYYYMMDD-HHMMSS-<role>
# ──────────────────────────────────────────────────────────────────────────────
aeef_run_id() {
    local role="${1:?aeef_run_id requires a role name}"
    echo "$(date +%Y%m%d-%H%M%S)-${role}"
}

# ──────────────────────────────────────────────────────────────────────────────
# aeef_ensure_branch — Checkout or create the role branch and merge upstream.
#
# Arguments:
#   $1 — role name (e.g. "product", "architect", "developer", "qc")
#
# Behavior:
#   - If the role branch already exists locally, check it out and merge upstream.
#   - If it does not exist locally but exists on origin, check it out from origin.
#   - If it does not exist anywhere, create it from the upstream branch.
#   - If a merge conflict occurs, abort the merge and return an error.
#
# Returns:
#   0 on success, 1 on failure
# ──────────────────────────────────────────────────────────────────────────────
aeef_ensure_branch() {
    local role="${1:?aeef_ensure_branch requires a role name}"
    local branch="${ROLE_BRANCH[$role]}"
    local upstream="${ROLE_UPSTREAM[$role]}"

    # Ensure we have latest refs from origin (non-fatal if offline)
    git fetch origin --quiet 2>/dev/null || warn "Could not fetch from origin (offline?)."

    # Ensure the upstream branch exists locally
    if ! git rev-parse --verify "$upstream" &>/dev/null; then
        if git rev-parse --verify "origin/${upstream}" &>/dev/null; then
            info "Tracking upstream branch '${upstream}' from origin..."
            git branch "$upstream" "origin/${upstream}" 2>/dev/null || true
        else
            if [[ "$upstream" != "main" ]]; then
                warn "Upstream branch '${upstream}' does not exist. Using 'main' as fallback."
                upstream="main"
            fi
        fi
    fi

    # Check if the role branch exists locally
    if git rev-parse --verify "$branch" &>/dev/null; then
        info "Branch '${branch}' exists locally. Checking out..."
        git checkout "$branch"

        info "Merging upstream '${upstream}' into '${branch}'..."
        if ! git merge "$upstream" --no-edit 2>/dev/null; then
            error "Merge conflict detected while merging '${upstream}' into '${branch}'."
            error "Aborting merge. Please resolve conflicts manually:"
            error "  1. git checkout ${branch}"
            error "  2. git merge ${upstream}"
            error "  3. Resolve conflicts, then: git merge --continue"
            error "  4. Re-run: aeef --role ${role}"
            git merge --abort 2>/dev/null || true
            return 1
        fi

    # Check if the role branch exists on origin
    elif git rev-parse --verify "origin/${branch}" &>/dev/null; then
        info "Branch '${branch}' found on origin. Checking out..."
        git checkout -b "$branch" "origin/${branch}"

        info "Merging upstream '${upstream}' into '${branch}'..."
        if ! git merge "$upstream" --no-edit 2>/dev/null; then
            error "Merge conflict detected while merging '${upstream}' into '${branch}'."
            git merge --abort 2>/dev/null || true
            return 1
        fi

    # Create the branch from upstream
    else
        info "Branch '${branch}' does not exist. Creating from '${upstream}'..."
        if ! git checkout -b "$branch" "$upstream" 2>/dev/null; then
            error "Failed to create branch '${branch}' from '${upstream}'."
            error "Ensure the upstream branch exists: git branch -a | grep ${upstream}"
            return 1
        fi
    fi

    info "Current branch: $(git branch --show-current)"
    return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# aeef_commit — Stage all changes and create a structured commit.
#
# Arguments:
#   $1 — role name
#
# Behavior:
#   - Stages all changes (git add -A)
#   - Creates a commit with structured message including AI-Usage trailer
#   - Skips commit if there are no changes
#
# Returns:
#   0 on success, 1 if nothing to commit
# ──────────────────────────────────────────────────────────────────────────────
aeef_commit() {
    local role="${1:?aeef_commit requires a role name}"
    local run_id="${AEEF_RUN_ID:-$(aeef_run_id "$role")}"
    local display_name="${ROLE_DISPLAY_NAME[$role]}"

    # Check for changes
    if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
        warn "No changes detected. Skipping commit."
        return 1
    fi

    git add -A

    local commit_msg
    commit_msg="$(cat <<EOF
feat(aeef): ${role} agent changes

Automated changes by the AEEF ${display_name}.

AI-Usage: aeef-cli/${role}
AEEF-Run-ID: ${run_id}
EOF
)"

    git commit -m "$commit_msg"
    info "Committed as: $(git log -1 --oneline)"
    return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# aeef_create_pr — Create a pull request from the role branch to downstream.
#
# Arguments:
#   $1 — role name
#
# Behavior:
#   - Pushes the role branch to origin
#   - Reads handoff artifact from .aeef/handoffs/ if present
#   - Creates a PR targeting the downstream branch
#   - Prints the PR URL
#
# Returns:
#   0 on success, 1 on failure
# ──────────────────────────────────────────────────────────────────────────────
aeef_create_pr() {
    local role="${1:?aeef_create_pr requires a role name}"
    local branch="${ROLE_BRANCH[$role]}"
    local downstream="${ROLE_DOWNSTREAM[$role]}"
    local display_name="${ROLE_DISPLAY_NAME[$role]}"
    local run_id="${AEEF_RUN_ID:-$(aeef_run_id "$role")}"

    # Determine the downstream role name for the PR title
    local downstream_role
    downstream_role="$(get_downstream_role "$downstream" 2>/dev/null || echo "$downstream")"

    # Push the branch to origin
    info "Pushing '${branch}' to origin..."
    if ! git push -u origin "$branch" 2>/dev/null; then
        error "Failed to push '${branch}' to origin."
        error "You may need to set up remote access or push manually:"
        error "  git push -u origin ${branch}"
        return 1
    fi

    # Build PR body
    local handoff_content=""
    local handoff_dir=".aeef/handoffs"
    if [[ -d "$handoff_dir" ]]; then
        local latest_handoff
        latest_handoff="$(ls -t "${handoff_dir}"/*.md 2>/dev/null | head -1)"
        if [[ -n "$latest_handoff" ]]; then
            handoff_content="$(cat "$latest_handoff")"
            info "Found handoff artifact: ${latest_handoff}"
        fi
    fi

    local pr_body
    pr_body="$(cat <<EOF
## AEEF Agent Handoff

**Role:** ${display_name}
**Run ID:** \`${run_id}\`
**Branch:** \`${branch}\` -> \`${downstream}\`

### Summary

Automated changes produced by the AEEF ${display_name}.
This PR hands off work to the next stage in the pipeline.

### Handoff Notes

${handoff_content:-_No handoff artifact found. The agent did not produce a structured handoff document._}

### Checklist

- [ ] Review agent-generated changes
- [ ] Validate against role contract
- [ ] Check provenance artifacts in \`.aeef/provenance/\`
- [ ] Approve or request revisions

---
_Generated by aeef-cli v${AEEF_VERSION:-0.1.0} | Run: ${run_id}_
EOF
)"

    # Ensure downstream branch exists on remote for the PR base
    if ! git rev-parse --verify "origin/${downstream}" &>/dev/null 2>&1; then
        if [[ "$downstream" != "main" ]]; then
            warn "Downstream branch '${downstream}' not found on origin."
            warn "Creating '${downstream}' from its upstream first..."
            local downstream_upstream="${ROLE_FALLBACK[$role]:-main}"
            git branch "$downstream" "$downstream_upstream" 2>/dev/null || true
            git push -u origin "$downstream" 2>/dev/null || true
        fi
    fi

    local pr_title="AEEF: ${role} -> ${downstream_role}"

    info "Creating pull request: ${pr_title}"
    local pr_url
    if pr_url="$(gh pr create \
        --base "$downstream" \
        --head "$branch" \
        --title "$pr_title" \
        --body "$pr_body" 2>&1)"; then
        success "Pull request created: ${pr_url}"
        return 0
    else
        # Check if a PR already exists
        if echo "$pr_url" | grep -qi "already exists"; then
            warn "A pull request already exists for '${branch}' -> '${downstream}'."
            local existing_url
            existing_url="$(gh pr list --head "$branch" --base "$downstream" --json url --jq '.[0].url' 2>/dev/null || echo "")"
            if [[ -n "$existing_url" ]]; then
                info "Existing PR: ${existing_url}"
            fi
            return 0
        fi
        error "Failed to create pull request: ${pr_url}"
        return 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# aeef_revert — Revert all working-tree changes and untracked files.
#
# Arguments:
#   $1 — role name
#
# Behavior:
#   - Restores all modified files to their last committed state
#   - Removes all untracked files and directories
#   - Prints a helpful fallback suggestion
# ──────────────────────────────────────────────────────────────────────────────
aeef_revert() {
    local role="${1:?aeef_revert requires a role name}"
    local fallback="${ROLE_FALLBACK[$role]}"

    warn "Reverting all changes on '${ROLE_BRANCH[$role]}'..."

    git checkout -- . 2>/dev/null || true
    git clean -fd 2>/dev/null || true

    info "Working tree restored to last commit."
    info "Fallback suggestion: switch to '${fallback}' and investigate:"
    info "  git checkout ${fallback}"
    info "  git log --oneline -10"
}
