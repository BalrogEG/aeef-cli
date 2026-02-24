#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# setup-claude-dir.sh — Prepare the .claude/ and .aeef/ directories for a role
# ──────────────────────────────────────────────────────────────────────────────

# ── Color helpers (if not already defined) ────────────────────────────────────
declare -f info    &>/dev/null || info()    { printf '\033[0;34m[aeef]\033[0m %s\n' "$*"; }
declare -f success &>/dev/null || success() { printf '\033[0;32m[aeef]\033[0m %s\n' "$*"; }
declare -f warn    &>/dev/null || warn()    { printf '\033[0;33m[aeef]\033[0m %s\n' "$*" >&2; }
declare -f error   &>/dev/null || error()   { printf '\033[0;31m[aeef]\033[0m %s\n' "$*" >&2; }

# ──────────────────────────────────────────────────────────────────────────────
# setup_claude_dir — Build the .claude/ and .aeef/ directories for a role.
#
# Arguments:
#   $1 — role name (product | architect | developer | qc)
#   $2 — project directory (absolute path)
#
# Behavior:
#   - Removes any existing .claude/ directory (from a previous run)
#   - Creates .claude/rules/, .claude/skills/, .claude/hooks/
#   - Copies role-specific files from $AEEF_ROOT/roles/$role/
#   - Copies shared hooks from $AEEF_ROOT/hooks/
#   - Creates .aeef/ directories for handoffs, provenance, and runs
#   - Creates .aeef/.gitignore to exclude ephemeral run data
#   - Prints a summary of what was configured
#
# Returns:
#   0 on success, 1 on failure
# ──────────────────────────────────────────────────────────────────────────────
setup_claude_dir() {
    local role="${1:?setup_claude_dir requires a role name}"
    local project_dir="${2:?setup_claude_dir requires a project directory}"
    local aeef_root="${AEEF_ROOT:?AEEF_ROOT is not set}"

    local claude_dir="${project_dir}/.claude"
    local aeef_dir="${project_dir}/.aeef"
    local role_src="${aeef_root}/roles/${role}"
    local hooks_src="${aeef_root}/hooks"

    # ── Clean up previous .claude/ directory ──────────────────────────────────
    if [[ -d "$claude_dir" ]]; then
        info "Removing existing .claude/ directory from previous run..."
        rm -rf "$claude_dir"
    fi

    # ── Create .claude/ structure ─────────────────────────────────────────────
    info "Creating .claude/ directory structure..."
    mkdir -p "${claude_dir}/rules"
    mkdir -p "${claude_dir}/skills"
    mkdir -p "${claude_dir}/hooks"

    local files_copied=0

    # ── Copy role-specific files ──────────────────────────────────────────────
    if [[ -d "$role_src" ]]; then
        info "Copying role-specific files from ${role_src}/..."

        # Copy rules (*.md files in rules/ subdirectory)
        if [[ -d "${role_src}/rules" ]]; then
            local rule_files
            rule_files="$(find "${role_src}/rules" -type f 2>/dev/null)"
            if [[ -n "$rule_files" ]]; then
                cp -r "${role_src}/rules/"* "${claude_dir}/rules/" 2>/dev/null || true
                files_copied=$((files_copied + $(echo "$rule_files" | wc -l)))
            fi
        fi

        # Copy skills (*.md files in skills/ subdirectory)
        if [[ -d "${role_src}/skills" ]]; then
            local skill_files
            skill_files="$(find "${role_src}/skills" -type f 2>/dev/null)"
            if [[ -n "$skill_files" ]]; then
                cp -r "${role_src}/skills/"* "${claude_dir}/skills/" 2>/dev/null || true
                files_copied=$((files_copied + $(echo "$skill_files" | wc -l)))
            fi
        fi

        # Copy CLAUDE.md (the main role context file) to .claude/
        if [[ -f "${role_src}/CLAUDE.md" ]]; then
            cp "${role_src}/CLAUDE.md" "${claude_dir}/CLAUDE.md"
            files_copied=$((files_copied + 1))
        fi

        # Copy any other top-level files from the role directory
        local top_level_files
        top_level_files="$(find "${role_src}" -maxdepth 1 -type f ! -name "CLAUDE.md" 2>/dev/null)"
        if [[ -n "$top_level_files" ]]; then
            while IFS= read -r f; do
                cp "$f" "${claude_dir}/" 2>/dev/null || true
                files_copied=$((files_copied + 1))
            done <<< "$top_level_files"
        fi
    else
        warn "Role source directory not found: ${role_src}"
        warn "Creating minimal .claude/CLAUDE.md for role '${role}'..."

        cat > "${claude_dir}/CLAUDE.md" <<CLAUDE_EOF
# AEEF ${role^} Agent

You are operating as the **${ROLE_DISPLAY_NAME[$role]}** within the
AI Engineering Excellence Framework (AEEF).

## Your Role

Refer to \`.claude/rules/contract.md\` for your full contract and constraints.

## Branch Context

- **Your branch:** \`${ROLE_BRANCH[$role]}\`
- **Upstream (input):** \`${ROLE_UPSTREAM[$role]}\`
- **Downstream (output):** \`${ROLE_DOWNSTREAM[$role]}\`

## Working Agreement

1. Stay within your permitted tools and scope.
2. Produce structured handoff artifacts in \`.aeef/handoffs/\`.
3. Record provenance metadata in \`.aeef/provenance/\`.
4. Follow the project coding standards and conventions.
CLAUDE_EOF
        files_copied=$((files_copied + 1))

        # Create a minimal contract
        cat > "${claude_dir}/rules/contract.md" <<CONTRACT_EOF
# ${ROLE_DISPLAY_NAME[$role]} Contract

## Permitted Actions
- Tools: ${ROLE_ALLOWED_TOOLS[$role]}

## Prohibited Actions
- Disallowed tools: ${ROLE_DISALLOWED_TOOLS[$role]:-None}

## Handoff Requirements
- Produce a handoff document in \`.aeef/handoffs/\` before completing.
- Include a summary of changes, decisions made, and open questions.

## Quality Gates
- All changes must be consistent with upstream artifacts.
- Do not introduce regressions or break existing contracts.
CONTRACT_EOF
        files_copied=$((files_copied + 1))
    fi

    # ── Copy shared hooks ─────────────────────────────────────────────────────
    if [[ -d "$hooks_src" ]]; then
        info "Copying shared hooks from ${hooks_src}/..."
        local hook_files
        hook_files="$(find "${hooks_src}" -type f 2>/dev/null)"
        if [[ -n "$hook_files" ]]; then
            cp -r "${hooks_src}/"* "${claude_dir}/hooks/" 2>/dev/null || true
            files_copied=$((files_copied + $(echo "$hook_files" | wc -l)))
        fi
    else
        info "No shared hooks directory found at ${hooks_src}. Skipping."
    fi

    # ── Create .aeef/ structure ───────────────────────────────────────────────
    info "Creating .aeef/ directory structure..."
    mkdir -p "${aeef_dir}/handoffs"
    mkdir -p "${aeef_dir}/provenance"
    mkdir -p "${aeef_dir}/runs"

    # ── Create .aeef/.gitignore ───────────────────────────────────────────────
    cat > "${aeef_dir}/.gitignore" <<'GITIGNORE_EOF'
# AEEF ephemeral data — do not commit run logs
runs/
GITIGNORE_EOF

    # ── Write run metadata ────────────────────────────────────────────────────
    local run_id="${AEEF_RUN_ID:-unknown}"
    cat > "${aeef_dir}/runs/${run_id}.json" <<RUN_EOF
{
  "run_id": "${run_id}",
  "role": "${role}",
  "branch": "${ROLE_BRANCH[$role]}",
  "upstream": "${ROLE_UPSTREAM[$role]}",
  "downstream": "${ROLE_DOWNSTREAM[$role]}",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "aeef_root": "${aeef_root}",
  "project_dir": "${project_dir}"
}
RUN_EOF

    # ── Summary ───────────────────────────────────────────────────────────────
    printf "\n"
    info "Setup summary for '${role}':"
    info "  .claude/CLAUDE.md      — Role context"
    info "  .claude/rules/         — $(find "${claude_dir}/rules" -type f 2>/dev/null | wc -l) file(s)"
    info "  .claude/skills/        — $(find "${claude_dir}/skills" -type f 2>/dev/null | wc -l) file(s)"
    info "  .claude/hooks/         — $(find "${claude_dir}/hooks" -type f 2>/dev/null | wc -l) file(s)"
    info "  .aeef/handoffs/        — Handoff artifacts"
    info "  .aeef/provenance/      — Provenance metadata"
    info "  .aeef/runs/            — Run logs (git-ignored)"
    info "  Total files copied:    ${files_copied}"
    printf "\n"

    return 0
}
