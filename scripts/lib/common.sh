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
export LIGHTSPEED_ENABLED
export OPENAI_API_KEY
export OPENAI_MODEL
export LIGHTSPEED_VLLM_MAX_TOKENS
export LIGHTSPEED_ENABLE_OPENAI
export LIGHTSPEED_SAFETY_GUARD
export MCP_TOKEN

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

# Extract apps domain suffix from a route host like keycloak-myns.apps.cluster.example.com
router_base_from_route_host() {
  local host="$1"
  local namespace="${2:-${WORKSHOP_NAMESPACE}}"
  local suffix="-${namespace}."

  [[ -n "${host}" && -n "${namespace}" ]] || return 1
  [[ "${host}" == *"${suffix}"* ]] || return 1
  echo "${host#*"${suffix}"}"
}

detect_router_base_from_namespace_routes() {
  local namespace="${1:-${WORKSHOP_NAMESPACE}}"
  local route_name host router_base

  require_oc
  [[ -n "${namespace}" ]] || return 1

  for route_name in keycloak people-frontend people-backend redhat-developer-hub \
    workshop-catalog-server argocd-server; do
    host=$(get_route_host "${namespace}" "${route_name}" 2>/dev/null || true)
    if router_base=$(router_base_from_route_host "${host}" "${namespace}"); then
      echo "${router_base}"
      return 0
    fi
  done

  host=$(oc get route -n "${namespace}" -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
  if router_base=$(router_base_from_route_host "${host}" "${namespace}"); then
    echo "${router_base}"
    return 0
  fi
  return 1
}

persist_cluster_router_base() {
  local detected="$1"
  local env_file="${SCRIPTS_DIR}/workshop.env"
  local current=""

  [[ -n "${detected}" && -f "${env_file}" ]] || return 0
  if grep -q '^export CLUSTER_ROUTER_BASE=' "${env_file}"; then
    current=$(grep '^export CLUSTER_ROUTER_BASE=' "${env_file}" \
      | sed -E 's/^export CLUSTER_ROUTER_BASE=//' \
      | sed -E 's/^"//; s/"$//; s/^'\''//; s/'\''$//')
    if [[ "${current}" == "${detected}" || "${current}" == "apps.example.com" ]]; then
      return 0
    fi
    sed_inplace "s|^export CLUSTER_ROUTER_BASE=.*|export CLUSTER_ROUTER_BASE=\"${detected}\"|" "${env_file}"
    echo "Persisted CLUSTER_ROUTER_BASE=${detected} in ${env_file}"
  fi
}

detect_cluster_router_base() {
  local host="" detected="" old_base="${CLUSTER_ROUTER_BASE:-}"

  if command -v oc >/dev/null 2>&1; then
    host=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [[ -z "${host}" ]]; then
      host=$(oc get route -n openshift-console -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
    fi
    if [[ -n "${host}" && "${host}" == console-openshift-console.* ]]; then
      detected="${host#console-openshift-console.}"
    fi

    if [[ -z "${detected}" ]]; then
      detected=$(detect_router_base_from_namespace_routes "${WORKSHOP_NAMESPACE}" 2>/dev/null || true)
    fi
  fi

  if [[ -n "${detected}" ]]; then
    if [[ -n "${old_base}" && "${old_base}" != "${detected}" && "${old_base}" != "apps.example.com" ]]; then
      echo "Updating CLUSTER_ROUTER_BASE: ${old_base} -> ${detected} (current cluster)"
    fi
    export CLUSTER_ROUTER_BASE="${detected}"
    persist_cluster_router_base "${detected}"
    return 0
  fi

  if [[ -n "${old_base}" && "${old_base}" != "apps.example.com" ]]; then
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

# GNU sed uses -i; BSD sed (macOS) requires -i ''.
sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# GNU base64 uses -d; macOS/BSD base64 uses -D.
base64_decode() {
  if printf 'dGVzdA==' | base64 -d >/dev/null 2>&1; then
    base64 -d
  else
    base64 -D
  fi
}

# Substitute ${VAR} placeholders from stdin. Uses gettext envsubst when installed;
# otherwise a pure-bash fallback (RHDAT / minimal sandboxes often lack gettext).
workshop_envsubst() {
  local var_spec="$1"
  if command -v envsubst >/dev/null 2>&1; then
    envsubst "${var_spec}"
    return 0
  fi

  local content token name value
  content=$(cat)
  for token in ${var_spec}; do
    name="${token#\$\{}"
    name="${name%\}}"
    if [[ "${name}" == "${token}" ]]; then
      name="${token#\$}"
    fi
    [[ -z "${name}" ]] && continue
    value="${!name-}"
    content="${content//\$\{${name}\}/${value}}"
    content="${content//\$${name}/${value}}"
  done
  printf '%s' "${content}"
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
  local rendered

  if [[ ! -f "${input}" ]]; then
    echo "Manifest not found: ${input}" >&2
    return 1
  fi

  rendered="$(
    workshop_envsubst \
      '${WORKSHOP_NAMESPACE} ${WORKSHOP_GIT_REPO} ${WORKSHOP_GIT_BRANCH} ${WORKSHOP_GITHUB_ORG} ${WORKSHOP_GITHUB_REPO} ${WORKSHOP_BACKEND_IMAGE} ${WORKSHOP_FRONTEND_IMAGE} ${WORKSHOP_IMAGE_REGISTRY} ${RHDH_NAMESPACE} ${RHDH_INSTANCE_NAME} ${RHDH_APP_TITLE} ${GITOPS_NAMESPACE} ${ARGOCD_INSTANCE_NAME} ${ARGOCD_APP_NAME} ${PEOPLE_DB_NAME} ${PEOPLE_DB_USER} ${PEOPLE_DB_PASSWORD} ${PEOPLE_KEYCLOAK_USER} ${PEOPLE_KEYCLOAK_PASSWORD} ${PEOPLE_NOTIFICATION_TOKEN} ${KEYCLOAK_ADMIN_USER} ${KEYCLOAK_ADMIN_PASSWORD} ${KEYCLOAK_REALM} ${KEYCLOAK_CLIENT_ID} ${KEYCLOAK_URL} ${KEYCLOAK_HOST} ${OIDC_AUTH_SERVER_URL} ${OIDC_ENABLED} ${CLUSTER_ROUTER_BASE} ${RHDH_KEYCLOAK_CLIENT_ID} ${RHDH_KEYCLOAK_CLIENT_SECRET} ${RHDH_KEYCLOAK_USER} ${RHDH_KEYCLOAK_PASSWORD} ${RHDH_OIDC_CLIENT_SECRET} ${WORKSHOP_CATALOG_URL} ${BACKEND_SECRET} ${GITHUB_TOKEN} ${ARGOCD_URL} ${ARGOCD_TOKEN} ${K8S_SA_TOKEN} ${K8S_CA_DATA} ${ORCHESTRATOR_DATA_INDEX_IMAGE} ${KEYCLOAK_SERVICE_USER} ${KEYCLOAK_SERVICE_PASSWORD} ${LIGHTSPEED_ENABLE_OPENAI} ${OPENAI_API_KEY} ${OPENAI_MODEL} ${LIGHTSPEED_VLLM_MAX_TOKENS} ${MCP_TOKEN} ${RHDH_HOST}' \
      <"${input}"
  )" || return 1

  if [[ -z "${rendered//[[:space:]]/}" ]]; then
    echo "render_manifest produced empty output for ${input} (check scripts/workshop.env exports)" >&2
    return 1
  fi

  printf '%s' "${rendered}"
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

# Prefer an existing Developer Hub route host for Helm upgrades (sandbox-safe).
# OpenShift sandboxes reject Route.spec.host when it does not match the assigned router domain.
resolve_rhdh_helm_global_host() {
  local host=""

  host=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null || true)
  if [[ -n "${host}" ]]; then
    echo "${host}"
    return 0
  fi
  host=$(get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null || true)
  if [[ -n "${host}" ]]; then
    echo "${host}"
    return 0
  fi
  echo ""
}

resolve_argocd_route_host() {
  if oc get route argocd-server -n "${GITOPS_NAMESPACE}" >/dev/null 2>&1; then
    get_route_host "${GITOPS_NAMESPACE}" "argocd-server"
    return 0
  fi
  if oc get route "${ARGOCD_INSTANCE_NAME}-server" -n "${GITOPS_NAMESPACE}" >/dev/null 2>&1; then
    get_route_host "${GITOPS_NAMESPACE}" "${ARGOCD_INSTANCE_NAME}-server"
    return 0
  fi
  echo ""
}

resolve_rhdh_deploy_name() {
  if oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    echo "redhat-developer-hub"
  elif oc get deployment "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    echo "${RHDH_INSTANCE_NAME}"
  else
    echo "redhat-developer-hub"
  fi
}

developer_hub_uses_plugins_pvc() {
  local deploy_name="${1:-$(resolve_rhdh_deploy_name)}"
  oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" -o json \
    | jq -e '.spec.template.spec.volumes[]
       | select(.name == "dynamic-plugins-root")
       | .persistentVolumeClaim.claimName' >/dev/null 2>&1
}

clear_dynamic_plugins_install_lock() {
  local pod
  pod="$(oc get pod -n "${RHDH_NAMESPACE}" -l app.kubernetes.io/name=developer-hub \
    -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null \
    | awk '{print $1}')"
  if [[ -n "${pod}" ]]; then
    for path in \
      /dynamic-plugins-root/install-dynamic-plugins.lock \
      /dynamic-plugins-root/dynamic-plugins.lock \
      /opt/app-root/src/dynamic-plugins-root/install-dynamic-plugins.lock \
      /opt/app-root/src/dynamic-plugins-root/dynamic-plugins.lock; do
      oc exec -n "${RHDH_NAMESPACE}" "${pod}" -c install-dynamic-plugins -- \
        rm -f "${path}" 2>/dev/null \
        || oc exec -n "${RHDH_NAMESPACE}" "${pod}" -c backstage-backend -- \
          rm -f "${path}" 2>/dev/null \
        || true
    done
  fi

  if ! oc get pvc dynamic-plugins-root -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    echo "Cleared dynamic plugins install lock (if present)."
    return 0
  fi

  local job_pod="workshop-plugins-lock-clear"
  oc delete pod "${job_pod}" -n "${RHDH_NAMESPACE}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  oc run "${job_pod}" -n "${RHDH_NAMESPACE}" --restart=Never \
    --image=registry.redhat.io/ubi9/ubi-minimal \
    --overrides='{"spec":{"containers":[{"name":"clear","image":"registry.redhat.io/ubi9/ubi-minimal","command":["sh","-c","rm -fv /mnt/install-dynamic-plugins.lock /mnt/dynamic-plugins.lock; echo cleared"],"volumeMounts":[{"name":"pvc","mountPath":"/mnt"}]}],"volumes":[{"name":"pvc","persistentVolumeClaim":{"claimName":"dynamic-plugins-root"}}]}}' \
    -- sleep 30 >/dev/null

  local i
  for i in $(seq 1 30); do
    if oc logs "${job_pod}" -n "${RHDH_NAMESPACE}" 2>/dev/null | grep -q cleared; then
      break
    fi
    sleep 2
  done
  oc logs "${job_pod}" -n "${RHDH_NAMESPACE}" 2>/dev/null || true
  oc delete pod "${job_pod}" -n "${RHDH_NAMESPACE}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  echo "Cleared dynamic plugins install lock (if present)."
}

clear_aap_management_plugins_from_pvc() {
  if ! oc get pvc dynamic-plugins-root -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    return 0
  fi

  local job_pod="workshop-aap-mgmt-plugins-clear"
  oc delete pod "${job_pod}" -n "${RHDH_NAMESPACE}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  oc run "${job_pod}" -n "${RHDH_NAMESPACE}" --restart=Never \
    --image=registry.redhat.io/ubi9/ubi-minimal \
    --overrides='{"spec":{"containers":[{"name":"clear","image":"registry.redhat.io/ubi9/ubi-minimal","command":["sh","-c","rm -rfv /mnt/internal-plugin-aap-management-dynamic-* /mnt/internal-plugin-aap-management-backend-dynamic-*; echo cleared-aap-mgmt-plugins"],"volumeMounts":[{"name":"pvc","mountPath":"/mnt"}]}],"volumes":[{"name":"pvc","persistentVolumeClaim":{"claimName":"dynamic-plugins-root"}}]}}' \
    -- sleep 30 >/dev/null

  local i
  for i in $(seq 1 30); do
    if oc logs "${job_pod}" -n "${RHDH_NAMESPACE}" 2>/dev/null | grep -q cleared-aap-mgmt-plugins; then
      break
    fi
    sleep 2
  done
  oc logs "${job_pod}" -n "${RHDH_NAMESPACE}" 2>/dev/null || true
  oc delete pod "${job_pod}" -n "${RHDH_NAMESPACE}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  echo "Cleared stale AAP Management plugin directories from dynamic-plugins-root PVC (if present)."
}

wait_for_developer_hub_pods_gone() {
  local i count
  for i in $(seq 1 60); do
    count="$(oc get pod -n "${RHDH_NAMESPACE}" -l app.kubernetes.io/name=developer-hub \
      --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    [[ "${count}" == "0" ]] && return 0
    sleep 5
  done
  return 1
}

rollout_timeout_to_seconds() {
  local spec="${1:-600s}"
  local num="${spec%s}"

  if [[ "${num}" =~ ^([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "${spec}" =~ ^([0-9]+)m$ ]]; then
    echo $(( BASH_REMATCH[1] * 60 ))
    return 0
  fi
  if [[ "${spec}" =~ ^([0-9]+)h$ ]]; then
    echo $(( BASH_REMATCH[1] * 3600 ))
    return 0
  fi
  echo 600
}

resolve_deployment_label_selector() {
  local deploy_name="$1"
  local namespace="$2"

  command -v jq >/dev/null 2>&1 || return 1
  oc get deployment "${deploy_name}" -n "${namespace}" -o json 2>/dev/null \
    | jq -r '.spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")'
}

deployment_pod_fatal_reason() {
  local namespace="$1"
  local label_selector="$2"
  local reason=""

  reason="$(oc get pod -n "${namespace}" -l "${label_selector}" -o json 2>/dev/null \
    | jq -r '[.items[] | .status.containerStatuses[]?, .status.initContainerStatuses[]?
       | .state.waiting.reason // empty]
       | map(select(. == "CrashLoopBackOff" or . == "ImagePullBackOff" or . == "ErrImagePull"
         or . == "CreateContainerConfigError" or . == "InvalidImageName" or . == "RunContainerError"))
       | .[0] // empty' 2>/dev/null || true)"
  if [[ -n "${reason}" ]]; then
    echo "${reason}"
    return 0
  fi

  if oc get pod -n "${namespace}" -l "${label_selector}" -o jsonpath='{.items[?(@.status.phase=="Failed")].metadata.name}' 2>/dev/null \
    | grep -q .; then
    echo "Failed"
    return 0
  fi

  return 1
}

deployment_rollout_progress_line() {
  local deploy_name="$1"
  local namespace="$2"
  local label_selector="$3"
  local spec_replicas ready_replicas pod_line init_active

  spec_replicas="$(oc get deployment "${deploy_name}" -n "${namespace}" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")"
  ready_replicas="$(oc get deployment "${deploy_name}" -n "${namespace}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
  ready_replicas="${ready_replicas:-0}"

  pod_line="$(oc get pod -n "${namespace}" -l "${label_selector}" \
    --sort-by=.metadata.creationTimestamp --no-headers 2>/dev/null | tail -1 || true)"
  if [[ -z "${pod_line}" ]]; then
    echo "Still waiting — scheduling pods (${ready_replicas}/${spec_replicas} ready)"
    return 0
  fi

  init_active="$(oc get pod -n "${namespace}" -l "${label_selector}" \
    -o json 2>/dev/null \
    | jq -r '[.items[-1].status.initContainerStatuses[]? | select(.state.running == null and .state.terminated == null) | .name] | join(", ")' 2>/dev/null || true)"
  if [[ -n "${init_active}" ]]; then
    echo "Still waiting — ${pod_line} (init: ${init_active}; ${ready_replicas}/${spec_replicas} ready)"
  else
    echo "Still waiting — ${pod_line} (${ready_replicas}/${spec_replicas} ready)"
  fi
}

print_deployment_pod_failure_hints() {
  local namespace="$1"
  local label_selector="$2"
  local fatal_reason="${3:-}"
  local pod crash_container log_container

  pod="$(oc get pod -n "${namespace}" -l "${label_selector}" \
    --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || true)"
  [[ -n "${pod}" ]] || return 0

  echo "  Pod: ${pod}" >&2
  crash_container="$(oc get pod "${pod}" -n "${namespace}" -o json 2>/dev/null \
    | jq -r '[.status.initContainerStatuses[]?, .status.containerStatuses[]?
       | select(.state.waiting.reason == "CrashLoopBackOff" or .state.waiting.reason == "ImagePullBackOff"
         or .state.waiting.reason == "ErrImagePull" or .state.waiting.reason == "CreateContainerConfigError")
       | "\(.name) (\(.state.waiting.reason))"] | first // empty' 2>/dev/null || true)"
  if [[ -n "${crash_container}" ]]; then
    echo "  Failing container: ${crash_container}" >&2
  fi

  log_container="${crash_container%% *}"
  if [[ -z "${log_container}" ]]; then
    log_container="install-dynamic-plugins"
  fi

  echo "  --- ${log_container} logs (last 25 lines) ---" >&2
  oc logs "${pod}" -n "${namespace}" -c "${log_container}" --tail=25 --previous 2>/dev/null \
    || oc logs "${pod}" -n "${namespace}" -c "${log_container}" --tail=25 2>/dev/null \
    || true

  if [[ "${AAP_ENABLED:-false}" == "true" || "${AAP_ENABLED:-false}" == "1" || "${AAP_ENABLED:-false}" == "yes" ]]; then
    if ! oc get secret redhat-developer-hub-dynamic-plugins-registry-auth -n "${namespace}" >/dev/null 2>&1; then
      echo "  HINT: AAP_ENABLED=true but secret redhat-developer-hub-dynamic-plugins-registry-auth is missing." >&2
      echo "        Set RH_REGISTRY_USERNAME/RH_REGISTRY_TOKEN and run ./scripts/setup-developer-hub-aap.sh" >&2
    fi
  fi

  if [[ "${fatal_reason}" == "CrashLoopBackOff" ]] \
    && oc logs "${pod}" -n "${namespace}" -c install-dynamic-plugins --tail=5 2>/dev/null \
      | grep -qiE 'Please login to the Red Hat Registry|unauthorized|authentication required'; then
    echo "  HINT: registry.redhat.io auth failed — configure RH registry credentials before re-running bootstrap." >&2
  fi
}

deployment_still_progressing() {
  local namespace="$1"
  local label_selector="$2"
  local pod_count running_or_init pending_scheduled

  pod_count="$(oc get pod -n "${namespace}" -l "${label_selector}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  [[ "${pod_count}" -gt 0 ]] || return 1

  running_or_init="$(oc get pod -n "${namespace}" -l "${label_selector}" -o json 2>/dev/null \
    | jq -r '[.items[] | select(.status.phase == "Running")
       | (.status.initContainerStatuses // [])[] | select(.state.running or (.state.terminated | not))
       | .name] | length' 2>/dev/null || echo "0")"
  if [[ "${running_or_init}" -gt 0 ]]; then
    return 0
  fi

  pending_scheduled="$(oc get pod -n "${namespace}" -l "${label_selector}" -o json 2>/dev/null \
    | jq -r '[.items[] | select(.status.phase == "Pending" and (.spec.nodeName // "") != "")] | length' 2>/dev/null || echo "0")"
  if [[ "${pending_scheduled}" -gt 0 ]]; then
    return 0
  fi

  if oc get pod -n "${namespace}" -l "${label_selector}" -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null \
    | grep -q .; then
    return 0
  fi

  return 1
}

# Friendly rollout wait: progress updates instead of oc rollout status noise/timeouts.
# Returns 0 when ready, or when still progressing after timeout (slow sandbox startup).
# Returns 1 only for fatal pod errors or a stuck deployment with no progress.
wait_for_deployment_rollout() {
  local deploy_name="$1"
  local namespace="$2"
  local timeout_spec="${3:-600s}"
  local hint="${4:-Startup can take several minutes on sandbox clusters.}"
  local label_selector="${5:-}"

  local timeout_secs interval=15 progress_interval=30
  local start now elapsed last_progress fatal_reason

  timeout_secs="$(rollout_timeout_to_seconds "${timeout_spec}")"
  if [[ -z "${label_selector}" ]]; then
    label_selector="$(resolve_deployment_label_selector "${deploy_name}" "${namespace}" 2>/dev/null || true)"
  fi
  [[ -n "${label_selector}" ]] || label_selector="app.kubernetes.io/name=developer-hub"

  echo "Waiting for deployment/${deploy_name} in ${namespace} (up to $(( timeout_secs / 60 )) min)..."
  echo "  ${hint}"

  start=$(date +%s)
  last_progress="${start}"
  while true; do
    now=$(date +%s)
    elapsed=$(( now - start ))

    if ! oc get deployment "${deploy_name}" -n "${namespace}" >/dev/null 2>&1; then
      if (( elapsed >= timeout_secs )); then
        echo "Deployment/${deploy_name} was not created within $(( timeout_secs / 60 )) minutes." >&2
        return 1
      fi
      if (( now - last_progress >= progress_interval )); then
        echo "  Still waiting — deployment/${deploy_name} not created yet..."
        last_progress="${now}"
      fi
      sleep "${interval}"
      continue
    fi

    local spec_replicas ready_replicas updated_replicas unavailable
    spec_replicas="$(oc get deployment "${deploy_name}" -n "${namespace}" \
      -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")"
    ready_replicas="$(oc get deployment "${deploy_name}" -n "${namespace}" \
      -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
    ready_replicas="${ready_replicas:-0}"
    updated_replicas="$(oc get deployment "${deploy_name}" -n "${namespace}" \
      -o jsonpath='{.status.updatedReplicas}' 2>/dev/null || echo "0")"
    updated_replicas="${updated_replicas:-0}"
    unavailable="$(oc get deployment "${deploy_name}" -n "${namespace}" \
      -o jsonpath='{.status.unavailableReplicas}' 2>/dev/null || echo "0")"
    unavailable="${unavailable:-0}"

    if [[ "${spec_replicas}" -gt 0 && "${ready_replicas}" -ge "${spec_replicas}" \
      && "${updated_replicas}" -ge "${spec_replicas}" && "${unavailable}" == "0" ]]; then
      echo "Deployment/${deploy_name} is ready (${ready_replicas}/${spec_replicas} replicas)."
      return 0
    fi

    if fatal_reason="$(deployment_pod_fatal_reason "${namespace}" "${label_selector}")"; then
      echo "Deployment/${deploy_name} has pods in ${fatal_reason} — this is a real failure." >&2
      print_deployment_pod_failure_hints "${namespace}" "${label_selector}" "${fatal_reason}"
      echo "  oc describe pod -n ${namespace} -l ${label_selector}" >&2
      echo "  oc logs -n ${namespace} -l ${label_selector} -c install-dynamic-plugins --tail=80" >&2
      return 1
    fi

    if (( elapsed >= timeout_secs )); then
      if deployment_still_progressing "${namespace}" "${label_selector}"; then
        echo "Note: deployment/${deploy_name} is still starting after $(( timeout_secs / 60 )) minutes but pods look healthy — continuing bootstrap."
        echo "  Watch progress: oc get pod -n ${namespace} -l ${label_selector} -w"
        return 0
      fi
      echo "Deployment/${deploy_name} did not become ready within $(( timeout_secs / 60 )) minutes." >&2
      echo "  oc get pod -n ${namespace} -l ${label_selector}" >&2
      return 1
    fi

    if (( now - last_progress >= progress_interval )); then
      deployment_rollout_progress_line "${deploy_name}" "${namespace}" "${label_selector}"
      last_progress="${now}"
    fi

    sleep "${interval}"
  done
}

wait_for_developer_hub_rollout() {
  local deploy_name="${1:-$(resolve_rhdh_deploy_name)}"
  local timeout_spec="${2:-}"
  local hint="Dynamic plugins and sidecars can take 10–15 minutes on sandbox clusters — this is normal."

  # shellcheck disable=SC1091
  source "${LIB_DIR}/developer-hub-dynamic-plugins.sh"
  if [[ -z "${timeout_spec}" ]]; then
    timeout_spec="$(rollout_timeout_for_config)"
  fi
  if is_aap_enabled; then
    hint="Ansible dynamic plugins are downloading — first install can take 15–30 minutes on sandbox."
  fi

  wait_for_deployment_rollout "${deploy_name}" "${RHDH_NAMESPACE}" "${timeout_spec}" "${hint}" \
    "app.kubernetes.io/name=developer-hub"
}

safe_rollout_developer_hub() {
  local deploy_name="${1:-$(resolve_rhdh_deploy_name)}"
  local timeout="${2:-900s}"
  local replicas

  replicas="$(oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" -o jsonpath='{.spec.replicas}')"
  if [[ -z "${replicas}" || "${replicas}" == "0" ]]; then
    replicas=1
  fi

  echo "Scaling ${deploy_name} to 0 to release dynamic-plugins PVC and avoid lock contention..."
  oc scale "deployment/${deploy_name}" -n "${RHDH_NAMESPACE}" --replicas=0
  wait_for_developer_hub_pods_gone || wait_for_deployment_rollout "${deploy_name}" "${RHDH_NAMESPACE}" 300s \
    "Waiting for pods to terminate before clearing plugin locks." \
    "app.kubernetes.io/name=developer-hub" || true

  if developer_hub_uses_plugins_pvc "${deploy_name}" \
    || oc get pvc dynamic-plugins-root -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    clear_dynamic_plugins_install_lock
    if [[ "${CLEAR_AAP_MANAGEMENT_PLUGINS_FROM_PVC:-false}" == "true" \
      || "${CLEAR_AAP_MANAGEMENT_PLUGINS_FROM_PVC:-false}" == "1" \
      || "${CLEAR_AAP_MANAGEMENT_PLUGINS_FROM_PVC:-false}" == "yes" ]]; then
      clear_aap_management_plugins_from_pvc
    fi
  fi

  echo "Scaling ${deploy_name} back to ${replicas} replica(s)..."
  oc scale "deployment/${deploy_name}" -n "${RHDH_NAMESPACE}" --replicas="${replicas}"
  wait_for_developer_hub_rollout "${deploy_name}" "${timeout}"
}

install_pyyaml_via_os_packages() {
  local -a attempted=()
  local mgr

  for mgr in microdnf dnf; do
    command -v "${mgr}" >/dev/null 2>&1 || continue

    if command -v sudo >/dev/null 2>&1 && [[ "$(id -u)" -ne 0 ]]; then
      attempted+=("sudo ${mgr} install -y python3-pyyaml")
      if sudo "${mgr}" install -y python3-pyyaml >/dev/null 2>&1 \
        && python3 -c 'import yaml' 2>/dev/null; then
        return 0
      fi
    fi

    attempted+=("${mgr} install -y python3-pyyaml")
    if "${mgr}" install -y python3-pyyaml >/dev/null 2>&1 \
      && python3 -c 'import yaml' 2>/dev/null; then
      return 0
    fi
  done

  printf '%s\n' "${attempted[@]}"
  return 1
}

ensure_pyyaml() {
  if python3 -c 'import yaml' 2>/dev/null; then
    return 0
  fi

  echo "PyYAML not found; installing for Developer Hub app-config scripts..." >&2

  local -a attempted=()
  local os_attempted

  os_attempted="$(install_pyyaml_via_os_packages || true)"
  if [[ -n "${os_attempted}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] && attempted+=("${line}")
    done <<<"${os_attempted}"
  fi
  if python3 -c 'import yaml' 2>/dev/null; then
    return 0
  fi

  attempted+=("python3 -m ensurepip + python3 -m pip install pyyaml")

  if ! python3 -m pip --version >/dev/null 2>&1; then
    # ensurepip writes to stdout; never capture this function inside $().
    python3 -m ensurepip --user --default-pip >/dev/null 2>&1 \
      || python3 -m ensurepip --default-pip >/dev/null 2>&1 \
      || true
  fi

  if python3 -m pip --version >/dev/null 2>&1; then
    local -a pip_install=(python3 -m pip install)
    if ! python3 -c 'import sys; raise SystemExit(0 if sys.prefix != sys.base_prefix else 1)' 2>/dev/null; then
      pip_install+=(--user)
      if python3 -m pip install --help 2>/dev/null | grep -q -- '--break-system-packages'; then
        pip_install+=(--break-system-packages)
      fi
    fi
    pip_install+=(-q pyyaml)
    "${pip_install[@]}" >/dev/null 2>&1 || true
  else
    attempted+=("python3 -m pip install --user pyyaml (pip unavailable after ensurepip)")
  fi

  if python3 -c 'import yaml' 2>/dev/null; then
    return 0
  fi

  echo "ERROR: failed to install PyYAML. Attempted:" >&2
  for method in "${attempted[@]}"; do
    echo "  - ${method}" >&2
  done
  echo "Install manually (RHEL/UBI): sudo dnf install -y python3-pyyaml" >&2
  echo "  or: sudo microdnf install -y python3-pyyaml" >&2
  return 1
}

load_mcp_token_from_cluster() {
  local token app_config

  if oc get secret lightspeed-mcp-token -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    token="$(oc get secret lightspeed-mcp-token -n "${RHDH_NAMESPACE}" \
      -o jsonpath='{.data.token}' 2>/dev/null | base64_decode 2>/dev/null || true)"
    token="${token#Bearer }"
    if [[ -n "${token}" && "${token}" != "changeme" ]]; then
      echo "${token}"
      return 0
    fi
  fi

  if oc get configmap redhat-developer-hub-app-config -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    app_config="$(oc get configmap redhat-developer-hub-app-config -n "${RHDH_NAMESPACE}" \
      -o jsonpath='{.data.app-config\.yaml}' 2>/dev/null || true)"
  elif oc get configmap app-config-rhdh -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    app_config="$(oc get configmap app-config-rhdh -n "${RHDH_NAMESPACE}" \
      -o jsonpath='{.data.app-config-rhdh\.yaml}' 2>/dev/null || true)"
  fi

  if [[ -n "${app_config}" ]]; then
    token="$(python3 - "${app_config}" <<'PY'
import sys, yaml
config = yaml.safe_load(sys.argv[1]) or {}
for entry in config.get("backend", {}).get("auth", {}).get("externalAccess", []) or []:
    if entry.get("type") != "static":
        continue
    options = entry.get("options") or {}
    if options.get("subject") == "mcp-clients" and options.get("token"):
        print(options["token"])
        break
PY
)"
    if [[ -n "${token}" && "${token}" != "changeme" ]]; then
      echo "${token}"
      return 0
    fi
  fi

  return 1
}

ensure_mcp_token() {
  if [[ -n "${MCP_TOKEN:-}" && "${MCP_TOKEN}" != "changeme" ]]; then
    export MCP_TOKEN
    return 0
  fi

  ensure_pyyaml

  if MCP_TOKEN="$(load_mcp_token_from_cluster)"; then
    export MCP_TOKEN
    echo "Using existing MCP_TOKEN from cluster (add to scripts/workshop.env to keep it stable across re-runs):"
    echo "  export MCP_TOKEN=\"${MCP_TOKEN}\""
    return 0
  fi

  MCP_TOKEN="$(openssl rand -base64 24 | tr -d '\n/+= ' | head -c 32)"
  export MCP_TOKEN
  echo "Generated MCP_TOKEN (add to scripts/workshop.env to keep it stable across re-runs):"
  echo "  export MCP_TOKEN=\"${MCP_TOKEN}\""
}

sync_mcp_token_in_app_config() {
  ensure_pyyaml
  ensure_mcp_token

  render_manifest "${MANIFESTS_DIR}/developer-hub/lightspeed-mcp-token-secret.yaml" | oc apply -f -

  local cm_key cm_name tmp merged
  if oc get configmap redhat-developer-hub-app-config -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    cm_name="redhat-developer-hub-app-config"
    cm_key="app-config.yaml"
  elif oc get configmap app-config-rhdh -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    cm_name="app-config-rhdh"
    cm_key="app-config-rhdh.yaml"
  else
    echo "Developer Hub app-config ConfigMap not found; MCP secret applied only." >&2
    return 0
  fi

  tmp="$(mktemp)"
  oc get configmap "${cm_name}" -n "${RHDH_NAMESPACE}" -o json \
    | jq -r --arg key "${cm_key}" '.data[$key]' >"${tmp}"

  local sync_status=0
  python3 - "${tmp}" "${MCP_TOKEN}" <<'PY' || sync_status=$?
import sys, yaml

path, token = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    config = yaml.safe_load(handle) or {}

external = config.setdefault("backend", {}).setdefault("auth", {}).setdefault("externalAccess", [])
updated = False
for entry in external:
    if entry.get("type") != "static":
        continue
    options = entry.setdefault("options", {})
    if options.get("subject") == "mcp-clients":
        if options.get("token") != token:
            options["token"] = token
            updated = True
        break
else:
    external.append(
        {
            "type": "static",
            "options": {"token": token, "subject": "mcp-clients"},
        }
    )
    updated = True

lightspeed = config.setdefault("lightspeed", {})
servers = lightspeed.setdefault("mcpServers", [])
for server in servers:
    if server.get("name") == "mcp::backstage":
        bearer = f"Bearer {token}"
        if server.get("token") != bearer:
            server["token"] = bearer
            updated = True
        break
else:
    servers.append({"name": "mcp::backstage", "token": f"Bearer {token}"})
    updated = True

if not updated:
    sys.exit(2)

with open(path, "w", encoding="utf-8") as handle:
    yaml.dump(config, handle, default_flow_style=False, sort_keys=False, allow_unicode=True)
PY

  if [[ "${sync_status}" -eq 0 ]]; then
    oc create configmap "${cm_name}" -n "${RHDH_NAMESPACE}" \
      --from-file="${cm_key}=${tmp}" \
      --dry-run=client -o yaml | oc apply -f -
    echo "Synced MCP token in ${cm_name}."
  elif [[ "${sync_status}" -eq 2 ]]; then
    echo "MCP token already synced in ${cm_name}."
  else
    rm -f "${tmp}"
    return 1
  fi
  rm -f "${tmp}"
}

merge_mcp_into_app_config() {
  ensure_pyyaml
  local base_file="$1"
  local mcp_file="$2"
  local output_file="$3"
  python3 - "${base_file}" "${mcp_file}" "${output_file}" <<'PY'
import sys
import yaml

def merge_lists(base_list, extra_list):
    seen = {yaml.dump(item, sort_keys=True) for item in base_list}
    for item in extra_list:
        key = yaml.dump(item, sort_keys=True)
        if key not in seen:
            base_list.append(item)
            seen.add(key)

def deep_merge(base, extra):
    for key, value in extra.items():
        if key not in base:
            base[key] = value
            continue
        if isinstance(base[key], dict) and isinstance(value, dict):
            deep_merge(base[key], value)
        elif isinstance(base[key], list) and isinstance(value, list):
            merge_lists(base[key], value)
        else:
            base[key] = value

with open(sys.argv[1], encoding="utf-8") as handle:
    base = yaml.safe_load(handle) or {}
with open(sys.argv[2], encoding="utf-8") as handle:
    extra = yaml.safe_load(handle) or {}

deep_merge(base, extra)

with open(sys.argv[3], "w", encoding="utf-8") as handle:
    yaml.dump(base, handle, default_flow_style=False, sort_keys=False, allow_unicode=True)
PY
}

resolve_keycloak_urls() {
  if command -v oc >/dev/null 2>&1 \
    && oc get route keycloak -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
    KEYCLOAK_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "keycloak")
    export KEYCLOAK_URL="https://${KEYCLOAK_HOST}"
  elif [[ -z "${KEYCLOAK_URL:-}" || "${KEYCLOAK_URL}" == *'${'* ]]; then
    export KEYCLOAK_URL="https://keycloak-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}"
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

route_response_is_application_unavailable() {
  local body_file="$1"
  local code="${2:-}"

  if [[ "${code}" == "503" ]]; then
    return 0
  fi
  [[ -f "${body_file}" ]] && grep -qi 'application is not available' "${body_file}"
}

route_http_is_ready() {
  local code="$1"
  local body_file="$2"

  case "${code}" in
    200 | 302 | 303)
      route_response_is_application_unavailable "${body_file}" "${code}" && return 1
      return 0
      ;;
  esac
  return 1
}

# Poll https://host/path until HTTP 200/302/303 (not OpenShift "Application is not available").
wait_for_route_ready() {
  local host="$1"
  local label="${2:-route}"
  local timeout="${3:-900}"
  local path="${4:-/}"
  local url attempt=0 code interval=10 progress_interval=60
  local start now elapsed last_progress body_file=""

  command -v curl >/dev/null 2>&1 || {
    echo "curl is required for route health checks" >&2
    return 1
  }

  [[ -n "${host}" ]] || {
    echo "${label}: route host is empty" >&2
    return 1
  }

  url="https://${host}${path}"
  body_file="$(mktemp)"

  echo "Waiting for ${label} at ${url} (up to $(( timeout / 60 )) min)..."
  start=$(date +%s)
  last_progress="${start}"
  while true; do
    now=$(date +%s)
    elapsed=$(( now - start ))
    attempt=$(( attempt + 1 ))

    code=$(curl -sk -o "${body_file}" -w "%{http_code}" "${url}" 2>/dev/null || echo "000")
    if route_http_is_ready "${code}" "${body_file}"; then
      rm -f "${body_file}"
      echo "${label} is reachable (HTTP ${code})."
      return 0
    fi

    if (( elapsed >= timeout )); then
      echo "${label} is not reachable at ${url} after $(( timeout / 60 )) minutes (last HTTP ${code})." >&2
      if route_response_is_application_unavailable "${body_file}" "${code}"; then
        echo "OpenShift router returned 'Application is not available' — endpoints may be empty or pods not ready." >&2
        echo "  oc get route,svc,endpoints -n ${RHDH_NAMESPACE:-${WORKSHOP_NAMESPACE}}" >&2
        echo "  oc get pod -n ${RHDH_NAMESPACE:-${WORKSHOP_NAMESPACE}} -l app.kubernetes.io/name=developer-hub" >&2
      fi
      rm -f "${body_file}"
      return 1
    fi

    if (( now - last_progress >= progress_interval )); then
      if route_response_is_application_unavailable "${body_file}" "${code}"; then
        echo "  Still waiting — HTTP ${code} (OpenShift: Application is not available; pods may still be starting)..."
      else
        echo "  Still waiting — HTTP ${code}..."
      fi
      last_progress="${now}"
    fi
    sleep "${interval}"
  done
}

wait_for_rhdh_route_ready() {
  local timeout="${1:-900}"
  local host="" start

  start=$(date +%s)
  echo "Waiting for Developer Hub route in ${RHDH_NAMESPACE}..."
  while true; do
    host=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null \
      || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null || true)
    if [[ -n "${host}" ]]; then
      break
    fi
    if (( $(date +%s) - start > 120 )); then
      echo "Developer Hub route not found. Check: oc get route -n ${RHDH_NAMESPACE}" >&2
      return 1
    fi
    sleep 5
  done

  wait_for_route_ready "${host}" "Developer Hub" "${timeout}" "/"
}

print_rhdh_route_url() {
  local host constructed

  host=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null \
    || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null || true)
  if [[ -z "${host}" ]]; then
    host="$(resolve_rhdh_host)"
    echo "Developer Hub (expected): https://${host}"
    echo "  Route not found yet — run: oc get route -n ${RHDH_NAMESPACE}"
    return 1
  fi

  constructed="redhat-developer-hub-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}"
  echo "Developer Hub:  https://${host}"
  if [[ "${host}" != "${constructed}" ]]; then
    echo "  (from oc get route — not ${constructed})"
  fi
}

# Returns 0 when ready, 1 when a repair was applied, 2 when repair is needed (dry-run).
ensure_deployment_running() {
  local deploy_name="${1}"
  local namespace="${2}"
  local desired_replicas="${3:-1}"
  local timeout="${4:-300}"
  local dry_run="${5:-false}"

  if ! oc get deployment "${deploy_name}" -n "${namespace}" >/dev/null 2>&1; then
    return 0
  fi

  local replicas ready
  replicas=$(oc get deployment "${deploy_name}" -n "${namespace}" -o jsonpath='{.spec.replicas}')
  ready=$(oc get deployment "${deploy_name}" -n "${namespace}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  ready="${ready:-0}"

  if [[ "${replicas}" -ge "${desired_replicas}" && "${ready}" -ge "${desired_replicas}" ]]; then
    echo "OK   deployment/${deploy_name} (${namespace}) ready=${ready}/${replicas}"
    return 0
  fi

  if [[ "${dry_run}" == "true" ]]; then
    echo "DOWN deployment/${deploy_name} (${namespace}) ready=${ready}/${replicas} -> would scale to ${desired_replicas}"
    return 2
  fi

  echo "Scaling deployment/${deploy_name} in ${namespace} to ${desired_replicas} (was ready=${ready}/${replicas})..."
  oc scale "deployment/${deploy_name}" --replicas="${desired_replicas}" -n "${namespace}"
  if ! oc rollout status "deployment/${deploy_name}" -n "${namespace}" --timeout="${timeout}s"; then
    echo "WARN deployment/${deploy_name} (${namespace}) rollout did not finish in ${timeout}s" >&2
    return 2
  fi
  echo "OK   deployment/${deploy_name} (${namespace}) scaled and ready"
  return 1
}

# Returns 0 when ready, 1 when a repair was applied, 2 when repair is needed (dry-run).
ensure_statefulset_running() {
  local sts_name="${1}"
  local namespace="${2}"
  local desired_replicas="${3:-1}"
  local timeout="${4:-300}"
  local dry_run="${5:-false}"

  if ! oc get statefulset "${sts_name}" -n "${namespace}" >/dev/null 2>&1; then
    return 0
  fi

  local replicas ready
  replicas=$(oc get statefulset "${sts_name}" -n "${namespace}" -o jsonpath='{.spec.replicas}')
  ready=$(oc get statefulset "${sts_name}" -n "${namespace}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  ready="${ready:-0}"

  if [[ "${replicas}" -ge "${desired_replicas}" && "${ready}" -ge "${desired_replicas}" ]]; then
    echo "OK   statefulset/${sts_name} (${namespace}) ready=${ready}/${replicas}"
    return 0
  fi

  if [[ "${dry_run}" == "true" ]]; then
    echo "DOWN statefulset/${sts_name} (${namespace}) ready=${ready}/${replicas} -> would scale to ${desired_replicas}"
    return 2
  fi

  echo "Scaling statefulset/${sts_name} in ${namespace} to ${desired_replicas} (was ready=${ready}/${replicas})..."
  oc scale "statefulset/${sts_name}" --replicas="${desired_replicas}" -n "${namespace}"
  if ! oc rollout status "statefulset/${sts_name}" -n "${namespace}" --timeout="${timeout}s"; then
    echo "WARN statefulset/${sts_name} (${namespace}) rollout did not finish in ${timeout}s" >&2
    return 2
  fi
  echo "OK   statefulset/${sts_name} (${namespace}) scaled and ready"
  return 1
}

ensure_developer_hub_running() {
  local dry_run="${1:-false}"
  local deploy_name=""

  if oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    deploy_name="redhat-developer-hub"
  elif oc get deployment "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    deploy_name="${RHDH_INSTANCE_NAME}"
  else
    return 0
  fi

  if [[ "${dry_run}" == "true" ]]; then
    ensure_deployment_running "${deploy_name}" "${RHDH_NAMESPACE}" 1 600 "${dry_run}"
    return $?
  fi

  local replicas ready
  replicas=$(oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" -o jsonpath='{.spec.replicas}')
  ready=$(oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  ready="${ready:-0}"

  if [[ "${replicas}" -ge 1 && "${ready}" -ge 1 ]]; then
    echo "OK   deployment/${deploy_name} (${RHDH_NAMESPACE}) ready=${ready}/${replicas}"
    return 0
  fi

  echo "Scaling deployment/${deploy_name} in ${RHDH_NAMESPACE} to 1 (was ready=${ready}/${replicas})..."
  oc scale "deployment/${deploy_name}" --replicas=1 -n "${RHDH_NAMESPACE}"
  if ! wait_for_developer_hub_rollout "${deploy_name}"; then
    echo "WARN deployment/${deploy_name} (${RHDH_NAMESPACE}) is not fully ready yet" >&2
    return 2
  fi
  echo "OK   deployment/${deploy_name} (${RHDH_NAMESPACE}) scaled and ready"
  return 1
}

ensure_all_workshop_instances() {
  local dry_run="${1:-false}"
  local check_only="${2:-false}"
  local probe_dry_run="${dry_run}"
  local rc=0
  local item status

  if [[ "${check_only}" == "true" ]]; then
    probe_dry_run="true"
  fi

  require_oc
  echo "Checking workshop instances (workshop=${WORKSHOP_NAMESPACE}, rhdh=${RHDH_NAMESPACE})..."

  local workloads=(
    "statefulset:${RHDH_NAMESPACE}:redhat-developer-hub-postgresql:1:300"
    "deployment:${WORKSHOP_NAMESPACE}:keycloak:1:600"
    "deployment:${WORKSHOP_NAMESPACE}:workshop-catalog-server:1:300"
    "deployment:${WORKSHOP_NAMESPACE}:people-postgres:1:300"
    "deployment:${WORKSHOP_NAMESPACE}:people-backend:1:600"
    "deployment:${WORKSHOP_NAMESPACE}:people-frontend:1:300"
  )

  if [[ "${AAP_MANAGEMENT_ENABLED:-false}" == "true" \
    || "${AAP_MANAGEMENT_ENABLED:-false}" == "1" \
    || "${AAP_MANAGEMENT_ENABLED:-false}" == "yes" ]]; then
    workloads+=("deployment:${WORKSHOP_NAMESPACE}:aap-management-plugin-server:1:180")
  fi

  for item in "${workloads[@]}"; do
    IFS=':' read -r kind namespace name desired timeout <<<"${item}"
    status=0
    if [[ "${kind}" == "statefulset" ]]; then
      ensure_statefulset_running "${name}" "${namespace}" "${desired}" "${timeout}" "${probe_dry_run}" || status=$?
    else
      ensure_deployment_running "${name}" "${namespace}" "${desired}" "${timeout}" "${probe_dry_run}" || status=$?
    fi
    if (( status > rc )); then
      rc=${status}
    fi
  done

  status=0
  ensure_developer_hub_running "${probe_dry_run}" || status=$?
  if (( status > rc )); then
    rc=${status}
  fi

  if [[ "${dry_run}" == "true" || "${check_only}" == "true" ]]; then
    if [[ "${rc}" -eq 2 ]]; then
      echo "Some instances are scaled down or not ready."
      return 1
    fi
    echo "All checked instances are running."
    return 0
  fi

  if [[ "${rc}" -ge 1 ]]; then
    if oc get deployment keycloak -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
      wait_keycloak_http_ready || true
    fi
    if oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
      local ready
      ready=$(oc get pod -l app.kubernetes.io/name=developer-hub -n "${RHDH_NAMESPACE}" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
      if [[ "${ready}" != "True" ]]; then
        echo "Restarting Developer Hub pod after dependency recovery..."
        oc delete pod -l app.kubernetes.io/name=developer-hub -n "${RHDH_NAMESPACE}" --wait=false
        wait_for_developer_hub_rollout redhat-developer-hub 600s 2>/dev/null || true
      fi
    fi
  fi

  echo "Workshop instance check complete."
  return 0
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
    -o jsonpath='{.data.GITHUB_TOKEN}' | base64_decode)"
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
