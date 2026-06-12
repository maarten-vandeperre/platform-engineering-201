#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Repairing People Service in ${WORKSHOP_NAMESPACE}..."

require_oc

resolve_keycloak_urls

if [[ "${OIDC_ENABLED}" == "true" ]]; then
  "${SCRIPTS_DIR}/configure-keycloak-realm.sh"
fi

for file in postgres-secret.yaml postgres-pvc.yaml postgres-deployment.yaml postgres-service.yaml; do
  render_manifest "${MANIFESTS_DIR}/people-app/${file}" | oc apply -f -
done

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

resolve_keycloak_urls
oc set env deployment/people-frontend -n "${WORKSHOP_NAMESPACE}" \
  WORKSHOP_NAMESPACE="${WORKSHOP_NAMESPACE}" \
  CLUSTER_ROUTER_BASE="${CLUSTER_ROUTER_BASE}" \
  KEYCLOAK_URL="${KEYCLOAK_URL}" \
  KEYCLOAK_REALM="${KEYCLOAK_REALM}" \
  KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID}" \
  OIDC_ENABLED="${OIDC_ENABLED}" \
  --overwrite
oc set env deployment/people-backend -n "${WORKSHOP_NAMESPACE}" \
  OIDC_AUTH_SERVER_URL="${OIDC_AUTH_SERVER_URL}" \
  OIDC_ENABLED="${OIDC_ENABLED}" \
  OIDC_CLIENT_ID="${KEYCLOAK_CLIENT_ID}" \
  --overwrite

echo "Ensuring application deployments are running..."
oc scale deployment/people-backend --replicas=1 -n "${WORKSHOP_NAMESPACE}"
oc scale deployment/people-frontend --replicas=1 -n "${WORKSHOP_NAMESPACE}"

echo "Waiting for backend..."
oc rollout status deployment/people-backend -n "${WORKSHOP_NAMESPACE}" --timeout=600s
echo "Waiting for frontend..."
oc rollout status deployment/people-frontend -n "${WORKSHOP_NAMESPACE}" --timeout=300s

"${SCRIPTS_DIR}/validate-workshop.sh"

echo "People Service repair complete."
