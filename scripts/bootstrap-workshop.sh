#!/usr/bin/env bash
# Re-exec with bash when invoked as `sh script.sh` (macOS /bin/sh is bash in POSIX mode).
if [[ -z "${BASH_VERSION:-}" ]] || { shopt -oq posix 2>/dev/null; }; then
  exec bash "$0" "$@"
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Platform Engineering 201 — full workshop bootstrap"
echo "Namespace: ${WORKSHOP_NAMESPACE}"
echo "Install method: ${WORKSHOP_INSTALL_METHOD:-helm}"
echo ""

chmod +x "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}/lib/"*.sh 2>/dev/null || true

detect_cluster_router_base
ensure_project

install_platform() {
  case "${WORKSHOP_INSTALL_METHOD:-helm}" in
    operator)
      "${SCRIPT_DIR}/install-operators.sh"
      if argocd_enabled; then
        "${SCRIPT_DIR}/setup-argocd.sh"
      else
        argocd_skip_message
      fi
      ;;
    helm)
      echo "Platform via Helm (Developer Hub after Keycloak; Argo CD optional)..."
      argocd_enabled || argocd_skip_message
      ;;
    skip-platform)
      echo "Skipping platform install (WORKSHOP_INSTALL_METHOD=skip-platform)."
      ;;
    *)
      echo "Unknown WORKSHOP_INSTALL_METHOD=${WORKSHOP_INSTALL_METHOD}. Use operator, helm, or skip-platform." >&2
      exit 1
      ;;
  esac
}

install_developer_hub() {
  case "${WORKSHOP_INSTALL_METHOD:-helm}" in
    operator)
      "${SCRIPT_DIR}/install-developer-hub.sh"
      ;;
    helm)
      if argocd_enabled; then
        "${SCRIPT_DIR}/install-argocd-helm.sh"
      fi
      "${SCRIPT_DIR}/install-developer-hub-helm.sh"
      ;;
    skip-platform)
      if ! oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1 \
        && ! oc get backstage "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
        echo "Developer Hub not found. Set WORKSHOP_INSTALL_METHOD=operator or helm." >&2
        exit 1
      fi
      ;;
  esac
}

install_platform

echo ""
echo "== Keycloak + People Service =="
"${SCRIPT_DIR}/setup-keycloak.sh"
"${SCRIPT_DIR}/deploy-people-app.sh"

echo ""
echo "== Developer Hub =="
install_developer_hub

if argocd_enabled; then
  echo ""
  echo "== Argo CD token for Developer Hub =="
  "${SCRIPT_DIR}/setup-argocd-token.sh" || echo "Warning: Argo CD token setup skipped or failed."
fi

echo ""
echo "== Developer Hub configuration =="
"${SCRIPT_DIR}/setup-developer-hub-kubernetes.sh"
"${SCRIPT_DIR}/setup-developer-hub-config.sh"
"${SCRIPT_DIR}/configure-developer-hub-catalog.sh"
"${SCRIPT_DIR}/setup-developer-hub-techdocs.sh"
"${SCRIPT_DIR}/setup-orchestrator.sh" || echo "Warning: Orchestrator setup skipped or failed."

echo ""
echo "== Platform readiness =="
"${SCRIPT_DIR}/ensure-workshop-platform.sh"

echo ""
echo "== Validation =="
"${SCRIPT_DIR}/validate-workshop.sh"

if [[ "${RUN_E2E:-false}" == "true" ]]; then
  echo ""
  echo "== End-to-end tests =="
  "${SCRIPT_DIR}/../e2e/run-e2e.sh"
fi

RHDH_HOST=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null \
  || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null || echo "")
FRONTEND_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "people-frontend" 2>/dev/null || echo "")

echo ""
echo "Workshop bootstrap complete."
[[ -n "${FRONTEND_HOST}" ]] && echo "People UI:      https://${FRONTEND_HOST}"
[[ -n "${RHDH_HOST}" ]] && echo "Developer Hub:  https://${RHDH_HOST}"
[[ -n "${RHDH_HOST}" ]] && echo "API catalog:    https://${RHDH_HOST}/catalog?filters%5Bkind%5D=api"
[[ -n "${RHDH_HOST}" ]] && echo "Tech Radar:     https://${RHDH_HOST}/tech-radar"
echo ""
echo "Sign in to Developer Hub: ${RHDH_KEYCLOAK_USER} / (password in workshop.env)"
echo "Repair later: ./scripts/ensure-workshop-platform.sh && ./scripts/repair-people-app.sh"
