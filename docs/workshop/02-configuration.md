# 2. Configure the workshop

All scripts read configuration from `scripts/workshop.env`. Start from the example file:

```bash
cp scripts/workshop.env.example scripts/workshop.env
```

## Key variables

| Variable | Description | Default |
|----------|-------------|---------|
| `WORKSHOP_NAMESPACE` | OpenShift project for app + operators | `rh-ee-mvandepe-dev` |
| `CLUSTER_ROUTER_BASE` | Cluster apps domain suffix for routes | **Must set for your cluster** |
| `WORKSHOP_GIT_REPO` | Git URL used by Argo CD and catalog | This repository |
| `WORKSHOP_GITHUB_ORG` | GitHub user/org for annotations | `maarten-vandeperre` |
| `GITHUB_TOKEN` | PAT for server-side GitHub API (scaffolder, proxy) | `changeme` |
| `AUTH_GITHUB_CLIENT_ID` | OAuth App client ID for CI tab | set via `./scripts/create-github-oauth-app.sh` |
| `AUTH_GITHUB_CLIENT_SECRET` | OAuth App client secret for CI tab | set via `./scripts/create-github-oauth-app.sh` |
| `WORKSHOP_BACKEND_IMAGE` | Backend container image | OpenShift ImageStream |
| `WORKSHOP_FRONTEND_IMAGE` | Frontend container image | OpenShift ImageStream |
| `WORKSHOP_INSTALL_METHOD` | Bootstrap path: `operator`, `helm`, `skip-platform` | `operator` |
| `SKIP_ARGOCD` | Skip Argo CD install and CD tab setup | `false` |
| `RUN_E2E` | Run Selenium tests after bootstrap | `false` |
| `RHDH_INSTANCE_NAME` | Developer Hub Backstage CR name | `developer-hub` |
| `ARGOCD_INSTANCE_NAME` | Argo CD instance name | `workshop-gitops` |
| `ARGOCD_APP_NAME` | Argo CD Application name | `people-service` |
| `KEYCLOAK_ADMIN_USER` | Keycloak admin console user | `admin` |
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password | `r3dh@t` |
| `KEYCLOAK_REALM` | Imported realm name | `workshop` |
| `KEYCLOAK_CLIENT_ID` | OIDC client for People Service | `people-service` |
| `OIDC_ENABLED` | Protect API with Keycloak | `true` |
| `RHDH_KEYCLOAK_CLIENT_ID` | Developer Hub OIDC client | `developer-hub` |
| `RHDH_KEYCLOAK_CLIENT_SECRET` | Developer Hub client secret | `developer-hub-workshop-secret` |
| `RHDH_KEYCLOAK_USER` | Developer Hub login user | `devhub` |
| `RHDH_KEYCLOAK_PASSWORD` | Developer Hub login password | `r#dh@t` |

## Auto-detect cluster router base

If `CLUSTER_ROUTER_BASE` is unset, bootstrap calls `detect_cluster_router_base()` in `scripts/lib/common.sh`, which reads the OpenShift console route. You can still set it explicitly when auto-detection fails.

## How rendering works

Manifests under `manifests/gitops/` contain shell-style placeholders such as `${WORKSHOP_NAMESPACE}`.

Scripts call `envsubst` via `scripts/lib/common.sh` before `oc apply`. This keeps manifests reusable without hard-coding one namespace.

## Image strategy

**Workshop default**: build images on-cluster with OpenShift BuildConfigs (`scripts/build-images-openshift.sh`).

**Production-style**: use GitHub Actions to push to GHCR, then point `WORKSHOP_*_IMAGE` at GHCR tags.

## Next step

Run the full bootstrap:

```bash
./scripts/bootstrap-workshop.sh
```

Or continue manually with [03-install-operators](03-install-operators.md) or [03b-install-with-helm](03b-install-with-helm.md).
