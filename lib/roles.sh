#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# roles.sh — AEEF role routing table and validation
# ──────────────────────────────────────────────────────────────────────────────

# ── Role branch mapping ──────────────────────────────────────────────────────
# Each role operates on a dedicated Git branch.
declare -A ROLE_BRANCH
ROLE_BRANCH[product]="aeef/product"
ROLE_BRANCH[architect]="aeef/architect"
ROLE_BRANCH[developer]="aeef/dev"
ROLE_BRANCH[qc]="aeef/qc"

# ── Upstream: where each role pulls changes FROM ─────────────────────────────
declare -A ROLE_UPSTREAM
ROLE_UPSTREAM[product]="main"
ROLE_UPSTREAM[architect]="aeef/product"
ROLE_UPSTREAM[developer]="aeef/architect"
ROLE_UPSTREAM[qc]="aeef/dev"

# ── Downstream: where each role pushes changes TO (via PR) ───────────────────
declare -A ROLE_DOWNSTREAM
ROLE_DOWNSTREAM[product]="aeef/architect"
ROLE_DOWNSTREAM[architect]="aeef/dev"
ROLE_DOWNSTREAM[developer]="aeef/qc"
ROLE_DOWNSTREAM[qc]="main"

# ── Fallback: branch to fall back to on failure ──────────────────────────────
declare -A ROLE_FALLBACK
ROLE_FALLBACK[product]="main"
ROLE_FALLBACK[architect]="aeef/product"
ROLE_FALLBACK[developer]="aeef/architect"
ROLE_FALLBACK[qc]="aeef/dev"

# ── Allowed tools per role ───────────────────────────────────────────────────
# Comma-separated list of Claude Code tools the role is permitted to use.
declare -A ROLE_ALLOWED_TOOLS
ROLE_ALLOWED_TOOLS[product]="Read,Grep,Glob,Write,Edit"
ROLE_ALLOWED_TOOLS[architect]="Read,Grep,Glob,Write,Edit,Bash(docker *),Bash(draw.io *)"
ROLE_ALLOWED_TOOLS[developer]="Read,Grep,Glob,Write,Edit,Bash(npm *),Bash(pip *),Bash(go *),Bash(git diff *),Bash(git status)"
ROLE_ALLOWED_TOOLS[qc]="Read,Grep,Glob,Bash(npm test *),Bash(pytest *),Bash(go test *),Bash(git *)"

# ── Disallowed tools per role ────────────────────────────────────────────────
# Comma-separated list of Claude Code tools the role is explicitly denied.
declare -A ROLE_DISALLOWED_TOOLS
ROLE_DISALLOWED_TOOLS[product]="Bash"
ROLE_DISALLOWED_TOOLS[architect]=""
ROLE_DISALLOWED_TOOLS[developer]="Bash(rm -rf *),Bash(git push *),Bash(git merge *)"
ROLE_DISALLOWED_TOOLS[qc]="Write,Edit"

# ── Display names ────────────────────────────────────────────────────────────
declare -A ROLE_DISPLAY_NAME
ROLE_DISPLAY_NAME[product]="Product Agent"
ROLE_DISPLAY_NAME[architect]="Architect Agent"
ROLE_DISPLAY_NAME[developer]="Developer Agent"
ROLE_DISPLAY_NAME[qc]="QC Agent"

# ── Valid roles list ─────────────────────────────────────────────────────────
# Mutable so optional role packs can append enterprise roles.
VALID_ROLES=("product" "architect" "developer" "qc")

add_valid_role() {
    local role="${1:-}"
    [[ -n "$role" ]] || return 1

    local existing
    for existing in "${VALID_ROLES[@]}"; do
        [[ "$existing" == "$role" ]] && return 0
    done

    VALID_ROLES+=("$role")
    return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# validate_role — Check whether a given role name is valid.
#
# Arguments:
#   $1 — role name to validate
#
# Returns:
#   0 if valid, 1 if invalid
# ──────────────────────────────────────────────────────────────────────────────
validate_role() {
    local role="${1:-}"
    [[ -z "$role" ]] && return 1

    local valid
    for valid in "${VALID_ROLES[@]}"; do
        if [[ "$valid" == "$role" ]]; then
            return 0
        fi
    done

    return 1
}

# ──────────────────────────────────────────────────────────────────────────────
# list_roles — Print a formatted table of all available roles.
# ──────────────────────────────────────────────────────────────────────────────
list_roles() {
    local role
    printf "%-12s %-18s %-18s %-18s %-18s\n" \
        "ROLE" "DISPLAY NAME" "BRANCH" "UPSTREAM" "DOWNSTREAM"
    printf "%-12s %-18s %-18s %-18s %-18s\n" \
        "────" "────────────" "──────" "────────" "──────────"

    for role in "${VALID_ROLES[@]}"; do
        printf "%-12s %-18s %-18s %-18s %-18s\n" \
            "$role" \
            "${ROLE_DISPLAY_NAME[$role]}" \
            "${ROLE_BRANCH[$role]}" \
            "${ROLE_UPSTREAM[$role]}" \
            "${ROLE_DOWNSTREAM[$role]}"
    done
}

# ──────────────────────────────────────────────────────────────────────────────
# get_downstream_role — Given a downstream branch, return the role name.
#
# Arguments:
#   $1 — branch name (e.g. "aeef/architect")
#
# Prints:
#   The role name (e.g. "architect") or "main" if the downstream is main.
# ──────────────────────────────────────────────────────────────────────────────
get_downstream_role() {
    local branch="${1:-}"
    local role

    if [[ "$branch" == "main" ]]; then
        echo "main"
        return 0
    fi

    for role in "${VALID_ROLES[@]}"; do
        if [[ "${ROLE_BRANCH[$role]}" == "$branch" ]]; then
            echo "$role"
            return 0
        fi
    done

    echo "unknown"
    return 1
}
