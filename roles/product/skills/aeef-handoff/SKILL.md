---
name: aeef-handoff
description: Generate an AEEF handoff artifact for the next agent role in the SDLC pipeline
argument-hint: "[summary of changes]"
allowed-tools: Read, Write, Bash
---

# AEEF Handoff Artifact Generator

## What is a Handoff Artifact?

A handoff artifact is a structured JSON document that records the work completed by the current agent role and provides context for the next agent in the AEEF Agent SDLC pipeline. It captures:

- **What was done** — a summary of changes and decisions made
- **What to do next** — guidance for the downstream agent
- **Evidence** — files changed, tests run, gates passed
- **Traceability** — links back to stories, designs, and prior handoffs

Handoff artifacts are the primary mechanism for agent-to-agent communication in the AEEF pipeline. They ensure continuity, accountability, and auditability across the software delivery lifecycle.

## Current Context

- **Current Role**: !`echo ${AEEF_ROLE:-"(not set — run via aeef CLI)"}`
- **Downstream Target**: !`echo ${AEEF_DOWNSTREAM:-"(not set)"}`
- **Upstream Source**: !`echo ${AEEF_UPSTREAM:-"(not set)"}`
- **Run ID**: !`echo ${AEEF_RUN_ID:-$(date +%Y%m%d-%H%M%S)-$(head -c 4 /dev/urandom | xxd -p)}`
- **Current Branch**: !`git branch --show-current 2>/dev/null || echo "(not in a git repo)"`

## Files Changed in This Role's Scope

!`git diff --name-only $(git merge-base HEAD ${AEEF_UPSTREAM:-main}) HEAD 2>/dev/null || echo "(no git changes detected)"`

## Handoff Artifact Schema

The handoff artifact must conform to this JSON structure:

```json
{
  "$schema": "aeef-handoff-v1",
  "metadata": {
    "run_id": "<AEEF_RUN_ID or generated>",
    "timestamp": "<ISO 8601 timestamp>",
    "source_role": "<current AEEF_ROLE>",
    "target_role": "<AEEF_DOWNSTREAM>",
    "branch": "<current git branch>",
    "commit_sha": "<HEAD commit SHA>"
  },
  "summary": "<1-3 sentence summary of what was accomplished>",
  "changes": {
    "files_added": ["<list of new files>"],
    "files_modified": ["<list of modified files>"],
    "files_deleted": ["<list of deleted files>"]
  },
  "artifacts": [
    {
      "type": "<story|design|code|test|report>",
      "path": "<relative file path>",
      "description": "<what this artifact contains>"
    }
  ],
  "acceptance_criteria_status": [
    {
      "criterion": "<acceptance criterion text>",
      "status": "<met|not_met|partial|not_applicable>",
      "evidence": "<how this was verified>"
    }
  ],
  "quality_gates": {
    "lint": "<pass|fail|skipped>",
    "typecheck": "<pass|fail|skipped>",
    "tests": "<pass|fail|skipped>",
    "coverage": "<percentage or skipped>",
    "sast": "<pass|fail|skipped>"
  },
  "escalations": ["<any issues that need human attention>"],
  "notes_for_next_agent": "<guidance, context, or warnings for the downstream agent>",
  "handoff_checklist": {
    "contract_checks_passed": true,
    "all_outputs_produced": true,
    "no_forbidden_actions": true,
    "escalations_documented": true
  }
}
```

## Instructions

Follow these steps to generate the handoff artifact:

### Step 1: Gather Context

1. Read the current role's contract from `.claude/rules/contract.md` to understand required checks
2. Identify all files changed using git diff against the upstream branch
3. Review any existing handoff artifacts in `.aeef/handoffs/` for prior context
4. If `$ARGUMENTS` was provided, use it as the change summary; otherwise, analyze the changes to generate one

### Step 2: Build the Artifact

1. Generate a run ID: use `$AEEF_RUN_ID` if set, otherwise generate one with format `YYYYMMDD-HHMMSS-<random>`
2. Populate all metadata fields from environment variables and git state
3. Use the `$ARGUMENTS` value (if provided) as the `summary` field: **$ARGUMENTS**
4. Categorize changed files into added, modified, and deleted
5. List all artifacts produced during this role's work
6. Assess acceptance criteria status (if applicable to this role)
7. Record quality gate results (if gates were run)
8. Document any escalations or issues needing human attention
9. Write guidance for the downstream agent in `notes_for_next_agent`

### Step 3: Validate and Save

1. Ensure the `.aeef/handoffs/` directory exists (create if needed):
   ```bash
   mkdir -p .aeef/handoffs
   ```

2. Validate the JSON structure is complete and well-formed

3. Save the artifact:
   ```
   .aeef/handoffs/<run-id>.json
   ```

4. Print a summary to the console:
   ```
   --- AEEF Handoff Artifact Generated ---
   Run ID:    <run-id>
   From:      <source_role>
   To:        <target_role>
   Files:     <count> changed
   Saved to:  .aeef/handoffs/<run-id>.json
   -----------------------------------------
   ```

### Step 4: Next Steps Guidance

After generating the handoff, remind the user to:
1. Review the handoff artifact for accuracy
2. Commit the artifact: `git add .aeef/handoffs/<run-id>.json`
3. Create a PR from the current branch to the downstream branch
4. Tag the PR with the run ID for traceability
