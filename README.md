# aeef-cli

**CLI wrapper for Claude Code that orchestrates AI agent roles via Git branches.**

aeef-cli implements the AI Engineering Excellence Framework (AEEF) agent pipeline.
It wraps the `claude` CLI to enforce role-specific permissions, manage Git branch
workflows, and produce structured handoff artifacts as work flows from product
definition through architecture, development, and quality control.

## Architecture

The AEEF pipeline uses dedicated Git branches for each agent role. Work flows
downstream through pull requests, and each role has scoped tool permissions.

```
                        AEEF Branch Flow
    ================================================================

    main
      |
      v
    aeef/product -----> Product Agent
      |                   - Reads codebase, writes specs
      |                   - No shell access
      v
    aeef/architect ----> Architect Agent
      |                   - Reads specs, writes design docs
      |                   - Limited shell (docker, draw.io)
      v
    aeef/dev ----------> Developer Agent
      |                   - Implements code changes
      |                   - Build tools (npm, pip, go)
      |                   - No destructive git operations
      v
    aeef/qc -----------> QC Agent
      |                   - Runs tests, validates contracts
      |                   - Read-only (no Write/Edit)
      |                   - Cleans up artifacts on success
      v
    main  <------------- PR merges validated changes back

    ================================================================
    Direction:  main -> product -> architect -> dev -> qc -> main
    Each arrow = a Pull Request reviewed before merge
```

## Prerequisites

| Tool    | Purpose                          | Install                          |
|---------|----------------------------------|----------------------------------|
| claude  | Claude Code CLI (the AI backend) | `npm install -g @anthropic-ai/claude-code` |
| gh      | GitHub CLI (PR creation)         | `brew install gh` or [cli.github.com](https://cli.github.com) |
| git     | Version control                  | Pre-installed on most systems    |
| jq      | JSON parsing (CI mode)           | `brew install jq` or `apt install jq` |

## Installation

```bash
# Clone the repository
git clone https://github.com/BalrogEG/aeef-cli.git
cd aeef-cli

# Run the installer
bash install.sh
```

The installer will:
1. Detect the aeef-cli root directory
2. Create `~/.local/bin/` if it does not exist
3. Symlink `bin/aeef` to `~/.local/bin/aeef`
4. Check that `~/.local/bin` is in your PATH
5. Verify all required dependencies are installed

After installation, restart your shell or run:

```bash
source ~/.bashrc  # or ~/.zshrc
```

## 5-Minute Apply Journey (Immediate Wrapper Adoption)

Use this when you want to apply the wrapper and hooks to an existing Git repo immediately.

```bash
# 1) Verify your local setup and target repo
aeef doctor --project ./my-app

# 2) Install AEEF hooks/rules/skills into the repo (copies .claude/ + .aeef/.gitignore)
aeef bootstrap --project ./my-app --role product

# 3) Start the first role
aeef --role product --project ./my-app
```

Notes:
- `aeef bootstrap` applies the reference wrapper assets (hooks, contracts, skills, role prompt) without running Claude yet.
- Add `--with-branches` if you want the role branch (`aeef/product`) created/synced during bootstrap.
- Add `--commit` to commit the installed wrapper files before the first agent run.
- Repeat `aeef bootstrap --role <role>` if you want to switch the local role profile before a run.

### Manual installation

If you prefer not to use the installer:

```bash
chmod +x bin/aeef
ln -s "$(pwd)/bin/aeef" ~/.local/bin/aeef
```

## Usage

### Commands (wrapper lifecycle)

| Command | Purpose |
|---------|---------|
| `aeef doctor --project ./repo` | Check dependencies and repo readiness |
| `aeef bootstrap --project ./repo --role product` | Apply hooks/rules/skills into a repo |
| `aeef roles` | List role-to-branch routing |
| `aeef --role <role> --project ./repo` | Run a role agent workflow |

### Basic syntax

```bash
aeef --role <role> [OPTIONS]
```

### Required flag

| Flag          | Description                                    |
|---------------|------------------------------------------------|
| `--role`      | Agent role: `product`, `architect`, `developer`, or `qc` |

### Optional flags

| Flag              | Default   | Description                              |
|-------------------|-----------|------------------------------------------|
| `--backend-cmd`   | `claude`  | Backend CLI command                      |
| `--project`       | `.`       | Project directory path                   |
| `--model`         | `sonnet`  | Model to use (sonnet, opus, etc.)        |
| `--max-turns`     | `25`      | Max conversation turns (CI mode)         |
| `--budget`        | `5`       | Max budget in USD (CI mode)              |
| `--ci`            | off       | Non-interactive CI mode                  |
| `--prompt`        | none      | Initial prompt for the agent             |
| `--help`          |           | Show usage information                   |
| `--version`       |           | Show version number                      |

### Examples

#### Interactive product agent session

```bash
aeef --role product --project ./my-app
```

This launches an interactive Claude session configured as the Product Agent.
You can converse with the agent, which has access to Read, Grep, Glob, Write,
and Edit tools but cannot run shell commands.

#### Architect agent with a specific model

```bash
aeef --role architect --model opus --project ./my-app
```

The Architect Agent can additionally run Docker and draw.io commands.

#### Developer agent in CI mode

```bash
aeef --role developer \
  --ci \
  --prompt "Implement the authentication service based on the architect's design in docs/design/" \
  --max-turns 30 \
  --budget 10 \
  --project ./my-app
```

In CI mode, the agent runs non-interactively with JSON output, a turn limit,
and a budget cap. It also skips interactive permission prompts.

#### QC agent in CI mode

```bash
aeef --role qc \
  --ci \
  --prompt "Run the full test suite and validate all contracts" \
  --project ./my-app
```

The QC Agent has read-only access (no Write or Edit tools) and can run test
commands (npm test, pytest, go test). On success, it cleans up all AEEF
artifacts (.claude/ and .aeef/ directories) from the branch.

## How It Works

### 1. Branch setup

When you run `aeef --role <role>`, the CLI:
- Checks out or creates the role-specific branch (e.g., `aeef/product`)
- Merges the latest changes from the upstream branch (e.g., `main`)
- If there are merge conflicts, it aborts and prints resolution instructions

### 2. Directory setup

The CLI creates two directories in your project:

**`.claude/`** -- Configuration for Claude Code:
- `CLAUDE.md` -- Role context document
- `rules/` -- Role-specific constraints (contract.md, etc.)
- `skills/` -- Role-specific skill definitions
- `hooks/` -- Pre/post execution hooks

**`.aeef/`** -- AEEF pipeline artifacts:
- `handoffs/` -- Structured handoff documents (committed)
- `provenance/` -- Audit trail and metadata (committed)
- `runs/` -- Ephemeral run logs (git-ignored)

### 3. Agent execution

Claude Code is launched with:
- A system prompt identifying the agent role
- Allowed tools scoped to the role
- Disallowed tools to prevent overreach
- The specified model

### 4. Post-run actions

**On success (exit code 0):**
- All changes are committed with structured metadata
- A pull request is created targeting the downstream branch
- (QC role only) Agent artifacts are cleaned up

**On failure (non-zero exit code):**
- Working tree is reverted to last commit
- Untracked files are cleaned
- A fallback suggestion is printed

## Role Permissions

| Role       | Allowed Tools                              | Disallowed Tools                         |
|------------|--------------------------------------------|------------------------------------------|
| product    | Read, Grep, Glob, Write, Edit              | Bash (all)                               |
| architect  | Read, Grep, Glob, Write, Edit, docker, draw.io | (none)                               |
| developer  | Read, Grep, Glob, Write, Edit, npm, pip, go, git diff, git status | rm -rf, git push, git merge |
| qc         | Read, Grep, Glob, npm test, pytest, go test, git | Write, Edit                         |

## Hooks and Compliance

AEEF hooks run before and after agent execution to enforce compliance:

- **Pre-run hooks** validate that the branch state is clean and upstream is merged
- **Post-run hooks** verify that handoff artifacts exist and contracts are satisfied
- **Shared hooks** (in the `hooks/` directory) are copied into `.claude/hooks/` for
  every role

To add a custom hook, place it in the `hooks/` directory of the aeef-cli installation:

```
aeef-cli/
  hooks/
    pre-run.sh      # Runs before agent starts
    post-run.sh     # Runs after agent completes
    validate.sh     # Validates artifacts
```

## Extending with New Roles

To add a new role to the AEEF pipeline:

### 1. Update `lib/roles.sh`

Add entries to each associative array:

```bash
ROLE_BRANCH[myrole]="aeef/myrole"
ROLE_UPSTREAM[myrole]="aeef/dev"          # which branch feeds into this role
ROLE_DOWNSTREAM[myrole]="aeef/qc"        # which branch this role feeds into
ROLE_FALLBACK[myrole]="aeef/dev"
ROLE_ALLOWED_TOOLS[myrole]="Read,Grep,Glob,Write"
ROLE_DISALLOWED_TOOLS[myrole]="Bash"
ROLE_DISPLAY_NAME[myrole]="My Custom Agent"
```

Add the role to `VALID_ROLES`:

```bash
readonly VALID_ROLES=("product" "architect" "developer" "qc" "myrole")
```

### 2. Create role directory

```
aeef-cli/
  roles/
    myrole/
      CLAUDE.md             # Role context document
      rules/
        contract.md         # Constraints and permissions
      skills/
        my-skill.md         # Role-specific skills
```

### 3. Test the role

```bash
aeef --role myrole --project ./test-project
```

## Directory Structure

```
aeef-cli/
  bin/
    aeef                    # Main CLI entry point
  lib/
    roles.sh                # Role routing table and validation
    git-workflow.sh         # Branch management, commit, PR, revert
    setup-claude-dir.sh     # .claude/ and .aeef/ directory generator
    cleanup.sh              # QC exit cleanup
  hooks/                    # Shared hooks (copied to .claude/hooks/)
  roles/
    product/                # Product Agent configuration
      CLAUDE.md
      rules/
      skills/
    architect/              # Architect Agent configuration
      CLAUDE.md
      rules/
      skills/
    developer/              # Developer Agent configuration
      CLAUDE.md
      rules/
      skills/
    qc/                     # QC Agent configuration
      CLAUDE.md
      rules/
      skills/
  schemas/                  # JSON schemas for artifacts
  templates/                # Templates for handoffs, PRs, etc.
  install.sh                # Installer script
  LICENSE                   # Apache 2.0
  README.md                 # This file
```

## CI/CD Integration

### GitHub Actions

```yaml
name: AEEF Pipeline
on:
  push:
    branches: [main]

jobs:
  product:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Product Agent
        run: |
          aeef --role product --ci \
            --prompt "Analyze requirements and produce specs" \
            --max-turns 20 --budget 3

  architect:
    needs: product
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: aeef/product
      - name: Run Architect Agent
        run: |
          aeef --role architect --ci \
            --prompt "Design system architecture from specs" \
            --max-turns 25 --budget 5

  developer:
    needs: architect
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: aeef/architect
      - name: Run Developer Agent
        run: |
          aeef --role developer --ci \
            --prompt "Implement the architecture design" \
            --max-turns 40 --budget 10

  qc:
    needs: developer
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: aeef/dev
      - name: Run QC Agent
        run: |
          aeef --role qc --ci \
            --prompt "Run tests and validate all contracts" \
            --max-turns 15 --budget 3
```

## Environment Variables

| Variable       | Description                                          |
|----------------|------------------------------------------------------|
| `AEEF_ROOT`    | Path to the aeef-cli installation (auto-detected)    |
| `AEEF_RUN_ID`  | Unique identifier for the current run (auto-generated) |
| `AEEF_VERSION` | CLI version string                                   |

## Troubleshooting

### Merge conflicts during branch setup

If you see "Merge conflict detected", resolve it manually:

```bash
git checkout aeef/product       # or whichever branch
git merge main                  # or the upstream branch
# Resolve conflicts in your editor
git merge --continue
aeef --role product             # Re-run
```

### "Backend command not found: claude"

Install Claude Code:

```bash
npm install -g @anthropic-ai/claude-code
```

### "gh not found"

Install the GitHub CLI:

```bash
brew install gh        # macOS
sudo apt install gh    # Ubuntu/Debian
```

Then authenticate: `gh auth login`

### Role branch does not exist

The CLI creates role branches automatically from the upstream branch. If the
upstream branch does not exist either, ensure the pipeline has been run in
order: product first, then architect, developer, and qc.

## License

Apache 2.0. See [LICENSE](./LICENSE) for details.

## Links

- [AEEF Standards Site](https://aeef.dev)
- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [GitHub CLI Documentation](https://cli.github.com/manual/)
