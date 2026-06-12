#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

require_oc

echo "Configuring Kubernetes and Topology plugin access for Developer Hub in ${RHDH_NAMESPACE}..."

oc create sa backstage-kubernetes -n "${RHDH_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: backstage-kubernetes-read
  namespace: ${RHDH_NAMESPACE}
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - configmaps
      - events
      - limitranges
      - resourcequotas
      - replicationcontrollers
    verbs: [get, list, watch]
  - apiGroups: ["apps"]
    resources: [deployments, replicasets, statefulsets, daemonsets]
    verbs: [get, list, watch]
  - apiGroups: ["autoscaling"]
    resources: [horizontalpodautoscalers]
    verbs: [get, list, watch]
  - apiGroups: ["networking.k8s.io"]
    resources: [ingresses]
    verbs: [get, list, watch]
  - apiGroups: ["batch"]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch]
  - apiGroups: ["route.openshift.io"]
    resources: [routes]
    verbs: [get, list, watch]
  - apiGroups: ["metrics.k8s.io"]
    resources: [pods, nodes]
    verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: backstage-kubernetes-read
  namespace: ${RHDH_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: backstage-kubernetes-read
subjects:
  - kind: ServiceAccount
    name: backstage-kubernetes
    namespace: ${RHDH_NAMESPACE}
EOF

oc create rolebinding backstage-kubernetes-view \
  --clusterrole=view \
  --serviceaccount="${RHDH_NAMESPACE}:backstage-kubernetes" \
  -n "${RHDH_NAMESPACE}" \
  --dry-run=client -o yaml | oc apply -f -

TOKEN=$(oc create token backstage-kubernetes -n "${RHDH_NAMESPACE}" --duration=8760h)

oc create secret generic backstage-kubernetes-token -n "${RHDH_NAMESPACE}" \
  --from-literal=K8S_CLUSTER_TOKEN="${TOKEN}" \
  --from-literal=token="${TOKEN}" \
  --dry-run=client -o yaml | oc apply -f -

TARGET_NS="${WORKSHOP_NAMESPACE:-${RHDH_NAMESPACE}}"
if [[ "${TARGET_NS}" != "${RHDH_NAMESPACE}" ]]; then
  cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: backstage-kubernetes-read
  namespace: ${TARGET_NS}
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - configmaps
      - events
      - limitranges
      - resourcequotas
      - replicationcontrollers
    verbs: [get, list, watch]
  - apiGroups: ["apps"]
    resources: [deployments, replicasets, statefulsets, daemonsets]
    verbs: [get, list, watch]
  - apiGroups: ["autoscaling"]
    resources: [horizontalpodautoscalers]
    verbs: [get, list, watch]
  - apiGroups: ["networking.k8s.io"]
    resources: [ingresses]
    verbs: [get, list, watch]
  - apiGroups: ["batch"]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch]
  - apiGroups: ["route.openshift.io"]
    resources: [routes]
    verbs: [get, list, watch]
  - apiGroups: ["metrics.k8s.io"]
    resources: [pods, nodes]
    verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: backstage-kubernetes-read
  namespace: ${TARGET_NS}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: backstage-kubernetes-read
subjects:
  - kind: ServiceAccount
    name: backstage-kubernetes
    namespace: ${RHDH_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: backstage-kubernetes-view
  namespace: ${TARGET_NS}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
  - kind: ServiceAccount
    name: backstage-kubernetes
    namespace: ${RHDH_NAMESPACE}
EOF
fi

echo "Kubernetes service account backstage-kubernetes configured."
