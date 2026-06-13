#!/usr/bin/env bash
# Enable Red Hat Developer Lightspeed (chat assistant) on Developer Hub.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Install Developer Lightspeed sidecars, secrets, and RBAC on Developer Hub.
Requires OPENAI_API_KEY when LIGHTSPEED_LLM_PROVIDER=openai (default).

Options:
  --force-rollout   Restart Developer Hub after patching
  --no-rollout      Apply manifests/patches only
  -h, --help        Show this help

Configure in scripts/workshop.env:
  LIGHTSPEED_ENABLED=true
  OPENAI_API_KEY=sk-...
  OPENAI_MODEL=gpt-4o-mini

See docs/workshop/06-install-developer-hub.md#developer-lightspeed
EOF
}

FORCE_ROLLOUT=false
NO_ROLLOUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-rollout) FORCE_ROLLOUT=true ;;
    --no-rollout) NO_ROLLOUT=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

is_truthy() {
  case "${1:-}" in
    true | True | TRUE | 1 | yes | Yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

require_oc

if ! is_truthy "${LIGHTSPEED_ENABLED:-false}"; then
  echo "LIGHTSPEED_ENABLED is not true; skipping Developer Lightspeed setup."
  exit 0
fi

export LIGHTSPEED_ENABLE_OPENAI="true"
export LIGHTSPEED_VLLM_MAX_TOKENS="${LIGHTSPEED_VLLM_MAX_TOKENS:-4096}"
export OPENAI_API_KEY="${OPENAI_API_KEY:-changeme}"
export OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"

if [[ "${OPENAI_API_KEY}" == "changeme" ]]; then
  echo "ERROR: LIGHTSPEED_ENABLED=true but OPENAI_API_KEY is still 'changeme'." >&2
  echo "Set OPENAI_API_KEY in scripts/workshop.env (OpenAI platform API key)." >&2
  exit 1
fi

deploy_name="redhat-developer-hub"
if ! oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  if oc get deployment "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    deploy_name="${RHDH_INSTANCE_NAME}"
  else
    echo "Developer Hub deployment not found in ${RHDH_NAMESPACE}; skipping Lightspeed setup." >&2
    exit 0
  fi
fi

echo "Setting up Developer Lightspeed in ${RHDH_NAMESPACE}..."

export RHDH_HOST="$(resolve_rhdh_host)"
ensure_mcp_token

render_manifest "${MANIFESTS_DIR}/developer-hub/lightspeed-stack-configmap.yaml" | oc apply -f -
render_manifest "${MANIFESTS_DIR}/developer-hub/lightspeed-app-config.yaml" | oc apply -f -
render_manifest "${MANIFESTS_DIR}/developer-hub/lightspeed-rbac-policies.yaml" | oc apply -f -
render_manifest "${MANIFESTS_DIR}/developer-hub/lightspeed-llama-stack-secret.yaml" | oc apply -f -
render_manifest "${MANIFESTS_DIR}/developer-hub/lightspeed-mcp-token-secret.yaml" | oc apply -f -
if [[ "${LIGHTSPEED_SAFETY_GUARD:-false}" == "true" ]]; then
  echo "LIGHTSPEED_SAFETY_GUARD=true — using default Llama Stack safety guard (requires SAFETY_URL)."
else
  render_manifest "${MANIFESTS_DIR}/developer-hub/lightspeed-llama-stack-configmap.yaml" | oc apply -f -
  echo "Using run-no-guard Llama Stack config (OpenAI workshop mode; no Llama Guard moderation)."
fi

patch_backstage_cr() {
  local cr_name="${1}"
  if ! oc get backstage "${cr_name}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    return 0
  fi

  local tmp merged
  tmp="$(mktemp)"
  oc get backstage "${cr_name}" -n "${RHDH_NAMESPACE}" -o json >"${tmp}"

  jq --arg user "${RHDH_KEYCLOAK_USER}" '
    .spec.application.appConfig.configMaps |= (
      (. // []) | if any(.name == "lightspeed-app-config") then . else . + [{"name": "lightspeed-app-config"}] end
    )
    | .spec.application.extraEnvs.secrets |= (
      (. // []) | if any(.name == "llama-stack-secrets") then . else . + [{"name": "llama-stack-secrets"}] end
    )
    | .spec.application.extraFiles = {
        mountPath: "/opt/app-root/src",
        configMaps: [{name: "lightspeed-rbac-policies"}]
      }
    | .spec.application.appConfig.configMaps |= (
      . // []
    )
    | .spec.application = (.spec.application // {})
  ' "${tmp}" >"${tmp}.patched"

  oc apply -f "${tmp}.patched"
  rm -f "${tmp}" "${tmp}.patched"
  echo "Patched Backstage CR ${cr_name} for Developer Lightspeed."
}

patch_backstage_cr "${RHDH_INSTANCE_NAME}"

deployment_has_lightspeed() {
  oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" -o json \
    | jq -e '.spec.template.spec.containers[] | select(.name == "llama-stack")' >/dev/null 2>&1
}

patch_deployment_lightspeed() {
  local use_no_guard="${1:-true}"
  local tmp
  tmp="$(mktemp)"
  oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" -o json \
    | jq --arg use_no_guard "${use_no_guard}" '
      .spec.template.spec.volumes = (
        (.spec.template.spec.volumes // [])
        | map(select(.name != "lightspeed-stack" and .name != "shared-storage" and .name != "rag-data-volume" and .name != "llama-stack-config" and .name != "lightspeed-mcp-token"))
        + [
          {name: "lightspeed-stack", configMap: {name: "lightspeed-stack"}},
          {name: "shared-storage", emptyDir: {}},
          {name: "rag-data-volume", emptyDir: {}},
          {name: "lightspeed-mcp-token", secret: {secretName: "lightspeed-mcp-token"}}
        ]
        + (if $use_no_guard == "true" then [{name: "llama-stack-config", configMap: {name: "llama-stack-config"}}] else [] end)
      )
      | .spec.template.spec.initContainers = (
        (.spec.template.spec.initContainers // [])
        | map(select(.name != "init-rag-data"))
        + [{
            name: "init-rag-data",
            image: "quay.io/redhat-ai-dev/rag-content:release-1.9-lcs",
            command: ["sh", "-c", "cp -r /rag/vector_db/rhdh_product_docs /rag-content/ && cp -r /rag/embeddings_model /rag-content/"],
            volumeMounts: [{name: "rag-data-volume", mountPath: "/rag-content"}]
          }]
      )
      | .spec.template.spec.containers = (
        (.spec.template.spec.containers // [])
        | map(
            if .name == "llama-stack" then
              .volumeMounts = (
                (.volumeMounts // [])
                | map(select(.name != "llama-stack-config"))
                + [
                  {name: "shared-storage", mountPath: "/app-root/.llama"},
                  {name: "rag-data-volume", mountPath: "/rag-content"}
                ]
                + (if $use_no_guard == "true" then [{name: "llama-stack-config", mountPath: "/app-root/run.yaml", subPath: "run.yaml"}] else [] end)
              )
            else .
            end
          )
        | map(select(.name != "llama-stack" and .name != "lightspeed-core"))
        + [
          {
            name: "llama-stack",
            image: "quay.io/redhat-ai-dev/llama-stack:0.1.4",
            envFrom: [{secretRef: {name: "llama-stack-secrets"}}],
            volumeMounts: (
              [
                {name: "shared-storage", mountPath: "/app-root/.llama"},
                {name: "rag-data-volume", mountPath: "/rag-content"}
              ]
              + (if $use_no_guard == "true" then [{name: "llama-stack-config", mountPath: "/app-root/run.yaml", subPath: "run.yaml"}] else [] end)
            )
          },
          {
            name: "lightspeed-core",
            image: "quay.io/lightspeed-core/lightspeed-stack:0.4.0",
            volumeMounts: [
              {name: "lightspeed-stack", mountPath: "/app-root/lightspeed-stack.yaml", subPath: "lightspeed-stack.yaml"},
              {name: "shared-storage", mountPath: "/tmp/data/feedback"},
              {name: "shared-storage", mountPath: "/tmp/data/transcripts"},
              {name: "shared-storage", mountPath: "/tmp/data/conversations"},
              {name: "lightspeed-mcp-token", mountPath: "/var/secrets/mcp", readOnly: true}
            ]
          }
        ]
      )
    ' >"${tmp}"
  oc apply -f "${tmp}"
  rm -f "${tmp}"
}

use_no_guard="true"
if [[ "${LIGHTSPEED_SAFETY_GUARD:-false}" == "true" ]]; then
  use_no_guard="false"
fi

if deployment_has_lightspeed; then
  echo "Updating Developer Lightspeed sidecars on ${deploy_name}..."
else
  echo "Patching ${deploy_name} with llama-stack and lightspeed-core sidecars..."
fi
patch_deployment_lightspeed "${use_no_guard}"

if [[ "${NO_ROLLOUT}" == "true" ]]; then
  echo "Developer Lightspeed configured (rollout skipped)."
  exit 0
fi

# Dev namespaces often hit replicaset quota during repeated rollouts.
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

echo "Rolling out Developer Hub to apply Developer Lightspeed configuration..."
oc rollout restart "deployment/${deploy_name}" -n "${RHDH_NAMESPACE}"
oc rollout status "deployment/${deploy_name}" -n "${RHDH_NAMESPACE}" --timeout=900s

RHDH_HOST=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null \
  || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null \
  || echo "developer-hub.example.com")

echo ""
echo "Developer Lightspeed enabled."
echo "  Chat page: https://${RHDH_HOST}/lightspeed"
echo "  MCP server: https://${RHDH_HOST}/api/mcp-actions/v1 (linked to Lightspeed as mcp::backstage)"
echo "  Open the floating action button (bottom-right) after signing in."
echo "  Model: ${OPENAI_MODEL} via OpenAI (use gpt-4o-mini or gpt-4o for MCP tool calling)"
