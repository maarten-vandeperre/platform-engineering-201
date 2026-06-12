# 6. Install Developer Hub

Deploy a Developer Hub (`Backstage`) instance with dynamic plugins for Kubernetes, Topology, Tech Radar, and Keycloak SSO.

Bootstrap runs this automatically. Manual install:

```bash
./scripts/install-developer-hub.sh    # operator path
./scripts/setup-developer-hub-config.sh
./scripts/configure-developer-hub-catalog.sh
```

Helm alternative:

```bash
./scripts/install-developer-hub-helm.sh
./scripts/setup-developer-hub-config.sh
./scripts/configure-developer-hub-catalog.sh
```

If Argo CD is ready, configure its token before or after RHDH config:

```bash
./scripts/setup-argocd-token.sh
./scripts/setup-developer-hub-config.sh
```

## Manifests (`manifests/gitops/developer-hub/`)

| File | Description |
|------|-------------|
| `app-config-rhdh.yaml` | OIDC, catalog locations, Argo CD, Kubernetes, Tech Radar |
| `dynamic-plugins-rhdh.yaml` | Kubernetes, Topology, Tech Radar plugins |
| `app-secrets-rhdh.yaml` | Secret template for tokens and OIDC client secret |
| `catalog-configmap.yaml` | Inline catalog entities (component, API, template) |
| `catalog-server.yaml` | HTTP server for catalog entities, OpenAPI file, Tech Radar JSON |
| `backstage-cr.yaml` | `Backstage` CR — creates route, mounts config + secrets |

Helm alternative: `manifests/helm/rhdh-values.yaml`

## Authentication (Keycloak)

Developer Hub uses the shared Keycloak `workshop` realm:

| Variable | Default | Description |
|----------|---------|-------------|
| `RHDH_KEYCLOAK_CLIENT_ID` | `developer-hub` | Confidential OIDC client in Keycloak |
| `RHDH_KEYCLOAK_CLIENT_SECRET` | `developer-hub-workshop-secret` | Client secret |
| `RHDH_KEYCLOAK_USER` | `devhub` | Workshop Developer Hub login |
| `RHDH_KEYCLOAK_PASSWORD` | `r#dh@t` | Workshop Developer Hub password |

`setup-developer-hub-config.sh`:

1. Ensures the `developer-hub` client and `devhub` user exist in Keycloak
2. Configures Kubernetes/Topology cluster access (`setup-developer-hub-kubernetes.sh`)
3. Patches Developer Hub app-config with OIDC provider settings
4. Enables Kubernetes, Topology, and Tech Radar dynamic plugins
5. Mounts `RHDH_OIDC_CLIENT_SECRET` into the backend pod
6. Restarts Developer Hub

## Catalog, OpenAPI, and Tech Radar

After install, run:

```bash
./scripts/configure-developer-hub-catalog.sh
```

This deploys the **workshop catalog server** (serves entities, OpenAPI, Tech Radar data) and registers the **People REST API** in the catalog. See [07-developer-hub-catalog](07-developer-hub-catalog.md).

## Access Developer Hub

```bash
RHDH_HOST=$(oc get route redhat-developer-hub -o jsonpath='{.spec.host}')
echo "https://${RHDH_HOST}"
echo "APIs:    https://${RHDH_HOST}/catalog?filters%5Bkind%5D=api"
echo "Radar:   https://${RHDH_HOST}/tech-radar"
```

Sign in with Keycloak user **`devhub` / `r#dh@t`**.

> **Important:** The password uses a **`#`** (hash), not **`3`**.  
> `r#dh@t` is correct — `r3dh@t` will fail (that password is for `admin` and `user`).

## TLS note

`NODE_TLS_REJECT_UNAUTHORIZED=0` is set on the Backstage CR for PoC clusters with self-signed certificates. Remove for production.

## Restart after config changes

```bash
./scripts/setup-developer-hub-config.sh
./scripts/configure-developer-hub-catalog.sh
```

## Repair Keycloak login failures

If sign-in shows "Application is not available", Keycloak is likely scaled to zero:

```bash
./scripts/repair-keycloak.sh
```

## Next step

[Catalog, template, and integrations](07-developer-hub-catalog.md)
