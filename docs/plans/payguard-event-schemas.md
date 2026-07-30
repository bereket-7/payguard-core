# Implementation Plan: payguard-event-schemas

**Owner:** @bereket-7
**Status:** Draft
**Last updated:** 2026-07-29
**Repo:** github.com/bereket-7/payguard-event-schemas
**Depends on:** nothing — this is the root of the dependency graph

---

## 1. Purpose and boundaries

**Owns:** the wire format of every event crossing the Kafka boundary. Avro schema files, their compatibility guarantees, their version history, and the published Java artifact that producers and consumers compile against.

**Does not own:** topic creation (local stack does that in [`docker-compose.yml`](../../local-dev/docker-compose.yml), production does it in `payguard-infrastructure`), partition counts, retention, or ACLs. It also does not own DTOs used *inside* a service — only the shared contract.

This repo is deliberately the smallest and most stable in the platform. A change here can break five services at once, so it is the one place where backward compatibility is enforced mechanically rather than by review.

---

## 2. Current state

Four schemas exist, each a single-line JSON file:

- `schemas/payment/payment-created.avsc` — `PaymentCreated`: `event_id`, `transaction_id`, `merchant_id`, `amount_minor`, `currency`, `occurred_at`
- `schemas/payment/payment-completed.avsc` — `PaymentCompleted`: `event_id`, `transaction_id`, `merchant_id`, `stripe_charge_id`, `occurred_at`
- `schemas/fraud/fraud-alert.avsc` — `FraudAlert`: `event_id`, `transaction_id`, `merchant_id`, `score`, `decision`, `reasons` (array of string), `occurred_at`
- `schemas/reconciliation/reconciliation-completed.avsc` — `ReconciliationCompleted`: `event_id`, `settlement_id`, `merchant_id`, `match_status`, `discrepancy_count`, `occurred_at`

Gaps:

- **`payment.failed` has no schema.** The topic is created by `kafka-init` with 3 partitions and is documented in the architecture doc as carrying `transaction_id` and a failure reason, but no `.avsc` exists.
- **No build.** There is no `pom.xml`, so services cannot depend on this repo. Every consumer would have to hand-write matching Java classes, which defeats the purpose of a shared contract library.
- **No compatibility enforcement.** Nothing prevents a field being removed or renamed.
- **Timestamps are strings.** `occurred_at` is `string` everywhere rather than Avro's `timestamp-millis` logical type.
- **No `merchant_id` on the record used as partition key.** It is present, which is correct — the architecture doc requires `merchant_id` as the Kafka partition key for tenant isolation. Worth asserting in a test so it is never dropped.

---

## 3. Target design

```
payguard-event-schemas/
├── pom.xml                          # avro-maven-plugin → generated Java sources
├── schemas/
│   ├── payment/
│   │   ├── payment-created.avsc
│   │   ├── payment-completed.avsc
│   │   └── payment-failed.avsc      # NEW
│   ├── fraud/
│   │   └── fraud-alert.avsc
│   └── reconciliation/
│       └── reconciliation-completed.avsc
├── src/test/java/com/payguard/events/
│   ├── SchemaParsesTest.java        # every .avsc is valid Avro
│   ├── CompatibilityTest.java       # new schema is backward-compatible with released version
│   └── PartitionKeyTest.java        # every record carries merchant_id
└── .github/workflows/ci.yml
```

The artifact publishes as `com.payguard:event-schemas:<version>` to GitHub Packages. Services add it as a normal Maven dependency and use the generated `SpecificRecord` classes with `KafkaAvroSerializer`.

Compatibility mode is **BACKWARD** on every subject: consumers can be upgraded after producers, which matches the deploy independence this platform is built around.

---

## 4. Milestones

### M1 — Buildable artifact and the missing schema

Branch: `feat/schemas-maven-artifact`

- Add `pom.xml`: `com.payguard:event-schemas:0.1.0-SNAPSHOT`, Java 17, `avro-maven-plugin` generating from `schemas/**` into `target/generated-sources`.
- Add `schemas/payment/payment-failed.avsc` — `PaymentFailed`: `event_id`, `transaction_id`, `merchant_id`, `failure_code`, `failure_message`, `occurred_at`.
- Reformat all `.avsc` files to 2-space indented multi-line JSON per [`.editorconfig`](../../.editorconfig). Single-line JSON is unreviewable in a diff, which matters most in the one repo where every change is a breaking-change risk.
- Add `.github/workflows/ci.yml`: `mvn verify` on PR.
- Add `SchemaParsesTest` asserting every file under `schemas/` parses via `new Schema.Parser()`.

**DoD:** `mvn verify` passes; the jar contains generated classes for all five records; CI runs on PR.

### M2 — Compatibility enforcement

Branch: `feat/schemas-compatibility-check`

- Add `PartitionKeyTest`: every record has a `merchant_id` field of type `string`.
- Add a Schema Registry compatibility job to CI using the `kafka-schema-registry-maven-plugin` `test-compatibility` goal against a registry started as a service container.
- Document the subject naming strategy (`<topic>-value`) and BACKWARD mode in the README.

**DoD:** removing a field from any schema fails CI.

### M3 — Publish and consume

Branch: `feat/schemas-publish-github-packages`

- Add `distributionManagement` for GitHub Packages and a release workflow triggered on tag `v*`.
- Tag `v0.1.0`.
- Update this repo's README with the dependency snippet services should copy.

**DoD:** `payguard-fraud-engine` can resolve `com.payguard:event-schemas:0.1.0` from a clean `~/.m2`.

### M4 — Logical types and enums

Branch: `refactor/schemas-logical-types`

Deferred deliberately until at least one producer and one consumer are live, so the migration is exercised end to end rather than theorised.

- `occurred_at` becomes `{"type":"long","logicalType":"timestamp-millis"}`.
- `decision` becomes an enum: `APPROVE`, `REVIEW`, `BLOCK`.
- `match_status` becomes an enum: `MATCHED`, `PARTIAL`, `UNMATCHED`.

Both are breaking changes, so they ship as `v2` subjects with a documented dual-publish window.

**DoD:** ADR written for the migration; both versions readable during the window.

---

## 5. Interfaces and contracts

Schema-to-topic mapping (topics as created in `local-dev/docker-compose.yml`):

- `payment.created` → `PaymentCreated` — producer: payment-service; consumers: reconciliation, notification
- `payment.completed` → `PaymentCompleted` — producer: payment-service; consumers: reconciliation, notification
- `payment.failed` → `PaymentFailed` — producer: payment-service; consumer: notification
- `fraud.alert.high` → `FraudAlert` — producer: fraud-engine; consumer: notification
- `fraud.alert.medium` → `FraudAlert` — producer: fraud-engine; consumer: notification
- `reconciliation.completed` → `ReconciliationCompleted` — producer: reconciliation; consumer: notification

`fraud.alert.high` and `fraud.alert.medium` intentionally share one record type. Severity is the topic, not a field, so a consumer can subscribe to only high-severity alerts without filtering.

Every record carries `event_id` (a UUID) so consumers can deduplicate under at-least-once delivery, and `merchant_id`, which is the partition key.

---

## 6. Data model and migrations

No database. "Migration" here means schema evolution: additive changes only (new field with a default), enforced by the M2 compatibility job. Removals and renames require a new major subject version and an ADR.

---

## 7. Configuration

No runtime configuration — this is a library. Consumers configure:

- `SPRING_KAFKA_PROPERTIES_SCHEMA_REGISTRY_URL=http://localhost:8081` (from [`local-dev/.env.example`](../../local-dev/.env.example))

Note that Schema Registry occupies port 8081 locally, which collides with User Service's configured port. See the [cross-cutting gaps](README.md#local-port-collisions).

---

## 8. Testing strategy

- **Unit:** schema parse test, partition-key test. No mocking needed — these are pure assertions over files.
- **Compatibility:** `test-compatibility` against a real Schema Registry service container in CI.
- **Contract:** each consuming service adds a Testcontainers test that round-trips a record through Kafka using the published artifact. Those live in the consuming repos, not here.

---

## 9. Observability and SLOs

Not a runtime component. The one operational signal that matters is serialization failure in a consumer, which surfaces as a poison message — the exact scenario in [`docs/runbooks/kafka-consumer-lag.md`](../runbooks/kafka-consumer-lag.md) Scenario D. Keeping compatibility enforced in CI is what prevents that runbook from being needed.

---

## 10. Security

- No secrets, no PII. `merchant_id` and `transaction_id` are internal identifiers.
- **No card data may ever be added to a schema.** Only Stripe tokens and charge IDs cross this boundary, per the PCI boundary in the architecture doc. A reviewer rejecting a field named anything like `card_number` or `pan` is the control here; consider adding a CI grep for a denylist of field names.
- Artifact publishing uses `GITHUB_TOKEN` scoped to packages.

---

## 11. Risks and open questions

- **Avro versus JSON Schema.** The repo README says "Avro contracts" and the architecture doc says "Avro/JSON schemas". Avro is assumed. If JSON Schema is wanted for external webhook payloads, that is a separate concern from the internal bus and should not change this library.
- **Registry availability in production.** If Schema Registry is unavailable, producers using `KafkaAvroSerializer` fail to serialize. MSK does not include a registry, so `payguard-infrastructure` must provision one (AWS Glue Schema Registry or self-hosted Confluent). Flagged in the [infrastructure plan](payguard-infrastructure.md).
- **Should severity be a field after all?** If a third severity is added later, three topics may be worse than one topic plus filtering. Revisit only with evidence.

---

## 12. Definition of done

- Five schemas, all valid, all 2-space formatted, all carrying `event_id` and `merchant_id`.
- `com.payguard:event-schemas` published and resolvable; at least two services consuming it.
- CI fails on a backward-incompatible change.
- README documents the dependency snippet, subject naming, and compatibility mode.
