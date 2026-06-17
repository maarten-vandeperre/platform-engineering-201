#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/aap.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/developer-hub-dynamic-plugins.sh"

echo "Configuring Developer Hub Keycloak SSO in ${RHDH_NAMESPACE}..."

require_oc

ensure_workshop_platform

resolve_keycloak_urls

"${SCRIPTS_DIR}/configure-keycloak-realm.sh"
"${SCRIPTS_DIR}/setup-developer-hub-kubernetes.sh"
"${SCRIPTS_DIR}/setup-developer-hub-dynamic-plugins-cache.sh" --no-rollout

export K8S_CLUSTER_NAME="${K8S_CLUSTER_NAME:-openshift}"
export K8S_CLUSTER_URL="${K8S_CLUSTER_URL:-https://kubernetes.default.svc}"

cleanup_old_replicasets() {
  local deploy_name="${1:-redhat-developer-hub}"
  oc get rs -n "${RHDH_NAMESPACE}" -o json \
    | jq -r --arg prefix "${deploy_name}-" \
      '.items[]
       | select(.metadata.name | startswith($prefix))
       | select(.spec.replicas == 0 or (.status.replicas // 0) == 0)
       | .metadata.name' \
    | while read -r rs; do
        [[ -n "${rs}" ]] || continue
        oc delete rs "${rs}" -n "${RHDH_NAMESPACE}" --ignore-not-found
      done

  # Dev namespaces often hit the replicaset quota; prune other stale RS too.
  oc get rs -n "${RHDH_NAMESPACE}" -o json \
    | jq -r '.items[]
       | select(.spec.replicas == 0 or (.status.replicas // 0) == 0)
       | .metadata.name' \
    | while read -r rs; do
        [[ -n "${rs}" ]] || continue
        oc delete rs "${rs}" -n "${RHDH_NAMESPACE}" --ignore-not-found
      done
}

configure_kubernetes_env() {
  local deploy_name="${1:-redhat-developer-hub}"
  if ! oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    return 0
  fi

  cleanup_old_replicasets "${deploy_name}"

  oc set env "deployment/${deploy_name}" -n "${RHDH_NAMESPACE}" \
    K8S_CLUSTER_NAME="${K8S_CLUSTER_NAME}" \
    K8S_CLUSTER_URL="${K8S_CLUSTER_URL}" \
    NODE_TLS_REJECT_UNAUTHORIZED=0 \
    K8S_CA_DATA- \
    --overwrite

  oc set env "deployment/${deploy_name}" -n "${RHDH_NAMESPACE}" \
    --from=secret/backstage-kubernetes-token \
    --overwrite
}
if [[ -z "${BACKEND_SECRET:-}" ]] && oc get secret redhat-developer-hub-auth -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  BACKEND_SECRET=$(oc get secret redhat-developer-hub-auth -n "${RHDH_NAMESPACE}" -o jsonpath='{.data.backend-secret}' | base64_decode)
fi
export BACKEND_SECRET="${BACKEND_SECRET:-workshop-backend-secret}"
export PEOPLE_NOTIFICATION_TOKEN="${PEOPLE_NOTIFICATION_TOKEN:-${BACKEND_SECRET}}"
export GITHUB_TOKEN="${GITHUB_TOKEN:-changeme}"
export AUTH_GITHUB_CLIENT_ID="${AUTH_GITHUB_CLIENT_ID:-changeme}"
export AUTH_GITHUB_CLIENT_SECRET="${AUTH_GITHUB_CLIENT_SECRET:-changeme}"
export ARGOCD_URL="${ARGOCD_URL:-changeme}"
export ARGOCD_TOKEN="${ARGOCD_TOKEN:-changeme}"

if [[ -z "${POSTGRESQL_ADMIN_PASSWORD:-}" ]] && oc get secret redhat-developer-hub-postgresql -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  POSTGRESQL_ADMIN_PASSWORD=$(oc get secret redhat-developer-hub-postgresql -n "${RHDH_NAMESPACE}" \
    -o jsonpath='{.data.postgres-password}' | base64_decode)
fi
export POSTGRESQL_ADMIN_PASSWORD="${POSTGRESQL_ADMIN_PASSWORD:-changeme}"

if [[ -z "${K8S_CLUSTER_TOKEN:-}" ]] && oc get secret backstage-kubernetes-token -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  K8S_CLUSTER_TOKEN=$(oc get secret backstage-kubernetes-token -n "${RHDH_NAMESPACE}" \
    -o jsonpath='{.data.K8S_CLUSTER_TOKEN}' | base64_decode)
fi
export K8S_CLUSTER_TOKEN="${K8S_CLUSTER_TOKEN:-changeme}"

RHDH_HOST=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null \
  || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null \
  || echo "developer-hub.example.com")

CATALOG_URL="${WORKSHOP_CATALOG_URL:-}"
if [[ -z "${CATALOG_URL}" ]] && oc get route workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
  CATALOG_URL="https://$(get_route_host "${WORKSHOP_NAMESPACE}" "workshop-catalog-server")/entities.yaml"
fi
CATALOG_URL="${CATALOG_URL:-${WORKSHOP_GIT_REPO}/blob/${WORKSHOP_GIT_BRANCH}/manifests/gitops/catalog/all.yaml}"

oc create secret generic rhdh-workshop-secrets -n "${RHDH_NAMESPACE}" \
  --from-literal=GITHUB_TOKEN="${GITHUB_TOKEN:-changeme}" \
  --from-literal=AUTH_GITHUB_CLIENT_ID="${AUTH_GITHUB_CLIENT_ID:-changeme}" \
  --from-literal=AUTH_GITHUB_CLIENT_SECRET="${AUTH_GITHUB_CLIENT_SECRET:-changeme}" \
  --from-literal=ARGOCD_URL="${ARGOCD_URL:-changeme}" \
  --from-literal=ARGOCD_TOKEN="${ARGOCD_TOKEN:-changeme}" \
  --from-literal=RHDH_OIDC_CLIENT_SECRET="${RHDH_OIDC_CLIENT_SECRET}" \
  --dry-run=client -o yaml | oc apply -f -

strip_placeholder_github_token() {
  local file="$1"
  if [[ "${GITHUB_TOKEN:-changeme}" != "changeme" ]]; then
    return 0
  fi
  # Invalid PAT breaks public GitHub reads (401). Omit token so fetch:template works.
  perl -pi -e 's/^\s*token: changeme\s*\n//' "${file}"
  perl -pi -e 's/^\s*Authorization: Bearer changeme\s*\n//' "${file}"
}

render_app_config() {
  local branding_dir="${MANIFESTS_DIR}/developer-hub/branding"
  export EGYPTIAN_FULL_LOGO="data:image/svg+xml;base64,$(base64 < "${branding_dir}/egyptian-full-logo.svg" | tr -d '\n')"
  export EGYPTIAN_ICON_LOGO="data:image/svg+xml;base64,$(base64 < "${branding_dir}/egyptian-icon-logo.svg" | tr -d '\n')"

  local base_file theme_file merged_file
  base_file="$(mktemp)"
  theme_file="$(mktemp)"
  merged_file="$(mktemp)"
  trap 'rm -f "${base_file}" "${theme_file}" "${merged_file}"' RETURN

  workshop_envsubst \
    '${RHDH_APP_TITLE} ${KEYCLOAK_URL} ${KEYCLOAK_REALM} ${RHDH_KEYCLOAK_CLIENT_ID} ${RHDH_OIDC_CLIENT_SECRET} ${AUTH_GITHUB_CLIENT_ID} ${AUTH_GITHUB_CLIENT_SECRET} ${CLUSTER_ROUTER_BASE} ${WORKSHOP_NAMESPACE} ${GITHUB_TOKEN} ${ARGOCD_URL} ${ARGOCD_TOKEN} ${BACKEND_SECRET} ${PEOPLE_NOTIFICATION_TOKEN} ${POSTGRESQL_ADMIN_PASSWORD} ${K8S_CLUSTER_TOKEN}' \
    <"${MANIFESTS_DIR}/developer-hub/app-config-rhdh.yaml" \
    | sed "s|PLACEHOLDER-RHDH-ROUTE|${RHDH_HOST}|g" \
    | sed "s|PLACEHOLDER-CATALOG-URL|${CATALOG_URL}|g" \
    | awk '/app-config-rhdh.yaml: \|/{flag=1;next} flag{sub(/^    /,""); print}' >"${base_file}"

  strip_placeholder_github_token "${base_file}"

  if is_lightspeed_enabled; then
    ensure_mcp_token
    local mcp_file merged_mcp lightspeed_file merged_ls
    mcp_file="$(mktemp)"
    merged_mcp="$(mktemp)"
    workshop_envsubst '${MCP_TOKEN}' <"${MANIFESTS_DIR}/developer-hub/app-config-mcp.yaml" >"${mcp_file}"
    merge_mcp_into_app_config "${base_file}" "${mcp_file}" "${merged_mcp}"
    cp "${merged_mcp}" "${base_file}"
    rm -f "${mcp_file}" "${merged_mcp}"

    lightspeed_file="$(mktemp)"
    merged_ls="$(mktemp)"
    workshop_envsubst '${MCP_TOKEN}' <"${MANIFESTS_DIR}/developer-hub/app-config-lightspeed-snippet.yaml" >"${lightspeed_file}"
    merge_mcp_into_app_config "${base_file}" "${lightspeed_file}" "${merged_ls}"
    cp "${merged_ls}" "${base_file}"
    rm -f "${lightspeed_file}" "${merged_ls}"
  fi

  if is_aap_enabled; then
    local aap_file merged_aap
    aap_file="$(mktemp)"
    merged_aap="$(mktemp)"
    export AAP_CHECK_SSL="${AAP_CHECK_SSL:-false}"
    # Only auto-detect local sandbox-aap when AAP_CONTROLLER_URL is unset — external workshop AAP must be set explicitly.
    if [[ -z "${AAP_CONTROLLER_URL:-}" || "${AAP_CONTROLLER_URL}" == "changeme" ]]; then
      if detected_url="$(aap_detect_controller_url 2>/dev/null || true)" && [[ -n "${detected_url}" ]]; then
        AAP_CONTROLLER_URL="${detected_url}"
      fi
    fi
    export AAP_CONTROLLER_URL="${AAP_CONTROLLER_URL:-changeme}"
    export AAP_TOKEN="${AAP_TOKEN:-changeme}"
    workshop_envsubst '${AAP_CONTROLLER_URL} ${AAP_TOKEN} ${AAP_CHECK_SSL}' \
      <"${MANIFESTS_DIR}/developer-hub/app-config-aap-snippet.yaml" >"${aap_file}"
    merge_mcp_into_app_config "${base_file}" "${aap_file}" "${merged_aap}"
    cp "${merged_aap}" "${base_file}"
    rm -f "${aap_file}" "${merged_aap}"
  fi

  if is_aap_management_enabled; then
    local mgmt_file merged_mgmt
    mgmt_file="$(mktemp)"
    merged_mgmt="$(mktemp)"
    export AAP_CHECK_SSL="${AAP_CHECK_SSL:-false}"
    export AAP_CONTROLLER_URL="${AAP_CONTROLLER_URL:-changeme}"
    export AAP_TOKEN="${AAP_TOKEN:-changeme}"
    export AAP_ADMIN_USERNAME="${AAP_ADMIN_USERNAME:-admin}"
    export AAP_ADMIN_PASSWORD="${AAP_ADMIN_PASSWORD:-changeme}"
    workshop_envsubst '${AAP_CONTROLLER_URL} ${AAP_TOKEN} ${AAP_ADMIN_USERNAME} ${AAP_ADMIN_PASSWORD} ${AAP_CHECK_SSL}' \
      <"${MANIFESTS_DIR}/developer-hub/app-config-aap-management-snippet.yaml" >"${mgmt_file}"
    merge_mcp_into_app_config "${base_file}" "${mgmt_file}" "${merged_mgmt}"
    cp "${merged_mgmt}" "${base_file}"
    rm -f "${mgmt_file}" "${merged_mgmt}"
  fi

  workshop_envsubst '${EGYPTIAN_FULL_LOGO} ${EGYPTIAN_ICON_LOGO}' \
    <"${MANIFESTS_DIR}/developer-hub/egyptian-theme.yaml" \
    | sed 's/^/  /' >"${theme_file}"

  awk -v theme_file="${theme_file}" '
    /^  sidebar:/ { in_sidebar=1 }
    in_sidebar && /^    logo:/ {
      print
      while ((getline line < theme_file) > 0) {
        print line
      }
      close(theme_file)
      in_sidebar=0
      next
    }
    { print }
  ' "${base_file}" >"${merged_file}"

  cat "${merged_file}"
}

prepare_developer_hub_rollout() {
  if is_aap_enabled; then
    echo "Validating and applying registry.redhat.io auth before Developer Hub rollout..."
    require_aap_registry_credentials
    "${SCRIPTS_DIR}/setup-developer-hub-aap.sh" --no-rollout
  fi

  if is_lightspeed_enabled; then
    "${SCRIPTS_DIR}/setup-developer-hub-lightspeed.sh" --no-rollout
  fi
}

APP_CONFIG=$(render_app_config)
apply_dynamic_plugins_config

if is_aap_management_enabled; then
  "${SCRIPTS_DIR}/setup-custom-aap-management-plugin.sh" --no-rollout
fi

if oc get configmap redhat-developer-hub-app-config -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  oc create configmap redhat-developer-hub-app-config -n "${RHDH_NAMESPACE}" \
    --from-literal=app-config.yaml="${APP_CONFIG}" \
    --dry-run=client -o yaml | oc apply -f -
else
  oc create configmap app-config-rhdh -n "${RHDH_NAMESPACE}" \
    --from-literal=app-config-rhdh.yaml="${APP_CONFIG}" \
    --dry-run=client -o yaml | oc apply -f -
fi

if oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  oc set env deployment/redhat-developer-hub -n "${RHDH_NAMESPACE}" \
    RHDH_OIDC_CLIENT_SECRET="${RHDH_OIDC_CLIENT_SECRET}" \
    --overwrite
  configure_kubernetes_env redhat-developer-hub
  prepare_developer_hub_rollout
  echo "Restarting Developer Hub to apply configuration..."
  rollout_timeout="$(rollout_timeout_for_config)"
  if is_aap_management_enabled; then
    export CLEAR_AAP_MANAGEMENT_PLUGINS_FROM_PVC=true
  fi
  if developer_hub_uses_plugins_pvc redhat-developer-hub \
    || oc get pvc dynamic-plugins-root -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    safe_rollout_developer_hub redhat-developer-hub "${rollout_timeout}"
  else
    oc delete pod -l app.kubernetes.io/name=developer-hub -n "${RHDH_NAMESPACE}" --wait=false
    wait_for_developer_hub_rollout redhat-developer-hub "${rollout_timeout}"
  fi
elif oc get deployment "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  oc set env "deployment/${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" \
    RHDH_OIDC_CLIENT_SECRET="${RHDH_OIDC_CLIENT_SECRET}" --overwrite
  oc rollout restart "deployment/${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}"
  wait_for_developer_hub_rollout "${RHDH_INSTANCE_NAME}" "$(rollout_timeout_for_config)"
fi

wait_for_rhdh_route_ready 900

echo ""
print_rhdh_route_url
echo "Sign in with Keycloak user ${RHDH_KEYCLOAK_USER} / (password from workshop.env)"

if [[ "${GITHUB_TOKEN:-changeme}" == "changeme" ]]; then
  echo ""
  echo "WARNING: GITHUB_TOKEN is still 'changeme'."
  echo "Scaffolder 'Publish to GitHub' will fail with 'No token available for host: github.com' until you run:"
  echo "  ./scripts/setup-github-auth.sh"
fi

if [[ "${AUTH_GITHUB_CLIENT_ID:-changeme}" == "changeme" ]] \
  || [[ "${AUTH_GITHUB_CLIENT_SECRET:-changeme}" == "changeme" ]]; then
  echo ""
  echo "WARNING: GitHub OAuth is not configured (AUTH_GITHUB_CLIENT_ID/SECRET still 'changeme')."
  echo "The CI tab Authorize GitHub popup will fail until you run:"
  echo "  ./scripts/setup-github-auth.sh --oauth-only"
  echo "  ./scripts/create-github-oauth-app.sh --oauth-app"
  echo "Callback URL: https://${RHDH_HOST}/api/auth/github/handler/frame"
fi

if is_lightspeed_enabled && [[ "${OPENAI_API_KEY:-changeme}" == "changeme" ]]; then
  echo ""
  echo "WARNING: LIGHTSPEED_ENABLED=true but OPENAI_API_KEY is 'changeme'."
  echo "Developer Lightspeed requires a valid OpenAI API key:"
  echo "  export OPENAI_API_KEY=sk-...   # in scripts/workshop.env"
  echo "  ./scripts/setup-developer-hub-lightspeed.sh"
fi

if is_aap_enabled && [[ "${AAP_TOKEN:-changeme}" == "changeme" ]]; then
  echo ""
  echo "WARNING: AAP_ENABLED=true but AAP_TOKEN is 'changeme'."
  echo "Create a Controller personal access token (User → Tokens) or set AAP_ADMIN_PASSWORD so"
  echo "setup-developer-hub-aap.sh can mint one:"
  echo "  export AAP_TOKEN=<pat>   # in scripts/workshop.env"
  echo "  ./scripts/setup-developer-hub-aap.sh"
fi

if is_aap_enabled && [[ "${RH_REGISTRY_TOKEN:-changeme}" == "changeme" ]]; then
  echo ""
  echo "WARNING: RH_REGISTRY_USERNAME/RH_REGISTRY_TOKEN not set."
  echo "Ansible OCI dynamic plugins require registry.redhat.io auth:"
  echo "  https://access.redhat.com/terms-based-registry/accounts"
  echo "Use the registry service account token — not an OpenShift or AAP token."
fi

if is_aap_enabled && ! is_aap_management_enabled; then
  echo ""
  echo "NOTE: AAP_ENABLED=true but AAP_MANAGEMENT_ENABLED is not true."
  echo "The upstream /ansible plugin is configured; the custom /aap-management plugin is skipped."
  echo "To install the custom AAP Management plugin (Templates + job history):"
  echo "  export AAP_MANAGEMENT_ENABLED=true   # in scripts/workshop.env"
  echo "  ./scripts/setup-developer-hub-config.sh"
  echo "Or: ./scripts/setup-custom-aap-management-plugin.sh"
fi

if is_aap_management_enabled && ! is_aap_enabled; then
  echo ""
  echo "WARNING: AAP_MANAGEMENT_ENABLED=true but AAP_ENABLED is not true."
  echo "The custom plugin needs AAP_CONTROLLER_URL and AAP_TOKEN; set AAP_ENABLED=true as well."
fi

"${SCRIPTS_DIR}/setup-developer-hub-techdocs.sh" || echo "Warning: TechDocs volume setup skipped."

if is_lightspeed_enabled; then
  "${SCRIPTS_DIR}/setup-developer-hub-lightspeed.sh" --no-rollout || \
    echo "Warning: Developer Lightspeed setup failed; see docs/workshop/06-install-developer-hub.md"
elif [[ "${LIGHTSPEED_ENABLED:-false}" != "false" ]]; then
  echo ""
  echo "NOTE: Set LIGHTSPEED_ENABLED=true and OPENAI_API_KEY in workshop.env, then re-run:"
  echo "  ./scripts/setup-developer-hub-lightspeed.sh"
fi

if is_aap_enabled; then
  "${SCRIPTS_DIR}/setup-developer-hub-aap.sh" --no-rollout || \
    echo "Warning: Ansible Automation Platform setup failed; see docs/workshop/06c-ansible-automation-platform.md"
elif [[ "${AAP_ENABLED:-false}" != "false" ]]; then
  echo ""
  echo "NOTE: Set AAP_ENABLED=true and AAP_* / RH_REGISTRY_* in workshop.env, then re-run:"
  echo "  ./scripts/setup-developer-hub-aap.sh"
fi

echo "Developer Hub configuration complete."
