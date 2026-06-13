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

deploy_name="redhat-developer-hub"
if ! oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  if oc get deployment "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    deploy_name="${RHDH_INSTANCE_NAME}"
  else
    echo "Developer Hub deployment not found in ${RHDH_NAMESPACE}; skipping plugins cache setup."
    exit 0
  fi
fi

uses_persistent_plugins_cache() {
  oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" -o json \
    | jq -e '.spec.template.spec.volumes[]
       | select(.name == "dynamic-plugins-root")
       | .persistentVolumeClaim.claimName' >/dev/null 2>&1
}

clear_plugins_install_lock() {
  local pod
  pod="$(oc get pod -n "${RHDH_NAMESPACE}" -l app.kubernetes.io/name=developer-hub \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "${pod}" ]]; then
    echo "No Developer Hub pod found; cannot clear install lock." >&2
    return 1
  fi

  for path in \
    /dynamic-plugins-root/install-dynamic-plugins.lock \
    /dynamic-plugins-root/dynamic-plugins.lock; do
    oc exec -n "${RHDH_NAMESPACE}" "${pod}" -c install-dynamic-plugins -- \
      rm -f "${path}" 2>/dev/null \
      || oc exec -n "${RHDH_NAMESPACE}" "${pod}" -c backstage-backend -- \
        rm -f "${path}" 2>/dev/null \
      || true
  done
  echo "Cleared stale dynamic plugins install lock (if present)."
}

echo "Setting up Developer Hub dynamic plugins cache in ${RHDH_NAMESPACE}..."

render_manifest "${MANIFESTS_DIR}/developer-hub/dynamic-plugins-pvc.yaml" | oc apply -f -

if [[ "${CLEAR_LOCK}" == "true" ]]; then
  clear_plugins_install_lock || true
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
if uses_persistent_plugins_cache; then
  echo "Deployment ${deploy_name} already uses PVC dynamic-plugins-root."
else
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
  oc rollout restart "deployment/${deploy_name}" -n "${RHDH_NAMESPACE}"
  oc rollout status "deployment/${deploy_name}" -n "${RHDH_NAMESPACE}" --timeout=600s
fi

echo "Dynamic plugins cache enabled (PVC dynamic-plugins-root)."
echo "Subsequent config-only restarts should be faster (plugins are not re-downloaded when unchanged)."
