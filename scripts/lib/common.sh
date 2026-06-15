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

# Argo CD is optional. Helm path skips it unless SKIP_ARGOCD=false (opt-in CD tab).
# Operator path installs Argo CD unless SKIP_ARGOCD=true.
argocd_enabled() {
  case "${SKIP_ARGOCD:-}" in
    true | TRUE | yes | YES | 1) return 1 ;;
    false | FALSE | no | NO | 0) return 0 ;;
  esac
  [[ "${WORKSHOP_INSTALL_METHOD:-helm}" != "helm" ]]
}

argocd_skip_message() {
  if argocd_enabled; then
    return 0
  fi
  echo "Argo CD skipped (Helm path default). Set SKIP_ARGOCD=false in workshop.env for GitOps CD tab."
}

detect_cluster_router_base() {
  local host=""
  host=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -z "${host}" ]]; then
    host=$(oc get route -n openshift-console -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
  fi
  if [[ -n "${host}" && "${host}" == console-openshift-console.* ]]; then
    local detected="${host#console-openshift-console.}"
    if [[ -n "${CLUSTER_ROUTER_BASE:-}" && "${CLUSTER_ROUTER_BASE}" != "${detected}" \
      && "${CLUSTER_ROUTER_BASE}" != "apps.example.com" ]]; then
      echo "Updating CLUSTER_ROUTER_BASE: ${CLUSTER_ROUTER_BASE} -> ${detected} (current cluster)"
    fi
    export CLUSTER_ROUTER_BASE="${detected}"
    return 0
  fi
  if [[ -n "${CLUSTER_ROUTER_BASE:-}" && "${CLUSTER_ROUTER_BASE}" != "apps.example.com" ]]; then
    return 0
  fi
  echo "Set CLUSTER_ROUTER_BASE in scripts/workshop.env (e.g. apps.cluster-name.example.com)" >&2
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
    '${WORKSHOP_NAMESPACE} ${WORKSHOP_GIT_REPO} ${WORKSHOP_GIT_BRANCH} ${WORKSHOP_GITHUB_ORG} ${WORKSHOP_GITHUB_REPO} ${WORKSHOP_BACKEND_IMAGE} ${WORKSHOP_FRONTEND_IMAGE} ${WORKSHOP_IMAGE_REGISTRY} ${RHDH_NAMESPACE} ${RHDH_INSTANCE_NAME} ${RHDH_APP_TITLE} ${GITOPS_NAMESPACE} ${ARGOCD_INSTANCE_NAME} ${ARGOCD_APP_NAME} ${PEOPLE_DB_NAME} ${PEOPLE_DB_USER} ${PEOPLE_DB_PASSWORD} ${PEOPLE_KEYCLOAK_USER} ${PEOPLE_KEYCLOAK_PASSWORD} ${PEOPLE_NOTIFICATION_TOKEN} ${KEYCLOAK_ADMIN_USER} ${KEYCLOAK_ADMIN_PASSWORD} ${KEYCLOAK_REALM} ${KEYCLOAK_CLIENT_ID} ${KEYCLOAK_URL} ${KEYCLOAK_HOST} ${OIDC_AUTH_SERVER_URL} ${OIDC_ENABLED} ${CLUSTER_ROUTER_BASE} ${RHDH_KEYCLOAK_CLIENT_ID} ${RHDH_KEYCLOAK_CLIENT_SECRET} ${RHDH_KEYCLOAK_USER} ${RHDH_KEYCLOAK_PASSWORD} ${RHDH_OIDC_CLIENT_SECRET} ${WORKSHOP_CATALOG_URL} ${BACKEND_SECRET} ${GITHUB_TOKEN} ${ARGOCD_URL} ${ARGOCD_TOKEN} ${K8S_SA_TOKEN} ${K8S_CA_DATA} ${ORCHESTRATOR_DATA_INDEX_IMAGE} ${KEYCLOAK_SERVICE_USER} ${KEYCLOAK_SERVICE_PASSWORD}' \
    <"${input}"
}

apply_rendered_dir() {
  local dir="$1"
  local file
  while IFS= read -r -d '' file; do
    render_manifest "${file}" | oc apply -f -
  done < <(find "${dir}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | sort -z)
}

# Clear pending-install/upgrade Helm locks left by interrupted installs (API timeout, Ctrl+C).
helm_unlock_release() {
  local release="$1"
  local namespace="$2"
  local status last_deployed

  command -v helm >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0
  if ! helm status "${release}" -n "${namespace}" >/dev/null 2>&1; then
    return 0
  fi

  status=$(helm status "${release}" -n "${namespace}" -o json 2>/dev/null | jq -r '.info.status // empty')
  case "${status}" in
    pending-install | pending-upgrade | pending-rollback)
      echo "Helm release ${release} is stuck in ${status} (often after API disconnect). Recovering..."
      last_deployed=$(helm history "${release}" -n "${namespace}" -o json 2>/dev/null \
        | jq -r '[.[] | select(.status == "deployed") | .revision] | last // empty')
      if [[ -n "${last_deployed}" ]]; then
        helm rollback "${release}" "${last_deployed}" -n "${namespace}" --wait --timeout 10m
      else
        echo "No deployed revision for ${release}; removing stuck release..." >&2
        helm uninstall "${release}" -n "${namespace}" --wait --timeout 10m || true
      fi
      ;;
  esac
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
    echo "Keycloak is not deployed in ${WORKSHOP_NAMESPACE}."
    echo "Deploying Keycloak (run ./scripts/bootstrap-workshop.sh for the full stack)..."
    "${SCRIPTS_DIR}/setup-keycloak.sh"
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

  local replicas ready replica_failure
  replicas=$(oc get deployment workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" \
    -o jsonpath='{.spec.replicas}')
  ready=$(oc get deployment workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  replica_failure=$(oc get deployment workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" \
    -o jsonpath='{.status.conditions[?(@.type=="ReplicaFailure")].status}' 2>/dev/null || echo "False")

  if [[ "${replica_failure}" == "True" ]] || [[ "${replicas}" == "0" || "${ready}" != "1" ]]; then
    echo "Ensuring workshop catalog server is running in ${WORKSHOP_NAMESPACE}..."
    if [[ "${replica_failure}" == "True" ]]; then
      echo "Re-applying catalog server manifest (previous rollout failed)..."
      render_manifest "${MANIFESTS_DIR}/developer-hub/catalog-server.yaml" | oc apply -f -
    fi
    oc scale deployment/workshop-catalog-server --replicas=1 -n "${WORKSHOP_NAMESPACE}"
    if ! oc rollout status deployment/workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" --timeout=300s; then
      echo "Catalog server rollout failed. Run ./scripts/configure-developer-hub-catalog.sh" >&2
      return 1
    fi
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

developer_hub_installed() {
  oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1 \
    || oc get deployment "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1 \
    || oc get backstage "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1
}

require_developer_hub() {
  if developer_hub_installed; then
    return 0
  fi
  cat <<EOF >&2
Developer Hub is not installed in ${RHDH_NAMESPACE}.
Install the workshop platform first:

  ./scripts/bootstrap-workshop.sh

Helm path (no operators):

  export WORKSHOP_INSTALL_METHOD=helm
  ./scripts/bootstrap-workshop.sh
EOF
  return 1
}

upsert_workshop_env() {
  local key="$1"
  local value="$2"
  local file="${SCRIPTS_DIR}/workshop.env"
  local tmp
  tmp="$(mktemp)"

  if [[ ! -f "${file}" ]]; then
    cp "${SCRIPTS_DIR}/workshop.env.example" "${file}"
    echo "Created ${file} from workshop.env.example"
  fi

  if grep -q "^export ${key}=" "${file}"; then
    awk -v k="${key}" -v v="${value}" '
      BEGIN { updated = 0 }
      $0 ~ "^export " k "=" {
        print "export " k "=\"" v "\""
        updated = 1
        next
      }
      { print }
      END {
        if (!updated) {
          print "export " k "=\"" v "\""
        }
      }
    ' "${file}" >"${tmp}"
  else
    cp "${file}" "${tmp}"
    printf '\nexport %s="%s"\n' "${key}" "${value}" >>"${tmp}"
  fi
  mv "${tmp}" "${file}"
}

validate_github_pat() {
  local token="$1"
  local tmp_headers tmp_body login scopes repo_access

  if [[ -z "${token}" || "${token}" == "changeme" ]]; then
    echo "GITHUB_TOKEN is not set." >&2
    return 1
  fi

  tmp_headers="$(mktemp)"
  tmp_body="$(mktemp)"
  if ! curl -fsSL -D "${tmp_headers}" -o "${tmp_body}" \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/user; then
    rm -f "${tmp_headers}" "${tmp_body}"
    echo "GitHub token validation failed (HTTP error from api.github.com/user)." >&2
    return 1
  fi

  login="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("login",""))' "${tmp_body}")"
  scopes="$(awk 'BEGIN { IGNORECASE=1 } /^x-oauth-scopes:/ { sub(/^[^:]+:[[:space:]]*/, ""); print }' "${tmp_headers}" | tr -d '\r')"
  rm -f "${tmp_headers}" "${tmp_body}"

  if [[ -z "${login}" ]]; then
    echo "GitHub token validation failed (empty login)." >&2
    return 1
  fi

  if [[ -n "${scopes}" && "${scopes}" != " " ]]; then
    if [[ "${scopes}" != *repo* ]]; then
      echo "GitHub token is missing the 'repo' scope (required for scaffolder publish)." >&2
      echo "Create a classic PAT at https://github.com/settings/tokens/new with scope: repo" >&2
      return 1
    fi
  fi

  repo_access="$(curl -fsSL -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${WORKSHOP_GITHUB_ORG}/platform-engineering-201" || echo "000")"
  if [[ "${repo_access}" != "200" && "${repo_access}" != "404" ]]; then
    echo "Warning: token could not read GitHub API repos endpoint (HTTP ${repo_access})." >&2
  fi

  echo "${login}"
}

verify_cluster_github_token() {
  local namespace="${RHDH_NAMESPACE:-${WORKSHOP_NAMESPACE}}"
  local secret_token app_config

  if ! oc get secret rhdh-workshop-secrets -n "${namespace}" >/dev/null 2>&1; then
    echo "Secret rhdh-workshop-secrets not found in ${namespace}." >&2
    return 1
  fi

  secret_token="$(oc get secret rhdh-workshop-secrets -n "${namespace}" \
    -o jsonpath='{.data.GITHUB_TOKEN}' | base64 -d)"
  if [[ -z "${secret_token}" || "${secret_token}" == "changeme" ]]; then
    echo "Cluster secret rhdh-workshop-secrets still has GITHUB_TOKEN=changeme." >&2
    return 1
  fi

  if oc get configmap redhat-developer-hub-app-config -n "${namespace}" >/dev/null 2>&1; then
    app_config="$(oc get configmap redhat-developer-hub-app-config -n "${namespace}" \
      -o jsonpath='{.data.app-config\.yaml}')"
  else
    app_config="$(oc get configmap app-config-rhdh -n "${namespace}" \
      -o jsonpath='{.data.app-config-rhdh\.yaml}' 2>/dev/null || true)"
  fi

  if [[ -z "${app_config}" ]]; then
    echo "Developer Hub app-config ConfigMap not found." >&2
    return 1
  fi

  if ! grep -Fq "token: ${secret_token}" <<<"${app_config}" \
    && ! grep -Fq "Authorization: Bearer ${secret_token}" <<<"${app_config}"; then
    echo "Developer Hub app-config does not contain the configured GitHub token." >&2
    return 1
  fi

  return 0
}
