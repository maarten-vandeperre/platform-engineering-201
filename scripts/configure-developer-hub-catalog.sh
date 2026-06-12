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
  --from-file=tech-radar.json="${MANIFESTS_DIR}/catalog/tech-radar.json" \
  --dry-run=client -o yaml \
  | oc apply -f -

rm -f "${OPENAPI_RENDERED}"

oc label configmap workshop-catalog-entities \
  -n "${WORKSHOP_NAMESPACE}" \
  app.kubernetes.io/part-of=developer-hub --overwrite

echo "Deploying workshop catalog server..."
render_manifest "${MANIFESTS_DIR}/developer-hub/catalog-server.yaml" | oc apply -f -
oc scale deployment/workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" --replicas=1

echo "Waiting for catalog server..."
for i in $(seq 1 60); do
  ready=$(oc get deployment workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [[ "${ready}" == "1" ]]; then
    break
  fi
  if (( i == 60 )); then
    echo "Warning: catalog server did not become ready in time." >&2
  fi
  sleep 5
done

CATALOG_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "workshop-catalog-server" 2>/dev/null || echo "")
if [[ -n "${CATALOG_HOST}" ]]; then
  echo "Catalog server: https://${CATALOG_HOST}/entities.yaml"
  echo "Tech Radar data: https://${CATALOG_HOST}/tech-radar.json"
  echo "OpenAPI file: https://${CATALOG_HOST}/people-api.yaml"
fi

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
  echo "Developer Hub catalog APIs: https://${RHDH_HOST}/catalog?filters%5Bkind%5D=api"
  echo "Developer Hub Tech Radar: https://${RHDH_HOST}/tech-radar"
  echo "People REST API entity: https://${RHDH_HOST}/catalog/default/api/people-rest-api"
fi

echo "Catalog configuration complete."
