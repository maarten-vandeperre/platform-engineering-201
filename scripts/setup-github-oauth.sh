#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "GitHub OAuth setup for Developer Hub GitHub Actions CI tab"
echo ""

require_oc
ensure_workshop_platform

if [[ "${AUTH_GITHUB_CLIENT_ID:-changeme}" == "changeme" ]] \
  || [[ "${AUTH_GITHUB_CLIENT_SECRET:-changeme}" == "changeme" ]]; then
  echo "GitHub OAuth credentials are not configured."
  echo "Run:"
  echo "  ./scripts/create-github-oauth-app.sh --oauth-app"
  echo ""
  echo "Fully automated alternative (GitHub App manifest flow):"
  echo "  ./scripts/create-github-oauth-app.sh"
  exit 1
fi

echo "Applying GitHub OAuth credentials to Developer Hub..."
"${SCRIPTS_DIR}/setup-developer-hub-config.sh"

RHDH_HOST="$(resolve_rhdh_host)"
CALLBACK_URL="https://${RHDH_HOST}/api/auth/github/handler/frame"
APP_SETTINGS_URL="https://github.com/settings/applications/${AUTH_GITHUB_CLIENT_ID}"

echo ""
echo "GitHub OAuth callback URL: ${CALLBACK_URL}"
echo "GitHub OAuth App settings: ${APP_SETTINGS_URL}"
echo "Open the CI tab and click Authorize GitHub again."
