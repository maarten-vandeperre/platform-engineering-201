# 4. Deploy the People Service

Deploy Keycloak (if not already running), PostgreSQL, build container images, and run the Quarkus + React application secured with OIDC.

```bash
./scripts/deploy-people-app.sh
```

The script automatically calls `setup-keycloak.sh` when `OIDC_ENABLED=true` and Keycloak URLs are not yet configured.

## Application architecture

```
Browser → Keycloak login → Route (people-frontend) → nginx → /api/* + Bearer token → people-backend (Quarkus OIDC)
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
| `imagestream-*.yaml` | Internal image registry tags |
| `build-backend.yaml` | OpenShift build for Quarkus (multi-stage Dockerfile) |
| `build-frontend.yaml` | OpenShift build for React/nginx |
| `backend-deployment.yaml` | Quarkus deployment with DB + OIDC env vars and health probes |
| `backend-service.yaml` / `backend-route.yaml` | API exposure |
| `frontend-deployment.yaml` | React UI with Keycloak runtime config (proxies `/api` to backend) |
| `frontend-service.yaml` / `frontend-route.yaml` | UI exposure |

Keycloak manifests live in `manifests/gitops/keycloak/` — see [Set up Keycloak](04b-setup-keycloak.md).

## Build script

`scripts/build-images-openshift.sh`:

1. Creates ImageStreams and BuildConfigs
2. Runs `oc start-build --from-dir` with local source
3. Points Deployments at `image-registry.openshift-image-registry.svc:5000/<namespace>/people-*:latest`

Backend Dockerfile (`apps/people-service/backend/Dockerfile`) performs a multi-stage Maven + Quarkus build inside the cluster (Java 17).

The frontend container generates `/config.js` at startup from `KEYCLOAK_URL`, `KEYCLOAK_REALM`, and `KEYCLOAK_CLIENT_ID` environment variables.

## Manual validation

```bash
source scripts/workshop.env
KEYCLOAK_HOST=$(oc get route keycloak -o jsonpath='{.spec.host}')
BACKEND=$(oc get route people-backend -o jsonpath='{.spec.host}')

TOKEN=$(curl -sk -X POST "https://${KEYCLOAK_HOST}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "client_id=${KEYCLOAK_CLIENT_ID}" \
  -d 'username=user' \
  -d 'password=r3dh@t' \
  -d 'grant_type=password' | jq -r .access_token)

curl -sk "https://${BACKEND}/q/health" | jq .
curl -sk -X POST "https://${BACKEND}/api/people" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"firstName":"Grace","lastName":"Hopper","age":85}' | jq .
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${BACKEND}/api/people" | jq .
```

Or run:

```bash
./scripts/validate-workshop.sh
```

Open the frontend route in a browser and sign in as `user` / `r3dh@t`.

## Application source

| Path | Description |
|------|-------------|
| `apps/people-service/backend/` | Quarkus REST API with OIDC, Flyway migration, Panache entity |
| `apps/people-service/frontend/` | React CRUD UI with Keycloak login |
| `apps/people-service/catalog-info.yaml` | Backstage component metadata for scaffolder output |

## Argo CD

When using Argo CD, sync `manifests/gitops/keycloak/` before or together with `manifests/gitops/people-app/`. Ensure rendered manifests include `OIDC_AUTH_SERVER_URL` pointing at your Keycloak route.
