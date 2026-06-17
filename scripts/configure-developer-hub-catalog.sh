#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Updating Developer Hub catalog entities in ${WORKSHOP_NAMESPACE}..."

require_oc
set +e
ensure_keycloak_running
keycloak_ok=$?
set -e
if [[ "${keycloak_ok}" -ne 0 ]]; then
  echo "Warning: Keycloak not reachable; continuing catalog update with KEYCLOAK_URL from workshop.env." >&2
fi
ensure_rhdh_postgres

if [[ -z "${KEYCLOAK_URL:-}" ]] && oc get route keycloak -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
  KEYCLOAK_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "keycloak")
  export KEYCLOAK_URL="https://${KEYCLOAK_HOST}"
fi
resolve_keycloak_urls

build_techdocs_configmap() {
  local techdocs_dir="${MANIFESTS_DIR}/techdocs"
  local site

  for site in quarkus-guide adrs; do
    if [[ ! -d "${techdocs_dir}/${site}" ]]; then
      continue
    fi
    oc create configmap "workshop-techdocs-${site}" \
      -n "${WORKSHOP_NAMESPACE}" \
      --from-file="${techdocs_dir}/${site}" \
      --dry-run=client -o yaml \
      | oc apply -f -
    oc label configmap "workshop-techdocs-${site}" \
      -n "${WORKSHOP_NAMESPACE}" \
      app.kubernetes.io/part-of=developer-hub --overwrite
  done
}

ensure_catalog_entities_configmap

echo "Publishing TechDocs sources..."
build_techdocs_configmap

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
  echo "Learning paths: https://${CATALOG_HOST}/learning-paths.json"
  echo "TechDocs (Quarkus): https://${CATALOG_HOST}/techdocs/quarkus-guide/mkdocs.yml"
  echo "TechDocs (ADRs): https://${CATALOG_HOST}/techdocs/adrs/mkdocs.yml"
  echo "OpenAPI file: https://${CATALOG_HOST}/people-api.yaml"
  echo "Scaffold archive: https://${CATALOG_HOST}/people-service-scaffold.tar.gz"
fi

if oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  echo "Restarting Developer Hub to reload catalog..."
  safe_rollout_developer_hub redhat-developer-hub 900s
elif oc get backstage "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  echo "Developer Hub operator instance detected; catalog ConfigMap updated."
else
  echo "Developer Hub deployment not found; catalog ConfigMap updated only."
fi

RHDH_HOST=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null || echo "")
if [[ -n "${RHDH_HOST}" ]]; then
  echo "Developer Hub catalog APIs: https://${RHDH_HOST}/catalog?filters%5Bkind%5D=api"
  echo "Developer Hub Tech Radar: https://${RHDH_HOST}/tech-radar"
  echo "Developer Hub Learning Paths: https://${RHDH_HOST}/learning-paths"
  echo "Quarkus TechDocs: https://${RHDH_HOST}/catalog/default/component/quarkus-workshop-guide/docs"
  echo "ADR TechDocs: https://${RHDH_HOST}/catalog/default/component/platform-architecture-records/docs"
  echo "People REST API entity: https://${RHDH_HOST}/catalog/default/api/people-rest-api"
  echo "People REST API CI tab: https://${RHDH_HOST}/catalog/default/api/people-rest-api/ci"
fi

echo "Catalog configuration complete."
