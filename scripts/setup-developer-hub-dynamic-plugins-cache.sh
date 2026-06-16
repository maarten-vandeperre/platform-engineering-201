#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Enable the Red Hat Developer Hub dynamic plugins cache by replacing the default
ephemeral dynamic-plugins-root volume with a persistent PVC of the same name.

This speeds up Developer Hub restarts: install-dynamic-plugins skips downloads
when plugin package references and config checksums are unchanged.

Options:
  --force-rollout   Patch the deployment and roll out even if PVC is already wired
  --no-rollout      Apply PVC/patch only; do not restart Developer Hub
  --clear-lock      Remove a stale install-dynamic-plugins lock file on the PVC
  -h, --help        Show this help

See docs/workshop/06-install-developer-hub.md
EOF
}

FORCE_ROLLOUT=false
CLEAR_LOCK=false
NO_ROLLOUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-rollout) FORCE_ROLLOUT=true ;;
    --clear-lock) CLEAR_LOCK=true ;;
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

require_oc

deploy_name="$(resolve_rhdh_deploy_name)"

echo "Setting up Developer Hub dynamic plugins cache in ${RHDH_NAMESPACE}..."

render_manifest "${MANIFESTS_DIR}/developer-hub/dynamic-plugins-pvc.yaml" | oc apply -f -

if ! oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  echo "Developer Hub deployment not found in ${RHDH_NAMESPACE}; PVC created — run again after Helm install."
  exit 0
fi

if [[ "${CLEAR_LOCK}" == "true" ]]; then
  clear_dynamic_plugins_install_lock || true
fi

patch_deployment_plugins_cache() {
  local deploy="$1"
  local patched_json tmp
  tmp="$(mktemp)"
  oc get deployment "${deploy}" -n "${RHDH_NAMESPACE}" -o json \
    | jq '
      .spec.template.spec.volumes |= map(
        if .name == "dynamic-plugins-root" then
          {
            name: "dynamic-plugins-root",
            persistentVolumeClaim: {
              claimName: "dynamic-plugins-root"
            }
          }
        else
          .
        end
      )
    ' >"${tmp}"
  oc apply -f "${tmp}"
  rm -f "${tmp}"
}

patched=false
if developer_hub_uses_plugins_pvc "${deploy_name}"; then
  echo "Deployment ${deploy_name} already uses PVC dynamic-plugins-root."
else
  replicas="$(oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" -o jsonpath='{.spec.replicas}')"
  if [[ -z "${replicas}" || "${replicas}" == "0" ]]; then
    replicas=1
  fi
  echo "Scaling ${deploy_name} to 0 before switching dynamic-plugins-root to PVC..."
  oc scale "deployment/${deploy_name}" -n "${RHDH_NAMESPACE}" --replicas=0
  wait_for_developer_hub_pods_gone || true
  echo "Patching ${deploy_name} to mount PVC dynamic-plugins-root..."
  patch_deployment_plugins_cache "${deploy_name}"
  patched=true
fi

if [[ "${NO_ROLLOUT}" == "true" ]]; then
  echo "Dynamic plugins cache configured (rollout skipped)."
  exit 0
fi

if [[ "${patched}" == "true" || "${FORCE_ROLLOUT}" == "true" ]]; then
  echo "Rolling out Developer Hub to pick up persistent plugins cache..."
  safe_rollout_developer_hub "${deploy_name}" 900s
fi

echo "Dynamic plugins cache enabled (PVC dynamic-plugins-root)."
echo "Subsequent config-only restarts should be faster (plugins are not re-downloaded when unchanged)."
