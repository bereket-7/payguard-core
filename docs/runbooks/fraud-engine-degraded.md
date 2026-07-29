# Runbook: Fraud Engine degraded / circuit breaker open

**Service(s):** payguard-fraud-engine, payguard-payment-service
**Alert / Symptom:** Fraud Engine p99 latency > 150ms, circuit breaker open, or scoring endpoint returning 5xx
**Severity:** P1 — directly impacts payment authorisation

---

## Quick triage (first 2 minutes)

```bash
# 1. Is the Fraud Engine pod running?
kubectl get pods -n payguard -l app=fraud-engine

# 2. Recent logs
kubectl logs -n payguard -l app=fraud-engine --tail=100

# 3. Check circuit breaker state from Payment Service metrics
curl http://<payment-service>/actuator/metrics/resilience4j.circuitbreaker.state
```

Expected healthy state: `CLOSED`. If `OPEN` or `HALF_OPEN`, the fallback rules engine is active — payments continue but ML scoring is bypassed.

---

## Diagnosis

### Scenario A — ONNX model load failure
**Symptom:** `OrtException` or `model file not found` in Fraud Engine logs.

```bash
# Check which model version is configured
kubectl get configmap fraud-engine-config -n payguard -o yaml | grep MODEL_VERSION

# Check the model exists in S3
aws s3 ls s3://payguard-model-registry/fraud-model/
```

**Resolution:** Roll back to the previous ONNX version by updating the `MODEL_VERSION` env var and redeploying, or redeploy with the last known-good image.

---

### Scenario B — Redis feature cache unavailable
**Symptom:** `RedisConnectionException` or high cache-miss rate in logs; scoring latency spikes because features are fetched from Postgres on every call.

```bash
# Check Redis pod / ElastiCache endpoint health
redis-cli -h <redis-host> -p 6379 PING   # should return PONG

kubectl get pods -n payguard -l app=redis
```

**Resolution:** If local Redis: restart the pod. If ElastiCache: check AWS Console → ElastiCache → Events for failover. The Fraud Engine degrades gracefully (falls back to DB feature lookups) but latency will increase — monitor p99 against the 200ms SLA.

---

### Scenario C — Pod OOMKilled / resource exhaustion
**Symptom:** Pod restarts, `OOMKilled` in `kubectl describe pod`.

```bash
kubectl describe pod -n payguard -l app=fraud-engine | grep -A5 "Last State"
```

**Resolution:** Scale the deployment horizontally while investigating memory leak:

```bash
kubectl scale deployment fraud-engine -n payguard --replicas=<current+2>
```

Open an issue to review ONNX Runtime memory settings and JVM heap configuration.

---

### Scenario D — High inference latency (model regression)
**Symptom:** Latency increased after a model deployment; circuit breaker intermittently opens.

```bash
# Identify model version in use
kubectl get deployment fraud-engine -n payguard -o jsonpath='{.spec.template.spec.containers[0].env}' | jq '.[] | select(.name=="MODEL_VERSION")'
```

**Resolution:** Roll back the model version (update env var, redeploy). Ensure the new model's inference benchmark was validated against the 150ms budget before promotion.

---

## Escalation

| Step | Action |
|---|---|
| > 5 min unresolved | Page on-call platform engineer |
| Circuit breaker open > 10 min | Notify payments team — SLA impact |
| Data loss suspected | Invoke incident commander, preserve logs before any restarts |

---

## Post-incident

- Document root cause in an incident report linked from the relevant GitHub issue
- If a model caused the regression, add an inference latency gate to `evaluate.py` in `payguard-fraud-model-training`
- Review circuit breaker thresholds if false positives occurred
