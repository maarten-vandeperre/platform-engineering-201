# 6. Install Developer Hub

Deploy a Developer Hub (`Backstage`) instance with dynamic plugins for Argo CD, GitHub Actions, and Kubernetes, secured with **Keycloak SSO**.

```bash
./scripts/install-developer-hub.sh    # operator or Helm install
./scripts/setup-developer-hub-config.sh
```

If Argo CD is ready, run the token script first:

```bash
./scripts/setup-argocd-token.sh
./scripts/setup-developer-hub-config.sh
```

## Manifests (`manifests/gitops/developer-hub/`)

| File | Description |
|------|-------------|
| `app-config-rhdh.yaml` | Backstage configuration: Keycloak OIDC, catalog, Argo CD, Kubernetes, GitHub proxy |
| `dynamic-plugins-rhdh.yaml` | Enables Kubernetes, Topology, and other workshop plugins |
| `app-secrets-rhdh.yaml` | Secret template for tokens and OIDC client secret |
| `catalog-configmap.yaml` | Inline catalog entities and software template |
| `backstage-cr.yaml` | `Backstage` CR — creates route, mounts config + secrets |

Helm alternative: `manifests/helm/rhdh-values.yaml`

## Authentication (Keycloak)

Developer Hub uses the shared Keycloak `workshop` realm:

| Variable | Default | Description |
|----------|---------|-------------|
| `RHDH_KEYCLOAK_CLIENT_ID` | `developer-hub` | Confidential OIDC client in Keycloak |
| `RHDH_KEYCLOAK_CLIENT_SECRET` | `developer-hub-workshop-secret` | Client secret (also exported as `RHDH_OIDC_CLIENT_SECRET`) |
| `RHDH_KEYCLOAK_USER` | `devhub` | Workshop Developer Hub login |
| `RHDH_KEYCLOAK_PASSWORD` | `r#dh@t` | Workshop Developer Hub password |

`setup-developer-hub-config.sh`:

1. Ensures the `developer-hub` client and `devhub` user exist in Keycloak
2. Configures Kubernetes/Topology cluster access (`setup-developer-hub-kubernetes.sh`)
3. Patches the Developer Hub app-config with OIDC provider settings
4. Enables the Kubernetes and Topology dynamic plugins
5. Mounts `RHDH_OIDC_CLIENT_SECRET` into the backend pod
6. Restarts Developer Hub

Example app-config excerpt:

```yaml
auth:
  environment: production
  providers:
    oidc:
      production:
        metadataUrl: https://<keycloak-route>/realms/workshop/.well-known/openid-configuration
        clientId: developer-hub
        clientSecret: ${RHDH_OIDC_CLIENT_SECRET}
```

Set the default sign-in provider so the login page shows Keycloak instead of GitHub:

```yaml
signInPage: oidc
```

## Access Developer Hub

```bash
RHDH_HOST=$(oc get route redhat-developer-hub -o jsonpath='{.spec.host}')
echo "https://${RHDH_HOST}"
```

Sign in with Keycloak user **`devhub` / `r#dh@t`**.

> **Important:** The password uses a **`#`** (hash), not **`3`**.  
> `r#dh@t` is correct — `r3dh@t` will fail (that password is for `admin` and `user`).

## TLS note

`NODE_TLS_REJECT_UNAUTHORIZED=0` is set on the Backstage CR for PoC clusters with self-signed certificates. Remove for production.

## Restart after config changes

```bash
./scripts/setup-developer-hub-config.sh
```
