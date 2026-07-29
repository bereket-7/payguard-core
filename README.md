# PayGuard Core

Umbrella repository for the PayGuard platform. All services and supporting repositories are included as git submodules so you can work across the entire codebase from one place.

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

## Getting started

### Clone with all submodules

```bash
git clone --recurse-submodules git@github.com:bereket-7/payguard-core.git
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

### Update all submodules to their latest remote commits

```bash
git submodule update --remote --merge
```

### Work inside a submodule

Each submodule is a fully independent git repository. Navigate into it and use git normally:

```bash
cd payguard-fraud-engine
git checkout -b feature/my-change
# make changes, commit, push
git push origin feature/my-change
```

### Pull latest changes across all submodules at once

```bash
git pull --recurse-submodules
```

### Record updated submodule pointers in payguard-core

After work is merged in a submodule, update the pointer this repo tracks:

```bash
git submodule update --remote payguard-fraud-engine
git add payguard-fraud-engine
git commit -m "chore: bump payguard-fraud-engine to latest main"
```

## Repository layout

```
payguard-core/
├── payguard-api-gateway/           ← submodule
├── payguard-user-service/          ← submodule
├── payguard-payment-service/       ← submodule
├── payguard-fraud-engine/          ← submodule
├── payguard-notification-service/  ← submodule
├── payguard-reconciliation-service/← submodule
├── payguard-fraud-model-training/  ← submodule
├── payguard-event-schemas/         ← submodule
├── payguard-infrastructure/        ← submodule
└── .gitmodules                     ← submodule registry
```
