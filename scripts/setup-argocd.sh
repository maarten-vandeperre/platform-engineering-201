#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Creating Argo CD instance and application in ${GITOPS_NAMESPACE}..."

ensure_project

apply_rendered_dir "${MANIFESTS_DIR}/argocd"

echo "Waiting for Argo CD server route..."
for _ in $(seq 1 60); do
  if oc get route "${ARGOCD_INSTANCE_NAME}-server" -n "${GITOPS_NAMESPACE}" >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

ARGOCD_HOST=$(get_route_host "${GITOPS_NAMESPACE}" "${ARGOCD_INSTANCE_NAME}-server" 2>/dev/null || true)
if [[ -n "${ARGOCD_HOST}" ]]; then
  echo "Argo CD UI: https://${ARGOCD_HOST}"
else
  echo "Argo CD route not ready yet. Check: oc get argocd,route -n ${GITOPS_NAMESPACE}"
fi
