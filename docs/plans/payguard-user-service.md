# Implementation Plan: payguard-user-service

**Owner:** @bereket-7
**Status:** Mostly complete
**Last updated:** 2026-08-20
**Repo:** github.com/bereket-7/payguard-user-service
**Depends on:** Keycloak (local stack + [ADR-005](../adr/ADR-005-keycloak-hybrid-auth.md)); every other service depends on the claim contract Keycloak issues for merchants provisioned here

---

## 1. Purpose and boundaries

**Owns:** merchant domain data — merchant records, dashboard user accounts, roles, invites, and internal notification preference APIs. Orchestrates Keycloak user provisioning on register/invite/role change.

**Does not own:** login, refresh, logout, JWT signing, or JWKS (Keycloak per [ADR-005](../adr/ADR-005-keycloak-hybrid-auth.md)). Token validation for other services (each service validates independently), API-level rate limiting (gateway), or any payment or fraud data.

The critical output of this service is not an endpoint — it is a **token format**. Once `merchant_id` and roles are baked into a claim set that five services read, changing it is a coordinated platform migration. So the claim contract deserves more design attention than the CRUD around it.

---

## 2. Current state

*(Surveyed 2026-08-20 against the submodule HEAD.)*

**Implemented (original M1–M5 superseded by Keycloak hybrid auth):**

- Port **8086** (Schema Registry collision on 8081 resolved)
- Domain: `Merchant`, `AppUser` (with Keycloak subject link), `Role`; Flyway V1–V7 including `V6__keycloak_link` and `V7__drop_legacy_auth`
- Controllers: `RegistrationController` (`POST /v1/merchants/register`), `MerchantController`, `UserController`, internal preferences API
- `KeycloakAdminClient` provisions users; `ScopeService` derives scopes from roles
- Auth: OAuth2 resource server validating Keycloak JWKS; `InternalServiceTokenFilter` for `/internal/**`
- Legacy local JWT issuer / JWKS / refresh tokens / signing-key rotation **removed**
- Tests for Keycloak admin client and scopes; CI + multi-stage non-root Dockerfile

**Remaining:**

- Service README may still mention HS256 — keep docs in sync with Keycloak
- Limited controller/API tests; no Testcontainers
- Claim-contract regression tests across gateway + payment still thin

---

## 3. Target design

```
src/main/java/com/payguard/user/
├── UserServiceApplication.java
├── config/
│   ├── SecurityConfig.java          # filter chain, password encoder
│   └── JwtConfig.java               # signing key, issuer, expiry
├── controller/
│   ├── AuthController.java          # /v1/auth/**
│   ├── MerchantController.java      # /v1/merchants/**
│   └── UserController.java          # /v1/users/**
├── service/
│   ├── AuthService.java
│   ├── TokenService.java            # issue, refresh, revoke
│   ├── MerchantService.java
│   └── UserService.java
├── domain/
│   ├── Merchant.java
│   ├── User.java
│   ├── Role.java                    # enum
│   └── RefreshToken.java
└── repository/
    ├── MerchantRepository.java
    ├── UserRepository.java
    └── RefreshTokenRepository.java
```

Token claim contract — the platform-wide interface:

```json
{
  "iss": "https://auth.payguard.io",
  "sub": "usr_01H...",
  "merchant_id": "mer_123",
  "roles": ["MERCHANT_ADMIN"],
  "scope": "payments:read payments:write",
  "iat": 1750000000,
  "exp": 1750003600
}
```

`merchant_id` is the tenancy anchor. Every service filters queries by it, so it is mandatory in every token except platform-admin tokens, which carry an explicit `PLATFORM_ADMIN` role instead.

Roles: `MERCHANT_ADMIN` (full merchant access, refunds, review decisions), `MERCHANT_ANALYST` (read-only plus reports), `PLATFORM_ADMIN` (cross-merchant support).

---

## 4. Milestones

### M1 — Foundation and port fix

Branch: `feat/user-service-foundation`

- Set `server.port: 8086` and document the change in the README, `local-dev/.env.example`, and the umbrella `README.md` port table.
- Add `spring-boot-starter-data-jpa`, `postgresql`, `flyway-core`, `spring-boot-starter-security`, `spring-boot-starter-validation`, `micrometer-registry-prometheus`.
- `Merchant`, `User`, `Role` entities; Flyway `V1__merchant_user.sql` with a unique index on `user.email` and a foreign key from user to merchant.
- BCrypt password encoder.
- Multi-stage Dockerfile, non-root user, `.github/workflows/ci.yml`.

**DoD:** service starts alongside the full local stack with no port collision; schema migrates cleanly.

### M2 — Registration and login

Branch: `feat/user-service-auth`

- `POST /v1/auth/register` creating a merchant plus its first `MERCHANT_ADMIN` user.
- `POST /v1/auth/login` returning an access token and a refresh token.
- Validation: email format, password policy, duplicate email returning 409.
- **Uniform failure response.** A wrong password and an unknown email must be indistinguishable in body, status, and timing, or the endpoint becomes an account-enumeration oracle.

**DoD:** register-then-login returns a usable token pair; enumeration test passes.

### M3 — Token issuance and validation contract

Branch: `feat/user-service-jwt-issuance`

- Add `spring-boot-starter-oauth2-resource-server` (and `nimbus-jose-jwt` transitively).
- `TokenService` issuing HS256 tokens from `JWT_SECRET` with `JWT_EXPIRY_SECONDS`, populating the claim set above.
- Refresh token rotation: single use, persisted hashed, revoked on use, with reuse detection invalidating the family.
- `POST /v1/auth/refresh`, `POST /v1/auth/logout`.
- **Publish the validation snippet** in the README so all five consuming services validate identically. Divergent validation is how a revoked-but-accepted token happens.

**DoD:** a token issued here validates in a second Spring Boot service configured only from the README; refresh rotation and reuse detection are tested.

### M4 — RBAC and merchant management

Branch: `feat/user-service-rbac`

- `@PreAuthorize` on every endpoint — no endpoint left implicitly open.
- `GET`/`PATCH /v1/merchants/{id}`, scoped so a merchant can only read itself; `PLATFORM_ADMIN` may read any.
- `POST /v1/users` to invite additional users to a merchant; `PATCH /v1/users/{id}/role`.
- Merchant tier field, since the gateway's rate limiting is tier-based.
- Notification preferences (email, SMS, both) live on the merchant — Notification Service needs them and this is the identity owner. Expose `GET /internal/v1/merchants/{id}/notification-preferences`.

**DoD:** a `MERCHANT_ANALYST` token is rejected on every write endpoint; cross-merchant reads return 404, not 403, to avoid confirming existence.

### M5 — Key rotation and hardening

Branch: `feat/user-service-key-rotation`

- Move from a shared HS256 secret to **RS256 with a JWKS endpoint** at `/.well-known/jwks.json`. A shared symmetric secret means every service can *mint* tokens, not just verify them — acceptable for local development, not for production.
- Support two active keys during rotation, with `kid` in the header.
- Login rate limiting and temporary lockout after repeated failures.
- Audit log for login, logout, role change, and password change.

**DoD:** consuming services validate via JWKS with no shared secret; a key can be rotated with no downtime.

---

## 5. Interfaces and contracts

### Provided

- `POST /v1/auth/register`, `/login`, `/refresh`, `/logout`
- `GET`/`PATCH /v1/merchants/{id}`
- `POST /v1/users`, `PATCH /v1/users/{id}/role`
- `GET /internal/v1/merchants/{id}/notification-preferences`
- `GET /.well-known/jwks.json` (M5)

### Produced

No Kafka events initially. `merchant.created` and `merchant.updated` would be useful for Notification Service to cache preferences locally rather than calling this service, but that trades a sync dependency for eventual consistency. Deferred until Notification Service demonstrates it needs it — see the [notification plan](payguard-notification-service.md).

### Consumed

Nothing. This service has no upstream dependencies, which is why it can be built in parallel with the fraud and payment work.

---

## 6. Data model and migrations

Database `payguard_users` (local port 5433):

- `V1__merchant_user.sql` — `merchant`, `app_user`, roles
- `V2__refresh_token.sql`
- `V3__merchant_tier_and_preferences.sql`
- `V4__auth_audit.sql`

Passwords are BCrypt hashes; refresh tokens are stored hashed. Neither is ever logged or returned.

---

## 7. Configuration

- Port **8086** (changed from 8081 to clear the Schema Registry collision)
- `SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5433/payguard_users`
- `JWT_SECRET`, `JWT_EXPIRY_SECONDS=3600`
- New: `payguard.jwt.issuer`, `payguard.jwt.refresh-expiry-seconds`, `payguard.auth.max-failed-attempts`

---

## 8. Testing strategy

- **Unit:** password policy, role checks, claim construction, refresh rotation and reuse detection.
- **Integration (Testcontainers Postgres):** register, login, refresh, logout; unique email constraint.
- **Security tests, treated as functional requirements:** account enumeration parity, cross-merchant access denial, expired token rejection, tampered signature rejection, revoked refresh token rejection, privilege escalation attempt via `PATCH /users/{id}/role` on self.
- **Cross-service contract test:** a minimal resource-server app configured from the README validates a real issued token. This is the test that keeps the platform's five validators aligned.

---

## 9. Observability and SLOs

SLO: p99 login under 300ms (BCrypt cost dominates and is intentional).

Metrics: `auth.login.count` by outcome, `auth.token.issued.count`, `auth.refresh.reuse_detected.count`, `auth.lockout.count`.

`auth.refresh.reuse_detected` is a security signal, not a performance one — a non-zero rate means either a client bug or a stolen token, and it should alert.

---

## 10. Security

This service *is* the platform's security boundary, so the whole section is load-bearing:

- BCrypt with a deliberate cost factor; never a fast hash.
- Uniform authentication failures to prevent enumeration.
- Short access tokens (1h) with rotating single-use refresh tokens.
- RS256 plus JWKS in production so no other service can mint tokens (M5).
- Every endpoint explicitly authorized; deny by default.
- Cross-merchant access returns 404 rather than 403.
- Audit trail for every authentication and authorization change.
- Secrets from Secrets Manager; `JWT_SECRET` in `.env` is local-only and the example value says so.

---

## 11. Risks and open questions

- **Shared HS256 secret is a genuine production risk.** Every service holding the signing key can forge tokens. M5 fixes it; until then, do not treat the local arrangement as a production design.
- **Notification preferences placement.** Putting them here creates a synchronous dependency from Notification Service to this one, which contradicts the "async everywhere except the fraud hop" principle in ADR-003. The alternative — publishing `merchant.updated` and letting Notification cache locally — is more consistent with the architecture. Worth an ADR before M4 hardens the endpoint.
- **Port change ripple.** Moving to 8086 touches `.env.example`, the umbrella README port table, and any gateway route configuration. Land it in one coordinated pair of PRs (service and umbrella) rather than piecemeal.
- **No OAuth2 authorization-code flow** is planned, only password grant plus refresh. If third-party integrations are ever needed, that is a much larger scope and a separate ADR.

---

## 12. Definition of done

- A merchant can register, log in, and receive a token that all five services validate identically.
- Every endpoint is explicitly authorized and cross-merchant access is impossible.
- Refresh rotation with reuse detection is live and monitored.
- No port collision with the local stack.
- Production runs on asymmetric keys with rotation support.
