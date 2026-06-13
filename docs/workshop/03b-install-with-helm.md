# 3b. Install with Helm (no operators)

If you **cannot install operators** (Forbidden on `OperatorGroup` / `Subscription`), use Helm instead. This is a supported path for both products.

## Overview

| Component | Helm chart | Operator required? |
|-----------|------------|--------------------|
| **Argo CD** | [argo/argo-cd](https://github.com/argoproj/argo-helm) | No |
| **Red Hat Developer Hub** | [redhat-developer-hub](https://charts.openshift.io/) | No |

Both install into **your namespace** using normal Deployments, Routes, and Secrets — permissions you already have.

## Option A: OpenShift Developer Console (easiest)

1. Switch to **Developer** perspective
2. Click **+Add** → **Helm Chart**
3. Search for **Red Hat Developer Hub** or add repo `https://charts.openshift.io/`
4. Select your namespace (`rh-ee-mvandepe-dev` or your `WORKSHOP_NAMESPACE`)
5. In **YAML view**, set:
   - `global.clusterRouterBase` → your cluster domain (e.g. `apps.rm1.0a51.p1.openshiftapps.com`)
   - Guest auth under `upstream.backstage.appConfig.auth.providers.guest`
6. Click **Create**

For Argo CD, add Helm repo `https://argoproj.github.io/argo-helm`, chart `argo-cd`, and set:

```yaml
openshift:
  enabled: true
server:
  route:
    enabled: true
```

## Option B: Helm CLI scripts

Set install method and run bootstrap (recommended):

```bash
export WORKSHOP_INSTALL_METHOD=helm
export CLUSTER_ROUTER_BASE=apps.your-cluster.example.com
./scripts/bootstrap-workshop.sh
```

Or run steps individually:

```bash
# 1. Keycloak + People app first (Helm RHDH needs KEYCLOAK_URL)
./scripts/setup-keycloak.sh
./scripts/deploy-people-app.sh

# 2. Argo CD
./scripts/install-argocd-helm.sh

# 3. Argo CD token for Developer Hub
./scripts/setup-argocd-token.sh

# 4. Developer Hub
export GITHUB_TOKEN=ghp_...       # scaffolder publish — run ./scripts/setup-github-auth.sh
./scripts/install-developer-hub-helm.sh
./scripts/setup-developer-hub-config.sh
./scripts/configure-developer-hub-catalog.sh
```

Values templates live in `manifests/helm/`.

## Argo CD CRD caveat

The Argo CD Helm chart creates **CustomResourceDefinitions** (`applications.argoproj.io`, etc.). On many shared clusters, only a **cluster admin** can create CRDs **once**.

If `./scripts/install-argocd-helm.sh` fails with Forbidden on CRDs:

1. Ask an admin to install CRDs once:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm template argocd argo/argo-cd --set crds.install=true --set server.service.type=ClusterIP \
  | oc apply -f -
```

2. Then retry with CRD install disabled:

```bash
ARGOCD_INSTALL_CRDS=false ./scripts/install-argocd-helm.sh
```

If CRDs cannot be installed at all, skip Argo CD and still use Developer Hub for catalog, Kubernetes, GitHub Actions, and the scaffolder template. The **CD tab** requires Argo CD.

## Developer Hub without Argo CD

You can run the workshop without Argo CD:

```bash
./scripts/install-developer-hub-helm.sh
```

You still get:

- Catalog component for `people-service`
- Kubernetes tab (deployments/routes in your namespace)
- GitHub Actions tab (with `GITHUB_TOKEN`)
- Scaffolder template

## Configuration

Add to `scripts/workshop.env`:

```bash
export CLUSTER_ROUTER_BASE=apps.rm1.0a51.p1.openshiftapps.com
export ARGOCD_ROUTE_HOST=argocd-rh-ee-mvandepe-dev.apps.rm1.0a51.p1.openshiftapps.com
export ARGOCD_INSTALL_CRDS=false   # after admin pre-installs CRDs
```

## Compare: Operator vs Helm

| | Operator | Helm |
|---|----------|------|
| Permissions | Needs OLM / OperatorGroup | Namespace Deploy/Route/Secret |
| Upgrades | Subscription channel | `helm upgrade` |
| RHDH config | Backstage CR + ConfigMaps | `values.yaml` |
| Argo CD | ArgoCD CR | `argo/argo-cd` chart |
| Workshop scripts | `install-operators.sh` | `install-*-helm.sh` |

## Next steps

- [Set up Argo CD Application](05-setup-argocd.md) — works with Helm-installed Argo CD
- [Catalog and integrations](07-developer-hub-catalog.md)
