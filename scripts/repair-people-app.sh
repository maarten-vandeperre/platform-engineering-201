#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Repairing People Service in ${WORKSHOP_NAMESPACE}..."

require_oc

resolve_keycloak_urls

if [[ "${OIDC_ENABLED}" == "true" ]]; then
  "${SCRIPTS_DIR}/repair-keycloak.sh"
fi

export PEOPLE_NOTIFICATION_TOKEN="${PEOPLE_NOTIFICATION_TOKEN:-${BACKEND_SECRET:-workshop-backend-secret}}"

for file in postgres-secret.yaml postgres-pvc.yaml postgres-deployment.yaml postgres-service.yaml; do
  render_manifest "${MANIFESTS_DIR}/people-app/${file}" | oc apply -f -
done

render_manifest "${MANIFESTS_DIR}/people-app/frontend-nginx-configmap.yaml" | oc apply -f -
render_manifest "${MANIFESTS_DIR}/people-app/workshop-runtime-config.yaml" | oc apply -f -
render_manifest "${MANIFESTS_DIR}/people-app/backend-notifications-secret.yaml" | oc apply -f -

echo "Ensuring PostgreSQL is running..."
oc scale deployment/people-postgres --replicas=1 -n "${WORKSHOP_NAMESPACE}"

if [[ "${REPAIR_RESET_POSTGRES_DATA:-false}" == "true" ]]; then
  echo "Resetting PostgreSQL data (REPAIR_RESET_POSTGRES_DATA=true)..."
  oc scale deployment/people-postgres --replicas=0 -n "${WORKSHOP_NAMESPACE}"
  oc wait --for=delete pod -l app=people-postgres -n "${WORKSHOP_NAMESPACE}" --timeout=120s 2>/dev/null || true
  oc delete pvc/people-postgres-data -n "${WORKSHOP_NAMESPACE}" --ignore-not-found
  render_manifest "${MANIFESTS_DIR}/people-app/postgres-pvc.yaml" | oc apply -f -
  oc scale deployment/people-postgres --replicas=1 -n "${WORKSHOP_NAMESPACE}"
else
  oc delete pod -l app=people-postgres -n "${WORKSHOP_NAMESPACE}" --ignore-not-found
fi

echo "Waiting for PostgreSQL..."
if ! oc rollout status deployment/people-postgres -n "${WORKSHOP_NAMESPACE}" --timeout=180s; then
  echo "PostgreSQL did not become ready; resetting data volume..."
  oc scale deployment/people-postgres --replicas=0 -n "${WORKSHOP_NAMESPACE}"
  oc wait --for=delete pod -l app=people-postgres -n "${WORKSHOP_NAMESPACE}" --timeout=120s 2>/dev/null || true
  oc delete pvc/people-postgres-data -n "${WORKSHOP_NAMESPACE}" --ignore-not-found
  render_manifest "${MANIFESTS_DIR}/people-app/postgres-pvc.yaml" | oc apply -f -
  render_manifest "${MANIFESTS_DIR}/people-app/postgres-deployment.yaml" | oc apply -f -
  oc scale deployment/people-postgres --replicas=1 -n "${WORKSHOP_NAMESPACE}"
  oc rollout status deployment/people-postgres -n "${WORKSHOP_NAMESPACE}" --timeout=300s
fi

for file in backend-deployment.yaml frontend-deployment.yaml; do
  render_manifest "${MANIFESTS_DIR}/people-app/${file}" | oc apply -f -
done

if [[ "${REBUILD_FRONTEND:-true}" == "true" ]]; then
  echo "Rebuilding frontend image (runtime-config + auth fixes)..."
  "${SCRIPTS_DIR}/build-images-openshift.sh" --frontend-only
fi

render_manifest "${MANIFESTS_DIR}/people-app/workshop-runtime-config.yaml" | oc apply -f -
oc set env deployment/people-backend -n "${WORKSHOP_NAMESPACE}" \
  OIDC_AUTH_SERVER_URL="${OIDC_AUTH_SERVER_URL}" \
  --overwrite

echo "Ensuring application deployments are running..."
oc scale deployment/people-backend --replicas=1 -n "${WORKSHOP_NAMESPACE}"
oc scale deployment/people-frontend --replicas=1 -n "${WORKSHOP_NAMESPACE}"

echo "Waiting for backend..."
oc rollout status deployment/people-backend -n "${WORKSHOP_NAMESPACE}" --timeout=600s
echo "Waiting for frontend..."
oc rollout status deployment/people-frontend -n "${WORKSHOP_NAMESPACE}" --timeout=300s
oc rollout restart deployment/people-frontend -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1 || true
oc rollout status deployment/people-frontend -n "${WORKSHOP_NAMESPACE}" --timeout=300s

"${SCRIPTS_DIR}/validate-workshop.sh"

echo "People Service repair complete."
