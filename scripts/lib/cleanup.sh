# shellcheck shell=bash
# Workshop cleanup helpers — sourced by cleanup-workshop.sh

cleanup_log() {
  echo "[cleanup] $*"
}

cleanup_run() {
  if [[ "${CLEANUP_DRY_RUN:-false}" == "true" ]]; then
    cleanup_log "DRY-RUN: $*"
    return 0
  fi
  "$@"
}

cleanup_delete_file() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    return 0
  fi
  cleanup_run render_manifest "${file}" | oc delete -f - --ignore-not-found --wait=false 2>/dev/null || true
}

cleanup_delete_dir() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    return 0
  fi
  local file
  local files=()
  while IFS= read -r -d '' file; do
    files+=("${file}")
  done < <(find "${dir}" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | sort -z)
  local i
  for ((i = ${#files[@]} - 1; i >= 0; i--)); do
    cleanup_delete_file "${files[i]}"
  done
}

cleanup_delete_if_exists() {
  local kind="$1"
  local name="$2"
  local namespace="$3"
  if ! oc get "${kind}" "${name}" -n "${namespace}" >/dev/null 2>&1; then
    return 0
  fi
  cleanup_log "Deleting ${kind}/${name} in ${namespace}"
  cleanup_run oc delete "${kind}" "${name}" -n "${namespace}" --ignore-not-found --wait=false
}

cleanup_helm_uninstall() {
  local release="$1"
  local namespace="$2"
  if ! command -v helm >/dev/null 2>&1; then
    return 0
  fi
  if ! helm status "${release}" -n "${namespace}" >/dev/null 2>&1; then
    return 0
  fi
  cleanup_log "Helm uninstall ${release} in ${namespace}"
  if [[ "${CLEANUP_DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi
  helm uninstall "${release}" -n "${namespace}" --wait --timeout 10m 2>/dev/null \
    || helm uninstall "${release}" -n "${namespace}" 2>/dev/null \
    || true
}

cleanup_delete_by_label() {
  local namespace="$1"
  local label="$2"
  shift 2
  if ! oc get namespace "${namespace}" >/dev/null 2>&1; then
    return 0
  fi
  cleanup_log "Deleting resources in ${namespace} with label ${label}"
  if [[ "${CLEANUP_DRY_RUN:-false}" == "true" ]]; then
    oc get deploy,statefulset,svc,route,pvc,buildconfig,build,imagestream,job,cronjob,pod,configmap,secret \
      -n "${namespace}" -l "${label}" --no-headers 2>/dev/null || true
    return 0
  fi
  oc delete deploy,statefulset,svc,route,pvc,buildconfig,build,imagestream,job,cronjob,pod,configmap,secret \
    -n "${namespace}" -l "${label}" --ignore-not-found --wait=false 2>/dev/null || true
}

cleanup_delete_backstage_cr() {
  local namespace="$1"
  local name="$2"
  if ! oc get backstage "${name}" -n "${namespace}" >/dev/null 2>&1; then
    return 0
  fi
  cleanup_log "Removing Backstage CR ${name} in ${namespace}"
  if [[ "${CLEANUP_DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi
  oc patch backstage "${name}" -n "${namespace}" --type=merge \
    -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  oc delete backstage "${name}" -n "${namespace}" --ignore-not-found --wait=false
}

cleanup_delete_argocd_instance() {
  local namespace="$1"
  local name="$2"
  if ! oc get argocd "${name}" -n "${namespace}" >/dev/null 2>&1; then
    return 0
  fi
  cleanup_log "Removing ArgoCD instance ${name} in ${namespace}"
  if [[ "${CLEANUP_DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi
  oc patch argocd "${name}" -n "${namespace}" --type=merge \
    -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  oc delete argocd "${name}" -n "${namespace}" --ignore-not-found --wait=false
}

cleanup_delete_subscriptions() {
  local namespace="$1"
  shift
  local sub
  for sub in "$@"; do
    cleanup_delete_if_exists subscription "${sub}" "${namespace}"
  done
}

cleanup_delete_known_configmaps() {
  local namespace="$1"
  shift
  local name
  for name in "$@"; do
    cleanup_delete_if_exists configmap "${name}" "${namespace}"
  done
}

cleanup_delete_known_secrets() {
  local namespace="$1"
  shift
  local name
  for name in "$@"; do
    cleanup_delete_if_exists secret "${name}" "${namespace}"
  done
}

cleanup_delete_pvcs() {
  local namespace="$1"
  shift
  local pvc
  for pvc in "$@"; do
    cleanup_delete_if_exists pvc "${pvc}" "${namespace}"
  done
}

cleanup_delete_rbac() {
  local namespace="$1"
  cleanup_delete_if_exists role backstage-kubernetes-read "${namespace}"
  cleanup_delete_if_exists rolebinding backstage-kubernetes-read "${namespace}"
  cleanup_delete_if_exists rolebinding backstage-kubernetes-view "${namespace}"
  cleanup_delete_if_exists serviceaccount backstage-kubernetes "${namespace}"
}

cleanup_delete_sonataflow_resources() {
  local namespace="$1"
  if [[ "${CLEANUP_DRY_RUN:-false}" == "true" ]]; then
    oc get sonataflow,sonataflowplatform -n "${namespace}" --no-headers 2>/dev/null || true
    return 0
  fi
  oc delete sonataflow --all -n "${namespace}" --ignore-not-found --wait=false 2>/dev/null || true
  oc delete sonataflowplatform --all -n "${namespace}" --ignore-not-found --wait=false 2>/dev/null || true
}

cleanup_delete_builds() {
  local namespace="$1"
  cleanup_delete_if_exists buildconfig people-backend "${namespace}"
  cleanup_delete_if_exists buildconfig people-frontend "${namespace}"
  if [[ "${CLEANUP_DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi
  oc delete build --all -n "${namespace}" --ignore-not-found --wait=false 2>/dev/null || true
}

cleanup_namespace_exists() {
  oc get namespace "$1" >/dev/null 2>&1
}

cleanup_list_remaining() {
  local namespace="$1"
  if ! cleanup_namespace_exists "${namespace}"; then
    cleanup_log "Namespace ${namespace} does not exist."
    return 0
  fi
  cleanup_log "Remaining resources in ${namespace} (excluding secrets unless labeled):"
  oc get deploy,statefulset,svc,route,pvc,buildconfig,imagestream,job,cronjob \
    -n "${namespace}" 2>/dev/null | sed 's/^/  /' || true
}
