#!/usr/bin/env bash
# Re-exec with bash when invoked as `sh script.sh` (macOS /bin/sh is bash in POSIX mode).
if [[ -z "${BASH_VERSION:-}" ]] || { shopt -oq posix 2>/dev/null; }; then
  exec bash "$0" "$@"
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Validate that workshop workloads are running and scale them back up when the
cluster idle policy has set replicas to 0 (typical after ~6 hours).

Checks (when present in the cluster):
  - Keycloak, workshop catalog server, People app (postgres/backend/frontend)
  - RHDH PostgreSQL, Red Hat Developer Hub
  - Custom AAP Management plugin server

Options:
  --check-only   Report status only; do not scale anything (exit 1 if down)
  --dry-run      Show what would be scaled without making changes (exit 1 if down)
  -h, --help     Show this help

Examples:
  $(basename "$0")                 # validate and repair
  $(basename "$0") --check-only    # CI / cron health probe
  $(basename "$0") --dry-run

Requires: oc, scripts/workshop.env (or defaults from workshop.env.example)
EOF
}

CHECK_ONLY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) CHECK_ONLY=true ;;
    --dry-run) DRY_RUN=true ;;
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

if [[ "${CHECK_ONLY}" == "true" && "${DRY_RUN}" == "true" ]]; then
  echo "Use either --check-only or --dry-run, not both." >&2
  exit 1
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  ensure_all_workshop_instances true false
  exit $?
fi

if [[ "${CHECK_ONLY}" == "true" ]]; then
  ensure_all_workshop_instances false true
  exit $?
fi

ensure_all_workshop_instances false false

RHDH_HOST=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null \
  || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null \
  || true)
if [[ -n "${RHDH_HOST}" ]]; then
  echo "Developer Hub: https://${RHDH_HOST}"
fi
