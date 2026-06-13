#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

export PEOPLE_NOTIFICATION_TOKEN="${PEOPLE_NOTIFICATION_TOKEN:-${BACKEND_SECRET:-workshop-backend-secret}}"

echo "Deploying People Service manifests to ${WORKSHOP_NAMESPACE}..."

ensure_project

# Keycloak must be available before the app is configured for OIDC.
if [[ "${OIDC_ENABLED}" == "true" ]]; then
  if [[ -z "${KEYCLOAK_URL:-}" || "${KEYCLOAK_URL}" == *'${'* || -z "${OIDC_AUTH_SERVER_URL:-}" ]]; then
    "${SCRIPTS_DIR}/setup-keycloak.sh"
  fi
  resolve_keycloak_urls
  if [[ -z "${KEYCLOAK_URL:-}" || "${KEYCLOAK_URL}" == *'${'* ]]; then
    export KEYCLOAK_URL="https://keycloak-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}"
    export OIDC_AUTH_SERVER_URL="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}"
  fi
fi

# Postgres and services first (exclude build configs and app deployments initially)
for file in postgres-secret.yaml postgres-pvc.yaml postgres-deployment.yaml postgres-service.yaml \
  frontend-nginx-configmap.yaml workshop-runtime-config.yaml backend-notifications-secret.yaml \
  imagestream-backend.yaml imagestream-frontend.yaml backend-service.yaml backend-route.yaml \
  frontend-service.yaml frontend-route.yaml; do
  render_manifest "${MANIFESTS_DIR}/people-app/${file}" | oc apply -f -
done

echo "Waiting for PostgreSQL..."
oc rollout status deployment/people-postgres -n "${WORKSHOP_NAMESPACE}" --timeout=300s

echo "Building container images on OpenShift..."
"${SCRIPTS_DIR}/build-images-openshift.sh"

for file in backend-deployment.yaml frontend-deployment.yaml; do
  render_manifest "${MANIFESTS_DIR}/people-app/${file}" | oc apply -f -
done

echo "Waiting for backend deployment..."
oc rollout status deployment/people-backend -n "${WORKSHOP_NAMESPACE}" --timeout=600s
echo "Waiting for frontend deployment..."
oc rollout status deployment/people-frontend -n "${WORKSHOP_NAMESPACE}" --timeout=300s

FRONTEND_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "people-frontend")
BACKEND_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "people-backend")

echo ""
echo "People frontend: https://${FRONTEND_HOST}"
echo "People backend:  https://${BACKEND_HOST}/api/people"
echo "Health check:    https://${BACKEND_HOST}/q/health"
