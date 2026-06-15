# 6. Install Developer Hub

Deploy a Developer Hub (`Backstage`) instance with dynamic plugins for Kubernetes, Topology, Tech Radar, and Keycloak SSO.

**Developer Hub vs Backstage:** RHDH is Red Hat’s distribution of Backstage. Everything you configure here — `app-config`, dynamic plugins, catalog locations, OIDC — is standard Backstage. Community Backstage on Kubernetes can run the same workshop with equivalent Helm/manifest setup; this repo’s install scripts target OpenShift.

Bootstrap runs this automatically. Manual install:

```bash
./scripts/install-developer-hub.sh    # operator path
./scripts/setup-developer-hub-dynamic-plugins-cache.sh
./scripts/setup-developer-hub-config.sh
./scripts/configure-developer-hub-catalog.sh
```

Helm alternative:

```bash
./scripts/install-developer-hub-helm.sh
./scripts/setup-developer-hub-dynamic-plugins-cache.sh
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
| `dynamic-plugins-rhdh.yaml` | Kubernetes, Topology, Tech Radar, GitHub scaffolder plugins |
| `dynamic-plugins-pvc.yaml` | Persistent volume claim for the dynamic plugins cache |
| `dynamic-plugins-cache-deployment-patch.yaml` | Replaces ephemeral `dynamic-plugins-root` with the PVC |
| `app-secrets-rhdh.yaml` | Secret template for tokens and OIDC client secret |
| `catalog-configmap.yaml` | Inline catalog entities (component, API, template) |
| `catalog-server.yaml` | HTTP server for catalog entities, OpenAPI file, Tech Radar JSON |
| `backstage-cr.yaml` | `Backstage` CR — creates route, mounts config + secrets |

Helm alternative: `manifests/helm/rhdh-values.yaml`

## Dynamic plugins cache (faster restarts)

By default, RHDH mounts `dynamic-plugins-root` as an **ephemeral** volume (`volumeClaimTemplate`). Every pod restart re-runs `install-dynamic-plugins` and re-downloads OCI plugin images (several minutes).

Enable the **persistent plugins cache** once per namespace:

```bash
./scripts/setup-developer-hub-dynamic-plugins-cache.sh
```

This script:

1. Creates PVC `dynamic-plugins-root` (5Gi, `ReadWriteOnce`) from [`dynamic-plugins-pvc.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-pvc.yaml)
2. Patches the `redhat-developer-hub` Deployment to mount that PVC instead of an ephemeral claim
3. Rolls out Developer Hub once

On later restarts, when plugin packages and config checksums are unchanged, `install-dynamic-plugins` skips downloads and startup is much faster.

`setup-developer-hub-config.sh` calls the cache script automatically (without an extra rollout). Config changes still trigger a single pod restart.

### Script options

| Option | Purpose |
|--------|---------|
| *(none)* | Create PVC, patch deployment, roll out once |
| `--no-rollout` | Apply PVC/patch only; used by `setup-developer-hub-config.sh` to avoid a double restart |
| `--force-rollout` | Restart Developer Hub even when the PVC is already mounted |
| `--clear-lock` | Remove a stale `install-dynamic-plugins` lock file on the PVC when the init container hangs on `Waiting for lock release` (common after a crashed or killed pod) |

Clear a stale lock without changing the PVC:

```bash
./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock
```

If the pod is still stuck, delete the Developer Hub pod so it recreates, or run `--clear-lock` again after the new pod is running.

### Troubleshooting the plugins cache

| Symptom | Fix |
|---------|-----|
| Init container stuck on `Waiting for lock release` | `./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock` |
| Force re-download all plugins after config change | Delete PVC `dynamic-plugins-root` (cache rebuilds on next start) |
| Helm install | Run `./scripts/setup-developer-hub-dynamic-plugins-cache.sh` after `helm upgrade` (do not add `extraVolumes` in values — breaks chart volumes) |

See [Red Hat docs: Use the dynamic plugins cache](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.9/html/configuring_red_hat_developer_hub/use-the-dynamic-plugins-cache_configuring-rhdh).

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

Ensure the persistent plugins cache is enabled first (one-time):

```bash
./scripts/setup-developer-hub-dynamic-plugins-cache.sh
```

Without the cache, each restart re-downloads all dynamic plugins.

## Repair Keycloak login failures

If sign-in shows "Application is not available", Keycloak is likely scaled to zero:

```bash
./scripts/repair-keycloak.sh
```

## Next step

[Catalog, template, and integrations](07-developer-hub-catalog.md)
