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

export CLUSTER_ROUTER_BASE RHDH_HELM_GLOBAL_HOST

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
workshop_envsubst '${CLUSTER_ROUTER_BASE} ${RHDH_HELM_GLOBAL_HOST}' \
  <"${MANIFESTS_DIR}/../helm/rhdh-values.yaml" >"${VALUES_FILE}"

helm upgrade --install redhat-developer-hub "${RHDH_HELM_CHART}" \
  -n "${RHDH_NAMESPACE}" \
  -f "${VALUES_FILE}"

rm -f "${VALUES_FILE}"

echo ""
echo "Waiting for Developer Hub Helm release to roll out..."
wait_for_developer_hub_rollout redhat-developer-hub 900s

"${SCRIPTS_DIR}/setup-developer-hub-dynamic-plugins-cache.sh" || true

# Helm always re-renders redhat-developer-hub-app-config from chart defaults on upgrade.
# Re-apply the full workshop app-config (catalog, auth, theme, plugins, etc.).
if [[ "${SKIP_RHDH_WORKSHOP_CONFIG:-false}" != "true" ]]; then
  echo ""
  echo "Applying full workshop app-config after Helm upgrade..."
  "${SCRIPTS_DIR}/setup-developer-hub-config.sh"
else
  echo ""
  echo "NOTE: SKIP_RHDH_WORKSHOP_CONFIG=true — run ./scripts/setup-developer-hub-config.sh to apply workshop app-config."
fi

wait_for_rhdh_route_ready 900
print_rhdh_route_url
