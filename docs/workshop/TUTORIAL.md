# Platform Engineering 201 — Complete Tutorial
_I've tested the commands on a MacBook._

End-to-end guide from a **clean OpenShift sandbox** to the **full workshop state**: People CRUD app, Keycloak, GitOps, Red Hat Developer Hub with catalog, TechDocs, Tech Radar, Learning Paths, GitHub integrations, Orchestrator workflow, Egyptian theme, and organization entity model.

Use this document as the **single tutorial outline**. Each step lists commands, what happens, why it matters, trade-offs, verification, and **exact files to edit** when customizing.

## Developer Hub and Backstage

This workshop is a **Backstage workshop** at heart: catalog entities, TechDocs, Tech Radar, scaffolder templates, dynamic plugins, Kubernetes/Topology, GitHub integrations, and Orchestrator are all standard Backstage concepts.

We use **Red Hat Developer Hub** (RHDH) because this is a Red Hat workshop — RHDH is Red Hat’s supported distribution of [Backstage](https://backstage.io/). The app-config, catalog YAML, and plugin patterns you configure here transfer directly to **Community Backstage**.

| This tutorial | Community Backstage on vanilla Kubernetes |
|---------------|-------------------------------------------|
| OpenShift + `oc` | Kubernetes + `kubectl` (same resources; Routes become Ingresses or port-forwards) |
| RHDH Helm chart or RHDH operator | [Backstage Helm chart](https://backstage.io/docs/deployment/helm) or your own manifests |
| OpenShift Routes | Ingress, Gateway API, or `kubectl port-forward` |
| Red Hat–branded dynamic plugins | Most plugins are open source; check each plugin’s install docs |

The scripts and manifests target OpenShift and are tested there. On plain Kubernetes you can reuse the **People app**, **Keycloak**, **catalog entities**, and **app-config** ideas; expect to adapt install scripts, ingress, and image pulls yourself. Treat `oc` in the commands as `kubectl` where the resource types match.

---

## How to use this tutorial

| Mode | When to use |
|------|-------------|
| **Fast path** | [Module 3 — One-command bootstrap](#module-3--one-command-bootstrap) |
| **Learning path** | Work through [Modules 0–12](#module-0--start-from-a-clean-sandbox) in order |
| **Repair path** | [Module 12 — Validation & repair](#module-12--validation--repair) after an idle sandbox |

**Companion docs** (deeper detail per topic):

| Module | Deep-dive doc |
|--------|----------------|
| Prerequisites | [01-prerequisites.md](01-prerequisites.md) |
| Configuration | [02-configuration.md](02-configuration.md) |
| Operators | [03-install-operators.md](03-install-operators.md) |
| Helm alternative | [03b-install-with-helm.md](03b-install-with-helm.md) |
| Keycloak | [04b-setup-keycloak.md](04b-setup-keycloak.md) |
| People app | [04-deploy-people-app.md](04-deploy-people-app.md) |
| Argo CD | [05-setup-argocd.md](05-setup-argocd.md) |
| Developer Hub | [06-install-developer-hub.md](06-install-developer-hub.md) |
| Catalog & plugins | [07-developer-hub-catalog.md](07-developer-hub-catalog.md) |
| Validation | [08-validation.md](08-validation.md) |

---

## Final state (what “done” looks like)

When the tutorial completes successfully, you have:

### Runtime workloads (namespace)

| Workload | Purpose |
|----------|---------|
| `people-backend`, `people-frontend`, `people-postgres` | Quarkus + React CRUD demo |
| `keycloak` | OIDC for People app and Developer Hub |
| `redhat-developer-hub` | Developer Hub (Backstage) |
| `redhat-developer-hub-postgresql` | Developer Hub database |
| `workshop-catalog-server` | Serves catalog entities, OpenAPI, Tech Radar, learning paths |
| `workshop-gitops` / Argo CD (optional) | GitOps CD for People app |
| `sonataflow-platform-data-index` | Orchestrator Data Index (standalone fallback) |
| `create-person-workflow` | Orchestrator workflow runtime |

### Developer Hub features

| Feature | URL path (relative to RHDH route) |
|---------|-----------------------------------|
| Catalog — People Service | `/catalog/default/component/people-service` |
| Catalog — People REST API | `/catalog/default/api/people-rest-api` |
| Tech Radar | `/tech-radar` |
| Learning Paths | `/learning-paths` |
| Orchestrator | `/orchestrator` |
| TechDocs — Quarkus guide | `/catalog/default/component/quarkus-workshop-guide/docs` |
| TechDocs — ADRs | `/catalog/default/component/platform-architecture-records/docs` |
| Scaffolder template | `/create/templates/default/quarkus-react-postgres-openshift` |
| Groups / Users / org model | `/catalog?filters[kind]=group`, `/catalog?filters[kind]=user` |

### Sign-in accounts

| System | User               | Password | Notes |
|--------|--------------------|----------|-------|
| People UI / API | `user` or `devhub` | `r3dh@t` | Role `people-crud` |
| Developer Hub | `devhub`           | `r#dh@t` | **`#` not `3`** |
| Keycloak admin | `admin`            | `r3dh@t` | Realm admin console |

### Sample URLs

Replace `<ns>` and `<router>` with your namespace and cluster router base:  
_For me, with my [developers.redhat.com](https://developers.redhat.com) cluster, it is 'https://console-openshift-console.apps.rm2.thpm.p1.openshiftapps.com/'_

```text
People UI:       https://people-frontend-<ns>.<router>/
People API:      https://people-backend-<ns>.<router>/api/people
OpenAPI (live):  https://people-backend-<ns>.<router>/q/openapi
Developer Hub:   https://redhat-developer-hub-<ns>.<router>/
Keycloak:        https://keycloak-<ns>.<router>/
Catalog server:  https://workshop-catalog-server-<ns>.<router>/entities.yaml
```

---

## Module 0 — Start from a clean sandbox

### Goal

Ensure you have an empty or reset OpenShift project before installing workshop resources. If needed, you can reset by running the clean-up script (scripts/cleanup-workshop.sh).

### Prerequisites

- OpenShift 4.x sandbox or dedicated namespace (you can get one for free at [developers.redhat.com](https://developers.redhat.com))
- `oc` logged in with permission to create Deployments, Routes, PVCs, BuildConfigs, Subscriptions (or Helm)

### Commands

```bash
# Clone or fork the repository
git clone https://github.com/<your-org>/platform-engineering-201.git
cd platform-engineering-201

# Set your namespace (must match workshop.env later)
# For me, it is maarten-vandeperre-dev
export WORKSHOP_NAMESPACE=<your-user>-dev

oc login --token=<token> --server=<api-url>
oc new-project "${WORKSHOP_NAMESPACE}" 2>/dev/null || oc project "${WORKSHOP_NAMESPACE}"

# Optional: remove prior workshop resources (destructive; safe if demo was partial)
./scripts/cleanup-workshop.sh --dry-run
./scripts/cleanup-workshop.sh --yes
```

See [09-cleanup-after-demo.md](09-cleanup-after-demo.md).

### What happens

OpenShift project is selected. Optional cleanup removes People app, Keycloak, catalog server, Argo CD, Developer Hub, orchestrator, and related workshop resources via [`cleanup-workshop.sh`](../../scripts/cleanup-workshop.sh).

### Why

Shared sandboxes often contain half-finished installs. Starting clean avoids duplicate routes, stale secrets, and conflicting operator subscriptions.

### Pros and cons

| Pros | Cons |
|------|------|
| Predictable bootstrap | Deletes existing demo data in that namespace |
| Easier troubleshooting | Operator CSVs may remain cluster-wide (needs admin to remove) |

### Customize

| Setting | File |
|---------|------|
| Default namespace | [`scripts/workshop.env.example`](../../scripts/workshop.env.example) → `WORKSHOP_NAMESPACE` |

### Verify

```bash
oc project
# Avoid `oc get all` — some sandboxes forbid listing applications.app.k8s.io
oc get deploy,statefulset,svc,route,pvc,buildconfig,imagestream,pod -n "${WORKSHOP_NAMESPACE}"
```

---

## Module 1 — Local tools and repository fork

### Goal

Install CLI tools and point catalog/GitOps annotations at **your** GitHub fork.

### Commands

```bash
# macOS example
brew install gettext jq   # provides envsubst

cp scripts/workshop.env.example scripts/workshop.env
# Edit: WORKSHOP_NAMESPACE, WORKSHOP_GIT_REPO, WORKSHOP_GITHUB_ORG, WORKSHOP_GITHUB_REPO, CLUSTER_ROUTER_BASE
```

### What happens

You create a **local** `scripts/workshop.env` (gitignored) from [`scripts/workshop.env.example`](../../scripts/workshop.env.example). That file holds every value that differs per person or cluster: namespace, GitHub fork, router domain, passwords, install method, and optional integrations (GitHub PAT, Argo CD, AAP, Lightspeed).

Every workshop script starts by sourcing [`scripts/lib/common.sh`](../../scripts/lib/common.sh). That library:

1. **Loads** `scripts/workshop.env` if it exists, otherwise falls back to `workshop.env.example`.
2. **Exports** the variables (for example `WORKSHOP_NAMESPACE`, `CLUSTER_ROUTER_BASE`, `KEYCLOAK_*`, `RHDH_*`) so child scripts and `envsubst` see the same values.
3. **Renders** manifests from `manifests/gitops/` via `render_manifest()`: placeholders like `${WORKSHOP_NAMESPACE}` in YAML are replaced with your values before `oc apply`.
4. **Auto-detects** `CLUSTER_ROUTER_BASE` from the OpenShift console route during bootstrap when you leave the example default.

So you edit one file; bootstrap, deploy, repair, cleanup, and validation scripts all read the same configuration without duplicating secrets or namespace names in Git.

### Why

Manifests stay generic in the repository (`namespace: ${WORKSHOP_NAMESPACE}`) while your fork and sandbox stay private in `workshop.env`. That pattern keeps the repo shareable, makes re-runs predictable, and lets you change namespace or credentials once instead of hunting through dozens of YAML files.

### Pros and cons

| Pros | Cons |
|------|------|
| One file drives entire workshop | Must re-run config scripts after edits |
| Fork-friendly | Wrong `CLUSTER_ROUTER_BASE` breaks all routes |

### Customize

| Setting | File |
|---------|------|
| All workshop variables (namespace, GitHub fork, router, credentials) | [`scripts/workshop.env`](../../scripts/workshop.env) (from [`.example`](../../scripts/workshop.env.example)) |
| GitHub org/repo for catalog CI, source links, and scaffolder | `WORKSHOP_GITHUB_ORG`, `WORKSHOP_GITHUB_REPO`, `WORKSHOP_GIT_REPO`, `WORKSHOP_GIT_BRANCH` in `workshop.env` — substituted into manifests at deploy time |
| Catalog entity content (titles, tags, extra links, templates) | [`manifests/gitops/developer-hub/catalog-configmap.yaml`](../../manifests/gitops/developer-hub/catalog-configmap.yaml) — re-run [`configure-developer-hub-catalog.sh`](../../scripts/configure-developer-hub-catalog.sh) after edits |

The files under `manifests/gitops/catalog/entities/` (`people-service.yaml`, `people-api.yaml`) use the same `${WORKSHOP_GITHUB_ORG}` / `${WORKSHOP_GITHUB_REPO}` placeholders; you do **not** edit them to point at your fork. Set your fork in `workshop.env` instead.

**Important!!!**   
Do not forget to review the workshop.env properties, with main focus on:
* CLUSTER_ROUTER_BASE
* WORKSHOP_NAMESPACE
* WORKSHOP_GIT_REPO
* WORKSHOP_GITHUB_ORG
* WORKSHOP_GITHUB_REPO

  
_If you don't use Ansible (later stage), you can entirely skip AAP_* and RH_REGISTRY_* properties._

See [02-configuration.md](02-configuration.md) for the full variable table.

### Verify

```bash
source scripts/workshop.env
echo "Namespace: ${WORKSHOP_NAMESPACE}, Router: ${CLUSTER_ROUTER_BASE}"
```

---

## Module 2 — GitHub integrations (optional but recommended)

### Goal

Enable Developer Hub **CI**, **Issues**, and **Pull Requests** tabs plus scaffolder publish.

### When to run this module

Developer Hub must exist before credentials can be **pushed to the cluster**. You have two valid paths:

| Path | When | Commands |
|------|------|----------|
| **A — credentials before bootstrap** (recommended) | After Module 1, **before** Module 3 | Save tokens to `workshop.env` only (`--no-apply`). Bootstrap (Module 3) applies them via `setup-developer-hub-config.sh`. |
| **B — credentials after bootstrap** | After Module 3 (or Module 9) | Run `./scripts/setup-github-auth.sh` with no flags — applies to a live Developer Hub. |

If you run `./scripts/setup-github-auth.sh` **without** `--no-apply` before bootstrap, it fails: Keycloak and Developer Hub are not installed yet (empty namespace).

### Commands

**Path A — before bootstrap** (save to `workshop.env` only):

```bash
./scripts/create-github-oauth-app.sh --oauth-app --no-apply
./scripts/setup-github-auth.sh --open-pat-url --no-apply

# Then continue to Module 3:
./scripts/bootstrap-workshop.sh
```

**Path B — after bootstrap**:

```bash
# OAuth App + PAT (recommended — interactive PAT prompt)
./scripts/setup-github-auth.sh --open-pat-url

# Or configure separately:
./scripts/create-github-oauth-app.sh --oauth-app   # CI tab Authorize GitHub popup
GITHUB_TOKEN=ghp_... ./scripts/setup-github-auth.sh --pat-only --no-interactive

# Re-apply credentials already in workshop.env:
./scripts/setup-github-auth.sh
```

### What happens

- **With `--no-apply`:** only `scripts/workshop.env` is updated (`GITHUB_TOKEN`, OAuth client ID/secret).
- **Without `--no-apply` (after bootstrap):** same env file updates, plus:
  - `GITHUB_TOKEN` → Secret `rhdh-workshop-secrets` (GitHub proxy, scaffolder)
  - OAuth client ID/secret → Developer Hub `auth.providers.github` in app-config

### Why

GitHub Actions plugin needs a **PAT** for workflow runs and an **OAuth App** for per-user authorization in the browser.

### Pros and cons

| Pros | Cons |
|------|------|
| Full GitHub tabs in catalog | Requires GitHub account and token management |
| Realistic IDP integration | OAuth callback URL must match your RHDH route exactly |

### Customize

| Setting | File |
|---------|------|
| GitHub PAT / OAuth placeholders | [`scripts/workshop.env`](../../scripts/workshop.env) |
| GitHub provider in app-config | [`manifests/gitops/developer-hub/app-config-rhdh.yaml`](../../manifests/gitops/developer-hub/app-config-rhdh.yaml) |
| GitHub proxy | same file → `proxy.endpoints.'/github/api'` |
| OAuth callback docs | [01-prerequisites.md](01-prerequisites.md) |

Callback URL pattern:

```text
https://redhat-developer-hub-<namespace>.<router>/api/auth/github/handler/frame
```

---

## Module 3 — One-command bootstrap (or break down into separate steps)

### Goal

Install the entire stack with one script (recommended after Modules 0–1; Module 2 credentials in `workshop.env` are applied automatically during bootstrap).
Run the commands one-by-one if you want to see what's happening, what's required for the Backstage setup.

### Commands

```bash
chmod +x scripts/*.sh scripts/lib/*.sh
source scripts/workshop.env

# Default in workshop.env.example: WORKSHOP_INSTALL_METHOD=helm (no OperatorHub subscriptions)
./scripts/bootstrap-workshop.sh

# Alternatives (set in workshop.env or export before bootstrap):
# export SKIP_ARGOCD=false                  # opt in to Argo CD Helm + GitOps CD tab
# export WORKSHOP_INSTALL_METHOD=operator   # OpenShift GitOps + RHDH operators (Module 4)
# export RUN_E2E=true                       # run Selenium tests at end
```

### What happens

[`scripts/bootstrap-workshop.sh`](../../scripts/bootstrap-workshop.sh) reads `WORKSHOP_INSTALL_METHOD` from `workshop.env`. **Helm** is the default for shared OpenShift sandboxes; **operator** is the supported Red Hat path when you have Subscription access.

**Helm path** (`WORKSHOP_INSTALL_METHOD=helm` — default). **Argo CD is skipped** unless you set `SKIP_ARGOCD=false` in `workshop.env` (opt-in for the GitOps CD tab; needs CRD permission on many clusters):

| Order | Script | Module |
|------:|--------|--------|
| 1 | `setup-keycloak.sh` | [5](#module-5--keycloak-identity) |
| 2 | `deploy-people-app.sh` | [7](#module-7--people-service-application) |
| 3 | `install-developer-hub-helm.sh` | [8](#module-8--red-hat-developer-hub), [03b](03b-install-with-helm.md) |
| 4 | (optional) `install-argocd-helm.sh` | [6](#module-6--argocd-gitops) — only if `SKIP_ARGOCD=false` |
| 5 | (optional) `setup-argocd-token.sh` | [6](#module-6--argocd-gitops) |
| 6–13 | config, catalog, orchestrator, validate | [9](#module-9--developer-hub-configuration)–[12](#module-12--validation--repair) |

Skip [Module 4](#module-4--install-platform-operators) on the Helm path — Argo CD and Developer Hub install from Helm charts instead of operators.

**Operator path** (`WORKSHOP_INSTALL_METHOD=operator`):

| Order | Script | Module |
|------:|--------|--------|
| 1 | `install-operators.sh` | [4](#module-4--install-platform-operators) |
| 2 | `setup-argocd.sh` | [6](#module-6--argocd-gitops) |
| 3 | `setup-keycloak.sh` | [5](#module-5--keycloak-identity) |
| 4 | `deploy-people-app.sh` | [7](#module-7--people-service-application) |
| 5 | `install-developer-hub.sh` | [8](#module-8--red-hat-developer-hub) |
| 6 | `setup-argocd-token.sh` | [6](#module-6--argocd-gitops) |
| 7–13 | config, catalog, orchestrator, validate | [9](#module-9--developer-hub-configuration)–[12](#module-12--validation--repair) |

### Why

Single entry point for demos and CI; each phase remains runnable individually if bootstrap fails mid-way.

### Pros and cons

| Pros | Cons |
|------|------|
| Fast time-to-demo (~20–40 min) | Long-running; failures require reading which phase failed |
| Idempotent-ish scripts | Shared sandboxes may hit quota (replica sets, PVCs) |

### Verify

See [Module 12](#module-12--validation--repair).

---

## Module 4 — Install platform operators

> **Helm path:** If `WORKSHOP_INSTALL_METHOD=helm` in `workshop.env` (the default), **skip this module**. Bootstrap installs Argo CD and Developer Hub with Helm instead — see [03b-install-with-helm.md](03b-install-with-helm.md) and the Helm table in [Module 3](#module-3--one-command-bootstrap-or-break-down-into-separate-steps).

### Goal

Install **OpenShift GitOps** and **Red Hat Developer Hub** operators in your namespace (`WORKSHOP_INSTALL_METHOD=operator` only).

### Commands

```bash
./scripts/install-operators.sh
```

### What happens

Applies OperatorGroup and Subscriptions from [`manifests/gitops/operators/`](../../manifests/gitops/operators/):

| File | Installs |
|------|----------|
| [`operatorgroup.yaml`](../../manifests/gitops/operators/operatorgroup.yaml) | OperatorGroup scoped to namespace |
| [`subscription-gitops.yaml`](../../manifests/gitops/operators/subscription-gitops.yaml) | OpenShift GitOps |
| [`subscription-rhdh.yaml`](../../manifests/gitops/operators/subscription-rhdh.yaml) | Red Hat Developer Hub |

### Why

Operators install CRDs and controllers for `ArgoCD` and `Backstage` custom resources — the supported RHDH install path on OpenShift.

### Pros and cons

| Pros | Cons |
|------|------|
| Supported Red Hat path | Needs Subscription permission in namespace |
| CR-based lifecycle | Slower first install (CSV rollout) |

**Helm alternative (default for most sandboxes):** [03b-install-with-helm.md](03b-install-with-helm.md) — set `WORKSHOP_INSTALL_METHOD=helm` in `workshop.env`; no subscriptions or Module 4.

### Customize

| Setting | File |
|---------|------|
| Operator namespace | `WORKSHOP_NAMESPACE` in [`scripts/workshop.env`](../../scripts/workshop.env) |

### Verify

```bash
oc get csv,subscription -n "${WORKSHOP_NAMESPACE}"
oc get crd | grep -E 'argoproj|rhdh|backstage'
```

---

## Module 5 — Keycloak identity

### Goal

Deploy Keycloak and import the **workshop** realm with clients for People Service and Developer Hub.

### Commands

```bash
./scripts/setup-keycloak.sh
./scripts/configure-keycloak-realm.sh   # called by setup-keycloak.sh
```

### What happens

| Resource | File |
|----------|------|
| Deployment, Service, Route | [`manifests/gitops/keycloak/keycloak-deployment.yaml`](../../manifests/gitops/keycloak/keycloak-deployment.yaml) |
| Admin secret | [`manifests/gitops/keycloak/keycloak-secret.yaml`](../../manifests/gitops/keycloak/keycloak-secret.yaml) |
| Realm JSON | [`manifests/gitops/keycloak/workshop-realm.json`](../../manifests/gitops/keycloak/workshop-realm.json) |

Creates realm `workshop`, clients `people-service` and `developer-hub`, users `user` and `devhub`, role `people-crud`.

### Why

Single OIDC provider for both the demo app and Developer Hub — realistic platform security story.

### Pros and cons

| Pros | Cons |
|------|------|
| One realm for app + portal | Dev Keycloak (not HA/production) |
| Scriptable realm import | Sandboxes scale Keycloak to 0 when idle |

### Customize

| Setting | File |
|---------|------|
| Realm name, admin password | [`scripts/workshop.env`](../../scripts/workshop.env) → `KEYCLOAK_*`, `RHDH_KEYCLOAK_*` |
| Realm clients and users | [`manifests/gitops/keycloak/workshop-realm.json`](../../manifests/gitops/keycloak/workshop-realm.json) |
| Realm import script | [`scripts/configure-keycloak-realm.sh`](../../scripts/configure-keycloak-realm.sh) |

### Verify

```bash
oc get route keycloak -n "${WORKSHOP_NAMESPACE}"
curl -sk "https://$(oc get route keycloak -o jsonpath='{.spec.host}')/realms/workshop/.well-known/openid-configuration" | head -3
```

---

## Module 6 — Argo CD (GitOps)

### Goal

Create an Argo CD instance and Application syncing People app manifests from Git.

### Commands

```bash
./scripts/setup-argocd.sh
# After Developer Hub is up:
./scripts/setup-argocd-token.sh
```

### What happens

| Resource | File |
|----------|------|
| ArgoCD CR | [`manifests/gitops/argocd/argocd-instance.yaml`](../../manifests/gitops/argocd/argocd-instance.yaml) |
| Application | [`manifests/gitops/argocd/application-people-service.yaml`](../../manifests/gitops/argocd/application-people-service.yaml) |
| Token → Developer Hub | [`scripts/setup-argocd-token.sh`](../../scripts/setup-argocd-token.sh) → Secret `argo-secrets` |

### Why

Demonstrates GitOps CD tab in Developer Hub (`argocd/app-name` annotation on `people-service`).

### Pros and cons

| Pros | Cons |
|------|------|
| End-to-end GitOps story | Extra operator workload |
| CD tab in catalog | Token must be refreshed if Argo CD admin password changes |

Skip with `SKIP_ARGOCD=true` in `workshop.env`.

### Customize

| Setting | File |
|---------|------|
| Argo CD instance name | [`scripts/workshop.env`](../../scripts/workshop.env) → `ARGOCD_INSTANCE_NAME` |
| Application name (must match annotation) | `ARGOCD_APP_NAME` + [`people-service.yaml`](../../manifests/gitops/catalog/entities/people-service.yaml) → `argocd/app-name` |
| Git source URL | `WORKSHOP_GIT_REPO`, `WORKSHOP_GIT_BRANCH` |
| Helm values (alternative install) | [`manifests/helm/argocd-values.yaml`](../../manifests/helm/argocd-values.yaml) |

---

## Module 7 — People Service application

### Goal

Build and deploy PostgreSQL, Quarkus backend, and React frontend with Keycloak protection.

### Commands

```bash
./scripts/deploy-people-app.sh
# Images built on-cluster unless WORKSHOP_*_IMAGE overrides set:
# ./scripts/build-images-openshift.sh
```

### What happens

Applies manifests under [`manifests/gitops/people-app/`](../../manifests/gitops/people-app/):

| Component | Key files |
|-----------|-----------|
| PostgreSQL | `postgres-deployment.yaml`, `postgres-pvc.yaml`, `postgres-secret.yaml` |
| Backend (Quarkus) | `backend-deployment.yaml`, `build-backend.yaml`, `backend-route.yaml` |
| Frontend (React/nginx) | `frontend-deployment.yaml`, `build-frontend.yaml`, `frontend-nginx-configmap.yaml` |
| Runtime OIDC URLs | `workshop-runtime-config.yaml` |
| Notification token | `backend-notifications-secret.yaml` |

Application source: [`apps/people-service/`](../../apps/people-service/)

### Why

Hands-on CRUD demo (`firstName`, `lastName`, `age`) with real persistence, OIDC, and OpenAPI — the anchor for catalog, TechDocs, Orchestrator workflow, and **Developer Hub notifications** on create.

When `POST /api/people` succeeds, the backend asynchronously calls Developer Hub `POST /api/notifications/notifications` (see [07-developer-hub-catalog.md](07-developer-hub-catalog.md#developer-hub-notifications-people-api)).

### Pros and cons

| Pros | Cons |
|------|------|
| OpenShift BuildConfigs (no external registry required) | First build takes several minutes |
| Live OpenAPI for catalog | PVC + builds consume sandbox quota |

### Customize

| Setting | File |
|---------|------|
| DB credentials | [`scripts/workshop.env`](../../scripts/workshop.env) → `PEOPLE_DB_*` |
| Container images | `WORKSHOP_BACKEND_IMAGE`, `WORKSHOP_FRONTEND_IMAGE` |
| Quarkus config / OIDC | [`apps/people-service/backend/src/main/resources/application.properties`](../../apps/people-service/backend/src/main/resources/application.properties) |
| Frontend API proxy / OpenAPI | [`apps/people-service/frontend/nginx.conf`](../../apps/people-service/frontend/nginx.conf), [`apps/people-service/frontend/public/runtime-config.js`](../../apps/people-service/frontend/public/runtime-config.js) |
| OpenAPI spec (static copy) | [`apps/people-service/openapi/people-api.yaml`](../../apps/people-service/openapi/people-api.yaml) |

### Verify

```bash
./scripts/validate-workshop.sh
# Or manually:
curl -sk "https://$(oc get route people-backend -o jsonpath='{.spec.host}')/q/health"
```

---

## Module 8 — Red Hat Developer Hub

### Goal

Install Developer Hub (Backstage) with dynamic plugins.

### Commands

```bash
# Operator path (default):
./scripts/install-developer-hub.sh

# Helm path:
./scripts/install-developer-hub-helm.sh
```

### What happens

| Resource | File |
|----------|------|
| Backstage CR | [`manifests/gitops/developer-hub/backstage-cr.yaml`](../../manifests/gitops/developer-hub/backstage-cr.yaml) |
| Helm values (alternative) | [`manifests/helm/rhdh-values.yaml`](../../manifests/helm/rhdh-values.yaml) |

Creates route `redhat-developer-hub`, PostgreSQL for Backstage, dynamic plugin installer init container.

### Why

Central developer portal for catalog, docs, templates, K8s/Topology, and Orchestrator.

### Pros and cons

| Pros | Cons |
|------|------|
| Full RHDH plugin stack | Heavy pod (plugins init + backend) |
| OIDC via Keycloak | RHDH PostgreSQL may scale to 0 in shared sandboxes |

### Customize

| Setting | File |
|---------|------|
| Instance name | [`scripts/workshop.env`](../../scripts/workshop.env) → `RHDH_INSTANCE_NAME`, `RHDH_NAMESPACE` |
| Backstage CR spec | [`manifests/gitops/developer-hub/backstage-cr.yaml`](../../manifests/gitops/developer-hub/backstage-cr.yaml) |

---

## Module 9 — Developer Hub configuration

### Goal

Wire OIDC, Kubernetes plugin, dynamic plugins, app-config, secrets, and Egyptian theme.

### Commands

```bash
./scripts/setup-developer-hub-kubernetes.sh
./scripts/setup-developer-hub-config.sh
```

### What happens

| Concern | File(s) |
|---------|---------|
| **App config** (OIDC, catalog, Argo CD, Tech Radar, Orchestrator, proxy) | [`manifests/gitops/developer-hub/app-config-rhdh.yaml`](../../manifests/gitops/developer-hub/app-config-rhdh.yaml) |
| **Dynamic plugins** (K8s, Topology, Tech Radar, GitHub, Orchestrator, notifications) | [`manifests/gitops/developer-hub/dynamic-plugins-rhdh.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-rhdh.yaml) |
| **Secrets** template | [`manifests/gitops/developer-hub/app-secrets-rhdh.yaml`](../../manifests/gitops/developer-hub/app-secrets-rhdh.yaml) |
| **Egyptian theme** (colors, typography, page headers) | [`manifests/gitops/developer-hub/egyptian-theme.yaml`](../../manifests/gitops/developer-hub/egyptian-theme.yaml) |
| **Logos** (SVG → base64 at deploy) | [`manifests/gitops/developer-hub/branding/`](../../manifests/gitops/developer-hub/branding/) |
| **K8s RBAC** for Topology | [`scripts/setup-developer-hub-kubernetes.sh`](../../scripts/setup-developer-hub-kubernetes.sh) |
| **Rendering / merge** | [`scripts/setup-developer-hub-config.sh`](../../scripts/setup-developer-hub-config.sh) |

Rendered into ConfigMaps `redhat-developer-hub-app-config` and `redhat-developer-hub-dynamic-plugins`.

### Why

Developer Hub reads config at startup; SSO and plugin mount points must match your cluster routes and secrets.

### Pros and cons

| Pros | Cons |
|------|------|
| GitOps-friendly config in repo | Pod restart required after changes |
| Theme without custom CSS | Large app-config blob |

### Customize

| What to change | File |
|----------------|------|
| Browser title | `RHDH_APP_TITLE` in [`scripts/workshop.env`](../../scripts/workshop.env) |
| OIDC client | `RHDH_KEYCLOAK_*` in workshop.env + Keycloak realm JSON |
| Enable/disable plugins | [`dynamic-plugins-rhdh.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-rhdh.yaml) |
| Orchestrator Data Index URL | `app-config-rhdh.yaml` → `orchestrator.dataIndexService.url` |
| Light/dark palette | [`egyptian-theme.yaml`](../../manifests/gitops/developer-hub/egyptian-theme.yaml) |
| Sidebar logos | [`branding/*.svg`](../../manifests/gitops/developer-hub/branding/) |

[RHDH branding docs](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.9/html/customizing_red_hat_developer_hub/customize-rhdh-theme-and-branding_customizing-rhdh)

### Verify

```bash
oc get configmap redhat-developer-hub-app-config -o yaml | grep -E 'title:|orchestrator:|techRadar:'
curl -sk -o /dev/null -w "%{http_code}\n" "https://$(oc get route redhat-developer-hub -o jsonpath='{.spec.host}')/api/auth/oidc/start"
# Expect 302 redirect to Keycloak
```

---

## Module 10 — Catalog, integrations & theme

### Goal

Register catalog entities, organization model, Tech Radar, Learning Paths, TechDocs, and GitHub/Argo CD annotations.

### Commands

```bash
./scripts/configure-developer-hub-catalog.sh
./scripts/setup-developer-hub-techdocs.sh
```

### What happens

| Asset | Source file |
|-------|-------------|
| Catalog entities (inline) | [`manifests/gitops/developer-hub/catalog-configmap.yaml`](../../manifests/gitops/developer-hub/catalog-configmap.yaml) |
| Organization model (3 teams, 8 users, 2 platforms, 4 apps, Kafka) | [`manifests/gitops/catalog/entities/organization-model.yaml`](../../manifests/gitops/catalog/entities/organization-model.yaml) |
| Entity diagram (Mermaid) | [`manifests/gitops/catalog/diagrams/organization-entity-diagram.md`](../../manifests/gitops/catalog/diagrams/organization-entity-diagram.md) |
| People Service entity | [`manifests/gitops/catalog/entities/people-service.yaml`](../../manifests/gitops/catalog/entities/people-service.yaml) |
| People REST API entity | [`manifests/gitops/catalog/entities/people-api.yaml`](../../manifests/gitops/catalog/entities/people-api.yaml) |
| TechDocs entities | [`quarkus-workshop-guide.yaml`](../../manifests/gitops/catalog/entities/quarkus-workshop-guide.yaml), [`platform-architecture-records.yaml`](../../manifests/gitops/catalog/entities/platform-architecture-records.yaml) |
| Scaffolder template | [`manifests/gitops/catalog/templates/quarkus-react-postgres-template.yaml`](../../manifests/gitops/catalog/templates/quarkus-react-postgres-template.yaml) |
| Tech Radar data | [`manifests/gitops/catalog/tech-radar.json`](../../manifests/gitops/catalog/tech-radar.json) |
| Learning paths | [`manifests/gitops/developer-hub/learning-paths.json`](../../manifests/gitops/developer-hub/learning-paths.json) |
| Catalog server deployment | [`manifests/gitops/developer-hub/catalog-server.yaml`](../../manifests/gitops/developer-hub/catalog-server.yaml) |
| TechDocs content | [`manifests/gitops/techdocs/`](../../manifests/gitops/techdocs/) |
| Git-hosted catalog Location | [`manifests/gitops/catalog/all.yaml`](../../manifests/gitops/catalog/all.yaml) |

[`configure-developer-hub-catalog.sh`](../../scripts/configure-developer-hub-catalog.sh) builds ConfigMap `workshop-catalog-entities` (org model first, then workshop entities) and restarts Developer Hub.

### Organization model summary

| Entity | Count |
|--------|------:|
| Organization | 1 — Nile Digital |
| Teams | 3 — Platform, Product, Data & Integration |
| Users | 8 |
| Platforms (Systems) | 2 — People Platform, Integration Platform |
| Applications | 4 — People, Billing, Inventory, Order Processor (Kafka) |
| PostgreSQL | 1 shared cluster |
| Keycloak | 1 — secures all apps |
| Kafka | 1 cluster + topics `person-events`, `order-events` |

Full diagram: [organization-entity-diagram.md](../../manifests/gitops/catalog/diagrams/organization-entity-diagram.md)

### Why

Developer Hub value is in **catalog graph**, docs, templates, and integrations — not just installing the pod.

### Pros and cons

| Pros | Cons |
|------|------|
| Rich demo in one namespace | Large ConfigMap (entity size limits) |
| Org model teaches Backstage kinds | Synthetic apps (Billing/Inventory) are catalog-only |

### Customize

| Integration | Annotation / file |
|-------------|-------------------|
| GitHub CI/Issues/PRs | `github.com/project-slug`, `backstage.io/source-location` on entities |
| Argo CD CD tab | `argocd/app-name` on `people-service` |
| Kubernetes tab | `backstage.io/kubernetes-id`, `backstage.io/kubernetes-namespace` |
| TechDocs | `backstage.io/techdocs-ref` + content under `manifests/gitops/techdocs/` |
| Orchestrator Workflows tab | `orchestrator.io/workflows: '["create-person"]'` (JSON array string) |
| Tech Radar entries | [`tech-radar.json`](../../manifests/gitops/catalog/tech-radar.json) |
| Learning paths | [`learning-paths.json`](../../manifests/gitops/developer-hub/learning-paths.json) |

### Verify

```bash
CATALOG=$(oc get route workshop-catalog-server -o jsonpath='{.spec.host}')
curl -sk "https://${CATALOG}/entities.yaml" | head -20
RHDH=$(oc get route redhat-developer-hub -o jsonpath='{.spec.host}')
echo "https://${RHDH}/catalog?filters%5Bkind%5D=component"
echo "https://${RHDH}/tech-radar"
```

---

## Module 11 — Orchestrator workflow

### Goal

Deploy **Create Person in People API** workflow (first name, last name, age → `POST /api/people`).

### Commands

```bash
./scripts/setup-orchestrator.sh

# Optional — full Serverless Logic (cluster admin, once):
./scripts/install-orchestrator-infra.sh
./scripts/setup-orchestrator.sh
```

### What happens

| Component | File |
|-----------|------|
| Workflow definition (SonataFlow YAML) | [`manifests/gitops/orchestrator/create-person.sw.yaml`](../../manifests/gitops/orchestrator/create-person.sw.yaml) |
| Input schema (form fields) | [`manifests/gitops/orchestrator/schemas/create-person.input-schema.json`](../../manifests/gitops/orchestrator/schemas/create-person.input-schema.json) |
| Standalone workflow runtime (FastAPI) | [`apps/create-person-workflow/`](../../apps/create-person-workflow/) |
| OpenShift Deployment/Build | [`manifests/gitops/orchestrator/create-person-workflow.yaml`](../../manifests/gitops/orchestrator/create-person-workflow.yaml) |
| Data Index (standalone fallback) | [`manifests/gitops/orchestrator/data-index.yaml`](../../manifests/gitops/orchestrator/data-index.yaml) |
| Registration in Data Index DB | [`apps/create-person-workflow/register-workflow.sh`](../../apps/create-person-workflow/register-workflow.sh), [`register-create-person-workflow-job.yaml`](../../manifests/gitops/orchestrator/register-create-person-workflow-job.yaml) |
| SonataFlow path (when operator installed) | [`create-person-sonataflow.yaml`](../../manifests/gitops/orchestrator/create-person-sonataflow.yaml) |

Without Serverless Logic operator, script deploys standalone Data Index + Python workflow service and registers `serviceUrl` in PostgreSQL.

### Why

Shows Developer Hub Orchestrator plugin executing a human-in-the-loop workflow against a secured API.

### Pros and cons

| Pros | Cons |
|------|------|
| Works without Serverless Logic operator | Standalone path uses direct DB registration (not event-driven) |
| E2E tested via `/orchestrator` | Entity Workflows tab history queries limited on standalone Data Index |

### Customize

| Setting | File |
|---------|------|
| Workflow input fields | [`create-person.input-schema.json`](../../manifests/gitops/orchestrator/schemas/create-person.input-schema.json) |
| People API + Keycloak env | [`create-person-props-configmap.yaml`](../../manifests/gitops/orchestrator/create-person-props-configmap.yaml) |
| Data Index image (requires `executionSummary`; use `logic-data-index-postgresql-rhel8:1.36.0` or newer) | `ORCHESTRATOR_DATA_INDEX_IMAGE` in [`scripts/workshop.env`](../../scripts/workshop.env) |
| Orchestrator plugin routes | [`dynamic-plugins-rhdh.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-rhdh.yaml) |

### Verify

```bash
# Direct workflow call
oc exec deploy/create-person-workflow -- \
  curl -s -X POST http://localhost:8080/create-person \
  -H 'Content-Type: application/json' \
  -d '{"firstName":"Tutorial","lastName":"Test","age":30}'

# UI: Developer Hub → Orchestrator → "Create Person in People API"
```

---

## Module 12 — Validation & repair

### Goal

Confirm the tutorial end state and recover from common sandbox issues.

### Commands

```bash
./scripts/validate-workshop.sh
./e2e/run-e2e.sh

# After idle sandbox / scaled-to-zero workloads:
./scripts/ensure-workshop-platform.sh
./scripts/repair-people-app.sh
./scripts/repair-developer-hub.sh
./scripts/configure-developer-hub-catalog.sh
./scripts/setup-developer-hub-config.sh
```

### What happens

[`validate-workshop.sh`](../../scripts/validate-workshop.sh) checks health endpoints, OIDC, CRUD, catalog server, and Developer Hub OIDC redirect.

[`e2e/run-e2e.sh`](../../e2e/run-e2e.sh) runs Selenium tests in [`e2e/tests/`](../../e2e/tests/).

### E2E coverage

| Test area | Test file |
|-----------|-----------|
| People API + UI | `test_people_app_api.py`, `test_people_app_ui.py` |
| OpenAPI | `test_openapi_exposure.py` |
| Developer Hub K8s/Topology | `test_developer_hub_topology.py` |
| Catalog, CI, Issues, Tech Radar, Learning Paths, Orchestrator | `test_developer_hub_extensions.py`, `test_developer_hub_catalog.py` |

### Repair quick reference

| Symptom | Script | Doc |
|---------|--------|-----|
| Keycloak / RHDH DB / catalog server down | `ensure-workshop-platform.sh` | [08-validation.md](08-validation.md) |
| People app broken | `repair-people-app.sh` | [04-deploy-people-app.md](04-deploy-people-app.md) |
| Developer Hub 500 / DB | `repair-developer-hub.sh` | [06-install-developer-hub.md](06-install-developer-hub.md) |
| Empty catalog / Tech Radar | `configure-developer-hub-catalog.sh` | [07-developer-hub-catalog.md](07-developer-hub-catalog.md) |
| Orchestrator ENOTFOUND | `setup-orchestrator.sh` | [07-developer-hub-catalog.md](07-developer-hub-catalog.md) |
| GitHub CI authorize fails | `create-github-oauth-app.sh --oauth-app` | [01-prerequisites.md](01-prerequisites.md) |

Full table: [08-validation.md](08-validation.md)

### Cleanup after demo

When the demo is finished and you want an empty namespace for the next run:

```bash
./scripts/cleanup-workshop.sh --dry-run
./scripts/cleanup-workshop.sh --yes
./scripts/bootstrap-workshop.sh
```

See [09-cleanup-after-demo.md](09-cleanup-after-demo.md).

---

## Configuration reference (all customizable files)

Use this index when you need to change one concern without reading the whole tutorial.

### Scripts and environment

| File | Purpose |
|------|---------|
| [`scripts/workshop.env`](../../scripts/workshop.env) | **Start here** — namespace, routes, credentials, install method |
| [`scripts/workshop.env.example`](../../scripts/workshop.env.example) | Template with defaults |
| [`scripts/lib/common.sh`](../../scripts/lib/common.sh) | Shared helpers, `envsubst`, `render_manifest` |
| [`scripts/bootstrap-workshop.sh`](../../scripts/bootstrap-workshop.sh) | Full install orchestration |
| [`scripts/cleanup-workshop.sh`](../../scripts/cleanup-workshop.sh) | Remove demo resources for a fresh start |

### People application

| File | Purpose |
|------|---------|
| [`apps/people-service/backend/`](../../apps/people-service/backend/) | Quarkus API, Flyway, OIDC |
| [`apps/people-service/frontend/`](../../apps/people-service/frontend/) | React UI, nginx, runtime config |
| [`manifests/gitops/people-app/`](../../manifests/gitops/people-app/) | OpenShift manifests |

### Identity

| File | Purpose |
|------|---------|
| [`manifests/gitops/keycloak/`](../../manifests/gitops/keycloak/) | Keycloak deploy + realm |
| [`scripts/configure-keycloak-realm.sh`](../../scripts/configure-keycloak-realm.sh) | Realm/client/user sync |

### GitOps

| File | Purpose |
|------|---------|
| [`manifests/gitops/argocd/`](../../manifests/gitops/argocd/) | Argo CD instance + Application |
| [`manifests/helm/argocd-values.yaml`](../../manifests/helm/argocd-values.yaml) | Helm Argo CD values |

### Developer Hub core

| File | Purpose |
|------|---------|
| [`manifests/gitops/developer-hub/app-config-rhdh.yaml`](../../manifests/gitops/developer-hub/app-config-rhdh.yaml) | OIDC, catalog locations, proxy, orchestrator |
| [`manifests/gitops/developer-hub/dynamic-plugins-rhdh.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-rhdh.yaml) | Plugin packages + mount points |
| [`manifests/gitops/developer-hub/egyptian-theme.yaml`](../../manifests/gitops/developer-hub/egyptian-theme.yaml) | Branding colors and typography |
| [`manifests/gitops/developer-hub/branding/`](../../manifests/gitops/developer-hub/branding/) | SVG logos |
| [`manifests/gitops/developer-hub/backstage-cr.yaml`](../../manifests/gitops/developer-hub/backstage-cr.yaml) | Backstage CR |
| [`manifests/helm/rhdh-values.yaml`](../../manifests/helm/rhdh-values.yaml) | Helm RHDH values |

### Catalog and documentation

| File | Purpose |
|------|---------|
| [`manifests/gitops/catalog/entities/`](../../manifests/gitops/catalog/entities/) | All catalog entities |
| [`manifests/gitops/catalog/diagrams/organization-entity-diagram.md`](../../manifests/gitops/catalog/diagrams/organization-entity-diagram.md) | Org entity diagram |
| [`manifests/gitops/developer-hub/catalog-configmap.yaml`](../../manifests/gitops/developer-hub/catalog-configmap.yaml) | Inline entities for ConfigMap deploy |
| [`manifests/gitops/catalog/tech-radar.json`](../../manifests/gitops/catalog/tech-radar.json) | Tech Radar |
| [`manifests/gitops/techdocs/`](../../manifests/gitops/techdocs/) | TechDocs sites |

### Orchestrator

| File | Purpose |
|------|---------|
| [`manifests/gitops/orchestrator/`](../../manifests/gitops/orchestrator/) | Workflow, Data Index, registration |
| [`apps/create-person-workflow/`](../../apps/create-person-workflow/) | Standalone workflow service |
| [`scripts/setup-orchestrator.sh`](../../scripts/setup-orchestrator.sh) | Deploy + register workflow |

### CI/CD

| File | Purpose |
|------|---------|
| [`.github/workflows/people-service-ci.yaml`](../../.github/workflows/people-service-ci.yaml) | PR/push CI |
| [`.github/workflows/build-and-push.yaml`](../../.github/workflows/build-and-push.yaml) | GHCR images |

### Tests

| File | Purpose |
|------|---------|
| [`e2e/run-e2e.sh`](../../e2e/run-e2e.sh) | E2E runner |
| [`e2e/tests/`](../../e2e/tests/) | Pytest + Selenium tests |
| [`scripts/validate-workshop.sh`](../../scripts/validate-workshop.sh) | HTTP validation |

---

## Re-run checklist after customization

After editing config files, run the minimal scripts for what you changed:

| You changed | Re-run |
|-------------|--------|
| `workshop.env` only | `source scripts/workshop.env` then affected phase scripts |
| People app manifests / app code | `./scripts/deploy-people-app.sh` or `./scripts/repair-people-app.sh` |
| Keycloak realm | `./scripts/configure-keycloak-realm.sh` |
| Developer Hub app-config / plugins / theme | `./scripts/setup-developer-hub-config.sh` |
| Catalog entities / Tech Radar / org model | `./scripts/configure-developer-hub-catalog.sh` |
| TechDocs content | `./scripts/setup-developer-hub-techdocs.sh` |
| Orchestrator | `./scripts/setup-orchestrator.sh` |
| Everything | `./scripts/bootstrap-workshop.sh` (or repair scripts if already installed) |

---

## Tutorial completion checklist

- [ ] Namespace clean and `workshop.env` configured
- [ ] Keycloak route reachable; realm `workshop` imported
- [ ] People UI loads; CRUD works with `user` / `r3dh@t`
- [ ] OpenAPI at `/q/openapi` and `/openapi.yaml`
- [ ] Developer Hub login with `devhub` / `r#dh@t`
- [ ] Catalog lists `people-service`, `people-rest-api`, org teams/users
- [ ] Tech Radar, Learning Paths, TechDocs tabs load
- [ ] Orchestrator shows **Create Person in People API**
- [ ] Egyptian theme visible (gold/lapis sidebar, **Nile Developer Hub** title)
- [ ] `./scripts/validate-workshop.sh` passes
- [ ] Optional: `./e2e/run-e2e.sh` passes

You have reached the **current workshop state**. For day-two operations use [08-validation.md](08-validation.md) and the repair scripts in [Module 12](#module-12--validation--repair).
