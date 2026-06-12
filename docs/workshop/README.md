# Developer Hub on OpenShift — Workshop Guide

This workshop installs **Red Hat Developer Hub** on OpenShift, deploys a sample **Quarkus + PostgreSQL + React** application with GitOps, and connects catalog entities, OpenAPI, Technology Radar, Argo CD, GitHub Actions, and a software template.

## Repository layout

| Path | Purpose |
|------|---------|
| `apps/people-service/` | Sample CRUD application (Java Quarkus backend, React frontend) |
| `manifests/gitops/` | GitOps manifests for operators, Argo CD, the app, Developer Hub, and catalog |
| `scripts/` | Bootstrap and helper scripts (configurable via `workshop.env`) |
| `e2e/` | Selenium end-to-end tests against the live cluster |
| `docs/workshop/` | Step-by-step workshop documentation |

## Day 0 → Done (recommended path)

### 1. Prerequisites

- OpenShift 4.x cluster and `oc` logged in
- Permission to create Deployments, Routes, PVCs, BuildConfigs in your namespace
- **Either** OperatorGroup/Subscription access **or** Helm (see step 3)
- Local tools: `curl`, `jq`, `envsubst` (gettext)

Optional for e2e: Python 3.9+, Google Chrome.

See [01-prerequisites](01-prerequisites.md).

### 2. Configure

```bash
cp scripts/workshop.env.example scripts/workshop.env
# Edit WORKSHOP_NAMESPACE, WORKSHOP_GIT_REPO, CLUSTER_ROUTER_BASE
```

**Critical:** set `CLUSTER_ROUTER_BASE` to your cluster apps domain (everything after the first hostname segment), e.g. `apps.cluster.example.com`. The bootstrap script can auto-detect this from the OpenShift console route when possible.

See [02-configuration](02-configuration.md).

### 3. Bootstrap (one command)

```bash
chmod +x scripts/*.sh scripts/lib/*.sh
./scripts/bootstrap-workshop.sh
```

This runs the full sequence:

| Phase | Script(s) |
|-------|-------------|
| Platform (operators) | `install-operators.sh`, `setup-argocd.sh` |
| Keycloak | `setup-keycloak.sh` |
| People app | `deploy-people-app.sh` |
| Developer Hub | `install-developer-hub.sh` |
| Argo CD token | `setup-argocd-token.sh` |
| RHDH config | `setup-developer-hub-kubernetes.sh`, `setup-developer-hub-config.sh`, `configure-developer-hub-catalog.sh` |
| Validate | `validate-workshop.sh` |

**Helm path** (no operators):

```bash
export WORKSHOP_INSTALL_METHOD=helm
./scripts/bootstrap-workshop.sh
```

**Skip platform** (RHDH already installed):

```bash
export WORKSHOP_INSTALL_METHOD=skip-platform
./scripts/bootstrap-workshop.sh
```

**Include e2e tests:**

```bash
RUN_E2E=true ./scripts/bootstrap-workshop.sh
```

### 4. Validate

```bash
./scripts/validate-workshop.sh
./e2e/run-e2e.sh
```

### 5. Sign in

| System | User | Password |
|--------|------|----------|
| People app | `user` | `r3dh@t` |
| Developer Hub | `devhub` | `r#dh@t` (hash `#`, not `3`) |
| Keycloak admin | `admin` | `r3dh@t` |

## Manual step-by-step modules

Follow these if you prefer to run each phase yourself or if bootstrap fails partway:

| Step | Module | What it does |
|------|--------|--------------|
| 1 | [01-prerequisites](01-prerequisites.md) | Tools, namespace, fork |
| 2 | [02-configuration](02-configuration.md) | `workshop.env` variables |
| 3a | [03-install-operators](03-install-operators.md) | GitOps + RHDH operators |
| 3b | [03b-install-with-helm](03b-install-with-helm.md) | Helm alternative (no operators) |
| 4 | [04b-setup-keycloak](04b-setup-keycloak.md) | Keycloak + workshop realm |
| 5 | [04-deploy-people-app](04-deploy-people-app.md) | PostgreSQL, builds, Quarkus + React |
| 6 | [05-setup-argocd](05-setup-argocd.md) | Argo CD instance + Application (optional) |
| 7 | [06-install-developer-hub](06-install-developer-hub.md) | Developer Hub instance + OIDC |
| 8 | [07-developer-hub-catalog](07-developer-hub-catalog.md) | Catalog, OpenAPI, Tech Radar |
| 9 | [08-validation](08-validation.md) | Validation, e2e, troubleshooting |

## What you will see in Developer Hub

- **Catalog → Component**: `people-service` with GitHub, Keycloak, People UI/API, and Topology links
- **Catalog → APIs**: `People REST API` (OpenAPI from live Quarkus `/q/openapi`)
- **Tech Radar**: Quarkus, React, PostgreSQL, OpenShift, Keycloak, Argo CD, Developer Hub
- **CD tab**: Argo CD sync status (when token configured)
- **CI tab**: GitHub Actions (requires `GITHUB_TOKEN` + GitHub OAuth App — see [01-prerequisites](01-prerequisites.md) or `./scripts/create-github-oauth-app.sh --oauth-app`)
- **Kubernetes / Topology**: People Service workloads in your namespace
- **Create → Template**: Quarkus + React + PostgreSQL scaffolder

## OpenAPI endpoints

| URL | Description |
|-----|-------------|
| `https://people-backend-<ns>.<router>/q/openapi` | Live Quarkus spec |
| `https://people-frontend-<ns>.<router>/openapi.yaml` | Same spec via frontend proxy |

## Repair scripts (shared dev namespaces)

Workloads may be scaled to zero between sessions:

```bash
./scripts/repair-keycloak.sh
./scripts/repair-people-app.sh
./scripts/repair-developer-hub.sh
./scripts/configure-developer-hub-catalog.sh
./scripts/setup-developer-hub-config.sh
./scripts/create-github-oauth-app.sh --oauth-app   # CI tab Authorize GitHub
```

## Sample application

- **Frontend**: `https://people-frontend-<namespace>.<cluster-domain>/`
- **Backend API**: `/api/people` (Keycloak Bearer token with `people-crud` role)
- **Health**: `/q/health` (unauthenticated)

Person fields: `firstName`, `lastName`, `age`.
