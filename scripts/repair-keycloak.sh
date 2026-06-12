#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Repairing Keycloak in ${WORKSHOP_NAMESPACE}..."

require_oc

for file in keycloak-secret.yaml keycloak-realm-configmap.yaml keycloak-deployment.yaml keycloak-service.yaml keycloak-route.yaml; do
  render_manifest "${MANIFESTS_DIR}/keycloak/${file}" | oc apply -f -
done

echo "Ensuring Keycloak is running..."
oc scale deployment/keycloak --replicas=1 -n "${WORKSHOP_NAMESPACE}"
oc rollout status deployment/keycloak -n "${WORKSHOP_NAMESPACE}" --timeout=600s

resolve_keycloak_urls
"${SCRIPTS_DIR}/configure-keycloak-realm.sh"

KEYCLOAK_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "keycloak")
echo "Keycloak: https://${KEYCLOAK_HOST}"
echo "Workshop realm: https://${KEYCLOAK_HOST}/realms/${KEYCLOAK_REALM}"
echo "Keycloak repair complete."
