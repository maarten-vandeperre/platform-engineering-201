# 2. Configure the workshop

> **Full path:** This module is [Module 1](TUTORIAL.md#module-1--local-tools-and-repository-fork) in the [complete tutorial](TUTORIAL.md).

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
| `GITHUB_TOKEN` | PAT for scaffolder publish and GitHub API proxy | `changeme` — configure with `./scripts/setup-github-auth.sh` |
| `AUTH_GITHUB_CLIENT_ID` | OAuth App client ID for CI tab | set via `./scripts/create-github-oauth-app.sh` |
| `AUTH_GITHUB_CLIENT_SECRET` | OAuth App client secret for CI tab | set via `./scripts/create-github-oauth-app.sh` |
| `WORKSHOP_BACKEND_IMAGE` | Backend container image | OpenShift ImageStream |
| `WORKSHOP_FRONTEND_IMAGE` | Frontend container image | OpenShift ImageStream |
| `WORKSHOP_INSTALL_METHOD` | Bootstrap path: `helm`, `operator`, `skip-platform` | `helm` |
| `SKIP_ARGOCD` | Argo CD install and CD tab. Helm: skipped unless set to `false`. Operator: installed unless `true`. | unset (Helm skips) |
| `RUN_E2E` | Run Selenium tests after bootstrap | `false` |
| `RHDH_INSTANCE_NAME` | Developer Hub Backstage CR name | `developer-hub` |
| `RHDH_APP_TITLE` | Browser title and header (Egyptian theme) | `Nile Developer Hub` |
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

## GitHub auth (OAuth + PAT)

Developer Hub uses two separate GitHub credentials:

| Credential | Purpose | Setup |
|------------|---------|--------|
| OAuth App (`AUTH_GITHUB_*`) | CI / Issues / Pull Requests tabs | `./scripts/create-github-oauth-app.sh --oauth-app` |
| PAT (`GITHUB_TOKEN`) | Scaffolder **Publish to GitHub**, GitHub API proxy | `./scripts/setup-github-auth.sh --open-pat-url` |

Configure both in one pass:

```bash
./scripts/setup-github-auth.sh --open-pat-url
```

See [01-prerequisites](01-prerequisites.md) for PAT scopes (`repo`, `workflow`).

## Next step

Run the full bootstrap:

```bash
./scripts/bootstrap-workshop.sh
```

Or continue manually with [03-install-operators](03-install-operators.md) or [03b-install-with-helm](03b-install-with-helm.md).
