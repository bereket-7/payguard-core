# PayGuard Core

Umbrella repository for the PayGuard platform — a real-time payment fraud detection system that scores every transaction in under 200ms.

All services and supporting repositories are registered here as git submodules. Clone once, get everything.

---

## Repositories

| Submodule | Language | Description |
|---|---|---|
| `payguard-api-gateway` | Java | Spring Cloud Gateway — edge routing, rate limiting, JWT pre-validation |
| `payguard-user-service` | Java | Registration, OAuth2/JWT issuance, merchant profiles, RBAC |
| `payguard-payment-service` | Java | Stripe integration, charges, refunds, webhook processing, outbox publisher |
| `payguard-fraud-engine` | Java | Real-time ONNX model scoring with rules-engine fallback |
| `payguard-notification-service` | Java | Kafka consumer — email/SMS delivery for alerts and reports |
| `payguard-reconciliation-service` | Java | Daily settlement matching and discrepancy detection |
| `payguard-fraud-model-training` | Python | Feature pipeline, XGBoost training, evaluation, ONNX export |
| `payguard-event-schemas` | Avro | Versioned Kafka event contracts shared across all services |
| `payguard-infrastructure` | HCL/YAML | Terraform (AWS EKS, RDS, MSK, ElastiCache, S3) + Kubernetes manifests |

---

## Repository layout

```
payguard-core/
│
├── services/
│   ├── payguard-api-gateway/             ← submodule
│   ├── payguard-user-service/            ← submodule
│   ├── payguard-payment-service/         ← submodule
│   ├── payguard-fraud-engine/            ← submodule
│   ├── payguard-notification-service/    ← submodule
│   ├── payguard-reconciliation-service/  ← submodule
│   ├── payguard-fraud-model-training/    ← submodule
│   ├── payguard-event-schemas/           ← submodule
│   └── payguard-infrastructure/          ← submodule
│
├── .github/
│   ├── workflows/
│   │   ├── submodule-sync-check.yml  # CI: verify all submodule pointers are reachable on remote
│   │   └── bump-submodule.yml        # Manual: bump any single submodule and open a PR
│   ├── CODEOWNERS                    # Ownership assignments per submodule and directory
│   └── pull_request_template.md      # PR checklist applied to every PR
│
├── docs/
│   ├── adr/                          # Architecture Decision Records (MADR format)
│   │   ├── README.md                 # Index + template
│   │   ├── ADR-001-polyrepo-with-submodules.md
│   │   ├── ADR-002-python-trains-java-serves.md
│   │   └── ADR-003-sync-payment-to-fraud-engine.md
│   ├── plans/                        # Per-service implementation plans
│   │   ├── README.md                 # Index + template + cross-cutting gaps
│   │   └── payguard-<service>.md     # One plan per submodule
│   ├── runbooks/                     # Operational runbooks
│   │   ├── README.md                 # Index + template
│   │   ├── fraud-engine-degraded.md
│   │   └── kafka-consumer-lag.md
│   └── PayGuard-Architecture.html    # Interactive architecture documentation
│
├── local-dev/
│   ├── docker-compose.yml            # Full local infrastructure stack
│   └── .env.example                  # Environment variable reference for all services
│
├── scripts/
│   ├── bootstrap.sh                  # First-time setup: init submodules, verify branches
│   ├── update-all.sh                 # Pull latest from all (or one) submodule(s)
│   ├── status.sh                     # Health dashboard: branch / sync / dirty / pointer state
│   └── local-dev.sh                  # docker-compose wrapper: up / down / logs / reset
│
├── .editorconfig                     # Consistent formatting across Java, Python, YAML, HCL
├── .gitignore                        # OS, IDE, secrets, build artefacts, Terraform state
├── .gitmodules                       # Submodule registry
├── CONTRIBUTING.md                   # Branching, commits, PR process, code style, workflows
└── README.md                         # This file
```

---

## Getting started

### Prerequisites

| Tool | Version |
|---|---|
| Git | ≥ 2.40 |
| Docker + Docker Compose | ≥ 25 / v2 |
| Java (JDK) | 17 LTS |
| Maven | ≥ 3.9 |
| Python | ≥ 3.11 (ML pipeline only) |

### Clone and initialise

```bash
# Recommended: clone with all submodules in one step
git clone --recurse-submodules git@github.com:bereket-7/payguard-core.git
cd payguard-core

# If you already cloned without --recurse-submodules
./scripts/bootstrap.sh

# In CI or environments without SSH keys, rewrite remotes to HTTPS
./scripts/bootstrap.sh --https
```

---

## Common tasks

### Check the state of all submodules

```bash
./scripts/status.sh           # detailed per-submodule report
./scripts/status.sh --short   # compact one-line-per-submodule summary
```

### Pull the latest from all submodules

```bash
./scripts/update-all.sh                        # update everything
./scripts/update-all.sh payguard-fraud-engine  # update one service
```

### Start the local infrastructure stack

```bash
./scripts/local-dev.sh up       # start Postgres ×5, Redis, Kafka, Schema Registry, Kafka UI
./scripts/local-dev.sh down     # stop all containers
./scripts/local-dev.sh logs     # tail all logs
./scripts/local-dev.sh reset    # wipe all volumes (destructive)
```

Default local application ports:

| Service | Host |
|---|---|
| API Gateway | http://localhost:8090 |
| User Service | http://localhost:8086 |
| Payment Service | http://localhost:8082 |
| Fraud Engine | http://localhost:8083 |
| Notification Service | http://localhost:8084 |
| Reconciliation Service | http://localhost:8085 |

Local service endpoints after `up`:

| Service | Host |
|---|---|
| Kafka UI | http://localhost:8080 |
| Schema Registry | http://localhost:8081 |
| Kafka broker | localhost:9092 |
| Redis | localhost:6379 |
| Postgres — user-service | localhost:5433 |
| Postgres — payment-service | localhost:5434 |
| Postgres — fraud-engine | localhost:5435 |
| Postgres — notification | localhost:5436 |
| Postgres — reconciliation | localhost:5437 |

### Work on a service

```bash
cd payguard-fraud-engine
git checkout -b feature/my-change
# ... develop, test, commit ...
git push origin feature/my-change
# Open a PR in the payguard-fraud-engine repo
```

### Bump a submodule pointer after a merge

```bash
# Manual
git submodule update --remote services/payguard-fraud-engine
git add services/payguard-fraud-engine
git commit -m "chore(deps): bump payguard-fraud-engine to <sha>"
git push

# Automated — trigger 'Bump submodule' from the GitHub Actions tab
```

---

## CI / GitHub Actions

| Workflow | Trigger | What it does |
|---|---|---|
| `submodule-sync-check` | push / PR to `main` | Verifies every submodule commit is reachable on its remote |
| `bump-submodule` | `workflow_dispatch` | Bumps one submodule to latest `main` and opens a PR |

---

## Documentation

| Resource | Location |
|---|---|
| Architecture documentation | [`docs/PayGuard-Architecture.html`](docs/PayGuard-Architecture.html) |
| Service implementation plans | [`docs/plans/`](docs/plans/README.md) |
| **Gap remediation plan** | [`docs/plans/gap-remediation-plan.md`](docs/plans/gap-remediation-plan.md) |
| Architecture Decision Records | [`docs/adr/`](docs/adr/README.md) |
| Ops runbooks | [`docs/runbooks/`](docs/runbooks/README.md) |
| Contributing guide | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Local env var reference | [`local-dev/.env.example`](local-dev/.env.example) |

### Verification

| Check | Command |
|---|---|
| Submodule health | `./scripts/status.sh` |
| Local infrastructure | `./scripts/local-dev.sh up` |
| ML feature contract | `./scripts/verify-ml-contract.sh` |
| End-to-end smoke (services running) | `./scripts/e2e-smoke.sh` |
| Full platform CI (GitHub Actions) | `.github/workflows/platform-ci.yml` |

---

## Architecture overview

```
Client
  │  HTTPS
  ▼
API Gateway ──────────────────────────────────────────────────────────────────┐
  │  route                                                                     │
  ├──► User Service        (Postgres)                                          │
  │                                                                            │
  └──► Payment Service     (Postgres) ──sync REST 200ms──► Fraud Engine        │
              │                                            (Postgres + Redis)  │
              │  Kafka (outbox)                                 │ Kafka         │
              ▼                                                 ▼              │
         ─────────────────── Kafka event bus ──────────────────────────────   │
              │                                                 │              │
              ▼                                                 ▼              │
     Reconciliation Service (Postgres)           Notification Service (Postgres)
```

Key design principles:
- **Database per service** — no shared schemas, no cross-service joins
- **Sync only on the critical path** — Payment → Fraud Engine is the single synchronous dependency; everything else is async over Kafka
- **Python trains, Java serves** — XGBoost model trained offline, exported to ONNX, served in-process by the JVM via ONNX Runtime
- **Card data never lands here** — Stripe.js tokenises on the client; PayGuard only sees Stripe tokens and charge IDs

See [`docs/adr/`](docs/adr/README.md) for the decisions behind these choices.
