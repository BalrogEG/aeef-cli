#!/usr/bin/env bash
set -euo pipefail

# AEEF Stop Hook — Quality Gate Check
# Receives JSON on stdin from Claude Code when the agent is about to stop.
# Checks that required handoff artifacts and quality gates have been met.
# If gates are not met, returns a systemMessage asking the user to complete them.
# Always exits 0 (uses "continue":true to allow the stop but with guidance).

###############################################################################
# Read stdin
###############################################################################

INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")"

###############################################################################
# Gate check state
###############################################################################

GATES_MET=true
MISSING_GATES=()

###############################################################################
# Gate 1: Handoff artifact exists
###############################################################################

HANDOFF_DIR=".aeef/handoffs"

if [[ -d "$HANDOFF_DIR" ]]; then
  # Check for at least one JSON file
  HANDOFF_COUNT="$(find "$HANDOFF_DIR" -maxdepth 1 -name '*.json' -type f 2>/dev/null | wc -l || echo 0)"
  if [[ "$HANDOFF_COUNT" -eq 0 ]]; then
    GATES_MET=false
    MISSING_GATES+=("No handoff artifact found in $HANDOFF_DIR. Run /aeef-handoff to generate one.")
  fi
else
  GATES_MET=false
  MISSING_GATES+=("Handoff directory $HANDOFF_DIR does not exist. Run /aeef-handoff to generate the handoff artifact.")
fi

###############################################################################
# Gate 2: Developer role — tests must have been run
###############################################################################

ROLE="${AEEF_ROLE:-}"
AUDIT_LOG=".aeef/runs/audit.log"

if [[ "$ROLE" == "developer" ]]; then
  if [[ -f "$AUDIT_LOG" ]]; then
    # Look for evidence of test execution in the audit log
    TEST_EVIDENCE="$(grep -cE '(npm.test|npx.jest|npx.vitest|pytest|go.test)' "$AUDIT_LOG" 2>/dev/null || echo 0)"
    if [[ "$TEST_EVIDENCE" -eq 0 ]]; then
      GATES_MET=false
      MISSING_GATES+=("No test execution found in audit log. Please run tests (npm test / pytest / go test) before completing.")
    fi
  else
    GATES_MET=false
    MISSING_GATES+=("Audit log not found. Please run tests (npm test / pytest / go test) before completing.")
  fi
fi

###############################################################################
# Output
###############################################################################

if [[ "$GATES_MET" == "true" ]]; then
  mkdir -p .aeef/runs
  jq -n \
    --arg role "${ROLE:-unknown}" \
    --arg now "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{
      gate_id: "gate-stop",
      stage: "stop",
      criteria_results: [
        {criterion: "handoff_artifact_exists", passed: true, note: "Handoff artifact present"}
      ],
      decision: "pass",
      required_human_approver: (if $role == "qc" then "human-approver" else null end),
      evidence_refs: [".aeef/handoffs", ".aeef/runs/audit.log", $now]
    }' > .aeef/runs/gate-decision.json
  # All gates passed — exit cleanly with no output
  exit 0
else
  # Build a system message listing missing gates
  GATE_LIST=""
  for gate in "${MISSING_GATES[@]}"; do
    GATE_LIST="${GATE_LIST}\n- ${gate}"
  done

  SYSTEM_MSG="Quality gates not yet met. Please run /aeef-gate to check and /aeef-handoff to generate the handoff artifact.\\n\\nMissing gates:${GATE_LIST}"

  jq -n -c \
    --arg msg "$SYSTEM_MSG" \
    '{"continue": true, "systemMessage": $msg}'

  mkdir -p .aeef/runs
  jq -n \
    --arg role "${ROLE:-unknown}" \
    '{
      gate_id: "gate-stop",
      stage: "stop",
      criteria_results: [
        {criterion: "handoff_artifact_exists", passed: false, note: "Missing handoff and/or test evidence"}
      ],
      decision: "fail",
      required_human_approver: (if $role == "qc" then "human-approver" else null end),
      evidence_refs: [".aeef/handoffs", ".aeef/runs/audit.log"]
    }' > .aeef/runs/gate-decision.json

  exit 0
fi
