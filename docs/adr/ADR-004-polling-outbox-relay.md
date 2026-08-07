# ADR-004: Polling outbox relay in payment-service

## Status

Accepted

## Context

The architecture document describes a transactional outbox pattern where payment state changes and Kafka events are written atomically in Postgres, then relayed to Kafka by a separate process. Debezium via Kafka Connect is the named CDC option, but the local development stack has no Kafka Connect deployment, and `payguard-infrastructure` does not yet provision Connect in production.

Payment Service must publish `payment.*` events reliably before downstream consumers (Notification, Reconciliation) can be built and tested. Blocking on Connect infrastructure would delay the entire event-driven path.

## Decision

Implement a **polling relay inside payment-service**:

- A scheduled job selects unpublished rows from the `outbox` table using `FOR UPDATE SKIP LOCKED`, limiting batch size.
- Each row is published to Kafka keyed by `merchant_id`.
- The row is marked `published_at` only after the broker acknowledges the send, in the same database transaction as the lock.
- Multiple replicas are safe because `SKIP LOCKED` prevents two instances from processing the same row.

The outbox table shape (`event_id`, `aggregate_id`, `event_type`, `topic`, `partition_key`, `payload`, `created_at`, `published_at`) is chosen so a future Debezium connector can replace the poller without a schema migration.

## Consequences

**Positive**

- No additional infrastructure beyond Postgres and Kafka already required by the service.
- Local development and CI can exercise the full payment → event path immediately.
- The relay decision is reversible: swapping to Debezium is an operational change, not a data model change.

**Negative**

- Events appear on Kafka after the configured poll interval (default 1s) rather than near-real-time CDC latency.
- Relay logic runs in the application process; a bug in the poller affects the same deployment unit as the API.
- Multi-replica deployments must tune poll interval and batch size to avoid duplicate publish attempts on failure (mitigated by idempotent consumers keyed on `event_id`).

## References

- [payguard-payment-service implementation plan](../plans/payguard-payment-service.md) — M4
- [PayGuard Architecture](../PayGuard-Architecture.html) — transactional outbox section
