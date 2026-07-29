# ADR-001: Polyrepo with git submodules as umbrella

**Status:** Accepted
**Date:** 2026-07-29
**Author(s):** @bereket-7

## Context

PayGuard is composed of six independently deployable services, a shared event-schema library, a Python training pipeline, and an infrastructure repo. We needed to decide how to organise source control:

- Should all services live in a single monorepo?
- Should each service live in its own repo with no umbrella?
- Should each service live in its own repo with a thin umbrella that ties them together?

Key forces:
- Services deploy on independent schedules; a monorepo build system would add coordination overhead.
- Teams (or future teams) own individual services and need clean blast-radius isolation.
- Developers still want a single `git clone` to get everything and a single place to run the local stack.
- CI pipelines should be per-service so a Python ML change doesn't re-test every Java service.

## Options considered

### Option A — Monorepo
Single repository containing all services as top-level directories.

- ✅ One clone, easy cross-service refactoring, unified CI tooling (e.g. Nx, Bazel)
- ❌ Every service's CI runs on every PR regardless of what changed (unless smart change detection is added)
- ❌ All services share the same git history, making `git blame` noisy across domains
- ❌ Requires build tooling investment (Nx/Gradle multi-project/Bazel) to stay fast at scale

### Option B — Pure polyrepo (no umbrella)
Each service in its own repo, no shared parent.

- ✅ Maximum independence; each team manages their own repo lifecycle
- ❌ No single place to run the full local stack or see cross-service status
- ❌ Cross-service changes require coordinating multiple PRs with no atomic grouping
- ❌ Onboarding requires cloning 9+ repos manually

### Option C — Polyrepo + git submodule umbrella (chosen)
Each service in its own repo; `payguard-core` is a thin umbrella that registers all repos as submodules.

- ✅ Each service retains an independent CI pipeline, deploy cadence, and ownership boundary
- ✅ One `git clone --recurse-submodules` gets the entire platform
- ✅ Umbrella hosts shared tooling: local dev stack, scripts, docs, CODEOWNERS
- ✅ Submodule pointers provide an explicit, auditable snapshot of which version of every service was in production together
- ❌ Developers must understand the submodule pointer model (HEAD vs. recorded SHA)
- ❌ Cross-service changes still require separate PRs; submodule bump PR is an extra step

## Decision

**Option C** — polyrepo with a git submodule umbrella (`payguard-core`).

The independent deploy cadence and ownership isolation outweigh the ergonomic cost of the submodule pointer model. The umbrella eliminates the biggest pain point of a pure polyrepo (onboarding, local dev setup) without collapsing service boundaries.

## Consequences

- All new services must have their own GitHub repository under the `bereket-7` org before they can be added to `payguard-core`.
- Every merged change to a service that needs to be reflected in the umbrella requires a submodule bump PR. The `bump-submodule` GitHub Actions workflow automates this.
- Developers cloning `payguard-core` with plain `git clone` (no `--recurse-submodules`) will get empty submodule directories — the bootstrap script handles this case.
- The shared `local-dev/docker-compose.yml` in this umbrella is the single source of truth for local infrastructure configuration.
