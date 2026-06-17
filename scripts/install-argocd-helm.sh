#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

require_oc
command -v helm >/dev/null 2>&1 || { echo "helm CLI is required" >&2; exit 1; }

ensure_project

detect_cluster_router_base

EXISTING_ARGOCD_HOST="$(resolve_argocd_route_host 2>/dev/null || true)"
ARGOCD_ROUTE_HOST="${ARGOCD_ROUTE_HOST:-${EXISTING_ARGOCD_HOST:-argocd-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}}}"
ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-admin123!}"
export ARGOCD_ROUTE_HOST ARGOCD_ADMIN_PASSWORD ARGOCD_INSTALL_CRDS

echo "Installing Argo CD via Helm into ${GITOPS_NAMESPACE}..."
if [[ -n "${EXISTING_ARGOCD_HOST}" ]]; then
  echo "Using existing Argo CD route host: ${EXISTING_ARGOCD_HOST}"
fi

helm_unlock_release argocd "${GITOPS_NAMESPACE}"

helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo >/dev/null

VALUES_FILE="$(mktemp)"
workshop_envsubst '${ARGOCD_ROUTE_HOST} ${ARGOCD_ADMIN_PASSWORD} ${ARGOCD_INSTALL_CRDS}' \
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

ARGOCD_ROUTE_HOST="$(resolve_argocd_route_host 2>/dev/null || echo "${ARGOCD_ROUTE_HOST}")"
echo "Argo CD route: https://${ARGOCD_ROUTE_HOST}"
echo "Login: admin / ${ARGOCD_ADMIN_PASSWORD}"
