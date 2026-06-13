# Dev mode

Quarkus dev mode provides live reload and a built-in development UI.

## Start dev mode

```bash
cd apps/people-service/backend
./mvnw quarkus:dev
```

Changes to Java sources trigger automatic recompilation. Database migrations run through Flyway on startup.

## Useful dev endpoints

| Endpoint | Purpose |
|----------|---------|
| `/q/dev` | Dev UI (when enabled) |
| `/q/health` | Liveness |
| `/q/health/ready` | Readiness including DB |
| `/q/openapi` | OpenAPI document |

## Debugging tips

1. Check Flyway migration logs if the database schema is missing.
2. Verify PostgreSQL connectivity with `/q/health/ready`.
3. Use `./scripts/repair-people-app.sh` if the OpenShift postgres pod is down.

## Live coding on OpenShift

The workshop also demonstrates deploying Quarkus to OpenShift with source-to-image or pre-built images. See [OpenShift deployment](openshift.md).
