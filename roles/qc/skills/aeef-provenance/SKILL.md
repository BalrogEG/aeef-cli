---
name: aeef-provenance
description: Generate an AEEF provenance record for AI-generated code changes
allowed-tools: Read, Write, Bash
---

# AEEF Provenance Record Generator

## Purpose

Provenance records document the origin, tooling, and review chain for AI-generated code changes. They are required for compliance with **PRD-STD-005** (AI Code Provenance Standard), which mandates that all AI-assisted code contributions include machine-readable provenance metadata.

A provenance record answers the critical questions:
- **Who** (or what) generated the code?
- **What tool and model** were used?
- **Which files** were affected?
- **What review** occurred before merge?
- **What quality gates** were passed?

This record becomes part of the permanent audit trail and is referenced by compliance checks, supply chain security tools, and governance dashboards.

## Current Context

- **Current Role**: !`echo ${AEEF_ROLE:-"(not set — run via aeef CLI)"}`
- **Run ID**: !`echo ${AEEF_RUN_ID:-$(date +%Y%m%d-%H%M%S)-$(head -c 4 /dev/urandom | xxd -p)}`
- **Current Branch**: !`git branch --show-current 2>/dev/null || echo "(not in a git repo)"`
- **HEAD Commit**: !`git rev-parse HEAD 2>/dev/null || echo "(not in a git repo)"`
- **Session ID**: !`echo ${CLAUDE_SESSION_ID:-"(not available)"}`

## Provenance Record Schema

The provenance record must conform to this JSON structure:

```json
{
  "$schema": "aeef-provenance-v1",
  "metadata": {
    "run_id": "<AEEF_RUN_ID or generated>",
    "timestamp": "<ISO 8601 timestamp>",
    "standard": "PRD-STD-005",
    "standard_version": "1.0.0"
  },
  "generation": {
    "tool": "claude-code",
    "tool_version": "<claude-code version if available>",
    "model": "<model identifier if available>",
    "session_id": "<CLAUDE_SESSION_ID or N/A>",
    "agent_roles_used": ["<list of AEEF roles that participated>"],
    "pipeline_run_id": "<AEEF_RUN_ID>"
  },
  "source": {
    "repository": "<git remote URL>",
    "branch": "<current branch>",
    "base_commit": "<merge base commit SHA>",
    "head_commit": "<HEAD commit SHA>",
    "commits": [
      {
        "sha": "<commit SHA>",
        "author": "<commit author>",
        "message": "<commit message>",
        "timestamp": "<commit timestamp>"
      }
    ]
  },
  "changes": {
    "files_added": ["<list of new files>"],
    "files_modified": ["<list of modified files>"],
    "files_deleted": ["<list of deleted files>"],
    "total_additions": "<lines added>",
    "total_deletions": "<lines deleted>"
  },
  "review_chain": {
    "product_review": {
      "agent": "product",
      "handoff_id": "<handoff artifact ID or N/A>",
      "human_approved": "<true|false|pending>"
    },
    "architect_review": {
      "agent": "architect",
      "handoff_id": "<handoff artifact ID or N/A>",
      "human_approved": "<true|false|pending>"
    },
    "developer_review": {
      "agent": "developer",
      "handoff_id": "<handoff artifact ID or N/A>",
      "human_approved": "<true|false|pending>"
    },
    "qc_review": {
      "agent": "qc",
      "handoff_id": "<handoff artifact ID or N/A>",
      "human_approved": "pending"
    }
  },
  "quality_gates": {
    "lint": "<pass|fail|skipped>",
    "typecheck": "<pass|fail|skipped>",
    "tests": "<pass|fail|skipped>",
    "coverage": {
      "status": "<pass|fail|skipped>",
      "percentage": "<number or N/A>"
    },
    "sast": {
      "status": "<pass|fail|skipped>",
      "critical_findings": 0,
      "high_findings": 0
    }
  },
  "compliance": {
    "standard": "PRD-STD-005",
    "ai_disclosure": true,
    "human_review_required": true,
    "human_review_completed": false,
    "provenance_chain_complete": "<true if all handoff artifacts exist>"
  },
  "attestation": {
    "generated_by": "aeef-cli/qc-agent",
    "timestamp": "<ISO 8601 timestamp>",
    "integrity_hash": "<SHA-256 hash of the record excluding this field>"
  }
}
```

## Instructions

### Step 1: Gather Generation Information

1. Determine the tool and model information:
   ```bash
   # Get claude-code version if available
   claude --version 2>/dev/null || echo "version not available"
   ```

2. Capture the session ID from the environment:
   ```bash
   echo "${CLAUDE_SESSION_ID:-not-available}"
   ```

3. Identify which agent roles participated by checking for handoff artifacts:
   ```bash
   ls -la .aeef/handoffs/ 2>/dev/null || echo "no handoffs found"
   ```

### Step 2: Gather Source Information

1. Get the repository URL:
   ```bash
   git remote get-url origin 2>/dev/null || echo "no remote configured"
   ```

2. Get the branch and commit information:
   ```bash
   git branch --show-current
   git rev-parse HEAD
   git merge-base HEAD ${AEEF_UPSTREAM:-main}
   ```

3. Get the commit log for this branch:
   ```bash
   git log $(git merge-base HEAD ${AEEF_UPSTREAM:-main})..HEAD --pretty=format:'{"sha":"%H","author":"%an","message":"%s","timestamp":"%aI"}' 2>/dev/null
   ```

### Step 3: Gather Change Information

1. Get file change details:
   ```bash
   # Files categorized
   git diff --name-status $(git merge-base HEAD ${AEEF_UPSTREAM:-main}) HEAD 2>/dev/null
   ```

2. Get line change statistics:
   ```bash
   git diff --stat $(git merge-base HEAD ${AEEF_UPSTREAM:-main}) HEAD 2>/dev/null
   ```

### Step 4: Build Review Chain

1. Read existing handoff artifacts from `.aeef/handoffs/` to populate the review chain
2. For each handoff artifact found, extract:
   - The source role
   - The handoff ID (run_id from the artifact)
   - Whether human approval was recorded
3. If a handoff artifact is missing for a role, record the handoff_id as "N/A"

### Step 5: Gather Quality Gate Results

1. Read the gate results file if it exists:
   ```bash
   cat .aeef/runs/gate-results.json 2>/dev/null || echo "no gate results found"
   ```

2. If gate results exist, extract the status for each gate
3. If no gate results exist, run `/aeef-gate` first and then read the results

### Step 6: Generate and Save the Provenance Record

1. Create the output directory:
   ```bash
   mkdir -p .aeef/provenance
   ```

2. Assemble the complete JSON provenance record following the schema above

3. Generate the integrity hash:
   - Serialize the JSON record (excluding the `attestation.integrity_hash` field)
   - Compute the SHA-256 hash of the serialized JSON
   - Insert the hash back into the record:
   ```bash
   # After saving the initial JSON without the hash:
   HASH=$(cat .aeef/provenance/<run-id>.json | python3 -c "
   import sys, json, hashlib
   data = json.load(sys.stdin)
   data['attestation']['integrity_hash'] = ''
   print(hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest())
   " 2>/dev/null || sha256sum .aeef/provenance/<run-id>.json | cut -d' ' -f1)
   ```

4. Save the final provenance record:
   ```
   .aeef/provenance/<run-id>.json
   ```

5. Print a summary to the console:
   ```
   --- AEEF Provenance Record Generated ---
   Run ID:        <run-id>
   Standard:      PRD-STD-005 v1.0.0
   Tool:          claude-code
   Files Changed: <count>
   Review Chain:  <count> handoffs found
   Quality Gates: <overall status>
   Integrity:     SHA-256:<hash>
   Saved to:      .aeef/provenance/<run-id>.json
   ------------------------------------------
   ```

### Step 7: Compliance Checklist

After generating the provenance record, verify and report:

- [ ] AI tool disclosure recorded (tool, model, session)
- [ ] All file changes catalogued
- [ ] Review chain populated from handoff artifacts
- [ ] Quality gate results included
- [ ] Integrity hash computed and embedded
- [ ] Human review flagged as required but pending

Remind the user that:
1. The provenance record must be committed alongside the code changes
2. Human review and approval are still required before merge to main
3. The `human_review_completed` field should be updated to `true` after human sign-off
4. This record will be referenced by compliance audits and supply chain security checks
