# Runbooks

Operational runbooks for the PayGuard platform. Each runbook covers a specific incident type or operational task — what to check first, how to diagnose, and how to resolve.

## Index

| Runbook | Covers |
|---|---|
| [fraud-engine-degraded.md](fraud-engine-degraded.md) | Fraud Engine slow / circuit breaker open |
| [kafka-consumer-lag.md](kafka-consumer-lag.md) | Kafka consumer group falling behind |

## Adding a runbook

Copy the template below, name the file `<short-kebab-description>.md`, and add a row to the index.

```markdown
# Runbook: <Title>

**Service(s):** ...
**Alert / Symptom:** ...
**Severity:** P1 / P2 / P3

## Quick triage (first 2 minutes)
1. ...

## Diagnosis
...

## Resolution steps
...

## Escalation
...

## Post-incident
...
```
