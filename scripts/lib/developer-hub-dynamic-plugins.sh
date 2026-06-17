#!/usr/bin/env bash

is_lightspeed_enabled() {
  [[ "${LIGHTSPEED_ENABLED:-false}" == "true" \
    || "${LIGHTSPEED_ENABLED:-false}" == "1" \
    || "${LIGHTSPEED_ENABLED:-false}" == "yes" ]]
}

is_aap_enabled() {
  [[ "${AAP_ENABLED:-false}" == "true" \
    || "${AAP_ENABLED:-false}" == "1" \
    || "${AAP_ENABLED:-false}" == "yes" ]]
}

is_aap_management_enabled() {
  [[ "${AAP_MANAGEMENT_ENABLED:-false}" == "true" \
    || "${AAP_MANAGEMENT_ENABLED:-false}" == "1" \
    || "${AAP_MANAGEMENT_ENABLED:-false}" == "yes" ]]
}

rh_registry_credentials_missing_message() {
  cat <<EOF >&2
ERROR: AAP_ENABLED=true but Red Hat registry credentials are missing.

Ansible OCI dynamic plugins are pulled from registry.redhat.io during install-dynamic-plugins.
Create a service account at https://access.redhat.com/terms-based-registry/accounts and set:

  export RH_REGISTRY_USERNAME=<username-from-token-tab>  # e.g. 11009103|my-sa-name
  export RH_REGISTRY_TOKEN=<token-from-token-tab>      # JWT (eyJ...) is normal

Or run:

  ./scripts/configure-aap-workshop-env.sh --rh-registry-username <sa> --rh-registry-token <token>

EOF
}

rh_registry_credentials_invalid_message() {
  local detail="${1:-registry.redhat.io rejected the credentials}"
  cat <<EOF >&2
ERROR: Red Hat registry credentials are invalid (${detail}).

RH_REGISTRY_USERNAME and RH_REGISTRY_TOKEN must come from the Token Information tab of a
Red Hat Container Registry service account — NOT your AAP login or OpenShift oc token.

Create or open a service account at:
  https://access.redhat.com/terms-based-registry/accounts

The registry token is a JWT (starts with eyJ...) — that is expected. Do not use OpenShift
tokens shaped like namespace:eyJ...

Then set in scripts/workshop.env:
  export RH_REGISTRY_USERNAME=<username-from-token-tab>  # e.g. 11009103|my-sa-name
  export RH_REGISTRY_TOKEN=<token-from-token-tab>

Re-run:
  ./scripts/setup-developer-hub-aap.sh --force-rollout

EOF
}

# Reject common misconfigurations before hitting the registry.
sanity_check_rh_registry_token() {
  local user="$1"
  local token="$2"

  # RH registry service account tokens are JWTs (eyJ...). Reject OpenShift SA tokens only.
  if [[ "${token}" == *":eyJ"* ]]; then
    rh_registry_credentials_invalid_message \
      "RH_REGISTRY_TOKEN looks like an OpenShift service account token (namespace:eyJ...) — use the password from the registry Token Information tab"
    return 1
  fi
  if [[ "${#token}" -gt 8192 ]]; then
    rh_registry_credentials_invalid_message \
      "RH_REGISTRY_TOKEN is unusually long — paste only the token from the Token Information tab"
    return 1
  fi
  if [[ -z "${user}" || "${user}" == "changeme" || -z "${token}" || "${token}" == "changeme" ]]; then
    rh_registry_credentials_missing_message
    return 1
  fi
  return 0
}

# Last validation step: format (sanity) or live (registry API).
RH_REGISTRY_VALIDATION_STEP=""

_rh_registry_auth_url() {
  printf '%s' \
    'https://registry.redhat.io/auth/realms/rhcc/protocol/redhat-docker-v2/auth?service=docker-registry&scope=repository:ubi9/ubi-minimal:pull'
}

_rh_registry_live_check_skopeo() {
  local user="$1"
  local token="$2"

  if skopeo login --username "${user}" --password "${token}" registry.redhat.io >/dev/null 2>&1; then
    skopeo logout registry.redhat.io >/dev/null 2>&1 || true
    return 0
  fi
  return 1
}

# registry.redhat.io uses Bearer tokens; GET /v2/ returns 401 even with valid basic auth.
_rh_registry_live_check_curl() {
  local user="$1"
  local token="$2"
  local http_code

  http_code="$(curl -s -o /dev/null -w '%{http_code}' \
    -u "${user}:${token}" \
    --connect-timeout 15 --max-time 30 \
    "$(_rh_registry_auth_url)" 2>/dev/null || true)"
  RH_REGISTRY_HTTP_CODE="${http_code}"
  [[ "${http_code}" == "200" ]]
}

# Verify credentials against registry.redhat.io (skopeo preferred; curl OAuth fallback).
validate_rh_registry_credentials() {
  local user="${1:-${RH_REGISTRY_USERNAME:-}}"
  local token="${2:-${RH_REGISTRY_TOKEN:-}}"

  RH_REGISTRY_VALIDATION_STEP="format"
  sanity_check_rh_registry_token "${user}" "${token}" || return 1

  if [[ "${RH_REGISTRY_SKIP_LIVE_VALIDATION:-false}" == "true" \
    || "${RH_REGISTRY_SKIP_LIVE_VALIDATION:-false}" == "1" ]]; then
    echo "WARNING: skipping live registry.redhat.io credential check (RH_REGISTRY_SKIP_LIVE_VALIDATION=true)." >&2
    return 0
  fi

  RH_REGISTRY_VALIDATION_STEP="live"
  local skopeo_failed=false

  if command -v skopeo >/dev/null 2>&1; then
    if _rh_registry_live_check_skopeo "${user}" "${token}"; then
      return 0
    fi
    skopeo_failed=true
    echo "WARNING: skopeo login to registry.redhat.io failed from this environment; trying curl OAuth check..." >&2
  fi

  if command -v curl >/dev/null 2>&1; then
    local http_code=""
    if _rh_registry_live_check_curl "${user}" "${token}"; then
      return 0
    fi
    http_code="${RH_REGISTRY_HTTP_CODE:-000}"
    if [[ "${http_code}" == "401" || "${http_code}" == "403" ]]; then
      local hint=""
      if [[ "${user}" != *"|"* ]]; then
        hint=" Username may need the full form from Token Information (e.g. 11009103|my-sa-name)."
      fi
      rh_registry_credentials_invalid_message \
        "registry.redhat.io rejected credentials (HTTP ${http_code}).${hint}"
      return 1
    fi
    if [[ "${http_code}" == "000" || -z "${http_code}" ]]; then
      echo "WARNING: cannot reach registry.redhat.io from this environment (HTTP ${http_code:-000})." >&2
      echo "  Format checks passed; applying credentials anyway. Confirm pulls on the cluster," >&2
      echo "  or set RH_REGISTRY_SKIP_LIVE_VALIDATION=true to silence this warning." >&2
      return 0
    fi
    if [[ "${skopeo_failed}" == "true" ]]; then
      echo "WARNING: registry.redhat.io live check inconclusive (skopeo failed, curl HTTP ${http_code})." >&2
      echo "  Applying credentials anyway — install-dynamic-plugins will verify on the cluster." >&2
      return 0
    fi
    rh_registry_credentials_invalid_message \
      "unexpected HTTP ${http_code} from registry.redhat.io auth endpoint"
    return 1
  fi

  if [[ "${skopeo_failed}" == "true" ]]; then
    echo "WARNING: skopeo login failed and curl is unavailable; applying credentials without live check." >&2
    echo "  Set RH_REGISTRY_SKIP_LIVE_VALIDATION=true to silence this warning." >&2
    return 0
  fi

  echo "WARNING: curl/skopeo not found; skipping live registry.redhat.io credential check." >&2
  return 0
}

require_aap_registry_credentials() {
  if [[ -n "${RH_REGISTRY_PULL_SECRET:-}" ]]; then
    return 0
  fi
  if [[ -z "${RH_REGISTRY_USERNAME:-}" || "${RH_REGISTRY_USERNAME}" == "changeme" \
    || -z "${RH_REGISTRY_TOKEN:-}" || "${RH_REGISTRY_TOKEN}" == "changeme" ]]; then
    rh_registry_credentials_missing_message
    return 1
  fi
  validate_rh_registry_credentials "${RH_REGISTRY_USERNAME}" "${RH_REGISTRY_TOKEN}"
}

rollout_timeout_for_config() {
  if is_aap_enabled; then
    echo "1800s"
  elif is_lightspeed_enabled || is_aap_management_enabled; then
    echo "900s"
  else
    echo "600s"
  fi
}

# Session cache: avoid repeated PVC probes during one bootstrap run.
_DEVELOPER_HUB_PLUGINS_ON_PVC="${_DEVELOPER_HUB_PLUGINS_ON_PVC:-}"

dynamic_plugins_pvc_exists() {
  oc get pvc dynamic-plugins-root -n "${RHDH_NAMESPACE}" >/dev/null 2>&1
}

# True when dynamic-plugins-root has plugin content and no install lock (PVC or running pod).
developer_hub_plugins_on_pvc() {
  local pod mount entries lock_present

  if [[ "${_DEVELOPER_HUB_PLUGINS_ON_PVC}" == "true" ]]; then
    return 0
  fi
  if [[ "${_DEVELOPER_HUB_PLUGINS_ON_PVC}" == "false" ]]; then
    return 1
  fi

  if ! dynamic_plugins_pvc_exists; then
    _DEVELOPER_HUB_PLUGINS_ON_PVC=false
    return 1
  fi

  pod="$(oc get pod -n "${RHDH_NAMESPACE}" -l app.kubernetes.io/name=developer-hub \
    -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null \
    | awk '{print $1}')"
  if [[ -n "${pod}" ]]; then
    for mount in /dynamic-plugins-root /opt/app-root/src/dynamic-plugins-root; do
      lock_present="$(oc exec -n "${RHDH_NAMESPACE}" "${pod}" -c backstage-backend -- \
        sh -c "test -f ${mount}/install-dynamic-plugins.lock && echo yes || echo no" 2>/dev/null || true)"
      if [[ "${lock_present}" == "yes" ]]; then
        continue
      fi
      entries="$(oc exec -n "${RHDH_NAMESPACE}" "${pod}" -c backstage-backend -- \
        sh -c "ls -A ${mount} 2>/dev/null \
          | grep -vE '^(install-dynamic-plugins\\.lock|dynamic-plugins\\.lock)$' \
          | head -1" 2>/dev/null || true)"
      if [[ -n "${entries}" ]]; then
        _DEVELOPER_HUB_PLUGINS_ON_PVC=true
        return 0
      fi
    done
    _DEVELOPER_HUB_PLUGINS_ON_PVC=false
    return 1
  fi

  local job_pod="workshop-plugins-pvc-probe"
  oc delete pod "${job_pod}" -n "${RHDH_NAMESPACE}" --ignore-not-found --wait=true >/dev/null 2>&1 || true
  oc run "${job_pod}" -n "${RHDH_NAMESPACE}" --restart=Never \
    --image=registry.redhat.io/ubi9/ubi-minimal \
    --overrides='{"spec":{"containers":[{"name":"probe","image":"registry.redhat.io/ubi9/ubi-minimal","command":["sh","-c","if test -f /mnt/install-dynamic-plugins.lock || test -f /mnt/dynamic-plugins.lock; then echo locked; elif ls -A /mnt 2>/dev/null | grep -qvE \"^(install-dynamic-plugins\\.lock|dynamic-plugins\\.lock)$\"; then echo populated; else echo empty; fi"],"volumeMounts":[{"name":"pvc","mountPath":"/mnt"}]}],"volumes":[{"name":"pvc","persistentVolumeClaim":{"claimName":"dynamic-plugins-root"}}]}}' \
    -- sleep 30 >/dev/null

  local i probe_result=""
  for i in $(seq 1 15); do
    probe_result="$(oc logs "${job_pod}" -n "${RHDH_NAMESPACE}" 2>/dev/null | tail -1 || true)"
    case "${probe_result}" in
      populated | locked | empty) break ;;
    esac
    sleep 1
  done
  oc delete pod "${job_pod}" -n "${RHDH_NAMESPACE}" --ignore-not-found --wait=false >/dev/null 2>&1 || true

  if [[ "${probe_result}" == "populated" ]]; then
    _DEVELOPER_HUB_PLUGINS_ON_PVC=true
    return 0
  fi
  _DEVELOPER_HUB_PLUGINS_ON_PVC=false
  return 1
}

mark_developer_hub_plugins_on_pvc() {
  _DEVELOPER_HUB_PLUGINS_ON_PVC=true
}

developer_hub_rollout_hint() {
  if is_aap_enabled && ! developer_hub_plugins_on_pvc; then
    echo "Ansible dynamic plugins are downloading — first install can take 15–30 minutes on sandbox."
    return 0
  fi
  if is_lightspeed_enabled; then
    echo "Rolling out Developer Hub (Lightspeed sidecars and init containers may take a few minutes on sandbox)..."
    return 0
  fi
  echo "Rolling out Developer Hub (sidecars may take a few minutes on sandbox)..."
}

developer_hub_active_init_hint() {
  local init_names="${1:-}"
  [[ -n "${init_names}" ]] || return 0

  if [[ "${init_names}" == *"install-dynamic-plugins"* ]]; then
    if is_aap_enabled && ! developer_hub_plugins_on_pvc; then
      echo "downloading Ansible plugins from registry.redhat.io"
      return 0
    fi
    echo "installing or verifying dynamic plugins"
    return 0
  fi
  if [[ "${init_names}" == *"init-rag-data"* ]]; then
    echo "initializing Lightspeed documentation index"
    return 0
  fi
  return 0
}

ensure_aap_management_plugin_build() {
  local integrity_file="${SCRIPTS_DIR}/../custom-plugins/aap-management/.build/integrity.env"
  if [[ ! -f "${integrity_file}" ]]; then
    "${SCRIPTS_DIR}/build-custom-aap-management-plugin.sh"
  fi
  # shellcheck disable=SC1090
  source "${integrity_file}"
  export AAP_MGMT_BACKEND_INTEGRITY AAP_MGMT_FRONTEND_INTEGRITY
}

render_dynamic_plugins() {
  local base_file merged_file
  base_file="$(mktemp)"
  merged_file="$(mktemp)"
  workshop_envsubst '${RHDH_NAMESPACE}' <"${MANIFESTS_DIR}/developer-hub/dynamic-plugins-rhdh.yaml" \
    | awk '/dynamic-plugins.yaml: \|/{flag=1;next} flag{sub(/^    /,""); print}' >"${base_file}"

  cp "${base_file}" "${merged_file}"
  if is_lightspeed_enabled; then
    printf '\n' >>"${merged_file}"
    cat "${MANIFESTS_DIR}/developer-hub/dynamic-plugins-lightspeed.yaml" >>"${merged_file}"
    printf '\n' >>"${merged_file}"
    cat "${MANIFESTS_DIR}/developer-hub/dynamic-plugins-mcp.yaml" >>"${merged_file}"
  fi
  if is_aap_enabled; then
    printf '\n' >>"${merged_file}"
    cat "${MANIFESTS_DIR}/developer-hub/dynamic-plugins-aap.yaml" >>"${merged_file}"
  fi
  if is_aap_management_enabled; then
    ensure_aap_management_plugin_build
    printf '\n' >>"${merged_file}"
    workshop_envsubst '${WORKSHOP_NAMESPACE} ${AAP_MGMT_BACKEND_INTEGRITY} ${AAP_MGMT_FRONTEND_INTEGRITY}' \
      <"${MANIFESTS_DIR}/developer-hub/dynamic-plugins-aap-management.yaml" >>"${merged_file}"
  fi

  cat "${merged_file}"
  rm -f "${base_file}" "${merged_file}"
}

apply_dynamic_plugins_config() {
  local plugins_yaml
  plugins_yaml=$(render_dynamic_plugins)
  local target_cm="dynamic-plugins-rhdh"
  if oc get configmap redhat-developer-hub-dynamic-plugins -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    target_cm="redhat-developer-hub-dynamic-plugins"
  fi
  oc create configmap "${target_cm}" -n "${RHDH_NAMESPACE}" \
    --from-literal=dynamic-plugins.yaml="${plugins_yaml}" \
    --dry-run=client -o yaml | oc apply -f -
  echo "Applied dynamic plugins to ConfigMap ${target_cm}"
}
