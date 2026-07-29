# Contributing to PayGuard

Thank you for taking the time to contribute. This document covers how to work across the PayGuard codebase from the `payguard-core` umbrella repo.

---

## Table of contents

1. [Repo model](#repo-model)
2. [First-time setup](#first-time-setup)
3. [Day-to-day workflow](#day-to-day-workflow)
4. [Branching strategy](#branching-strategy)
5. [Commit conventions](#commit-conventions)
6. [Pull request process](#pull-request-process)
7. [Code style](#code-style)
8. [Working with the local dev stack](#working-with-the-local-dev-stack)
9. [Adding a new service](#adding-a-new-service)
10. [Architecture decisions (ADRs)](#architecture-decisions-adrs)

---

## Repo model

PayGuard is a **polyrepo** — each service lives in its own GitHub repository. `payguard-core` is a thin umbrella that registers all of them as git submodules and hosts shared tooling, docs, and the local dev stack.

```
payguard-core/                    ← you are here (umbrella)
├── services/
│   ├── payguard-api-gateway/         ← submodule → github.com/bereket-7/payguard-api-gateway
│   ├── payguard-user-service/        ← submodule
│   ├── payguard-payment-service/     ← submodule
│   ├── payguard-fraud-engine/        ← submodule
│   ├── payguard-notification-service/← submodule
│   ├── payguard-reconciliation-service/← submodule
│   ├── payguard-fraud-model-training/← submodule
│   ├── payguard-event-schemas/       ← submodule
│   └── payguard-infrastructure/      ← submodule
```

**The golden rule:** changes to service code are committed and PR'd inside the submodule repo. Changes to umbrella tooling (scripts, docs, local-dev, CI) are committed here.

---

## First-time setup

### Prerequisites

| Tool | Version | Required for |
|---|---|---|
| Git | ≥ 2.40 | submodule operations |
| Docker + Docker Compose | ≥ 25 / v2 | local dev stack |
| Java (JDK) | 17 LTS | Java services |
| Maven | ≥ 3.9 | Java builds |
| Python | ≥ 3.11 | ML training pipeline |

### Clone and initialise

```bash
# SSH (recommended)
git clone --recurse-submodules git@github.com:bereket-7/payguard-core.git
cd payguard-core

# Or run the bootstrap script after a plain clone
./scripts/bootstrap.sh

# In a CI environment without SSH keys, rewrite remotes to HTTPS
./scripts/bootstrap.sh --https
```

---

## Day-to-day workflow

### Check the health of all submodules

```bash
./scripts/status.sh           # detailed view
./scripts/status.sh --short   # one-line-per-submodule summary
```

### Pull the latest from every submodule

```bash
./scripts/update-all.sh                        # update all
./scripts/update-all.sh payguard-fraud-engine  # update one
```

### Work on a specific service

```bash
cd services/payguard-fraud-engine
git checkout -b feature/my-change
# ... make changes, run tests ...
git push origin feature/my-change
# Open a PR in the payguard-fraud-engine repo
```

After your PR is merged, bump the submodule pointer in this umbrella:

```bash
# Option 1 — manual
cd payguard-core
git submodule update --remote services/payguard-fraud-engine
git add services/payguard-fraud-engine
git commit -m "chore(deps): bump payguard-fraud-engine to <short-sha>"
git push

# Option 2 — automated
# Trigger the 'Bump submodule' GitHub Actions workflow from the Actions tab
```

---

## Branching strategy

We follow **trunk-based development** with short-lived feature branches.

| Branch | Purpose |
|---|---|
| `main` | Always deployable. Protected — no direct pushes. |
| `feature/<ticket>-short-description` | New functionality |
| `fix/<ticket>-short-description` | Bug fixes |
| `chore/<description>` | Tooling, deps, config (no production logic change) |
| `docs/<description>` | Documentation only |

- Branch from `main`, target `main`.
- Keep branches short-lived — merge within a few days or break the work into smaller pieces.
- Delete branches after merging.

---

## Commit conventions

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>

[optional body]

[optional footer: BREAKING CHANGE / Closes #issue]
```

**Types:**

| Type | When to use |
|---|---|
| `feat` | New feature visible to users or consumers |
| `fix` | Bug fix |
| `chore` | Tooling, dependency bumps, config — no logic change |
| `docs` | Documentation only |
| `refactor` | Code restructuring with no behaviour change |
| `test` | Adding or fixing tests |
| `ci` | CI pipeline changes |
| `perf` | Performance improvement |

**Scope** is the service or area: `fraud-engine`, `payment-service`, `local-dev`, `scripts`, `adr`, etc.

**Examples:**

```
feat(fraud-engine): add velocity feature to ONNX scoring pipeline
fix(payment-service): handle Stripe idempotency key collision on retry
chore(deps): bump payguard-fraud-engine to a1b2c3d
docs(adr): add ADR-004 for Redis cache invalidation strategy
ci: add submodule sync check to PR workflow
```

---

## Pull request process

1. **Open the PR in the correct repo** — service changes go to the service repo, umbrella changes go here.
2. **Fill in the PR template** — all sections are required.
3. **Keep PRs small** — aim for < 400 lines changed. Large PRs block review and are harder to revert.
4. **Pass all CI checks** before requesting review.
5. **One approving review required** from a CODEOWNER before merging.
6. **Squash merge** for feature/fix branches to keep `main` history linear. Use the conventional commit format for the squash message.
7. **Submodule bumps** use a regular merge commit (not squash) so the pointer history is visible.

---

## Code style

### Java

- Follow [Google Java Style Guide](https://google.github.io/styleguide/javaguide.html) with 120-character line limit (configured in `.editorconfig`).
- Every public class and method has a Javadoc comment explaining *what* and *why*, not *how*.
- Use constructor injection — no `@Autowired` on fields.
- No `System.out.println` — use SLF4J `log` in all production code.

### Python (ML pipeline)

- Follow [PEP 8](https://peps.python.org/pep-0008/) with 120-character line limit.
- Type-annotate all function signatures.
- Every module has a docstring explaining its purpose and inputs/outputs.
- Pin dependencies in `requirements.txt` with `==` for reproducible training runs.

### YAML / HCL

- 2-space indent (enforced by `.editorconfig`).
- Every Kubernetes resource has `app`, `component`, and `version` labels.
- Terraform resources have a `Name` tag and a `managed-by = "terraform"` tag.

---

## Working with the local dev stack

The `local-dev/docker-compose.yml` starts all infrastructure dependencies (Postgres × 6, Redis, Kafka, Schema Registry, Kafka UI). Services themselves run locally via `mvn spring-boot:run` or your IDE.

```bash
# Start everything
./scripts/local-dev.sh up

# Tail logs for a specific container
./scripts/local-dev.sh logs kafka

# Stop the stack
./scripts/local-dev.sh down

# Wipe all volumes and start fresh (destructive)
./scripts/local-dev.sh reset
```

Copy `local-dev/.env.example` to each service's root as `.env` and fill in the values. The `.env` file is gitignored — never commit it.

Port reference:

| Service | Port |
|---|---|
| Postgres — api-gateway | 5432 |
| Postgres — user-service | 5433 |
| Postgres — payment-service | 5434 |
| Postgres — fraud-engine | 5435 |
| Postgres — notification | 5436 |
| Postgres — reconciliation | 5437 |
| Redis | 6379 |
| Kafka | 9092 |
| Schema Registry | 8081 |
| Kafka UI | http://localhost:8080 |

---

## Adding a new service

1. Create a new GitHub repository under the `bereket-7` org: `payguard-<service-name>`.
2. Add it as a submodule from the `payguard-core` root:
   ```bash
   git submodule add git@github.com:bereket-7/payguard-<service-name>.git services/payguard-<service-name>
   git add .gitmodules services/payguard-<service-name>
   git commit -m "chore: add payguard-<service-name> submodule"
   ```
3. Add the new service to:
   - `.github/CODEOWNERS` — assign an owner
   - `.github/workflows/bump-submodule.yml` — add to the `options` list
   - `local-dev/docker-compose.yml` — add a Postgres service on the next available port
   - `local-dev/.env.example` — document the required env vars
   - `README.md` — add a row to the submodule table
4. Open a PR to `payguard-core` with these changes.

---

## Architecture decisions (ADRs)

Significant decisions are documented in [`docs/adr/`](docs/adr/README.md). If your change introduces a new pattern, picks a new technology, or reverses a previous decision, write an ADR.

An ADR is **required** for:
- Introducing a new runtime or language to the platform
- Changing the communication pattern between services (sync ↔ async)
- Replacing a backing data store
- Any decision that would surprise a new engineer three months from now

Use the template in [`docs/adr/README.md`](docs/adr/README.md) and open the ADR in the same PR as the implementation.
