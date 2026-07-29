# ADR-003: Synchronous Payment → Fraud Engine call

**Status:** Accepted
**Date:** 2026-07-29
**Author(s):** @bereket-7

## Context

When a payment is initiated, PayGuard must decide — before the Stripe charge is created — whether the transaction is approved, flagged for review, or blocked. This decision must be attached to the same request so the caller receives a definitive response, not a "pending" state.

The question is: should the Payment Service call the Fraud Engine synchronously (blocking), or should it publish an event and wait for an async response?

## Options considered

### Option A — Synchronous REST call (chosen)
Payment Service calls the Fraud Engine over HTTP with a hard timeout (200ms). The decision is returned inline; Payment Service proceeds or aborts based on the result.

- ✅ The client gets a real-time approve/block response in a single request
- ✅ No correlation-ID choreography, no reply-to topic, no polling
- ✅ Simple failure semantics: timeout → fallback rules engine → safe default decision
- ❌ Fraud Engine becomes the single synchronous dependency in an otherwise async system
- ❌ Fraud Engine degradation directly impacts Payment Service latency

### Option B — Async event (publish and subscribe)
Payment Service publishes a `payment.scoring_requested` event; Fraud Engine processes it and publishes back a `fraud.decision` event; Payment Service correlates via a reply channel.

- ✅ Fully decoupled at the network level
- ❌ Adds latency indirection: Kafka round-trip is typically 5–50ms but introduces non-deterministic scheduling lag under load
- ❌ Requires a correlation mechanism (reply-to topic or callback URL), complicating both services
- ❌ The client request must either block waiting for the correlation or return a "pending" status — neither is acceptable for a real-time payment flow

## Decision

**Option A** — synchronous REST call from Payment Service to Fraud Engine, with a 200ms hard timeout and a Resilience4j circuit breaker.

Fraud detection is the one place in the platform where latency is the point. The synchronous model is the right tool: it keeps the client contract simple, the failure path explicit (circuit opens → fallback rules engine → decision), and the audit trail direct (request ID links the payment and fraud records without event correlation).

## Consequences

- The Fraud Engine is the only service that Payment Service calls synchronously. All other inter-service communication is via Kafka.
- The 200ms timeout is a hard SLA. Fraud Engine must return a decision within this window or the fallback `RulesFallbackEngine` takes over. Silent hangs are not acceptable.
- The Payment → Fraud Engine call runs over mTLS inside the EKS cluster.
- A Resilience4j circuit breaker wraps the call in Payment Service. When open, the fallback rules engine provides the decision so payments are never blocked by Fraud Engine unavailability alone.
- Fraud Engine must be horizontally scalable (Kubernetes HPA on CPU/latency) and sit on the critical scaling path alongside Payment Service.
- Distributed tracing (Gateway → Payment → Fraud Engine) must cover this hop to attribute latency to a specific service during incidents.
