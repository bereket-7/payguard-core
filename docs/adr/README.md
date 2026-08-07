# Architecture Decision Records

This directory captures significant architectural decisions made for the PayGuard platform. Each ADR is a lightweight, timestamped record of the context, options considered, and the choice made — so future engineers understand *why* the system is shaped the way it is, not just *how* it works.

## Format

Every ADR follows the [MADR](https://adr.github.io/madr/) template:
- **Status** — Proposed / Accepted / Superseded / Deprecated
- **Context** — The problem or constraint that forced a decision
- **Decision** — What was chosen and why
- **Consequences** — Trade-offs accepted by making this choice

## Index

| ID | Title | Status | Date |
|---|---|---|---|
| [ADR-001](ADR-001-polyrepo-with-submodules.md) | Polyrepo with git submodules as umbrella | Accepted | 2026-07-29 |
| [ADR-002](ADR-002-python-trains-java-serves.md) | Python trains, Java serves via ONNX | Accepted | 2026-07-29 |
| [ADR-003](ADR-003-sync-payment-to-fraud-engine.md) | Synchronous Payment → Fraud Engine call | Accepted | 2026-07-29 |
| [ADR-004](ADR-004-polling-outbox-relay.md) | Polling outbox relay in payment-service | Accepted | 2026-08-01 |

## Adding a new ADR

1. Copy the template below into a new file: `ADR-NNN-short-title.md`
2. Fill in all sections
3. Add a row to the index above
4. Open a PR — ADRs are reviewed like code changes

```
# ADR-NNN: Title

**Status:** Proposed
**Date:** YYYY-MM-DD
**Author(s):** @handle

## Context
<!-- What is the problem, constraint, or architectural force? -->

## Options considered
<!-- List the realistic alternatives with their trade-offs -->

## Decision
<!-- What was chosen and the primary reason -->

## Consequences
<!-- Positive and negative outcomes accepted by this choice -->
```
