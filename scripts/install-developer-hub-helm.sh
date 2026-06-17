#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

require_oc
command -v helm >/dev/null 2>&1 || { echo "helm CLI is required" >&2; exit 1; }

ensure_project
resolve_keycloak_urls

detect_cluster_router_base

RHDH_HELM_GLOBAL_HOST="$(resolve_rhdh_helm_global_host)"
ARGOCD_HOST="$(resolve_argocd_route_host 2>/dev/null || true)"
ARGOCD_URL="${ARGOCD_URL:-https://${ARGOCD_HOST:-argocd-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}}}"
ARGOCD_TOKEN="${ARGOCD_TOKEN:-changeme}"
GITHUB_TOKEN="${GITHUB_TOKEN:-changeme}"

export CLUSTER_ROUTER_BASE RHDH_APP_TITLE WORKSHOP_GIT_REPO WORKSHOP_GIT_BRANCH \
  KEYCLOAK_URL KEYCLOAK_REALM RHDH_KEYCLOAK_CLIENT_ID RHDH_OIDC_CLIENT_SECRET \
  ARGOCD_URL ARGOCD_TOKEN GITHUB_TOKEN RHDH_HELM_GLOBAL_HOST

RHDH_HELM_CHART="${RHDH_HELM_CHART:-https://github.com/openshift-helm-charts/charts/releases/download/redhat-redhat-developer-hub-1.9.3/redhat-developer-hub-1.9.3.tgz}"

echo "Installing Red Hat Developer Hub via Helm into ${RHDH_NAMESPACE}..."
if [[ -n "${RHDH_HELM_GLOBAL_HOST}" ]]; then
  echo "Using existing Developer Hub route host: ${RHDH_HELM_GLOBAL_HOST}"
fi

helm_unlock_release redhat-developer-hub "${RHDH_NAMESPACE}"

oc create secret generic rhdh-workshop-secrets -n "${RHDH_NAMESPACE}" \
  --from-literal=ARGOCD_URL="${ARGOCD_URL}" \
  --from-literal=ARGOCD_TOKEN="${ARGOCD_TOKEN}" \
  --from-literal=GITHUB_TOKEN="${GITHUB_TOKEN}" \
  --from-literal=RHDH_OIDC_CLIENT_SECRET="${RHDH_OIDC_CLIENT_SECRET}" \
  --dry-run=client -o yaml | oc apply -f -

VALUES_FILE="$(mktemp)"
workshop_envsubst '${CLUSTER_ROUTER_BASE} ${RHDH_HELM_GLOBAL_HOST} ${RHDH_APP_TITLE} ${WORKSHOP_GIT_REPO} ${WORKSHOP_GIT_BRANCH} ${KEYCLOAK_URL} ${KEYCLOAK_REALM} ${RHDH_KEYCLOAK_CLIENT_ID} ${RHDH_OIDC_CLIENT_SECRET} ${ARGOCD_URL} ${ARGOCD_TOKEN} ${GITHUB_TOKEN}' \
  <"${MANIFESTS_DIR}/../helm/rhdh-values.yaml" >"${VALUES_FILE}"

helm upgrade --install redhat-developer-hub "${RHDH_HELM_CHART}" \
  -n "${RHDH_NAMESPACE}" \
  -f "${VALUES_FILE}" \
  --wait --timeout 15m

rm -f "${VALUES_FILE}"

"${SCRIPTS_DIR}/setup-developer-hub-dynamic-plugins-cache.sh" || true

RHDH_HOST="$(resolve_rhdh_host)"
echo "Developer Hub: https://${RHDH_HOST}"
