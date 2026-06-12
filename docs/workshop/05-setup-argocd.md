# 5. Set up OpenShift GitOps (Argo CD)

Create an Argo CD instance and Application that syncs the People Service manifests from Git.

```bash
./scripts/setup-argocd.sh
```

Bootstrap runs this automatically unless `SKIP_ARGOCD=true`.

## Manifests (`manifests/gitops/argocd/`)

| File | Description |
|------|-------------|
| `argocd-instance.yaml` | `ArgoCD` CR named `${ARGOCD_INSTANCE_NAME}` with route enabled, `rhdh` API account |
| `application-people-service.yaml` | Syncs `manifests/gitops/people-app/` from `${WORKSHOP_GIT_REPO}` |

The Argo CD Application excludes `build-*.yaml` so build configs are managed locally during the workshop.

## Argo CD token for Developer Hub

After Argo CD is running:

```bash
./scripts/setup-argocd-token.sh
```

This script:

1. Logs in to Argo CD as `admin`
2. Creates a long-lived API token for account `rhdh`
3. Stores `ARGOCD_URL` and `ARGOCD_TOKEN` in Secret `argo-secrets`

## Verify

```bash
oc get argocd,applications -n $WORKSHOP_NAMESPACE
ARGO_HOST=$(oc get route ${ARGOCD_INSTANCE_NAME}-server -o jsonpath='{.spec.host}')
echo "https://${ARGO_HOST}"
```

The `people-service` Application should show **Synced** / **Healthy** once Git contains the manifests and the repo is reachable from the cluster.

## Developer Hub annotation

The catalog component uses:

```yaml
argocd/app-name: people-service
```

This links the Backstage component to the Argo CD Application for the **CD** tab.
