#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

WORKSHOP_ENV_FILE="${SCRIPTS_DIR}/workshop.env"
SCOPE_OAUTH=true
SCOPE_PAT=true
APPLY_CONFIG=true
INTERACTIVE=true
OPEN_PAT_URL=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Configure GitHub integration for Developer Hub:

  - GitHub OAuth App  → CI / Issues / Pull Requests tabs (Authorize GitHub popup)
  - GitHub PAT        → scaffolder publish:github and server-side GitHub API proxy

Examples:
  ./scripts/setup-github-auth.sh
  GITHUB_TOKEN=ghp_... ./scripts/setup-github-auth.sh --no-interactive
  ./scripts/setup-github-auth.sh --pat-only
  ./scripts/setup-github-auth.sh --oauth-only

Options:
  --pat-only        Configure only the GitHub PAT (scaffolder publish)
  --oauth-only      Apply only OAuth credentials already in workshop.env
  --no-interactive  Do not prompt; require GITHUB_TOKEN in the environment
  --open-pat-url    Open the GitHub PAT creation page in a browser
  --no-apply        Update workshop.env only; skip setup-developer-hub-config.sh
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pat-only)
      SCOPE_OAUTH=false
      ;;
    --oauth-only)
      SCOPE_PAT=false
      ;;
    --no-interactive)
      INTERACTIVE=false
      ;;
    --open-pat-url)
      OPEN_PAT_URL=true
      ;;
    --no-apply)
      APPLY_CONFIG=false
      ;;
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

open_url() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then
    open "${url}"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "${url}"
  else
    echo "Open this URL in your browser: ${url}"
  fi
}

configure_oauth() {
  if [[ "${AUTH_GITHUB_CLIENT_ID:-changeme}" == "changeme" ]] \
    || [[ "${AUTH_GITHUB_CLIENT_SECRET:-changeme}" == "changeme" ]]; then
    echo ""
    echo "GitHub OAuth is not configured in ${WORKSHOP_ENV_FILE}."
    echo "Required for the CI / Issues / Pull Requests tabs (Authorize GitHub popup)."
    echo ""
    echo "Run one of:"
    echo "  ./scripts/create-github-oauth-app.sh --oauth-app"
    echo "  ./scripts/create-github-oauth-app.sh"
    return 1
  fi

  local rhdh_host callback_url app_settings_url
  rhdh_host="$(resolve_rhdh_host)"
  callback_url="https://${rhdh_host}/api/auth/github/handler/frame"
  app_settings_url="https://github.com/settings/applications/${AUTH_GITHUB_CLIENT_ID}"

  echo "GitHub OAuth credentials found (client ID ${AUTH_GITHUB_CLIENT_ID})."
  echo ""
  echo "Authorization callback URL (must be registered on the GitHub OAuth App):"
  echo "  ${callback_url}"
  echo ""
  echo "GitHub OAuth App settings:"
  echo "  ${app_settings_url}"
  echo ""
  echo "If Authorize GitHub shows 'Invalid Redirect URI', add the callback URL above in GitHub."
  echo "Reusing an app from another namespace/cluster requires updating the callback URL there."
  return 0
}

prompt_for_pat() {
  local pat_url="https://github.com/settings/tokens/new?scopes=repo,workflow&description=Platform%20Engineering%20201%20Developer%20Hub"

  if [[ "${OPEN_PAT_URL}" == "true" ]]; then
    open_url "${pat_url}"
  fi

  echo ""
  echo "GitHub Personal Access Token required for scaffolder Publish to GitHub."
  echo "Create a classic PAT with scopes:"
  echo "  - repo   (create/push repositories such as ${WORKSHOP_GITHUB_ORG}/test-scaffolding)"
  echo "  - workflow (optional, improves GitHub Actions tab)"
  echo ""
  echo "PAT creation URL:"
  echo "  ${pat_url}"
  echo ""

  if [[ ! -t 0 ]]; then
    echo "Non-interactive shell and GITHUB_TOKEN is unset." >&2
    echo "Run: GITHUB_TOKEN=ghp_... ./scripts/setup-github-auth.sh --no-interactive" >&2
    return 1
  fi

  read -rsp "Paste GitHub PAT (input hidden): " GITHUB_TOKEN
  echo ""
  export GITHUB_TOKEN
}

configure_pat() {
  if [[ -z "${GITHUB_TOKEN:-}" || "${GITHUB_TOKEN}" == "changeme" ]]; then
    if [[ "${INTERACTIVE}" == "true" ]]; then
      prompt_for_pat || return 1
    else
      echo "GITHUB_TOKEN is not set (still 'changeme')." >&2
      echo "Run: GITHUB_TOKEN=ghp_... ./scripts/setup-github-auth.sh --no-interactive" >&2
      return 1
    fi
  fi

  local login
  login="$(validate_github_pat "${GITHUB_TOKEN}")"
  echo "GitHub PAT validated for user: ${login}"
  upsert_workshop_env "GITHUB_TOKEN" "${GITHUB_TOKEN}"
  echo "Saved GITHUB_TOKEN to ${WORKSHOP_ENV_FILE}"
  return 0
}

echo "GitHub auth setup for Developer Hub (${RHDH_NAMESPACE:-${WORKSHOP_NAMESPACE}})"
echo ""

oauth_ready=true
pat_ready=true

if [[ "${SCOPE_OAUTH}" == "true" ]]; then
  if ! configure_oauth; then
    oauth_ready=false
  fi
fi

if [[ "${SCOPE_PAT}" == "true" ]]; then
  if ! configure_pat; then
    pat_ready=false
  fi
fi

if [[ "${pat_ready}" != "true" && "${SCOPE_PAT}" == "true" ]]; then
  exit 1
fi

if [[ "${APPLY_CONFIG}" == "true" ]]; then
  require_oc
  ensure_workshop_platform
  require_developer_hub
  # shellcheck disable=SC1091
  source "${WORKSHOP_ENV_FILE}"
  "${SCRIPTS_DIR}/setup-developer-hub-config.sh"
fi

if [[ "${SCOPE_PAT}" == "true" && "${APPLY_CONFIG}" == "true" && "${pat_ready}" == "true" ]]; then
  if verify_cluster_github_token; then
    echo ""
    echo "Cluster GitHub PAT verified in Secret and Developer Hub app-config."
  else
    echo ""
    echo "Warning: cluster GitHub token verification failed; check Developer Hub pod logs." >&2
  fi
fi

RHDH_HOST="$(resolve_rhdh_host)"
echo ""
echo "Developer Hub: https://${RHDH_HOST}"
if [[ "${oauth_ready}" == "true" && "${SCOPE_OAUTH}" == "true" ]]; then
  echo "GitHub OAuth callback: https://${RHDH_HOST}/api/auth/github/handler/frame"
  echo "Use Authorize GitHub on the CI tab after signing in with Keycloak."
fi
if [[ "${pat_ready}" == "true" && "${SCOPE_PAT}" == "true" ]]; then
  echo "Scaffolder publish target example: github.com/${WORKSHOP_GITHUB_ORG}/test-scaffolding"
  echo "Retry Create → Quarkus + React + PostgreSQL on OpenShift."
fi

if [[ "${oauth_ready}" != "true" && "${SCOPE_OAUTH}" == "true" ]]; then
  exit 1
fi
