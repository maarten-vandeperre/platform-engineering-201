#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Configuring Developer Hub Keycloak SSO in ${RHDH_NAMESPACE}..."

require_oc

resolve_keycloak_urls

if [[ -z "${KEYCLOAK_URL:-}" ]] && oc get route keycloak -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
  KEYCLOAK_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "keycloak")
  export KEYCLOAK_URL="https://${KEYCLOAK_HOST}"
  export OIDC_AUTH_SERVER_URL="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}"
fi

"${SCRIPTS_DIR}/configure-keycloak-realm.sh"
"${SCRIPTS_DIR}/setup-developer-hub-kubernetes.sh"

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
  BACKEND_SECRET=$(oc get secret redhat-developer-hub-auth -n "${RHDH_NAMESPACE}" -o jsonpath='{.data.backend-secret}' | base64 -d)
fi
export BACKEND_SECRET="${BACKEND_SECRET:-workshop-backend-secret}"
export GITHUB_TOKEN="${GITHUB_TOKEN:-changeme}"
export ARGOCD_URL="${ARGOCD_URL:-changeme}"
export ARGOCD_TOKEN="${ARGOCD_TOKEN:-changeme}"

if [[ -z "${POSTGRESQL_ADMIN_PASSWORD:-}" ]] && oc get secret redhat-developer-hub-postgresql -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  POSTGRESQL_ADMIN_PASSWORD=$(oc get secret redhat-developer-hub-postgresql -n "${RHDH_NAMESPACE}" \
    -o jsonpath='{.data.postgres-password}' | base64 -d)
fi
export POSTGRESQL_ADMIN_PASSWORD="${POSTGRESQL_ADMIN_PASSWORD:-changeme}"

if [[ -z "${K8S_CLUSTER_TOKEN:-}" ]] && oc get secret backstage-kubernetes-token -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  K8S_CLUSTER_TOKEN=$(oc get secret backstage-kubernetes-token -n "${RHDH_NAMESPACE}" \
    -o jsonpath='{.data.K8S_CLUSTER_TOKEN}' | base64 -d)
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
  --from-literal=ARGOCD_URL="${ARGOCD_URL:-changeme}" \
  --from-literal=ARGOCD_TOKEN="${ARGOCD_TOKEN:-changeme}" \
  --from-literal=RHDH_OIDC_CLIENT_SECRET="${RHDH_OIDC_CLIENT_SECRET}" \
  --dry-run=client -o yaml | oc apply -f -

render_app_config() {
  envsubst \
    '${RHDH_APP_TITLE} ${KEYCLOAK_URL} ${KEYCLOAK_REALM} ${RHDH_KEYCLOAK_CLIENT_ID} ${RHDH_OIDC_CLIENT_SECRET} ${CLUSTER_ROUTER_BASE} ${WORKSHOP_NAMESPACE} ${GITHUB_TOKEN} ${ARGOCD_URL} ${ARGOCD_TOKEN} ${BACKEND_SECRET} ${POSTGRESQL_ADMIN_PASSWORD} ${K8S_CLUSTER_TOKEN}' \
    <"${MANIFESTS_DIR}/developer-hub/app-config-rhdh.yaml" \
    | sed "s|PLACEHOLDER-RHDH-ROUTE|${RHDH_HOST}|g" \
    | sed "s|PLACEHOLDER-CATALOG-URL|${CATALOG_URL}|g" \
    | awk '/app-config-rhdh.yaml: \|/{flag=1;next} flag{sub(/^    /,""); print}'
}

render_dynamic_plugins() {
  envsubst '${RHDH_NAMESPACE}' <"${MANIFESTS_DIR}/developer-hub/dynamic-plugins-rhdh.yaml" \
    | awk '/dynamic-plugins.yaml: \|/{flag=1;next} flag{sub(/^    /,""); print}'
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

APP_CONFIG=$(render_app_config)
apply_dynamic_plugins_config

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
  echo "Restarting Developer Hub to apply configuration..."
  oc delete pod -l app.kubernetes.io/name=developer-hub -n "${RHDH_NAMESPACE}" --wait=false
  for i in $(seq 1 60); do
    ready=$(oc get pod -l app.kubernetes.io/name=developer-hub -n "${RHDH_NAMESPACE}" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ "${ready}" == "True" ]]; then
      echo "Developer Hub pod is ready."
      break
    fi
    if (( i == 60 )); then
      echo "Warning: timed out waiting for Developer Hub pod; configuration was applied." >&2
    fi
    sleep 10
  done
elif oc get deployment "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  oc set env "deployment/${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" \
    RHDH_OIDC_CLIENT_SECRET="${RHDH_OIDC_CLIENT_SECRET}" --overwrite
  oc rollout restart "deployment/${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}"
  oc rollout status "deployment/${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" --timeout=600s
fi

echo ""
echo "Developer Hub: https://${RHDH_HOST}"
echo "Sign in with Keycloak user ${RHDH_KEYCLOAK_USER} / (password from workshop.env)"
echo "Developer Hub configuration complete."
