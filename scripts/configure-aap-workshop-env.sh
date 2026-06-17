#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/aap.sh"

CONSOLE_URL=""
ADMIN_USER=""
ADMIN_PASS=""
RH_USER=""
RH_TOKEN=""
INTERACTIVE=true
APPLY=false
DRY_RUN=false
FORCE_TOKEN=false

missing=()
warnings=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Populate scripts/workshop.env with Ansible Automation Platform (AAP) variables for
the Developer Hub plugin.

Can auto-detect from the cluster (OpenShift sandbox-aap routes and admin secret)
and mint a Controller personal access token from admin credentials.

What this script CAN set automatically:
  AAP_ENABLED, AAP_CONTROLLER_URL, AAP_ADMIN_USERNAME, AAP_ADMIN_PASSWORD,
  AAP_TOKEN (via Controller API), AAP_CHECK_SSL

What you must still provide (cannot be derived from AAP console login):
  RH_REGISTRY_USERNAME, RH_REGISTRY_TOKEN
  Red Hat Container Registry service account from:
  https://access.redhat.com/terms-based-registry/accounts

Examples:
  ./scripts/configure-aap-workshop-env.sh \\
    --url https://sandbox-aap-rh-ee-mvandepe-dev.apps.rm1.0a51.p1.openshiftapps.com \\
    --username admin \\
    --password 'your-password' \\
    --rh-registry-username <your-rh-registry-sa> \\
    --rh-registry-token <your-rh-registry-token> \\
    --apply
  ./scripts/configure-aap-workshop-env.sh \\
    --url https://sandbox-aap-rh-ee-mvandepe-dev.apps.rm1.0a51.p1.openshiftapps.com \\
    --username admin \\
    --password 'your-password'
  ./scripts/configure-aap-workshop-env.sh

Options:
  --url URL                 AAP console or Controller URL
  --username USER           AAP admin username
  --password PASS           AAP admin password
  --rh-registry-username U  Red Hat registry service account name
  --rh-registry-token T     Red Hat registry service account token
  --force-token             Replace AAP_TOKEN even if already set
  --no-interactive          Fail instead of prompting
  --apply                   Run setup-developer-hub-aap.sh after updating env
  --dry-run                 Print values without writing workshop.env
  -h, --help                Show this help

See docs/workshop/06c-ansible-automation-platform.md
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --url) CONSOLE_URL="$2"; shift 2 ;;
      --username) ADMIN_USER="$2"; shift 2 ;;
      --password) ADMIN_PASS="$2"; shift 2 ;;
      --rh-registry-username) RH_USER="$2"; shift 2 ;;
      --rh-registry-token) RH_TOKEN="$2"; shift 2 ;;
      --force-token) FORCE_TOKEN=true; shift ;;
      --no-interactive) INTERACTIVE=false; shift ;;
      --apply) APPLY=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h | --help) usage; exit 0 ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

resolve_console_url() {
  local resolved=""

  if [[ -n "${CONSOLE_URL}" ]]; then
    resolved="$(aap_resolve_controller_url_from_console "${CONSOLE_URL}")"
    echo "Using Controller URL ${resolved} (from --url ${CONSOLE_URL})"
  elif resolved="$(aap_detect_controller_url 2>/dev/null || true)" && [[ -n "${resolved}" ]]; then
    echo "Detected AAP_CONTROLLER_URL=${resolved} from cluster"
  else
    missing+=("AAP_CONTROLLER_URL (--url or sandbox-aap route in ${WORKSHOP_NAMESPACE})")
    return 1
  fi

  export AAP_CONTROLLER_URL="${resolved}"
}

resolve_admin_credentials() {
  ADMIN_USER="${ADMIN_USER:-${AAP_ADMIN_USERNAME:-admin}}"
  ADMIN_PASS="${ADMIN_PASS:-${AAP_ADMIN_PASSWORD:-}}"

  if [[ -z "${ADMIN_PASS}" || "${ADMIN_PASS}" == "changeme" ]]; then
    if cluster_pass="$(aap_read_admin_password_from_cluster 2>/dev/null || true)" && [[ -n "${cluster_pass}" ]]; then
      ADMIN_PASS="${cluster_pass}"
      echo "Read AAP admin password from secret sandbox-aap-admin-password"
    elif [[ "${INTERACTIVE}" == "true" && -t 0 ]]; then
      read -r -s -p "AAP admin password for ${ADMIN_USER}: " ADMIN_PASS
      echo ""
    else
      missing+=("AAP_ADMIN_PASSWORD (--password or sandbox-aap-admin-password secret)")
      return 1
    fi
  fi

  export AAP_ADMIN_USERNAME="${ADMIN_USER}"
  export AAP_ADMIN_PASSWORD="${ADMIN_PASS}"
}

resolve_aap_token() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    if [[ -n "${AAP_TOKEN:-}" && "${AAP_TOKEN}" != "changeme" ]]; then
      echo "Would keep existing AAP_TOKEN from workshop.env"
    else
      echo "Would attempt to create AAP_TOKEN via Controller API (skipped in --dry-run)"
    fi
    return 0
  fi

  if [[ -n "${AAP_TOKEN:-}" && "${AAP_TOKEN}" != "changeme" && "${FORCE_TOKEN}" != "true" ]]; then
    echo "Keeping existing AAP_TOKEN from workshop.env"
    return 0
  fi

  local token base="${AAP_CONTROLLER_URL%/}"
  if ! aap_api_reachable "${base}" "${AAP_ADMIN_USERNAME}" "${AAP_ADMIN_PASSWORD}" >/dev/null; then
    local controller_host
    controller_host="$(aap_route_host sandbox-aap-controller)"
    if [[ -n "${controller_host}" ]]; then
      base="https://${controller_host}"
      export AAP_CONTROLLER_URL="${base}"
      echo "Controller API not reachable at prior URL; switched to ${base}"
    fi
  fi

  if ! aap_api_reachable "${base}" "${AAP_ADMIN_USERNAME}" "${AAP_ADMIN_PASSWORD}" >/dev/null; then
    warnings+=("Could not reach Controller API to create AAP_TOKEN (is sandbox-aap running?). Create a PAT manually: User → Tokens")
    missing+=("AAP_TOKEN")
    return 1
  fi

  echo "Creating Controller personal access token via ${base}/api/v2/tokens/ ..."
  if token="$(aap_create_token "${base}" "${AAP_ADMIN_USERNAME}" "${AAP_ADMIN_PASSWORD}")"; then
    export AAP_TOKEN="${token}"
    echo "Created AAP_TOKEN"
    return 0
  fi

  warnings+=("Controller API reachable but token creation failed. Create a PAT manually and re-run with --force-token")
  missing+=("AAP_TOKEN")
  return 1
}

resolve_rh_registry() {
  RH_USER="${RH_USER:-${RH_REGISTRY_USERNAME:-}}"
  RH_TOKEN="${RH_TOKEN:-${RH_REGISTRY_TOKEN:-}}"

  if [[ -n "${RH_USER}" && "${RH_USER}" != "changeme" \
    && -n "${RH_TOKEN}" && "${RH_TOKEN}" != "changeme" ]]; then
    export RH_REGISTRY_USERNAME="${RH_USER}"
    export RH_REGISTRY_TOKEN="${RH_TOKEN}"
    # shellcheck disable=SC1091
    source "${SCRIPTS_DIR}/lib/developer-hub-dynamic-plugins.sh"
    validate_rh_registry_credentials "${RH_REGISTRY_USERNAME}" "${RH_REGISTRY_TOKEN}" || return 1
    return 0
  fi

  if [[ "${DRY_RUN}" != "true" ]] && aap_try_detect_rh_registry 2>/dev/null; then
    echo "Detected RH registry credentials from cluster pull secret"
    # shellcheck disable=SC1091
    source "${SCRIPTS_DIR}/lib/developer-hub-dynamic-plugins.sh"
    validate_rh_registry_credentials "${RH_REGISTRY_USERNAME}" "${RH_REGISTRY_TOKEN}" || return 1
    return 0
  fi

  if [[ "${INTERACTIVE}" == "true" && -t 0 ]]; then
    echo ""
    echo "Red Hat Container Registry credentials are required to pull Ansible OCI plugins."
    echo "Create a service account: https://access.redhat.com/terms-based-registry/accounts"
    read -r -p "RH registry username (Enter to skip): " RH_USER
    if [[ -n "${RH_USER}" ]]; then
      read -r -s -p "RH registry token: " RH_TOKEN
      echo ""
      export RH_REGISTRY_USERNAME="${RH_USER}"
      export RH_REGISTRY_TOKEN="${RH_TOKEN}"
      # shellcheck disable=SC1091
      source "${SCRIPTS_DIR}/lib/developer-hub-dynamic-plugins.sh"
      validate_rh_registry_credentials "${RH_REGISTRY_USERNAME}" "${RH_REGISTRY_TOKEN}" || return 1
      return 0
    fi
  fi

  missing+=("RH_REGISTRY_USERNAME and RH_REGISTRY_TOKEN (separate from AAP login — see https://access.redhat.com/terms-based-registry/accounts)")
  return 1
}

write_workshop_env() {
  export AAP_ENABLED=true
  export AAP_CHECK_SSL="${AAP_CHECK_SSL:-false}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo ""
    echo "Dry run — would write to scripts/workshop.env:"
    echo "  AAP_ENABLED=${AAP_ENABLED}"
    echo "  AAP_CONTROLLER_URL=${AAP_CONTROLLER_URL:-}"
    echo "  AAP_ADMIN_USERNAME=${AAP_ADMIN_USERNAME:-}"
    echo "  AAP_ADMIN_PASSWORD=$([[ -n "${AAP_ADMIN_PASSWORD:-}" ]] && echo '***set***' || echo '(empty)')"
    echo "  AAP_TOKEN=$([[ -n "${AAP_TOKEN:-}" && "${AAP_TOKEN}" != changeme ]] && echo '***set***' || echo changeme)"
    echo "  AAP_CHECK_SSL=${AAP_CHECK_SSL}"
    echo "  RH_REGISTRY_USERNAME=${RH_REGISTRY_USERNAME:-changeme}"
    echo "  RH_REGISTRY_TOKEN=$([[ -n "${RH_REGISTRY_TOKEN:-}" && "${RH_REGISTRY_TOKEN}" != changeme ]] && echo '***set***' || echo changeme)"
    return 0
  fi

  upsert_workshop_env AAP_ENABLED "${AAP_ENABLED}"
  upsert_workshop_env AAP_CHECK_SSL "${AAP_CHECK_SSL}"
  [[ -n "${AAP_CONTROLLER_URL:-}" ]] && upsert_workshop_env AAP_CONTROLLER_URL "${AAP_CONTROLLER_URL}"
  [[ -n "${AAP_ADMIN_USERNAME:-}" ]] && upsert_workshop_env AAP_ADMIN_USERNAME "${AAP_ADMIN_USERNAME}"
  [[ -n "${AAP_ADMIN_PASSWORD:-}" ]] && upsert_workshop_env AAP_ADMIN_PASSWORD "${AAP_ADMIN_PASSWORD}"
  [[ -n "${AAP_TOKEN:-}" && "${AAP_TOKEN}" != "changeme" ]] && upsert_workshop_env AAP_TOKEN "${AAP_TOKEN}"
  if [[ -n "${RH_REGISTRY_USERNAME:-}" && "${RH_REGISTRY_USERNAME}" != "changeme" ]]; then
    upsert_workshop_env RH_REGISTRY_USERNAME "${RH_REGISTRY_USERNAME}"
  fi
  if [[ -n "${RH_REGISTRY_TOKEN:-}" && "${RH_REGISTRY_TOKEN}" != "changeme" ]]; then
    upsert_workshop_env RH_REGISTRY_TOKEN "${RH_REGISTRY_TOKEN}"
  fi

  echo ""
  echo "Updated scripts/workshop.env"
}

main() {
  parse_args "$@"
  require_oc

  echo "Configuring AAP workshop.env for namespace ${WORKSHOP_NAMESPACE} ..."
  echo ""

  resolve_console_url || true
  resolve_admin_credentials || true
  if [[ -n "${AAP_CONTROLLER_URL:-}" ]]; then
    resolve_aap_token || true
  fi
  resolve_rh_registry || true
  write_workshop_env

  if ((${#warnings[@]} > 0)); then
    echo ""
    echo "Warnings:"
    for w in "${warnings[@]}"; do
      echo "  - ${w}"
    done
  fi

  if ((${#missing[@]} > 0)); then
    echo ""
    echo "Still missing (cannot be derived from console URL + admin password alone):"
    for m in "${missing[@]}"; do
      echo "  - ${m}"
    done
    echo ""
    echo "Re-run after setting missing values, e.g.:"
    echo "  ./scripts/configure-aap-workshop-env.sh --rh-registry-username <sa> --rh-registry-token <token>"
    if [[ "${APPLY}" == "true" ]]; then
      echo ""
      echo "Skipping --apply until all required variables are set."
    fi
    return 1
  fi

  if [[ "${APPLY}" == "true" ]]; then
    echo ""
    echo "Applying Ansible plugin to Developer Hub..."
    # shellcheck disable=SC1091
    source "${SCRIPTS_DIR}/workshop.env"
    "${SCRIPTS_DIR}/setup-developer-hub-aap.sh"
  fi

  echo ""
  echo "Done. Next:"
  echo "  source scripts/workshop.env"
  echo "  ./scripts/setup-developer-hub-config.sh"
}

main "$@"
