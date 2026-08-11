# Keycloak degraded mode

## Symptoms

- Users cannot log in or refresh tokens (`401` / `503` from Keycloak token endpoint).
- New registrations fail at user-service with Keycloak provisioning errors.
- Existing API calls with **valid, unexpired** JWTs continue to work — gateway and resource servers validate locally via cached JWKS.

## Impact

| Flow | Behaviour |
|---|---|
| Login / refresh | **Blocked** — Keycloak is the only token issuer |
| Register / invite | **Blocked** — dual-write to Keycloak fails |
| Authenticated API calls | **Works** until access token expiry (default 5–60 min depending on realm settings) |
| Internal `/internal/**` hops | **Unaffected** — uses `X-PayGuard-Internal-Token`, not OIDC |

## Immediate actions

1. Check Keycloak health: `curl -sf http://<keycloak>/health/ready`
2. Check Keycloak Postgres (if external): connection count, disk, replication lag.
3. Review Keycloak pod logs: `kubectl logs -l app=keycloak --tail=200`
4. Confirm JWKS still reachable: `curl -sf http://<keycloak>/realms/payguard/protocol/openid-connect/certs`

## Mitigation

- **Scale Keycloak replicas** if CPU/memory bound (K8s: increase `replicas` in `k8s/base/keycloak/deployment.yml`).
- **Restart unhealthy pods** after confirming Postgres is healthy.
- Communicate to merchants: existing sessions remain valid until token expiry; new logins unavailable.

## Recovery verification

1. Obtain a token: `POST /realms/payguard/protocol/openid-connect/token` (password or refresh grant).
2. Run `./scripts/e2e-smoke.sh` against the affected environment.
3. Confirm registration: `POST /v1/merchants/register` returns `201`.

## Prevention

- Monitor Keycloak `/health/ready` and `/metrics` (Prometheus).
- Run Keycloak with dedicated Postgres (separate from app RDS).
- Keep realm export (`local-dev/keycloak/payguard-realm.json`) in sync with production protocol mappers — claim drift breaks payment RBAC silently.

## References

- [ADR-005](../adr/ADR-005-keycloak-hybrid-auth.md)
- [local-dev Keycloak stack](../../local-dev/docker-compose.yml)
