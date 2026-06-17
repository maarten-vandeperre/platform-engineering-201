# End-to-end tests

Selenium and HTTP tests validate the People Service, Keycloak, OpenAPI, Developer Hub catalog/API listing, GitHub Actions CI tab, Tech Radar, and Kubernetes/Topology views.

## Prerequisites

- Google Chrome (or Chromium)
- Python 3.9+
- Network access to the workshop OpenShift routes
- Healthy stack: run repair scripts if workloads were scaled down

```bash
./scripts/repair-keycloak.sh
./scripts/repair-people-app.sh
./scripts/repair-developer-hub.sh
./scripts/setup-developer-hub-dynamic-plugins-cache.sh   # one-time, faster restarts
# ./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock   # stale install lock
./scripts/configure-developer-hub-catalog.sh
./scripts/setup-developer-hub-config.sh
```

## Run

```bash
chmod +x e2e/run-e2e.sh scripts/repair-*.sh
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
| `LIGHTSPEED_ENABLED` | `false` (set `true` to run Lightspeed e2e tests) |

Run with a visible browser:

```bash
E2E_HEADLESS=false ./e2e/run-e2e.sh
```

## What is validated

1. Backend `/q/health/ready` is `UP`, including the database health check.
2. OpenAPI is reachable at `/q/openapi` (backend) and `/openapi.yaml` (frontend proxy).
3. Workshop catalog server serves entities, OpenAPI file, and Tech Radar JSON.
4. Authenticated People API CRUD works through Keycloak (HTTP).
5. Frontend `/config.js` has no `${...}` placeholders and login redirects to Keycloak (no 414 URL).
6. Frontend UI CRUD: create, update, and delete a person in the browser.
7. Developer Hub Keycloak client is registered.
8. Developer Hub Kubernetes and Topology tabs show healthy workloads.
9. Developer Hub API catalog lists **People REST API**.
10. Developer Hub **CI** tab on the People REST API entity loads GitHub Actions content.
11. Developer Hub Tech Radar page loads workshop technologies.
12. Developer Hub TechDocs pages render for Quarkus guide and ADR catalog entities.
13. Developer Hub AAP Management plugin lists templates and shows job run logs/progress.
14. Developer Hub scaffolder exposes `publish:github` and lists the Quarkus template.
15. Developer Hub **Developer Lightspeed** (when `LIGHTSPEED_ENABLED=true`): sidecars, plugin, and `/lightspeed` page.
