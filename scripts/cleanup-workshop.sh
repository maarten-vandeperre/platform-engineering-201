#!/usr/bin/env bash
# Re-exec with bash when invoked as `sh script.sh` (macOS /bin/sh is bash in POSIX mode).
if [[ -z "${BASH_VERSION:-}" ]] || { shopt -oq posix 2>/dev/null; }; then
  exec bash "$0" "$@"
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/cleanup.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Remove workshop/demo resources from OpenShift so you can start fresh with
./scripts/bootstrap-workshop.sh. Safe to run after a partial demo — missing
resources are skipped.

Removes (when present):
  - Argo CD application and Helm release (operator or Helm install paths)
  - Red Hat Developer Hub (Helm release or Backstage CR + related config)
  - People Service, Keycloak, catalog server, TechDocs config
  - Orchestrator workflows, Data Index, SonataFlow resources
  - Custom AAP Management plugin server
  - Workshop configmaps, secrets, builds, imagestreams, and PVCs

Options:
  --yes               Skip confirmation prompt
  --dry-run           Show what would be deleted without making changes
  --keep-pvcs         Keep persistent volume claims (database data survives)
  --remove-operators  Also delete operator Subscriptions in the workshop namespace
  --delete-namespace  Delete the OpenShift project(s) when finished
  -h, --help          Show this help

Examples:
  $(basename "$0") --dry-run
  $(basename "$0") --yes
  $(basename "$0") --yes --remove-operators --delete-namespace

See docs/workshop/09-cleanup-after-demo.md
EOF
}

CLEANUP_DRY_RUN=false
CLEANUP_YES=false
CLEANUP_KEEP_PVCS=false
CLEANUP_REMOVE_OPERATORS=false
CLEANUP_DELETE_NAMESPACE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) CLEANUP_YES=true ;;
    --dry-run) CLEANUP_DRY_RUN=true ;;
    --keep-pvcs) CLEANUP_KEEP_PVCS=true ;;
    --remove-operators) CLEANUP_REMOVE_OPERATORS=true ;;
    --delete-namespace) CLEANUP_DELETE_NAMESPACE=true ;;
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

export CLEANUP_DRY_RUN

require_oc

namespaces=("${WORKSHOP_NAMESPACE}")
if [[ "${RHDH_NAMESPACE}" != "${WORKSHOP_NAMESPACE}" ]]; then
  namespaces+=("${RHDH_NAMESPACE}")
fi
if [[ "${GITOPS_NAMESPACE}" != "${WORKSHOP_NAMESPACE}" && "${GITOPS_NAMESPACE}" != "${RHDH_NAMESPACE}" ]]; then
  namespaces+=("${GITOPS_NAMESPACE}")
fi

echo "Workshop cleanup"
echo "  Workshop namespace:  ${WORKSHOP_NAMESPACE}"
echo "  Developer Hub namespace: ${RHDH_NAMESPACE}"
echo "  GitOps namespace:    ${GITOPS_NAMESPACE}"
echo ""

if [[ "${CLEANUP_YES}" != "true" && "${CLEANUP_DRY_RUN}" != "true" ]]; then
  cat <<EOF
This will delete demo workloads and configuration in the namespace(s) above.
Local files (scripts/workshop.env, git clone) are not modified.

Continue? [y/N]
EOF
  read -r reply
  if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

cleanup_phase() {
  cleanup_log "$1"
}

cleanup_phase "Stopping GitOps sync for People Service"
cleanup_delete_if_exists application "${ARGOCD_APP_NAME}" "${GITOPS_NAMESPACE}"

cleanup_phase "Removing Developer Hub (Helm or Operator)"
cleanup_helm_uninstall redhat-developer-hub "${RHDH_NAMESPACE}"
cleanup_delete_backstage_cr "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}"

cleanup_phase "Removing Argo CD (Helm)"
cleanup_helm_uninstall argocd "${GITOPS_NAMESPACE}"

cleanup_phase "Removing Orchestrator infrastructure (Helm)"
cleanup_helm_uninstall orchestrator-infra "${WORKSHOP_NAMESPACE}"

cleanup_phase "Removing Orchestrator manifests"
cleanup_delete_dir "${MANIFESTS_DIR}/orchestrator"
cleanup_delete_sonataflow_resources "${WORKSHOP_NAMESPACE}"
cleanup_delete_if_exists deployment sonataflow-platform-data-index "${WORKSHOP_NAMESPACE}"
cleanup_delete_if_exists service sonataflow-platform-data-index-service "${WORKSHOP_NAMESPACE}"
cleanup_delete_if_exists deployment create-person-workflow "${WORKSHOP_NAMESPACE}"
cleanup_delete_if_exists service create-person-workflow "${WORKSHOP_NAMESPACE}"
cleanup_delete_if_exists route create-person-workflow "${WORKSHOP_NAMESPACE}"

cleanup_phase "Removing People Service manifests"
cleanup_delete_dir "${MANIFESTS_DIR}/people-app"
cleanup_delete_builds "${WORKSHOP_NAMESPACE}"
cleanup_delete_if_exists imagestream people-backend "${WORKSHOP_NAMESPACE}"
cleanup_delete_if_exists imagestream people-frontend "${WORKSHOP_NAMESPACE}"
cleanup_delete_by_label "${WORKSHOP_NAMESPACE}" "app.kubernetes.io/part-of=people-service"

cleanup_phase "Removing Keycloak"
cleanup_delete_dir "${MANIFESTS_DIR}/keycloak"

cleanup_phase "Removing Developer Hub workshop add-ons"
cleanup_delete_dir "${MANIFESTS_DIR}/developer-hub"
cleanup_delete_by_label "${WORKSHOP_NAMESPACE}" "app.kubernetes.io/part-of=developer-hub"
if [[ "${RHDH_NAMESPACE}" != "${WORKSHOP_NAMESPACE}" ]]; then
  cleanup_delete_by_label "${RHDH_NAMESPACE}" "app.kubernetes.io/part-of=developer-hub"
fi

cleanup_phase "Removing generated Developer Hub configuration"
for ns in "${WORKSHOP_NAMESPACE}" "${RHDH_NAMESPACE}"; do
  cleanup_delete_known_configmaps "${ns}" \
    workshop-catalog-entities \
    workshop-techdocs-quarkus-guide \
    workshop-techdocs-adrs \
    app-config-rhdh \
    redhat-developer-hub-app-config \
    redhat-developer-hub-dynamic-plugins \
    dynamic-plugins-rhdh \
    create-person-workflow-schemas
  cleanup_delete_known_secrets "${ns}" \
    rhdh-workshop-secrets \
    app-secrets-rhdh \
    argo-secrets \
    backstage-kubernetes-token \
    redhat-developer-hub-auth \
    redhat-developer-hub-postgresql \
    redhat-developer-hub-dynamic-plugins-registry-auth \
    redhat-developer-hub-pull-secret
done

cleanup_phase "Removing Kubernetes plugin RBAC"
cleanup_delete_rbac "${RHDH_NAMESPACE}"
if [[ "${WORKSHOP_NAMESPACE}" != "${RHDH_NAMESPACE}" ]]; then
  cleanup_delete_rbac "${WORKSHOP_NAMESPACE}"
fi

if [[ "${CLEANUP_KEEP_PVCS}" != "true" ]]; then
  cleanup_phase "Removing persistent volume claims"
  for ns in "${WORKSHOP_NAMESPACE}" "${RHDH_NAMESPACE}"; do
    cleanup_delete_pvcs "${ns}" \
      people-postgres-data \
      redhat-developer-hub-postgresql \
      redhat-developer-hub-dynamic-plugins-cache \
      dynamic-plugins-cache \
      rhdh-dynamic-plugins-cache
  done
  if [[ "${CLEANUP_DRY_RUN}" != "true" ]]; then
    oc delete pvc --all -n "${WORKSHOP_NAMESPACE}" --ignore-not-found --wait=false 2>/dev/null || true
    if [[ "${RHDH_NAMESPACE}" != "${WORKSHOP_NAMESPACE}" ]]; then
      oc delete pvc --all -n "${RHDH_NAMESPACE}" --ignore-not-found --wait=false 2>/dev/null || true
    fi
  fi
else
  cleanup_log "Keeping PVCs (--keep-pvcs)"
fi

if [[ "${CLEANUP_REMOVE_OPERATORS}" == "true" ]]; then
  cleanup_phase "Removing operator subscriptions"
  cleanup_delete_dir "${MANIFESTS_DIR}/operators"
  if [[ "${CLEANUP_DRY_RUN}" == "true" ]]; then
    oc get subscription,operatorgroup -n "${WORKSHOP_NAMESPACE}" 2>/dev/null || true
  else
    oc delete subscription --all -n "${WORKSHOP_NAMESPACE}" --ignore-not-found --wait=false 2>/dev/null || true
    oc delete operatorgroup --all -n "${WORKSHOP_NAMESPACE}" --ignore-not-found --wait=false 2>/dev/null || true
  fi
fi

cleanup_phase "Removing Argo CD instance (Operator path)"
cleanup_delete_argocd_instance "${GITOPS_NAMESPACE}" "${ARGOCD_INSTANCE_NAME}"

if [[ "${CLEANUP_DELETE_NAMESPACE}" == "true" ]]; then
  cleanup_phase "Deleting OpenShift project(s)"
  for ns in "${namespaces[@]}"; do
    if cleanup_namespace_exists "${ns}"; then
      cleanup_log "Deleting project ${ns}"
      cleanup_run oc delete project "${ns}" --wait=false 2>/dev/null || true
    fi
  done
else
  cleanup_phase "Verifying remaining resources"
  for ns in "${namespaces[@]}"; do
    cleanup_list_remaining "${ns}"
  done
fi

echo ""
if [[ "${CLEANUP_DRY_RUN}" == "true" ]]; then
  echo "Dry-run complete. Re-run without --dry-run to apply."
elif [[ "${CLEANUP_DELETE_NAMESPACE}" == "true" ]]; then
  echo "Cleanup complete. Project deletion continues in the background."
  echo "Recreate with: cp scripts/workshop.env.example scripts/workshop.env && ./scripts/bootstrap-workshop.sh"
else
  echo "Cleanup complete. Namespace(s) are empty of demo workloads."
  echo "Start again with: ./scripts/bootstrap-workshop.sh"
fi
