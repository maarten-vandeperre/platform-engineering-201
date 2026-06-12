#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Building People Service images on OpenShift from local source..."

ensure_project

apply_rendered() {
  render_manifest "$1" | oc apply -f -
}

apply_rendered "${MANIFESTS_DIR}/people-app/imagestream-backend.yaml"
apply_rendered "${MANIFESTS_DIR}/people-app/imagestream-frontend.yaml"

FRONTEND_ONLY=false
BACKEND_ONLY=false
for arg in "$@"; do
  case "${arg}" in
    --frontend-only) FRONTEND_ONLY=true ;;
    --backend-only) BACKEND_ONLY=true ;;
  esac
done

if [[ "${FRONTEND_ONLY}" != "true" ]]; then
  apply_rendered "${MANIFESTS_DIR}/people-app/build-backend.yaml"
  echo "Starting backend build (this may take several minutes)..."
  oc start-build people-backend -n "${WORKSHOP_NAMESPACE}" --from-dir="${REPO_ROOT}/apps/people-service/backend" --wait --follow
fi

if [[ "${BACKEND_ONLY}" != "true" ]]; then
  apply_rendered "${MANIFESTS_DIR}/people-app/build-frontend.yaml"
  echo "Starting frontend build..."
  oc start-build people-frontend -n "${WORKSHOP_NAMESPACE}" --from-dir="${REPO_ROOT}/apps/people-service/frontend" --wait --follow
fi

oc set image deployment/people-backend backend="image-registry.openshift-image-registry.svc:5000/${WORKSHOP_NAMESPACE}/people-backend:latest" -n "${WORKSHOP_NAMESPACE}" 2>/dev/null || true
oc set image deployment/people-frontend frontend="image-registry.openshift-image-registry.svc:5000/${WORKSHOP_NAMESPACE}/people-frontend:latest" -n "${WORKSHOP_NAMESPACE}" 2>/dev/null || true

echo "Images built and deployments updated."
