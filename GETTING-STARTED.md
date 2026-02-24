# AEEF CLI — Getting Started (Install + Apply Hooks)

This is the fastest path to apply the AEEF reference wrapper to an existing Git repository.

## 1. Install the wrapper from Git

```bash
git clone https://github.com/BalrogEG/aeef-cli.git
cd aeef-cli
bash install.sh
```

## 2. Verify prerequisites and target repository

```bash
aeef doctor --project /path/to/your-repo
```

What `aeef doctor` checks:
- `git`, `claude`, `jq` (required)
- `gh` (optional, but required for automatic PR creation)
- Target path is a Git repository
- Whether AEEF hooks are already installed (`.claude/hooks/`)

## 3. Apply hooks, contracts, and skills to the repo (bootstrap)

```bash
aeef bootstrap --project /path/to/your-repo --role product
```

This copies the role profile into your project:
- `.claude/CLAUDE.md`
- `.claude/settings.json`
- `.claude/rules/contract.md`
- `.claude/skills/*`
- `.claude/hooks/*`
- `.aeef/.gitignore`

Optional flags:
- `--with-branches`: create/sync the AEEF role branch workflow during bootstrap
- `--commit`: commit wrapper files immediately

Example:

```bash
aeef bootstrap --project /path/to/your-repo --role product --with-branches --commit
```

## 4. Run the first role

```bash
aeef --role product --project /path/to/your-repo
```

## 5. Continue the branch-per-role workflow

```bash
aeef --role architect --project /path/to/your-repo
aeef --role developer --project /path/to/your-repo
aeef --role qc --project /path/to/your-repo
```

## What gets enforced automatically

- Tool restrictions per role (via Claude Code `--allowedTools` / `--disallowedTools`)
- Hook-based policy enforcement (`PreToolUse`, `UserPromptSubmit`, `Stop`)
- Handoff artifacts in `.aeef/handoffs/`
- Audit logs in `.aeef/runs/`
- PR-based handoff to the next branch (if `gh` is installed)

## Common first-time issues

### `Backend command not found: claude`
Install Claude Code CLI and authenticate, then rerun `aeef doctor`.

### `Not a git repository`
Run `git init` (or clone the target repo) before `aeef bootstrap`.

### PR creation skipped
Install GitHub CLI (`gh`) and run `gh auth login`.
