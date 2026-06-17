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

## Developer Lightspeed (OpenAI)

Optional AI chat assistant in Developer Hub. Requires an [OpenAI API key](https://platform.openai.com/).

| Variable | Description | Default |
|----------|-------------|---------|
| `LIGHTSPEED_ENABLED` | Install Lightspeed plugins and sidecars | `false` |
| `OPENAI_API_KEY` | OpenAI platform API key | `changeme` |
| `OPENAI_MODEL` | Model id (e.g. `gpt-4o-mini`, `gpt-4o`) | `gpt-4o-mini` |
| `LIGHTSPEED_VLLM_MAX_TOKENS` | Max tokens hint for the LLM stack | `4096` |
| `MCP_TOKEN` | Auth token for RHDH MCP server + Lightspeed MCP client | auto-generated if `changeme` |

```bash
export LIGHTSPEED_ENABLED=true
export OPENAI_API_KEY=sk-...
./scripts/setup-developer-hub-config.sh   # installs Lightspeed + MCP plugins
```

See [06-install-developer-hub](06-install-developer-hub.md#developer-lightspeed) for architecture and troubleshooting.

## Ansible Automation Platform (AAP)

Optional integration with Ansible Automation Platform Controller in Developer Hub — adds `/ansible` sidebar, Controller content, and Ansible software templates.

> **Full guide:** [06c — Ansible Automation Platform plugin](06c-ansible-automation-platform.md)

| Variable | Description | Default |
|----------|-------------|---------|
| `AAP_ENABLED` | Install Ansible dynamic plugins and app-config | `false` |
| `AAP_CONTROLLER_URL` | Controller base URL | auto-detected from `sandbox-aap-controller` route |
| `AAP_TOKEN` | Controller personal access token (**User → Tokens**) | `changeme` |
| `AAP_CHECK_SSL` | Verify Controller TLS certificate | `false` |
| `RH_REGISTRY_USERNAME` | Red Hat registry service account for OCI plugin pulls | `changeme` |
| `RH_REGISTRY_TOKEN` | Red Hat registry token | `changeme` |
| `AAP_ADMIN_USERNAME` | Admin user (auto-create PAT only) | `admin` |
| `AAP_ADMIN_PASSWORD` | Admin password (auto-create PAT only) | `changeme` |
| `AAP_CREATOR_SERVICE_ENABLED` | Add `ansible-devtools-server` sidecar for templates | `true` |
| `AAP_DEVTOOLS_IMAGE` | Dev-tools sidecar image | `registry.redhat.io/.../ansible-dev-tools-rhel8:latest` |
| `RH_REGISTRY_PULL_SECRET` | Reuse existing OpenShift pull secret instead of username/token | *(empty)* |

```bash
./scripts/configure-aap-workshop-env.sh \
  --url https://sandbox-aap-rh-ee-mvandepe-dev.apps.rm1.0a51.p1.openshiftapps.com \
  --username admin \
  --password 'your-password' \
  --rh-registry-username <your-rh-registry-sa> \
  --rh-registry-token <your-rh-registry-token> \
  --apply
```

Or set variables manually in `scripts/workshop.env` and run `./scripts/setup-developer-hub-config.sh`.

**Important:** `AAP_ADMIN_USERNAME` / `AAP_ADMIN_PASSWORD` are **not** used by the plugin — only for optional PAT auto-creation via `configure-aap-workshop-env.sh`. The plugin requires `AAP_TOKEN` and `RH_REGISTRY_*`.

See [06c-ansible-automation-platform.md](06c-ansible-automation-platform.md) for step-by-step setup, verification, and troubleshooting.

## Auto-detect cluster router base

If `CLUSTER_ROUTER_BASE` is unset or left at `apps.example.com`, bootstrap calls `detect_cluster_router_base()` in `scripts/lib/common.sh`, which:

1. Reads the OpenShift console route (`openshift-console/console`).
2. Falls back to existing routes in your workshop namespace (Keycloak, People Service, Developer Hub, Argo CD).
3. Updates and persists the detected value to `scripts/workshop.env` when it differs from a stale cluster domain.

Helm install scripts reuse an **existing Developer Hub route host** when upgrading, so sandbox clusters do not reject Route patches with a hostname from the wrong router domain.

You can still set `CLUSTER_ROUTER_BASE` explicitly when auto-detection fails. See [01-prerequisites — Route permission errors](01-prerequisites.md#route-permission-errors-during-helm-install) for troubleshooting.

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
