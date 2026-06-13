#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Updating Developer Hub catalog entities in ${WORKSHOP_NAMESPACE}..."

require_oc
ensure_workshop_platform

if [[ -z "${KEYCLOAK_URL:-}" ]] && oc get route keycloak -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
  KEYCLOAK_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "keycloak")
  export KEYCLOAK_URL="https://${KEYCLOAK_HOST}"
fi
resolve_keycloak_urls

extract_entities_yaml() {
  render_manifest "${MANIFESTS_DIR}/developer-hub/catalog-configmap.yaml" | awk '
    /^  entities.yaml: \|/ { in_entities=1; next }
    in_entities && /^  [^ ]/ { exit }
    in_entities { sub(/^    /, ""); print }
  '
}

append_organization_entities() {
  render_manifest "${MANIFESTS_DIR}/catalog/entities/organization-model.yaml"
  render_manifest "${MANIFESTS_DIR}/catalog/entities/workshop-organization.yaml"
}

build_entities_yaml() {
  append_organization_entities
  printf '\n---\n'
  extract_entities_yaml
}

build_scaffold_archive() {
  local scaffold_dir="${REPO_ROOT}/apps/people-service-scaffold"
  local archive
  archive="$(mktemp)"

  tar --exclude='node_modules' --exclude='target' --exclude='.git' --exclude='dist' \
    -czf "${archive}" -C "${scaffold_dir}" .
  echo "${archive}"
}

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

OPENAPI_RENDERED="$(mktemp)"
SCAFFOLD_ARCHIVE="$(build_scaffold_archive)"
envsubst '${WORKSHOP_NAMESPACE} ${CLUSTER_ROUTER_BASE}' \
  <"${REPO_ROOT}/apps/people-service/openapi/people-api.yaml" >"${OPENAPI_RENDERED}"

oc create configmap workshop-catalog-entities \
  -n "${WORKSHOP_NAMESPACE}" \
  --from-literal=entities.yaml="$(build_entities_yaml)" \
  --from-file=people-api.yaml="${OPENAPI_RENDERED}" \
  --from-file=tech-radar.json="${MANIFESTS_DIR}/catalog/tech-radar.json" \
  --from-file=learning-paths.json="${MANIFESTS_DIR}/developer-hub/learning-paths.json" \
  --from-file=people-service-scaffold.tar.gz="${SCAFFOLD_ARCHIVE}" \
  --dry-run=client -o yaml \
  | oc apply -f -

rm -f "${OPENAPI_RENDERED}" "${SCAFFOLD_ARCHIVE}"

oc label configmap workshop-catalog-entities \
  -n "${WORKSHOP_NAMESPACE}" \
  app.kubernetes.io/part-of=developer-hub --overwrite

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
  echo "Developer Hub Learning Paths: https://${RHDH_HOST}/learning-paths"
  echo "Quarkus TechDocs: https://${RHDH_HOST}/catalog/default/component/quarkus-workshop-guide/docs"
  echo "ADR TechDocs: https://${RHDH_HOST}/catalog/default/component/platform-architecture-records/docs"
  echo "People REST API entity: https://${RHDH_HOST}/catalog/default/api/people-rest-api"
  echo "People REST API CI tab: https://${RHDH_HOST}/catalog/default/api/people-rest-api/ci"
fi

echo "Catalog configuration complete."
