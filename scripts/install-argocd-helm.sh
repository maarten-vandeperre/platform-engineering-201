#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

require_oc
command -v helm >/dev/null 2>&1 || { echo "helm CLI is required" >&2; exit 1; }

ensure_project

detect_cluster_router_base

ARGOCD_ROUTE_HOST="${ARGOCD_ROUTE_HOST:-argocd-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}}"
ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-admin123!}"
export ARGOCD_ROUTE_HOST ARGOCD_ADMIN_PASSWORD ARGOCD_INSTALL_CRDS

echo "Installing Argo CD via Helm into ${GITOPS_NAMESPACE}..."

helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo >/dev/null

VALUES_FILE="$(mktemp)"
envsubst '${ARGOCD_ROUTE_HOST} ${ARGOCD_ADMIN_PASSWORD} ${ARGOCD_INSTALL_CRDS}' \
  <"${MANIFESTS_DIR}/../helm/argocd-values-minimal.yaml" >"${VALUES_FILE}"

if [[ "${ARGOCD_INSTALL_CRDS:-true}" == "true" ]]; then
  helm upgrade --install argocd argo/argo-cd \
    -n "${GITOPS_NAMESPACE}" \
    -f "${VALUES_FILE}" \
    --wait --timeout 15m
else
  helm template argocd argo/argo-cd -n "${GITOPS_NAMESPACE}" -f "${VALUES_FILE}" \
    | awk 'BEGIN{RS="---"; ORS="---\n"} !/kind: (CustomResourceDefinition|ClusterRole|ClusterRoleBinding)/' \
    | oc apply -f -
  oc rollout status deployment/argocd-server -n "${GITOPS_NAMESPACE}" --timeout=300s || true
fi

rm -f "${VALUES_FILE}"

"${SCRIPT_DIR}/fix-argocd-rbac.sh"

echo "Argo CD route: https://${ARGOCD_ROUTE_HOST}"
echo "Login: admin / ${ARGOCD_ADMIN_PASSWORD}"
