# 4. Deploy the People Service

Deploy PostgreSQL, build container images, and run the Quarkus + React application secured with Keycloak OIDC.

Keycloak must be running first — see [Set up Keycloak](04b-setup-keycloak.md). Bootstrap and `deploy-people-app.sh` call `setup-keycloak.sh` automatically when `OIDC_ENABLED=true`.

```bash
./scripts/deploy-people-app.sh
```

## Application architecture

```
Browser → Keycloak login → Route (people-frontend) → nginx → /api/* + Bearer token → people-backend (Quarkus OIDC)
         ↳ /openapi.yaml ─────────────────────────────────────────────────────────────→ /q/openapi
                                                                                              ↓
                                                                                    people-postgres (PostgreSQL)
```

## Manifests (`manifests/gitops/people-app/`)

| File | Description |
|------|-------------|
| `postgres-secret.yaml` | Database name, user, password |
| `postgres-pvc.yaml` | 1Gi persistent volume for PostgreSQL data |
| `postgres-deployment.yaml` | PostgreSQL 16 |
| `postgres-service.yaml` | ClusterIP service on port 5432 |
| `frontend-nginx-configmap.yaml` | Nginx config with `/api`, `/q`, and `/openapi.yaml` proxies |
| `imagestream-*.yaml` | Internal image registry tags |
| `build-backend.yaml` | OpenShift build for Quarkus (multi-stage Dockerfile) |
| `build-frontend.yaml` | OpenShift build for React/nginx |
| `backend-deployment.yaml` | Quarkus deployment with DB + OIDC env vars and health probes |
| `backend-service.yaml` / `backend-route.yaml` | API exposure |
| `frontend-deployment.yaml` | React UI with Keycloak runtime config (mounts nginx ConfigMap) |
| `frontend-service.yaml` / `frontend-route.yaml` | UI exposure |

Keycloak manifests live in `manifests/gitops/keycloak/` — see [Set up Keycloak](04b-setup-keycloak.md).

## Build script

`scripts/build-images-openshift.sh`:

1. Creates ImageStreams and BuildConfigs
2. Runs `oc start-build --from-dir` with local source
3. Points Deployments at `image-registry.openshift-image-registry.svc:5000/<namespace>/people-*:latest`

## OpenAPI

| Endpoint | Description |
|----------|-------------|
| `/q/openapi` | Live Quarkus OpenAPI (backend route) |
| `/openapi.yaml` | Same spec via frontend nginx proxy |
| `/openapi.json` | JSON representation via frontend proxy |

The frontend header includes an **OpenAPI** link when OIDC is enabled.

## Manual validation

```bash
./scripts/validate-workshop.sh
```

Or test CRUD manually — see [08-validation](08-validation.md).

Open the frontend route in a browser and sign in as `user` / `r3dh@t`.

## Application source

| Path | Description |
|------|-------------|
| `apps/people-service/backend/` | Quarkus REST API with OIDC, Flyway migration, Panache entity |
| `apps/people-service/frontend/` | React CRUD UI with Keycloak login |
| `apps/people-service/openapi/people-api.yaml` | Static OpenAPI reference copy |
| `apps/people-service/catalog-info.yaml` | Backstage component metadata for the workshop demo |
| `apps/people-service-scaffold/catalog-info.yaml` | Templated catalog metadata used by the Developer Hub scaffolder |

## Repair

If PostgreSQL, backend, or frontend stop working (common in shared dev namespaces):

```bash
./scripts/repair-people-app.sh
```

This also ensures Keycloak is running, applies `people-workshop-runtime` ConfigMap with concrete URLs, rebuilds the frontend image, and restarts the pod so `/config.js` is regenerated.

**Note:** Argo CD excludes `*-deployment.yaml` and runtime ConfigMaps from auto-sync because Git manifests contain `${...}` placeholders that must be rendered with `envsubst` via the repair/bootstrap scripts.

## Next step

[Install OpenShift GitOps / Argo CD](05-setup-argocd.md) (optional) or [Install Developer Hub](06-install-developer-hub.md).
