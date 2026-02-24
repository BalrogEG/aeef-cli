---
name: aeef-gate
description: Run AEEF quality gate checks and report pass/fail status
allowed-tools: Bash, Read
---

# AEEF Quality Gate Runner

## Purpose

Quality gates are mandatory checkpoints that must pass before a handoff can proceed. This skill runs all applicable quality gates for the current project, reports pass/fail status for each gate, and saves a structured results file for traceability.

Quality gates enforce the AEEF standard that all AI-generated code meets minimum quality thresholds before moving downstream in the pipeline.

## Current Context

- **Current Role**: !`echo ${AEEF_ROLE:-"(not set — run via aeef CLI)"}`
- **Run ID**: !`echo ${AEEF_RUN_ID:-$(date +%Y%m%d-%H%M%S)-$(head -c 4 /dev/urandom | xxd -p)}`
- **Project Root**: !`pwd`

## Quality Gates to Check

| Gate | Description | Threshold |
|------|-------------|-----------|
| **Lint** | Static code style and error checking | Zero errors |
| **Type Check** | Static type analysis (strict mode) | Zero errors |
| **Tests** | Unit and integration test suite | All pass |
| **Coverage** | Line coverage percentage | >= 80% |
| **SAST** | Static Application Security Testing | No critical/high findings |

## Instructions

### Step 1: Detect Project Stack

Determine the project's technology stack by checking for marker files in the project root:

```bash
# Check which stack is present
if [ -f "package.json" ]; then
  echo "STACK=typescript"
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
  echo "STACK=python"
elif [ -f "go.mod" ]; then
  echo "STACK=go"
else
  echo "STACK=unknown"
fi
```

Run this detection first and use the result to determine which commands to execute below.

### Step 2: Run Quality Gates Per Stack

#### TypeScript / Node.js Stack

Run each gate in sequence, capturing exit codes:

1. **Lint**:
   ```bash
   npx eslint . --max-warnings 0 2>&1
   ```
   If eslint is not configured, try: `npm run lint 2>&1`

2. **Type Check**:
   ```bash
   npx tsc --noEmit 2>&1
   ```

3. **Tests**:
   ```bash
   npm test 2>&1
   ```

4. **Coverage**:
   ```bash
   npx jest --coverage --coverageReporters=text 2>&1
   ```
   Parse the "All files" line for the line coverage percentage.
   If Jest is not the test runner, try: `npx vitest run --coverage 2>&1`

5. **SAST**:
   ```bash
   npx semgrep scan --config auto --severity ERROR --severity WARNING --json 2>&1
   ```
   If semgrep is not installed, check for `.semgrep/` rules directory and run:
   ```bash
   npx semgrep scan --config .semgrep/ --severity ERROR --severity WARNING --json 2>&1
   ```
   If no SAST tool is available, record as "skipped" with a note.

#### Python Stack

1. **Lint**:
   ```bash
   ruff check . 2>&1
   ```
   If ruff is not available, try: `python -m flake8 . 2>&1`

2. **Type Check**:
   ```bash
   mypy app/ 2>&1
   ```
   If `app/` does not exist, try: `mypy src/ 2>&1` or `mypy . 2>&1`

3. **Tests**:
   ```bash
   python -m pytest 2>&1
   ```

4. **Coverage**:
   ```bash
   python -m pytest --cov --cov-report=term 2>&1
   ```
   Parse the "TOTAL" line for the coverage percentage.

5. **SAST**:
   ```bash
   semgrep scan --config auto --severity ERROR --severity WARNING --json 2>&1
   ```
   If semgrep is not available, try: `bandit -r app/ -f json 2>&1`

#### Go Stack

1. **Lint**:
   ```bash
   golangci-lint run ./... 2>&1
   ```
   If golangci-lint is not available, try: `go vet ./... 2>&1`

2. **Type Check**:
   Go compilation is the type check:
   ```bash
   go build ./... 2>&1
   ```

3. **Tests**:
   ```bash
   go test ./... -v 2>&1
   ```

4. **Coverage**:
   ```bash
   go test ./... -coverprofile=coverage.out 2>&1 && go tool cover -func=coverage.out 2>&1
   ```
   Parse the "total:" line for the coverage percentage.

5. **SAST**:
   ```bash
   semgrep scan --config auto --severity ERROR --severity WARNING --json 2>&1
   ```
   If semgrep is not available, try: `gosec ./... 2>&1`

### Step 3: Evaluate Results

For each gate, determine the status:

- **PASS**: Command exited with code 0 and output meets threshold
- **FAIL**: Command exited with non-zero code or output does not meet threshold
- **SKIPPED**: Tool not available or not applicable to this stack
- **ERROR**: Tool crashed or produced unexpected output

Coverage gate has a numeric threshold:
- **PASS**: >= 80% line coverage
- **FAIL**: < 80% line coverage

SAST gate evaluation:
- **PASS**: No critical or high severity findings
- **FAIL**: One or more critical or high severity findings
- **SKIPPED**: No SAST tool available

### Step 4: Output Results Table

Print a formatted table to the console:

```
╔══════════════════════════════════════════════════════╗
║              AEEF Quality Gate Results               ║
╠══════════════╦══════════╦════════════════════════════╣
║ Gate         ║ Status   ║ Details                    ║
╠══════════════╬══════════╬════════════════════════════╣
║ Lint         ║ PASS     ║ 0 errors, 0 warnings       ║
║ Type Check   ║ PASS     ║ No type errors              ║
║ Tests        ║ PASS     ║ 42 passed, 0 failed         ║
║ Coverage     ║ PASS     ║ 87.3% (threshold: 80%)      ║
║ SAST         ║ SKIPPED  ║ semgrep not available        ║
╠══════════════╬══════════╬════════════════════════════╣
║ OVERALL      ║ PASS     ║ 4/4 required gates passed   ║
╚══════════════╩══════════╩════════════════════════════╝
```

The OVERALL status is:
- **PASS**: All non-skipped gates passed
- **FAIL**: One or more gates failed

### Step 5: Save Results

1. Create the output directory:
   ```bash
   mkdir -p .aeef/runs
   ```

2. Save structured results to `.aeef/runs/gate-results.json`:

```json
{
  "$schema": "aeef-gate-results-v1",
  "metadata": {
    "run_id": "<AEEF_RUN_ID or generated>",
    "timestamp": "<ISO 8601 timestamp>",
    "role": "<AEEF_ROLE>",
    "stack": "<detected stack>",
    "project_root": "<absolute path>"
  },
  "gates": {
    "lint": {
      "status": "pass|fail|skipped|error",
      "exit_code": 0,
      "details": "<summary of output>",
      "command": "<command that was run>"
    },
    "typecheck": {
      "status": "pass|fail|skipped|error",
      "exit_code": 0,
      "details": "<summary of output>",
      "command": "<command that was run>"
    },
    "tests": {
      "status": "pass|fail|skipped|error",
      "exit_code": 0,
      "details": "<summary: X passed, Y failed>",
      "command": "<command that was run>"
    },
    "coverage": {
      "status": "pass|fail|skipped|error",
      "percentage": 87.3,
      "threshold": 80,
      "details": "<coverage summary>",
      "command": "<command that was run>"
    },
    "sast": {
      "status": "pass|fail|skipped|error",
      "findings": {
        "critical": 0,
        "high": 0,
        "medium": 0,
        "low": 0
      },
      "details": "<summary of findings>",
      "command": "<command that was run>"
    }
  },
  "overall": {
    "status": "pass|fail",
    "gates_passed": 4,
    "gates_failed": 0,
    "gates_skipped": 1,
    "gates_total": 5
  }
}
```

3. Print the save location:
   ```
   Results saved to: .aeef/runs/gate-results.json
   ```

### Step 6: Guidance on Failures

If any gate fails, provide specific remediation guidance:

- **Lint failure**: List the specific lint errors and suggest fixes
- **Type check failure**: Show the type errors and recommend corrections
- **Test failure**: Identify failing tests and likely causes
- **Coverage below threshold**: Identify files with low coverage and suggest what to test
- **SAST findings**: List the findings with severity and remediation guidance

Remind the user that all gates must pass before running `/aeef-handoff`.
