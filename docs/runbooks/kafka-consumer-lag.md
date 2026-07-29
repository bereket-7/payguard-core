# Runbook: Kafka consumer group falling behind

**Service(s):** payguard-notification-service, payguard-reconciliation-service, payguard-fraud-engine (alert publisher)
**Alert / Symptom:** Consumer group lag > threshold on any PayGuard topic; delayed fraud alerts or settlement reports
**Severity:** P2 for notification/reconciliation lag; P1 if fraud.alert topics are lagging

---

## Quick triage (first 2 minutes)

```bash
# List all PayGuard consumer groups and their lag
kafka-consumer-groups.sh \
  --bootstrap-server <kafka-host>:9092 \
  --describe \
  --all-groups \
  | grep -E "GROUP|payguard"

# Or, using the Kafka UI: http://localhost:8080 (local) or the deployed instance
# Navigate to: Consumer Groups → select group → inspect per-partition lag
```

Key topics and expected consumer groups:

| Topic | Consumer Group |
|---|---|
| `payment.created` | `reconciliation-service`, `notification-service` |
| `payment.completed` | `reconciliation-service`, `notification-service` |
| `payment.failed` | `notification-service` |
| `fraud.alert.high` | `notification-service` |
| `fraud.alert.medium` | `notification-service` |
| `reconciliation.completed` | `notification-service` |

---

## Diagnosis

### Scenario A — Consumer pod is down or crash-looping

```bash
kubectl get pods -n payguard -l app=<notification-service|reconciliation-service>
kubectl logs -n payguard -l app=<service> --tail=100 --previous
```

**Resolution:** Fix the crash cause (see logs), then the pod will rejoin and reprocess from its last committed offset. Kafka's at-least-once delivery and idempotent consumer design means replaying messages is safe.

---

### Scenario B — Consumer is running but processing too slowly (throughput bottleneck)

```bash
# Check CPU / memory pressure on consumer pods
kubectl top pods -n payguard -l app=notification-service

# Check if DB inserts are the bottleneck (slow query log on pg-notification)
# Connect to the DB and inspect pg_stat_activity:
psql -h localhost -p 5436 -U payguard -d payguard_notifications \
  -c "SELECT pid, state, query_start, query FROM pg_stat_activity WHERE state != 'idle';"
```

**Resolution:** Scale out the consumer deployment. Partition count limits parallelism — if all partitions are already assigned, increasing replicas beyond partition count has no effect:

```bash
# Scale notification-service consumers (max effective = partition count per topic = 3)
kubectl scale deployment notification-service -n payguard --replicas=3
```

If lag is structural (partition count too low), open a ticket to increase topic partition count during a maintenance window.

---

### Scenario C — Producer is flooding the topic (sudden burst)

**Symptom:** Lag appeared suddenly after a high-volume event (batch payment processing, reconciliation run).

**Resolution:** This is expected transient lag. Monitor the consumer group catch-up rate:

```bash
# Watch lag every 5s
watch -n5 "kafka-consumer-groups.sh --bootstrap-server <host>:9092 --describe --group notification-service"
```

If lag is not shrinking, treat as Scenario B.

---

### Scenario D — Poison message (consumer stuck on one offset)

**Symptom:** Lag stuck at exactly N messages; consumer is running but not advancing.

```bash
# Find the stuck partition and offset
kafka-consumer-groups.sh \
  --bootstrap-server <host>:9092 \
  --describe \
  --group notification-service

# Inspect the message at that offset
kafka-console-consumer.sh \
  --bootstrap-server <host>:9092 \
  --topic fraud.alert.high \
  --partition <n> \
  --offset <stuck-offset> \
  --max-messages 1
```

**Resolution:**
1. Inspect and log the poison message payload.
2. Manually skip the offset (advance committed offset past the bad message):
   ```bash
   kafka-consumer-groups.sh \
     --bootstrap-server <host>:9092 \
     --group notification-service \
     --topic fraud.alert.high \
     --reset-offsets --to-offset <stuck-offset+1> \
     --partition <n> --execute
   ```
3. File a bug — the consumer should be sending unprocessable messages to a dead-letter topic, not blocking.

---

## Escalation

| Condition | Action |
|---|---|
| `fraud.alert.high` lag > 1 min | P1 — fraud alerts are delayed; page on-call |
| Reconciliation lag spans a settlement window (> 24h) | Notify finance team |
| Poison message confirmed | Engineering lead + preserve message for analysis |

---

## Post-incident

- If a poison message caused the incident: add a dead-letter queue (DLQ) handler to the affected consumer and add the message format to the test suite
- If throughput was the cause: document the event that triggered the burst and adjust topic partition counts proactively
- Update consumer group lag alerting thresholds if they produced false positives
