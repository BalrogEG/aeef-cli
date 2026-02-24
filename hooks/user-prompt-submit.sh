#!/usr/bin/env bash
set -euo pipefail

# AEEF User-Prompt-Submit Hook — Prompt Policy Validation
# Receives JSON on stdin from Claude Code containing the user's prompt.
# Checks for policy violations (secrets, safety bypass, gate bypass).
# Exit 0 = allow, Exit 2 = block (reason on stderr).

###############################################################################
# Helpers
###############################################################################

allow() {
  exit 0
}

block() {
  local reason="${1:-Blocked by AEEF prompt policy}"
  echo "$reason" >&2
  exit 2
}

###############################################################################
# Read and parse stdin
###############################################################################

INPUT="$(cat)"

PROMPT="$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)"

# If we cannot extract a prompt, allow (fail-open)
if [[ -z "$PROMPT" ]]; then
  allow
fi

###############################################################################
# Policy 1: Check for secrets / credentials in the prompt
###############################################################################

# AWS access key pattern (AKIA...)
if echo "$PROMPT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
  block "[AEEF Policy] Prompt appears to contain an AWS access key. Remove credentials before submitting."
fi

# AWS secret key pattern (40 char base64)
if echo "$PROMPT" | grep -qE '[A-Za-z0-9/+=]{40}' && echo "$PROMPT" | grep -qiE '(secret|aws_secret|secret_access_key)'; then
  block "[AEEF Policy] Prompt appears to contain an AWS secret key. Remove credentials before submitting."
fi

# Generic API key patterns
if echo "$PROMPT" | grep -qiE '(api[_-]?key|apikey)\s*[:=]\s*['\''"][A-Za-z0-9_\-]{20,}['\''"]'; then
  block "[AEEF Policy] Prompt appears to contain an API key. Remove credentials before submitting."
fi

# Password patterns
if echo "$PROMPT" | grep -qiE '(password|passwd|pwd)\s*[:=]\s*['\''"][^'\''"]{8,}['\''"]'; then
  block "[AEEF Policy] Prompt appears to contain a password. Remove credentials before submitting."
fi

# Bearer tokens
if echo "$PROMPT" | grep -qiE 'bearer\s+[A-Za-z0-9_\-\.]{20,}'; then
  block "[AEEF Policy] Prompt appears to contain a bearer token. Remove credentials before submitting."
fi

# Private key blocks
if echo "$PROMPT" | grep -qE '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'; then
  block "[AEEF Policy] Prompt appears to contain a private key. Remove credentials before submitting."
fi

###############################################################################
# Policy 2: Safety bypass attempts
###############################################################################

if echo "$PROMPT" | grep -qiE '\-\-no[_-]?verify'; then
  block "[AEEF Policy] AEEF policy prohibits bypassing safety checks. The --no-verify flag is not allowed."
fi

if echo "$PROMPT" | grep -qiE '\-\-force'; then
  block "[AEEF Policy] AEEF policy prohibits bypassing safety checks. The --force flag is not allowed."
fi

###############################################################################
# Policy 3: Quality gate bypass attempts
###############################################################################

if echo "$PROMPT" | grep -qiE 'disable\s*(the\s+)?gate'; then
  block "[AEEF Policy] AEEF policy prohibits bypassing quality gates."
fi

if echo "$PROMPT" | grep -qiE 'skip\s*(the\s+)?test'; then
  block "[AEEF Policy] AEEF policy prohibits bypassing quality gates. Tests must be run."
fi

if echo "$PROMPT" | grep -qiE 'skip\s*(the\s+)?lint'; then
  block "[AEEF Policy] AEEF policy prohibits bypassing quality gates. Linting must be run."
fi

###############################################################################
# All checks passed — allow the prompt
###############################################################################

allow
