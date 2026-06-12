#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

require_oc

echo "Applying namespace RBAC for Helm-installed Argo CD in ${GITOPS_NAMESPACE}..."

for sa in argocd-application-controller argocd-server; do
  oc create rolebinding "argocd-workshop-${sa}" \
    --clusterrole=admin \
    --serviceaccount="${GITOPS_NAMESPACE}:${sa}" \
    -n "${WORKSHOP_NAMESPACE}" \
    --dry-run=client -o yaml | oc apply -f - 2>/dev/null || true
done

echo "Argo CD RBAC updated for namespace ${WORKSHOP_NAMESPACE}."
