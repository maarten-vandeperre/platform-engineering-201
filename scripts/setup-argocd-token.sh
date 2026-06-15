#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

require_oc
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

ARGOCD_ROUTE="${ARGOCD_INSTANCE_NAME}-server"
if ! oc get route "${ARGOCD_ROUTE}" -n "${GITOPS_NAMESPACE}" >/dev/null 2>&1; then
  if oc get route argocd-server -n "${GITOPS_NAMESPACE}" >/dev/null 2>&1; then
    ARGOCD_ROUTE="argocd-server"
  else
    echo "Argo CD route not found in ${GITOPS_NAMESPACE}. Run ./scripts/setup-argocd.sh or install-argocd-helm.sh" >&2
    exit 1
  fi
fi

ARGOCD_HOST=$(get_route_host "${GITOPS_NAMESPACE}" "${ARGOCD_ROUTE}")
ARGOCD_URL="https://${ARGOCD_HOST}"
export ARGOCD_URL

echo "Configuring Argo CD token for Developer Hub (${ARGOCD_URL})..."

ADMIN_PASS=""
for secret_name in "${ARGOCD_INSTANCE_NAME}-cluster" "argocd-cluster" "argocd-initial-admin-secret"; do
  if oc get secret "${secret_name}" -n "${GITOPS_NAMESPACE}" >/dev/null 2>&1; then
    ADMIN_PASS=$(oc get secret "${secret_name}" -n "${GITOPS_NAMESPACE}" \
      -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d || true)
    [[ -z "${ADMIN_PASS}" ]] && ADMIN_PASS=$(oc get secret "${secret_name}" -n "${GITOPS_NAMESPACE}" \
      -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
    [[ -n "${ADMIN_PASS}" ]] && break
  fi
done

if [[ -z "${ADMIN_PASS}" ]]; then
  ADMIN_PASS="${ARGOCD_ADMIN_PASSWORD:-admin123!}"
  echo "Using ARGOCD_ADMIN_PASSWORD from workshop.env"
fi

TOKEN=""
# Use HTTP API only — avoids interactive `argocd login` prompts when the CLI is installed.
SESSION=$(curl -sk -X POST "${ARGOCD_URL}/api/v1/session" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"${ADMIN_PASS}\"}" | jq -r '.token // empty')
if [[ -n "${SESSION}" && "${SESSION}" != "null" ]]; then
  TOKEN=$(curl -sk -X POST "${ARGOCD_URL}/api/v1/account/rhdh/token" \
    -H "Authorization: Bearer ${SESSION}" | jq -r '.token // empty')
  [[ -z "${TOKEN}" || "${TOKEN}" == "null" ]] && TOKEN="${SESSION}"
fi

if [[ -z "${TOKEN}" || "${TOKEN}" == "null" ]]; then
  echo "Could not obtain Argo CD API token. CD tab in Developer Hub may be empty." >&2
  TOKEN="${ARGOCD_TOKEN:-changeme}"
fi

oc create secret generic argo-secrets -n "${RHDH_NAMESPACE}" \
  --from-literal=ARGOCD_URL="${ARGOCD_URL}" \
  --from-literal=ARGOCD_TOKEN="${TOKEN}" \
  --dry-run=client -o yaml | oc apply -f -

echo "Stored Argo CD credentials in secret argo-secrets (namespace ${RHDH_NAMESPACE})."
