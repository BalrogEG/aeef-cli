#!/usr/bin/env bash
set -euo pipefail

# AEEF Post-Tool-Use Hook — Audit Logging
# Receives JSON on stdin from Claude Code with tool execution details.
# Appends an entry to .aeef/runs/audit.log.
# Always exits 0 (never blocks).

###############################################################################
# Read and parse stdin
###############################################################################

INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")"
TOOL_INPUT_SUMMARY="$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null | head -c 200 || echo "{}")"
TOOL_SUCCESS="$(echo "$INPUT" | jq -r '.tool_response.success // "unknown"' 2>/dev/null || echo "unknown")"

###############################################################################
# Determine log directory
###############################################################################

LOG_DIR=".aeef/runs"
LOG_FILE="${LOG_DIR}/audit.log"

# Create the directory if it does not exist
mkdir -p "$LOG_DIR"

###############################################################################
# Write log entry
###############################################################################

TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# Build a single-line JSON log entry for easy parsing
LOG_ENTRY="$(jq -n -c \
  --arg ts "$TIMESTAMP" \
  --arg sid "$SESSION_ID" \
  --arg tool "$TOOL_NAME" \
  --arg input "$TOOL_INPUT_SUMMARY" \
  --arg success "$TOOL_SUCCESS" \
  '{timestamp: $ts, session_id: $sid, tool_name: $tool, tool_input_summary: $input, success: $success}'
)"

echo "$LOG_ENTRY" >> "$LOG_FILE"

###############################################################################
# Always allow — audit hooks must never block
###############################################################################

exit 0
