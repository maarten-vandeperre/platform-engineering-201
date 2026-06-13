#!/usr/bin/env bash
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${LIB_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPTS_DIR}/.." && pwd)"
MANIFESTS_DIR="${REPO_ROOT}/manifests/gitops"

if [[ -f "${SCRIPTS_DIR}/workshop.env" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPTS_DIR}/workshop.env"
else
  # shellcheck disable=SC1091
  source "${SCRIPTS_DIR}/workshop.env.example"
fi

export WORKSHOP_NAMESPACE
export WORKSHOP_GIT_REPO
export WORKSHOP_GIT_BRANCH
export WORKSHOP_GITHUB_ORG
export WORKSHOP_GITHUB_REPO
export WORKSHOP_IMAGE_REGISTRY
export WORKSHOP_BACKEND_IMAGE
export WORKSHOP_FRONTEND_IMAGE
export RHDH_NAMESPACE
export RHDH_INSTANCE_NAME
export RHDH_APP_TITLE
export GITOPS_NAMESPACE
export ARGOCD_INSTANCE_NAME
export ARGOCD_APP_NAME
export PEOPLE_DB_NAME
export PEOPLE_DB_USER
export PEOPLE_DB_PASSWORD
export KEYCLOAK_ADMIN_USER
export KEYCLOAK_ADMIN_PASSWORD
export KEYCLOAK_REALM
export KEYCLOAK_CLIENT_ID
export KEYCLOAK_URL
export OIDC_AUTH_SERVER_URL
export OIDC_ENABLED
export CLUSTER_ROUTER_BASE
export RHDH_KEYCLOAK_CLIENT_ID
export RHDH_KEYCLOAK_CLIENT_SECRET
export RHDH_KEYCLOAK_USER
export RHDH_KEYCLOAK_PASSWORD
export RHDH_OIDC_CLIENT_SECRET
export WORKSHOP_CATALOG_URL
export WORKSHOP_INSTALL_METHOD
export SKIP_ARGOCD
export RUN_E2E

detect_cluster_router_base() {
  if [[ -n "${CLUSTER_ROUTER_BASE:-}" && "${CLUSTER_ROUTER_BASE}" != "apps.example.com" ]]; then
    return 0
  fi
  local host=""
  host=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -z "${host}" ]]; then
    host=$(oc get route -n openshift-console -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
  fi
  if [[ -n "${host}" && "${host}" == console-openshift-console.* ]]; then
    export CLUSTER_ROUTER_BASE="${host#console-openshift-console.}"
    echo "Detected CLUSTER_ROUTER_BASE=${CLUSTER_ROUTER_BASE}"
  elif [[ -z "${CLUSTER_ROUTER_BASE:-}" ]]; then
    echo "Set CLUSTER_ROUTER_BASE in scripts/workshop.env (e.g. apps.cluster-name.example.com)" >&2
  fi
}

require_oc() {
  command -v oc >/dev/null 2>&1 || {
    echo "oc CLI is required" >&2
    exit 1
  }
}

ensure_project() {
  require_oc
  if ! oc get namespace "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
    oc new-project "${WORKSHOP_NAMESPACE}"
  else
    oc project "${WORKSHOP_NAMESPACE}"
  fi
}

render_manifest() {
  local input="$1"
  envsubst \
    '${WORKSHOP_NAMESPACE} ${WORKSHOP_GIT_REPO} ${WORKSHOP_GIT_BRANCH} ${WORKSHOP_GITHUB_ORG} ${WORKSHOP_GITHUB_REPO} ${WORKSHOP_BACKEND_IMAGE} ${WORKSHOP_FRONTEND_IMAGE} ${RHDH_NAMESPACE} ${RHDH_INSTANCE_NAME} ${RHDH_APP_TITLE} ${GITOPS_NAMESPACE} ${ARGOCD_INSTANCE_NAME} ${ARGOCD_APP_NAME} ${PEOPLE_DB_NAME} ${PEOPLE_DB_USER} ${PEOPLE_DB_PASSWORD} ${KEYCLOAK_ADMIN_USER} ${KEYCLOAK_ADMIN_PASSWORD} ${KEYCLOAK_REALM} ${KEYCLOAK_CLIENT_ID} ${KEYCLOAK_URL} ${KEYCLOAK_HOST} ${OIDC_AUTH_SERVER_URL} ${OIDC_ENABLED} ${CLUSTER_ROUTER_BASE} ${RHDH_KEYCLOAK_CLIENT_ID} ${RHDH_KEYCLOAK_CLIENT_SECRET} ${RHDH_KEYCLOAK_USER} ${RHDH_KEYCLOAK_PASSWORD} ${RHDH_OIDC_CLIENT_SECRET} ${WORKSHOP_CATALOG_URL} ${BACKEND_SECRET} ${GITHUB_TOKEN} ${ARGOCD_URL} ${ARGOCD_TOKEN} ${K8S_SA_TOKEN} ${K8S_CA_DATA} ${ORCHESTRATOR_DATA_INDEX_IMAGE}' \
    <"${input}"
}

apply_rendered_dir() {
  local dir="$1"
  local file
  while IFS= read -r -d '' file; do
    render_manifest "${file}" | oc apply -f -
  done < <(find "${dir}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | sort -z)
}

wait_for_csv() {
  local namespace="$1"
  local csv_name_prefix="$2"
  local timeout="${3:-600}"
  echo "Waiting for CSV matching ${csv_name_prefix} in ${namespace}..."
  local start
  start=$(date +%s)
  while true; do
    if oc get csv -n "${namespace}" 2>/dev/null | awk 'NR>1 {print $1}' | grep -q "^${csv_name_prefix}"; then
      local phase
      phase=$(oc get csv -n "${namespace}" -o name | grep "${csv_name_prefix}" | head -1 | xargs -I{} oc get {} -n "${namespace}" -o jsonpath='{.status.phase}')
      if [[ "${phase}" == "Succeeded" ]]; then
        echo "Operator ready."
        return 0
      fi
    fi
    if (( $(date +%s) - start > timeout )); then
      echo "Timed out waiting for operator CSV" >&2
      return 1
    fi
    sleep 10
  done
}

get_route_host() {
  local namespace="$1"
  local name="$2"
  oc get route "${name}" -n "${namespace}" -o jsonpath='{.spec.host}'
}

resolve_rhdh_host() {
  get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null \
    || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null \
    || echo "redhat-developer-hub-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}"
}

resolve_keycloak_urls() {
  if [[ -z "${KEYCLOAK_URL:-}" || "${KEYCLOAK_URL}" == *'${'* ]]; then
    if oc get route keycloak -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
      KEYCLOAK_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "keycloak")
      export KEYCLOAK_URL="https://${KEYCLOAK_HOST}"
    else
      export KEYCLOAK_URL="https://keycloak-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}"
    fi
  fi
  export OIDC_AUTH_SERVER_URL="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}"
  export KEYCLOAK_HOST="${KEYCLOAK_URL#https://}"
  KEYCLOAK_HOST="${KEYCLOAK_HOST#http://}"
  export KEYCLOAK_HOST
}

wait_keycloak_http_ready() {
  resolve_keycloak_urls
  local url="${OIDC_AUTH_SERVER_URL}/.well-known/openid-configuration"
  local attempt code
  for attempt in $(seq 1 60); do
    code=$(curl -sk -o /tmp/workshop-keycloak-check.json -w "%{http_code}" "${url}" 2>/dev/null || echo "000")
    if [[ "${code}" == "200" ]] && grep -q '"issuer"' /tmp/workshop-keycloak-check.json 2>/dev/null; then
      return 0
    fi
    if (( attempt % 6 == 0 )); then
      echo "Waiting for Keycloak at ${url} (HTTP ${code})..."
    fi
    sleep 5
  done
  echo "Keycloak is not reachable. Run ./scripts/repair-keycloak.sh" >&2
  return 1
}

ensure_keycloak_running() {
  if ! oc get deployment keycloak -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
    return 0
  fi

  local replicas ready
  replicas=$(oc get deployment keycloak -n "${WORKSHOP_NAMESPACE}" -o jsonpath='{.spec.replicas}')
  ready=$(oc get deployment keycloak -n "${WORKSHOP_NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

  if [[ "${replicas}" == "0" || "${ready}" != "1" ]]; then
    echo "Ensuring Keycloak is running in ${WORKSHOP_NAMESPACE} (replicas=${replicas}, ready=${ready})..."
    oc scale deployment/keycloak --replicas=1 -n "${WORKSHOP_NAMESPACE}"
    oc rollout status deployment/keycloak -n "${WORKSHOP_NAMESPACE}" --timeout=600s
  fi

  wait_keycloak_http_ready
}

ensure_rhdh_postgres() {
  if ! oc get statefulset redhat-developer-hub-postgresql -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    return 0
  fi

  local replicas ready
  replicas=$(oc get statefulset redhat-developer-hub-postgresql -n "${RHDH_NAMESPACE}" \
    -o jsonpath='{.spec.replicas}')
  ready=$(oc get statefulset redhat-developer-hub-postgresql -n "${RHDH_NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

  if [[ "${replicas}" == "0" || "${ready}" != "1" ]]; then
    echo "Ensuring RHDH PostgreSQL is running in ${RHDH_NAMESPACE}..."
    oc scale statefulset/redhat-developer-hub-postgresql -n "${RHDH_NAMESPACE}" --replicas=1
    oc rollout status statefulset/redhat-developer-hub-postgresql -n "${RHDH_NAMESPACE}" --timeout=300s
  fi
}

ensure_catalog_server() {
  if ! oc get deployment workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
    return 0
  fi

  local replicas ready
  replicas=$(oc get deployment workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" \
    -o jsonpath='{.spec.replicas}')
  ready=$(oc get deployment workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

  if [[ "${replicas}" == "0" || "${ready}" != "1" ]]; then
    echo "Ensuring workshop catalog server is running in ${WORKSHOP_NAMESPACE}..."
    oc scale deployment/workshop-catalog-server --replicas=1 -n "${WORKSHOP_NAMESPACE}"
    oc rollout status deployment/workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" --timeout=300s
  fi
}

ensure_workshop_platform() {
  require_oc
  echo "Ensuring workshop platform dependencies are running..."
  ensure_keycloak_running
  ensure_rhdh_postgres
  ensure_catalog_server
  echo "Workshop platform dependencies are ready."
}
