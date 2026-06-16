# 8. Validation and troubleshooting

## Automated validation

```bash
./scripts/validate-workshop.sh
```

Expected output:

- Backend health JSON with `"status": "UP"` (database check included)
- Keycloak pod ready and realm reachable
- Keycloak token obtained for user `user`
- HTTP 401 on unauthenticated API call (when OIDC enabled)
- Created person JSON with `id`, `firstName`, `lastName`, `age`
- HTTP 204 on delete
- HTTP 200 on frontend `/`
- OpenAPI reachable at backend `/q/openapi` and frontend `/openapi.yaml`
- Catalog server serves `entities.yaml` and `tech-radar.json`
- Keycloak token for Developer Hub user `devhub`
- HTTP 302 on Developer Hub OIDC start (redirect to Keycloak)
- OpenShift resources labeled `app.kubernetes.io/part-of=people-service`

## End-to-end tests

Requires Python 3.9+ and Google Chrome:

```bash
./e2e/run-e2e.sh
```

Tests cover:

1. Keycloak reachability and OIDC client registration
2. Backend/database health and People API CRUD
3. Frontend login, runtime config, and UI CRUD
4. OpenAPI exposure (backend, frontend, catalog server)
5. Developer Hub Kubernetes and Topology tabs
6. Developer Hub API catalog listing (`People REST API`)
7. Developer Hub **CI** tab on the People REST API entity (GitHub Actions plugin)
8. Developer Hub **Issues** and **Pull Requests** tabs on the People Service entity (GitHub plugins)
9. Developer Hub Tech Radar page
10. Developer Hub **Documentation** tabs (Quarkus guide + ADR site)
11. Developer Hub **Learning Paths** (developers.redhat.com tutorials)
12. Developer Hub **Orchestrator** (`create-person` workflow)

Run with visible browser:

```bash
E2E_HEADLESS=false ./e2e/run-e2e.sh
```

## Manual checks

### OpenShift resources

```bash
oc get deploy,svc,route,pvc,pod -n $WORKSHOP_NAMESPACE -l app.kubernetes.io/part-of=people-service
oc get deploy,pod -n $WORKSHOP_NAMESPACE -l app=keycloak
oc get deploy,pod -n $WORKSHOP_NAMESPACE -l app=workshop-catalog-server
```

### OpenAPI

```bash
BACKEND=$(oc get route people-backend -o jsonpath='{.spec.host}')
FRONTEND=$(oc get route people-frontend -o jsonpath='{.spec.host}')
curl -sk "https://${BACKEND}/q/openapi" | head -5
curl -sk -o /dev/null -w "HTTP %{http_code}\n" "https://${FRONTEND}/openapi.yaml"
```

### Developer Hub

```bash
RHDH_HOST=$(oc get route redhat-developer-hub -o jsonpath='{.spec.host}')
echo "https://${RHDH_HOST}/catalog?filters%5Bkind%5D=api"
echo "https://${RHDH_HOST}/tech-radar"
```

Sign in as **`devhub` / `r#dh@t`**.

### API CRUD (with Keycloak)

See [04-deploy-people-app](04-deploy-people-app.md) or run `./scripts/validate-workshop.sh`.

## Repair scripts

| Symptom | Script |
|---------|--------|
| Keycloak / RHDH PostgreSQL / catalog server scaled to 0 | `./scripts/ensure-workshop-platform.sh` |
| Keycloak "Application is not available" / scaled to 0 | `./scripts/ensure-workshop-platform.sh` or `./scripts/repair-keycloak.sh` |
| PostgreSQL crash-loop / backend not ready | `./scripts/repair-people-app.sh` |
| API catalog or Tech Radar empty | `./scripts/configure-developer-hub-catalog.sh` |
| Developer Hub login/K8s/API issues | `./scripts/setup-developer-hub-config.sh` |
| GitHub Actions CI tab / Authorize GitHub (first time) | `./scripts/create-github-oauth-app.sh --oauth-app` |
| Re-apply GitHub OAuth + PAT to Developer Hub | `./scripts/setup-github-auth.sh` |
| Developer Hub login 500 / `ECONNREFUSED :5432` | `./scripts/repair-developer-hub.sh` (RHDH PostgreSQL scaled to 0) |
| TechDocs tab empty / build failed | `./scripts/setup-developer-hub-techdocs.sh` then `./scripts/setup-developer-hub-config.sh` |
| Learning Paths empty | Re-run `./scripts/configure-developer-hub-catalog.sh` |
| Orchestrator `FieldUndefined executionSummary` on All runs | Upgrade Data Index: `./scripts/setup-orchestrator.sh` (uses `registry.redhat.io/.../logic-data-index-postgresql-rhel8:1.36.0` + `QUARKUS_FLYWAY_OUT_OF_ORDER=true`) |
| Orchestrator `ENOTFOUND sonataflow-platform-data-index-service` | `./scripts/setup-orchestrator.sh` (deploys standalone Data Index) |
| Orchestrator empty / workflow missing | `./scripts/install-orchestrator-infra.sh` then `./scripts/setup-orchestrator.sh` |
| Full stack after idle namespace | `./scripts/ensure-workshop-platform.sh` then `./scripts/repair-people-app.sh` and `./e2e/run-e2e.sh` |

Reset PostgreSQL data (destructive):

```bash
REPAIR_RESET_POSTGRES_DATA=true ./scripts/repair-people-app.sh
```

## Common issues

| Symptom | Fix |
|---------|-----|
| Bootstrap fails on operators | Use `WORKSHOP_INSTALL_METHOD=helm` or ask admin to install operators |
| Helm `another operation is in progress` | Re-run `./scripts/install-developer-hub-helm.sh` (auto-unlocks), or `helm rollback redhat-developer-hub <rev> -n $WORKSHOP_NAMESPACE` |
| Helm `connection refused` / `unexpected EOF` during `--wait` | API blip or sandbox idle — `oc login` again, then resume with `./scripts/install-developer-hub-helm.sh` |
| Keycloak login popup shows OpenShift 503 | `./scripts/ensure-workshop-platform.sh` |
| Backend `CrashLoopBackOff` | `./scripts/repair-people-app.sh` — check postgres logs |
| Frontend `${KEYCLOAK_URL}` placeholders / 414 login URL | `./scripts/repair-people-app.sh` (rebuilds frontend, applies runtime ConfigMap) |
| Image pull error for GHCR | Use OpenShift builds (default) or add `imagePullSecrets` |
| Argo CD 403 in Developer Hub | `./scripts/setup-argocd-token.sh` |
| GitHub Actions tab empty | Set valid `GITHUB_TOKEN` in secrets |
| Scaffolder Fetch skeleton 401 on `api.github.com` | Re-run `./scripts/configure-developer-hub-catalog.sh` (skeleton is served from catalog server) |
| Scaffolder Publish to GitHub 401 | Run `./scripts/setup-github-auth.sh` with a PAT that has `repo` scope |
| Scaffolder `No token available for host: github.com` | Run `./scripts/setup-github-auth.sh` (PAT missing from cluster app-config) |
| Scaffolder `publish:github` not registered | Enable `backstage-plugin-scaffolder-backend-module-github-dynamic` in `dynamic-plugins-rhdh.yaml`, run `./scripts/setup-developer-hub-config.sh` |
| Developer Hub restart very slow | Run once: `./scripts/setup-developer-hub-dynamic-plugins-cache.sh` (persistent PVC for `dynamic-plugins-root`) |
| `install-dynamic-plugins` stuck on `Waiting for lock release` | `./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock` (removes stale lock on PVC; see [06-install-developer-hub.md](06-install-developer-hub.md#script-options)) |
| GitHub Actions Authorize popup 404 (`client_id=changeme`) | `./scripts/create-github-oauth-app.sh --oauth-app` |
| GitHub Actions "Unknown auth provider github" | `./scripts/create-github-oauth-app.sh --oauth-app` then `./scripts/setup-developer-hub-config.sh` |
| Lost OAuth client secret | Regenerate in GitHub app settings, update `workshop.env`, run `./scripts/setup-github-auth.sh --oauth-only` |
| Developer Hub login 500 (`ECONNREFUSED :5432`) | `./scripts/repair-developer-hub.sh` |
| Catalog entity missing | `./scripts/configure-developer-hub-catalog.sh` |
| Catalog server `ProgressDeadlineExceeded` / `ReplicaFailure` | Fixed in manifest (removed hardcoded `runAsUser`); run `./scripts/configure-developer-hub-catalog.sh` |
| API returns 401/403 | Obtain Keycloak token; user must have `people-crud` role |
| Wrong cluster URLs | Set `CLUSTER_ROUTER_BASE` in `workshop.env` and re-run config scripts |
| No Lightspeed chat button | `LIGHTSPEED_ENABLED=true`, valid `OPENAI_API_KEY`, `./scripts/setup-developer-hub-lightspeed.sh` |
| Lightspeed chat errors | Check `oc logs deploy/redhat-developer-hub -c llama-stack`; verify OpenAI key and model |
| No Ansible sidebar / `Init:CrashLoopBackOff` | `AAP_ENABLED=true`, `RH_REGISTRY_USERNAME`/`RH_REGISTRY_TOKEN`, `./scripts/setup-developer-hub-aap.sh` — [06c-ansible-automation-platform.md](06c-ansible-automation-platform.md) |
| Ansible page empty / Controller errors | Verify `AAP_CONTROLLER_URL` and `AAP_TOKEN` (Controller PAT, not admin password) |

## Clean up

```bash
oc delete application people-service -n $WORKSHOP_NAMESPACE --ignore-not-found
oc delete argocd workshop-gitops -n $WORKSHOP_NAMESPACE --ignore-not-found
oc delete backstage developer-hub -n $WORKSHOP_NAMESPACE --ignore-not-found
oc delete deployment,svc,route,bc,is,pvc,secret -l app.kubernetes.io/part-of=people-service -n $WORKSHOP_NAMESPACE
oc delete deploy,svc,route keycloak workshop-catalog-server -n $WORKSHOP_NAMESPACE --ignore-not-found
```

To remove operators, delete Subscriptions and CSVs (may require admin).
