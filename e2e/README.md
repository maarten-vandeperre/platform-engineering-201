# End-to-end tests

Selenium and HTTP tests validate the People Service application, PostgreSQL database, Keycloak login, and Developer Hub Kubernetes/Topology views.

## Prerequisites

- Google Chrome (or Chromium)
- Python 3.9+
- Network access to the workshop OpenShift routes
- Keycloak realm configured: `./scripts/configure-keycloak-realm.sh`
- Healthy People Service stack: `./scripts/repair-people-app.sh`

If PostgreSQL is crash-looping or scaled to zero, run the repair script first. Use `REPAIR_RESET_POSTGRES_DATA=true ./scripts/repair-people-app.sh` only when you need a fresh database volume.

## Run

```bash
chmod +x e2e/run-e2e.sh scripts/repair-people-app.sh
./e2e/run-e2e.sh
```

Optional environment variables:

| Variable | Default |
|----------|---------|
| `RHDH_URL` | `https://redhat-developer-hub-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}` |
| `PEOPLE_BACKEND_URL` | `https://people-backend-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}` |
| `PEOPLE_FRONTEND_URL` | `https://people-frontend-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}` |
| `KEYCLOAK_URL` | `https://keycloak-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}` |
| `PEOPLE_KEYCLOAK_USER` | `user` |
| `PEOPLE_KEYCLOAK_PASSWORD` | `r3dh@t` |
| `RHDH_KEYCLOAK_USER` | `devhub` |
| `RHDH_KEYCLOAK_PASSWORD` | `r#dh@t` |
| `E2E_HEADLESS` | `true` |
| `E2E_TIMEOUT_SECONDS` | `180` |

Run with a visible browser:

```bash
E2E_HEADLESS=false ./e2e/run-e2e.sh
```

## What is validated

1. Backend `/q/health/ready` is `UP`, including the database health check.
2. OpenAPI is reachable at `/q/openapi` (backend) and `/openapi.yaml` (frontend proxy).
3. Workshop catalog server serves entities, OpenAPI file, and Tech Radar JSON.
4. Authenticated People API CRUD works through Keycloak.
5. People frontend login and create-person flow works.
6. Developer Hub Keycloak client is registered.
7. Developer Hub Kubernetes and Topology tabs show healthy workloads.
8. Developer Hub API catalog lists **People REST API**.
9. Developer Hub Tech Radar page loads workshop technologies.
