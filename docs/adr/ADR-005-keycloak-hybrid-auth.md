# ADR-005: Keycloak hybrid authentication

## Status

Accepted

## Context

PayGuard originally issued RS256 JWTs from `payguard-user-service`, including login, refresh, password verification, signing key rotation, and JWKS publication. That design kept the critical path simple for local development but duplicated responsibilities that mature identity platforms already solve: credential storage, brute-force protection, token lifecycle, and signing key management.

The user-service also owns merchant domain data (tiers, notification preferences), user invites, and RBAC — concerns that are not Keycloak's source of truth in our model. Downstream services (API gateway, payment-service, fraud-engine) depend on a stable JWT claim contract: `sub`, `merchant_id`, `merchant_tier`, `roles`, and `scope`.

## Options considered

1. **Keep custom JWT issuance in user-service** — no new infrastructure, but ongoing security maintenance (rotation runbooks, password hashing, refresh token families) stays in application code.
2. **Replace user-service entirely with Keycloak** — Keycloak does not model PayGuard merchant records or internal notification preference APIs; would require custom SPIs or a parallel domain service anyway.
3. **Hybrid: Keycloak for auth, user-service for domain** — Keycloak handles login, refresh, and JWT signing; user-service orchestrates registration/invites and syncs attributes to Keycloak via the Admin API.

## Decision

Adopt **option 3 (hybrid)**:

- Keycloak is the OIDC identity provider and JWT issuer for all user-facing authentication.
- `payguard-user-service` remains the source of truth for merchants and app users in Postgres, provisioning Keycloak users on register/invite/role change.
- Keycloak protocol mappers emit the existing claim contract so gateway and resource servers require no Java changes beyond JWKS/issuer configuration.
- Service-to-service `X-PayGuard-Internal-Token` remains unchanged (out of scope for this ADR).

## Consequences

**Positive**

- Login, refresh, logout, and password reset move to a battle-tested IdP.
- JWKS and signing key rotation are Keycloak's responsibility; user-service drops `JwtKeyService`, `TokenService`, and rotation endpoints.
- MFA and social login can be enabled in Keycloak later without PayGuard code changes.

**Negative**

- Keycloak becomes a critical dependency; login fails when it is unavailable (existing tokens remain valid until expiry).
- Registration and invite flows require dual writes (Postgres + Keycloak Admin API); partial failures need operational handling.
- Claim values (`merchant_id`, `merchant_tier`, `scope`) must stay in sync with DB on every write — enforced by provisioning code and integration tests.

## References

- [Hybrid Keycloak plan](../plans/gap-remediation-plan.md)
- [payguard-user-service plan](../plans/payguard-user-service.md)
