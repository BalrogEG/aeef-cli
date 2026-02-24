#!/usr/bin/env bash
set -euo pipefail

# AEEF Session-Start Hook — Environment Setup
# Receives JSON on stdin from Claude Code with session info.
# Writes environment variables to $CLAUDE_ENV_FILE so they are available to
# the Claude Code session.
# Prints a welcome banner to stderr (non-blocking).
# Always exits 0.

###############################################################################
# Read stdin (required by hook protocol, but we mainly use env vars)
###############################################################################

INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")"

###############################################################################
# Write environment variables to CLAUDE_ENV_FILE
###############################################################################

ENV_FILE="${CLAUDE_ENV_FILE:-}"

if [[ -n "$ENV_FILE" ]]; then
  {
    echo "AEEF_ROLE=${AEEF_ROLE:-}"
    echo "AEEF_BRANCH=${AEEF_BRANCH:-}"
    echo "AEEF_UPSTREAM=${AEEF_UPSTREAM:-}"
    echo "AEEF_DOWNSTREAM=${AEEF_DOWNSTREAM:-}"
    echo "AEEF_RUN_ID=${AEEF_RUN_ID:-}"
    echo "AEEF_CLI_ROOT=${AEEF_CLI_ROOT:-}"
  } >> "$ENV_FILE"
fi

###############################################################################
# Ensure .aeef working directories exist
###############################################################################

mkdir -p .aeef/runs .aeef/handoffs

###############################################################################
# Welcome message (stderr — informational, non-blocking)
###############################################################################

ROLE="${AEEF_ROLE:-<not set>}"
BRANCH="${AEEF_BRANCH:-<not set>}"
UPSTREAM="${AEEF_UPSTREAM:-<none>}"
DOWNSTREAM="${AEEF_DOWNSTREAM:-<none>}"
RUN_ID="${AEEF_RUN_ID:-$SESSION_ID}"

cat >&2 <<BANNER
====================================================================
  AEEF Agent Session Initialised
--------------------------------------------------------------------
  Role         : ${ROLE}
  Branch       : ${BRANCH}
  Upstream     : ${UPSTREAM}
  Downstream   : ${DOWNSTREAM}
  Run ID       : ${RUN_ID}
  Session ID   : ${SESSION_ID}
====================================================================
  Contract enforcement is ACTIVE for role: ${ROLE}
  Audit logging is enabled.
  Use /aeef-gate to check quality gates.
  Use /aeef-handoff to generate the handoff artifact.
====================================================================
BANNER

###############################################################################
# Exit successfully
###############################################################################

exit 0
