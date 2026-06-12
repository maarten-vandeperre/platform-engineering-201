#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Updating Developer Hub catalog entities in ${WORKSHOP_NAMESPACE}..."

require_oc

if [[ -z "${KEYCLOAK_URL:-}" ]] && oc get route keycloak -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
  KEYCLOAK_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "keycloak")
  export KEYCLOAK_URL="https://${KEYCLOAK_HOST}"
fi

extract_entities_yaml() {
  render_manifest "${MANIFESTS_DIR}/developer-hub/catalog-configmap.yaml" | awk '
    /^  entities.yaml: \|/ { in_entities=1; next }
    in_entities && /^  [^ ]/ { exit }
    in_entities { sub(/^    /, ""); print }
  '
}

OPENAPI_RENDERED="$(mktemp)"
envsubst '${WORKSHOP_NAMESPACE} ${CLUSTER_ROUTER_BASE}' \
  <"${REPO_ROOT}/apps/people-service/openapi/people-api.yaml" >"${OPENAPI_RENDERED}"

oc create configmap workshop-catalog-entities \
  -n "${WORKSHOP_NAMESPACE}" \
  --from-literal=entities.yaml="$(extract_entities_yaml)" \
  --from-file=people-api.yaml="${OPENAPI_RENDERED}" \
  --dry-run=client -o yaml \
  | oc apply -f -

rm -f "${OPENAPI_RENDERED}"

oc label configmap workshop-catalog-entities \
  -n "${WORKSHOP_NAMESPACE}" \
  app.kubernetes.io/part-of=developer-hub --overwrite

if oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  echo "Restarting Developer Hub to reload catalog..."
  oc delete pod -l app.kubernetes.io/name=developer-hub -n "${RHDH_NAMESPACE}" --wait=false
elif oc get backstage "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  echo "Developer Hub operator instance detected; catalog ConfigMap updated."
else
  echo "Developer Hub deployment not found; catalog ConfigMap updated only."
fi

RHDH_HOST=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null || echo "")
if [[ -n "${RHDH_HOST}" ]]; then
  echo "Developer Hub: https://${RHDH_HOST}/catalog/default/component/people-service"
  echo "OpenAPI entity: https://${RHDH_HOST}/catalog/default/api/people-rest-api"
fi

echo "Catalog configuration complete."
