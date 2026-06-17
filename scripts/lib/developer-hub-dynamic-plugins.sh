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

require_aap_registry_credentials() {
  if [[ -n "${RH_REGISTRY_PULL_SECRET:-}" ]]; then
    return 0
  fi
  if [[ -n "${RH_REGISTRY_USERNAME:-}" && "${RH_REGISTRY_USERNAME}" != "changeme" \
    && -n "${RH_REGISTRY_TOKEN:-}" && "${RH_REGISTRY_TOKEN}" != "changeme" ]]; then
    return 0
  fi
  cat <<EOF >&2
ERROR: AAP_ENABLED=true but Red Hat registry credentials are missing.

Ansible OCI dynamic plugins are pulled from registry.redhat.io during install-dynamic-plugins.
Create a service account at https://access.redhat.com/terms-based-registry/accounts and set:

  export RH_REGISTRY_USERNAME=<service-account-name>
  export RH_REGISTRY_TOKEN=<token>

Or run:

  ./scripts/configure-aap-workshop-env.sh --rh-registry-username <sa> --rh-registry-token <token>

EOF
  return 1
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
