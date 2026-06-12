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
    '${WORKSHOP_NAMESPACE} ${WORKSHOP_GIT_REPO} ${WORKSHOP_GIT_BRANCH} ${WORKSHOP_GITHUB_ORG} ${WORKSHOP_GITHUB_REPO} ${WORKSHOP_BACKEND_IMAGE} ${WORKSHOP_FRONTEND_IMAGE} ${RHDH_NAMESPACE} ${RHDH_INSTANCE_NAME} ${RHDH_APP_TITLE} ${GITOPS_NAMESPACE} ${ARGOCD_INSTANCE_NAME} ${ARGOCD_APP_NAME} ${PEOPLE_DB_NAME} ${PEOPLE_DB_USER} ${PEOPLE_DB_PASSWORD} ${KEYCLOAK_ADMIN_USER} ${KEYCLOAK_ADMIN_PASSWORD} ${KEYCLOAK_REALM} ${KEYCLOAK_CLIENT_ID} ${KEYCLOAK_URL} ${OIDC_AUTH_SERVER_URL} ${OIDC_ENABLED} ${CLUSTER_ROUTER_BASE} ${RHDH_KEYCLOAK_CLIENT_ID} ${RHDH_KEYCLOAK_CLIENT_SECRET} ${RHDH_KEYCLOAK_USER} ${RHDH_KEYCLOAK_PASSWORD} ${RHDH_OIDC_CLIENT_SECRET} ${WORKSHOP_CATALOG_URL} ${BACKEND_SECRET} ${GITHUB_TOKEN} ${ARGOCD_URL} ${ARGOCD_TOKEN} ${K8S_SA_TOKEN} ${K8S_CA_DATA}' \
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
}
