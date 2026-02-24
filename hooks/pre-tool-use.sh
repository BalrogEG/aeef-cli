#!/usr/bin/env bash
set -euo pipefail

# AEEF Pre-Tool-Use Hook — Contract Enforcement
# Receives JSON on stdin from Claude Code with tool_name and tool_input.
# Exit 0 = allow, Exit 2 = block (reason on stderr).

###############################################################################
# Helpers
###############################################################################

allow() {
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
EOF
  exit 0
}

block() {
  local reason="${1:-Blocked by AEEF contract enforcement}"
  echo "$reason" >&2
  exit 2
}

###############################################################################
# Read and parse stdin
###############################################################################

INPUT="$(cat)"

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
TOOL_INPUT="$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null || echo '{}')"

# If we cannot determine the tool, allow (fail-open for unknown hooks)
if [[ -z "$TOOL_NAME" ]]; then
  allow
fi

ROLE="${AEEF_ROLE:-}"

# If no role is set, allow everything (no contract to enforce)
if [[ -z "$ROLE" ]]; then
  allow
fi

###############################################################################
# Utility: check if a file path matches source-code patterns
###############################################################################

is_source_code_path() {
  local path="$1"
  # Match directory-based patterns and extension-based patterns
  if [[ "$path" == *src/* ]] || \
     [[ "$path" == *app/* ]] || \
     [[ "$path" == *internal/* ]] || \
     [[ "$path" == *cmd/* ]] || \
     [[ "$path" == *.ts ]] || \
     [[ "$path" == *.py ]] || \
     [[ "$path" == *.go ]]; then
    return 0
  fi
  return 1
}

is_allowed_doc_path() {
  local path="$1"
  if [[ "$path" == *.md ]] || \
     [[ "$path" == *.json ]] || \
     [[ "$path" == *.yaml ]] || \
     [[ "$path" == *.yml ]]; then
    return 0
  fi
  return 1
}

###############################################################################
# Extract file_path from tool input (used by Write / Edit)
###############################################################################

get_file_path() {
  echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null || true
}

###############################################################################
# Extract command from Bash tool input
###############################################################################

get_command() {
  echo "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null || true
}

###############################################################################
# Role: product
# - Block ALL Bash tool calls
# - Block Write/Edit to source code files
# - Allow Write/Edit to .md, .json, .yaml
###############################################################################

enforce_product() {
  if [[ "$TOOL_NAME" == "Bash" ]]; then
    block "[product] Bash tool is not permitted for the product role. Use Write/Edit for document changes only."
  fi

  if [[ "$TOOL_NAME" == "Write" ]] || [[ "$TOOL_NAME" == "Edit" ]]; then
    local fp
    fp="$(get_file_path)"
    if [[ -z "$fp" ]]; then
      allow  # no file path — let Claude Code handle the error
    fi
    if is_source_code_path "$fp"; then
      block "[product] Writing to source code files is not permitted for the product role. File: $fp"
    fi
    if is_allowed_doc_path "$fp"; then
      allow
    fi
    # For any other extension, block to be safe
    block "[product] The product role may only write to .md, .json, .yaml files. File: $fp"
  fi

  # All other tools (Read, Grep, Glob, etc.) are allowed
  allow
}

###############################################################################
# Role: architect
# - Block Write/Edit to source code files
# - Allow Bash only for docker/diagram commands
###############################################################################

enforce_architect() {
  if [[ "$TOOL_NAME" == "Write" ]] || [[ "$TOOL_NAME" == "Edit" ]]; then
    local fp
    fp="$(get_file_path)"
    if [[ -z "$fp" ]]; then
      allow
    fi
    if is_source_code_path "$fp"; then
      block "[architect] Writing to source code files is not permitted for the architect role. File: $fp"
    fi
    allow
  fi

  if [[ "$TOOL_NAME" == "Bash" ]]; then
    local cmd
    cmd="$(get_command)"
    if [[ -z "$cmd" ]]; then
      allow
    fi
    # Allow docker and diagram-related commands
    if echo "$cmd" | grep -qiE '^(docker|docker-compose|docker compose|d2|mermaid|mmdc|plantuml|dot|graphviz|structurizr)'; then
      allow
    fi
    # Also allow piped commands that start with allowed tools
    if echo "$cmd" | grep -qiE '(docker|docker-compose|docker compose|d2 |mermaid|mmdc |plantuml|dot |structurizr)'; then
      allow
    fi
    block "[architect] Bash is restricted to docker and diagram commands for the architect role. Command: ${cmd:0:120}"
  fi

  allow
}

###############################################################################
# Role: developer
# - Block dangerous Bash commands
# - Block writing to sensitive paths
# - Allow everything else
###############################################################################

enforce_developer() {
  if [[ "$TOOL_NAME" == "Bash" ]]; then
    local cmd
    cmd="$(get_command)"
    if [[ -z "$cmd" ]]; then
      allow
    fi

    # Block dangerous commands
    if echo "$cmd" | grep -qE 'rm\s+-rf\s'; then
      block "[developer] Destructive command 'rm -rf' is blocked by AEEF policy."
    fi
    if echo "$cmd" | grep -qE 'git\s+push'; then
      block "[developer] 'git push' is blocked. Use /aeef-handoff to complete your work and hand off."
    fi
    if echo "$cmd" | grep -qE 'git\s+merge'; then
      block "[developer] 'git merge' is blocked by AEEF policy. Use the PR-based handoff workflow."
    fi
    if echo "$cmd" | grep -qE 'git\s+checkout\s+main'; then
      block "[developer] 'git checkout main' is blocked. Stay on your assigned branch."
    fi

    allow
  fi

  if [[ "$TOOL_NAME" == "Write" ]] || [[ "$TOOL_NAME" == "Edit" ]]; then
    local fp
    fp="$(get_file_path)"
    if [[ -z "$fp" ]]; then
      allow
    fi

    # Block writing to sensitive paths
    if [[ "$fp" == *.env ]] || [[ "$fp" == *.env.* ]] || [[ "$fp" == */.env* ]]; then
      block "[developer] Writing to .env files is blocked by AEEF policy. File: $fp"
    fi
    if [[ "$fp" == *secrets/* ]] || [[ "$fp" == *secrets* && -d "${fp%/*}/secrets" ]]; then
      block "[developer] Writing to secrets/ directory is blocked by AEEF policy. File: $fp"
    fi
    # Simpler check for secrets/ in path
    if echo "$fp" | grep -qE '(^|/)secrets/'; then
      block "[developer] Writing to secrets/ directory is blocked by AEEF policy. File: $fp"
    fi
    if echo "$fp" | grep -qE '(^|/)infrastructure/'; then
      block "[developer] Writing to infrastructure/ directory is blocked by AEEF policy. File: $fp"
    fi

    allow
  fi

  allow
}

###############################################################################
# Role: qc
# - Block ALL Write and Edit tool calls (read-only + test execution)
# - Allow Bash only for test commands
###############################################################################

enforce_qc() {
  if [[ "$TOOL_NAME" == "Write" ]] || [[ "$TOOL_NAME" == "Edit" ]]; then
    block "[qc] The QC role is read-only. Write and Edit tools are not permitted."
  fi

  if [[ "$TOOL_NAME" == "Bash" ]]; then
    local cmd
    cmd="$(get_command)"
    if [[ -z "$cmd" ]]; then
      allow
    fi

    # Allow specific test/review commands
    if echo "$cmd" | grep -qE '(npm\s+test|npx\s+jest|npx\s+vitest|pytest|go\s+test|git\s+diff|git\s+log|git\s+status|git\s+show|npm\s+run\s+lint|npm\s+run\s+typecheck|npx\s+tsc|npx\s+eslint|ruff|mypy|golangci-lint|semgrep)'; then
      allow
    fi

    block "[qc] Bash is restricted to test, lint, and git-review commands for the QC role. Command: ${cmd:0:120}"
  fi

  allow
}

###############################################################################
# Role: scrum / devmgr / executive
# - Planning/reporting roles: no source code writes, no Bash by default
###############################################################################

enforce_reporting_role() {
  local role_name="$1"

  if [[ "$TOOL_NAME" == "Bash" ]]; then
    block "[${role_name}] Bash is not permitted for this role. Use Read/Grep/Write/Edit for planning and reporting artifacts only."
  fi

  if [[ "$TOOL_NAME" == "Write" ]] || [[ "$TOOL_NAME" == "Edit" ]]; then
    local fp
    fp="$(get_file_path)"
    [[ -z "$fp" ]] && allow
    if is_source_code_path "$fp"; then
      block "[${role_name}] Writing to source code files is not permitted for this role. File: $fp"
    fi
    if echo "$fp" | grep -qE '(^|/)(secrets|infrastructure)/'; then
      block "[${role_name}] Writing to restricted paths is not permitted. File: $fp"
    fi
    allow
  fi

  allow
}

###############################################################################
# Role: qa (enterprise role-pack)
# - Same enforcement as qc (read-only, test/lint execution)
###############################################################################

enforce_qa() {
  enforce_qc
}

###############################################################################
# Role: security / compliance
###############################################################################

enforce_security() {
  if [[ "$TOOL_NAME" == "Write" ]] || [[ "$TOOL_NAME" == "Edit" ]]; then
    local fp
    fp="$(get_file_path)"
    [[ -z "$fp" ]] && allow
    if is_source_code_path "$fp"; then
      block "[security] Editing source code is restricted. Produce findings/reports or scoped remediation instructions."
    fi
    if echo "$fp" | grep -qE '(^|/)secrets/|(^|/)\\.env'; then
      block "[security] Writing secrets or .env files is blocked."
    fi
    allow
  fi

  if [[ "$TOOL_NAME" == "Bash" ]]; then
    local cmd
    cmd="$(get_command)"
    [[ -z "$cmd" ]] && allow
    if echo "$cmd" | grep -qiE '(semgrep|bandit|govulncheck|npm audit|pip-audit|trivy|grype|syft|license-checker|go-licenses|git diff|git show|git status|jq|cat)'; then
      allow
    fi
    block "[security] Bash is restricted to scan, audit, and review commands. Command: ${cmd:0:120}"
  fi

  allow
}

enforce_compliance() {
  if [[ "$TOOL_NAME" == "Bash" ]]; then
    local cmd
    cmd="$(get_command)"
    [[ -z "$cmd" ]] && allow
    if echo "$cmd" | grep -qiE '(jq|git diff|git show|git status|cat|ls)'; then
      allow
    fi
    block "[compliance] Bash is restricted to evidence/review commands. Command: ${cmd:0:120}"
  fi

  if [[ "$TOOL_NAME" == "Write" ]] || [[ "$TOOL_NAME" == "Edit" ]]; then
    local fp
    fp="$(get_file_path)"
    [[ -z "$fp" ]] && allow
    if is_source_code_path "$fp"; then
      block "[compliance] Editing source code is not permitted."
    fi
    if echo "$fp" | grep -qE '(^|/)infrastructure/|(^|/)secrets/'; then
      block "[compliance] Editing infrastructure or secrets is not permitted."
    fi
    allow
  fi

  allow
}

###############################################################################
# Role: platform / ops
###############################################################################

enforce_platform() {
  if [[ "$TOOL_NAME" == "Write" ]] || [[ "$TOOL_NAME" == "Edit" ]]; then
    local fp
    fp="$(get_file_path)"
    [[ -z "$fp" ]] && allow
    if is_source_code_path "$fp"; then
      block "[platform] Editing application source code is not permitted. Limit changes to deployment/infrastructure artifacts."
    fi
    allow
  fi

  if [[ "$TOOL_NAME" == "Bash" ]]; then
    local cmd
    cmd="$(get_command)"
    [[ -z "$cmd" ]] && allow
    if echo "$cmd" | grep -qiE '^(docker|docker compose|docker-compose|kubectl|helm|terraform|aws|gcloud|az|gh|kustomize|jq|yq)'; then
      allow
    fi
    if echo "$cmd" | grep -qiE '(kubectl|helm|terraform|docker|kustomize|gh workflow)'; then
      allow
    fi
    block "[platform] Bash is restricted to infrastructure and deployment commands. Command: ${cmd:0:120}"
  fi

  allow
}

enforce_ops() {
  if [[ "$TOOL_NAME" == "Write" ]] || [[ "$TOOL_NAME" == "Edit" ]]; then
    local fp
    fp="$(get_file_path)"
    [[ -z "$fp" ]] && allow
    if is_source_code_path "$fp"; then
      block "[ops] Editing application source code is not permitted during operations."
    fi
    allow
  fi

  if [[ "$TOOL_NAME" == "Bash" ]]; then
    local cmd
    cmd="$(get_command)"
    [[ -z "$cmd" ]] && allow
    if echo "$cmd" | grep -qiE '(docker|docker compose|kubectl|helm|curl|jq|journalctl|systemctl|git diff|git show|gh|./shared/scripts/|shared/scripts/)'; then
      allow
    fi
    block "[ops] Bash is restricted to monitoring, incident response, and deployment runtime commands. Command: ${cmd:0:120}"
  fi

  allow
}

###############################################################################
# Dispatch by role
###############################################################################

case "$ROLE" in
  product)   enforce_product ;;
  scrum)     enforce_reporting_role "scrum" ;;
  architect) enforce_architect ;;
  developer) enforce_developer ;;
  qc)        enforce_qc ;;
  qa)        enforce_qa ;;
  security)  enforce_security ;;
  compliance) enforce_compliance ;;
  platform)  enforce_platform ;;
  devmgr)    enforce_reporting_role "devmgr" ;;
  ops)       enforce_ops ;;
  executive) enforce_reporting_role "executive" ;;
  *)
    # Unknown role — allow but warn
    echo "[aeef] Warning: unknown role '$ROLE', no contract enforcement applied." >&2
    allow
    ;;
esac
