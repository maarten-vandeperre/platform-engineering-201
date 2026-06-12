# 3. Install operators

Install **OpenShift GitOps** and **Red Hat Developer Hub** operators in your namespace.

```bash
./scripts/install-operators.sh
```

Or run the full bootstrap (includes this step):

```bash
./scripts/bootstrap-workshop.sh
```

## Manifests applied

| File | Description |
|------|-------------|
| `manifests/gitops/operators/operatorgroup.yaml` | Targets operator installation to `${WORKSHOP_NAMESPACE}` |
| `manifests/gitops/operators/subscription-gitops.yaml` | Subscribes to `openshift-gitops-operator` |
| `manifests/gitops/operators/subscription-rhdh.yaml` | Subscribes to `rhdh` (Developer Hub) |

## Verify

```bash
oc get subscription,csv -n $WORKSHOP_NAMESPACE
```

Wait until both CSVs show `Succeeded`:

```bash
watch oc get csv -n $WORKSHOP_NAMESPACE
```

Operator installation can take 5–10 minutes.

## Why a script?

Operator Subscriptions require the Operator Lifecycle Manager (OLM). While subscriptions are declarative YAML, waiting for CSV readiness and handling first-time install order is easier with a script than pure GitOps sync.

After operators are installed, GitOps manages application workloads.

## Operator permissions

Installing operators requires permission to create `OperatorGroup` and `Subscription` resources. If `./scripts/install-operators.sh` fails with **Forbidden**, ask your cluster administrator to install:

- **Red Hat OpenShift GitOps** operator
- **Red Hat Developer Hub** operator

Alternatively, install them from **OperatorHub** in the OpenShift Console (Administrator perspective).

Once operators are available, continue with [Set up Argo CD](05-setup-argocd.md) and [Install Developer Hub](06-install-developer-hub.md).
