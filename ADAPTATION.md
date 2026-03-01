# AEEF CLI Adaptation Guide (MCP Required, A2A Progressive)

This repository is the runtime wrapper for AEEF role-based orchestration.

## Interoperability policy

- MCP required for tool-facing integrations in new orchestration adapters.
- A2A progressive for cross-runtime and cross-vendor agent workflows.

## New schema assets

- `schemas/agent-contract.schema.json`
- `schemas/hook-contract.schema.json`
- `schemas/gate-decision.schema.json`
- `schemas/handoff-artifact.schema.json`
- `schemas/ai-provenance.schema.json`
- `schemas/run-ledger-entry.schema.json`

## Template assets

- `templates/hook-contract.json`
- `templates/gate-decision.json`
- `templates/handoff-artifact.json`
- `templates/provenance-record.json`
- `templates/run-ledger-entry.json`

## Runtime evidence outputs

Hooks write auditable artifacts into `.aeef/runs`:

- `audit.log`
- `run-ledger.jsonl`
- `gate-decision.json`

## Recommended rollout

1. Use built-in 4-role baseline (`product`, `architect`, `developer`, `qc`).
2. Enable schema validation in CI for handoff, gate, provenance, run-ledger artifacts.
3. Add enterprise role packs only after baseline gate stability is proven.
