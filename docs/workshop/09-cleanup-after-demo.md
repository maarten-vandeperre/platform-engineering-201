# Cleanup after the demo

Use this when the workshop or demo is finished and you want a **clean OpenShift namespace** to run `./scripts/bootstrap-workshop.sh` again.

The cleanup script is **idempotent** and **partial-state safe**: if you stopped halfway through the tutorial, only resources that exist are removed.

## Quick start

```bash
# Preview what would be removed
./scripts/cleanup-workshop.sh --dry-run

# Remove all demo workloads (keeps the OpenShift project)
./scripts/cleanup-workshop.sh --yes

# Full reset including PVCs and project deletion
./scripts/cleanup-workshop.sh --yes --delete-namespace
```

Local files such as `scripts/workshop.env` are **not** deleted.

## What gets removed

| Area | Resources |
|------|-----------|
| **GitOps** | Argo CD `Application`, Helm release `argocd`, optional `ArgoCD` CR |
| **Developer Hub** | Helm release `redhat-developer-hub` or `Backstage` CR, dynamic plugin config, PostgreSQL StatefulSet, plugin cache PVC |
| **People Service** | Deployments, routes, builds, imagestreams, postgres PVC |
| **Keycloak** | Deployment, route, secrets, realm ConfigMap |
| **Catalog / TechDocs** | `workshop-catalog-server`, entity ConfigMaps, TechDocs sources |
| **Orchestrator** | Workflow manifests, Data Index, SonataFlow CRs, Helm `orchestrator-infra` |
| **AAP custom plugin** | `aap-management-plugin-server` (when deployed) |
| **RBAC** | `backstage-kubernetes` ServiceAccount and RoleBindings |

## Options

| Flag | Effect |
|------|--------|
| `--dry-run` | Print actions only; exit without changes |
| `--yes` | Skip confirmation prompt |
| `--keep-pvcs` | Leave PVCs in place (database data retained) |
| `--remove-operators` | Delete `Subscription` and `OperatorGroup` in the workshop namespace |
| `--delete-namespace` | Delete the OpenShift project(s) after cleanup |

## Typical flows

### End of a shared demo namespace (recommended)

Keeps the project so you can bootstrap again without requesting a new namespace:

```bash
./scripts/cleanup-workshop.sh --yes
./scripts/bootstrap-workshop.sh
```

### End of a personal sandbox (full wipe)

```bash
./scripts/cleanup-workshop.sh --yes --remove-operators --delete-namespace
cp scripts/workshop.env.example scripts/workshop.env
# edit WORKSHOP_NAMESPACE, CLUSTER_ROUTER_BASE, secrets
oc new-project "${WORKSHOP_NAMESPACE}"
./scripts/bootstrap-workshop.sh
```

### Idle environment (scale-to-zero only)

If workloads were scaled down but not deleted, use the keep-alive script instead:

```bash
./scripts/ensure-workshop-instances.sh
./scripts/repair-people-app.sh   # if People Service still returns 503
```

Cleanup is **not** required for idle scale-to-zero; repair scales instances back up.

## Verification

After cleanup (without `--delete-namespace`):

```bash
oc get deploy,statefulset,svc,route,pvc,buildconfig,imagestream,pod -n "${WORKSHOP_NAMESPACE}"
```

The namespace should contain no People Service, Keycloak, Developer Hub, or catalog workloads. Some cluster-scoped operator CSVs may remain until `--remove-operators` is used.

## Related scripts

| Script | Purpose |
|--------|---------|
| [`cleanup-workshop.sh`](../../scripts/cleanup-workshop.sh) | Delete demo resources |
| [`ensure-workshop-instances.sh`](../../scripts/ensure-workshop-instances.sh) | Scale idle workloads back up |
| [`bootstrap-workshop.sh`](../../scripts/bootstrap-workshop.sh) | Fresh install |

## Troubleshooting

| Issue | Action |
|-------|--------|
| Backstage CR stuck terminating | Re-run cleanup; finalizers are cleared automatically |
| Helm uninstall hangs | Check `oc get pods -n ${RHDH_NAMESPACE}`; delete stuck pods, retry |
| PVC `Terminating` | Ensure no pod still mounts the volume; `oc delete pod --all -n <ns>` |
| Operators still installed | Re-run with `--remove-operators` (requires permission to delete Subscriptions) |
