# Keycloak setup

This module deploys **Keycloak** on OpenShift and pre-configures a workshop realm for the People Service application.

## What gets installed

| Resource | File | Purpose |
|----------|------|---------|
| Admin Secret | `manifests/gitops/keycloak/keycloak-secret.yaml` | Keycloak bootstrap admin credentials |
| Realm import | `manifests/gitops/keycloak/keycloak-realm-configmap.yaml` | `workshop` realm, OIDC client, demo user |
| Deployment | `manifests/gitops/keycloak/keycloak-deployment.yaml` | Keycloak 26 with realm import on startup |
| Service | `manifests/gitops/keycloak/keycloak-service.yaml` | ClusterIP on port 8080 |
| Route | `manifests/gitops/keycloak/keycloak-route.yaml` | External HTTPS access |

## Configuration

Set these in `scripts/workshop.env` (defaults shown in `workshop.env.example`):

| Variable | Default | Description |
|----------|---------|-------------|
| `KEYCLOAK_ADMIN_USER` | `admin` | Keycloak admin console username |
| `KEYCLOAK_ADMIN_PASSWORD` | `r3dh@t` | Keycloak admin console password |
| `KEYCLOAK_REALM` | `workshop` | Realm imported for the demo app |
| `KEYCLOAK_CLIENT_ID` | `people-service` | Public OIDC client used by frontend and API |
| `OIDC_ENABLED` | `true` | Enable OAuth on backend and frontend |

After the first deploy, `setup-keycloak.sh` writes `KEYCLOAK_URL` and `OIDC_AUTH_SERVER_URL` to your `workshop.env`.

For Developer Hub SSO, also configure:

| Variable | Default | Description |
|----------|---------|-------------|
| `RHDH_KEYCLOAK_CLIENT_ID` | `developer-hub` | Confidential OIDC client for Developer Hub |
| `RHDH_KEYCLOAK_CLIENT_SECRET` | `developer-hub-workshop-secret` | Client secret |
| `RHDH_KEYCLOAK_USER` | `devhub` | Developer Hub login username |
| `RHDH_KEYCLOAK_PASSWORD` | `r#dh@t` | Developer Hub login password |

On an already-running Keycloak instance, apply realm updates idempotently:

```bash
./scripts/configure-keycloak-realm.sh
```

## Deploy with oc apply

Bootstrap deploys Keycloak automatically. Manual install:

```bash
source scripts/workshop.env
./scripts/setup-keycloak.sh
```

Or repair an existing deployment scaled to zero:

```bash
./scripts/repair-keycloak.sh
```

Or apply manifests manually:

```bash
source scripts/lib/common.sh
for f in manifests/gitops/keycloak/*.yaml; do
  render_manifest "$f" | oc apply -f -
done
oc rollout status deployment/keycloak -n "${WORKSHOP_NAMESPACE}"
```

## Deploy with Argo CD

When Argo CD is available, add `manifests/gitops/keycloak/` to your Application source path (or create a dedicated Application). Sync order:

1. Keycloak Secret + ConfigMap
2. Keycloak Deployment, Service, Route
3. People Service backend/frontend (needs `OIDC_AUTH_SERVER_URL`)

## Accounts

| Account | Username | Password | Purpose |
|---------|----------|----------|---------|
| Keycloak admin | `admin` | `r3dh@t` | Manage realms at `/admin` |
| Application user | `user` | `r3dh@t` | CRUD on `/api/people` (role: `people-crud`) |
| Developer Hub user | `devhub` | `r#dh@t` (**`#`** not `3`) | Sign in to Developer Hub and use the People API (roles: `developer-hub-user`, `people-crud`) |

## Realm details

The imported `workshop` realm contains:

- **Role** `people-crud` — required by the Quarkus API (`@RolesAllowed("people-crud")`)
- **Client** `people-service` — public OIDC client for the People app
- **Client** `developer-hub` — confidential OIDC client for Developer Hub SSO
- **User** `user` — assigned the `people-crud` role
- **User** `devhub` — assigned the `developer-hub-user` and `people-crud` roles

## Verify Keycloak

```bash
KEYCLOAK_HOST=$(oc get route keycloak -n "${WORKSHOP_NAMESPACE}" -o jsonpath='{.spec.host}')

# Realm metadata
curl -sk "https://${KEYCLOAK_HOST}/realms/workshop" | jq .

# Obtain a token for API testing
curl -sk -X POST "https://${KEYCLOAK_HOST}/realms/workshop/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'client_id=people-service' \
  -d 'username=user' \
  -d 'password=r3dh@t' \
  -d 'grant_type=password' | jq .
```

Open the admin console at `https://<keycloak-route>/admin` and sign in with `admin` / `r3dh@t`.

## Next step

Continue with [Deploy the People Service](04-deploy-people-app.md), then [Install Developer Hub](06-install-developer-hub.md) and run `./scripts/setup-developer-hub-config.sh` to wire Keycloak SSO.
