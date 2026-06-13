#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

WORKSHOP_ENV_FILE="${SCRIPTS_DIR}/workshop.env"
MODE="manifest"
APPLY_CONFIG=true
OPEN_BROWSER=true
MANIFEST_PORT="${GITHUB_MANIFEST_PORT:-8765}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Create GitHub credentials for the Developer Hub GitHub Actions CI tab and
store them in scripts/workshop.env.

Modes:
  manifest (default)  Automated GitHub App manifest flow. GitHub does not
                      expose an API to create legacy OAuth Apps; this creates
                      a GitHub App that provides OAuth client ID/secret
                      compatible with Developer Hub.
  oauth               Open the OAuth App registration form in your browser,
                      then save the Client ID/secret you receive.

Options:
  --oauth-app         Same as --mode oauth
  --mode MODE         manifest | oauth
  --no-apply          Do not run setup-developer-hub-config.sh
  --no-open           Do not open a browser window
  -h, --help          Show this help

Reuse an existing OAuth App (does not delete anything on GitHub):
  source scripts/workshop.env
  ./scripts/setup-github-oauth.sh

Use create-github-oauth-app.sh only for first-time setup or new credentials.

Requires: python3, curl, and oc (to detect the Developer Hub callback URL).
Optional: gh (to choose org vs personal app registration URL)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --oauth-app) MODE="oauth" ;;
    --mode)
      MODE="${2:-}"
      shift
      ;;
    --no-apply) APPLY_CONFIG=false ;;
    --no-open) OPEN_BROWSER=false ;;
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
ensure_workshop_platform

upsert_workshop_env() {
  local key="$1"
  local value="$2"
  local file="${WORKSHOP_ENV_FILE}"
  local tmp
  tmp="$(mktemp)"

  if [[ ! -f "${file}" ]]; then
    cp "${SCRIPTS_DIR}/workshop.env.example" "${file}"
    echo "Created ${file} from workshop.env.example"
  fi

  if grep -q "^export ${key}=" "${file}"; then
    awk -v k="${key}" -v v="${value}" '
      BEGIN { updated = 0 }
      $0 ~ "^export " k "=" {
        print "export " k "=\"" v "\""
        updated = 1
        next
      }
      { print }
      END {
        if (!updated) {
          print "export " k "=\"" v "\""
        }
      }
    ' "${file}" >"${tmp}"
  else
    cp "${file}" "${tmp}"
    printf 'export %s="%s"\n' "${key}" "${value}" >>"${tmp}"
  fi

  mv "${tmp}" "${file}"
}

open_url() {
  local url="$1"
  if [[ "${OPEN_BROWSER}" != "true" ]]; then
    echo "Open this URL in your browser:"
    echo "  ${url}"
    return 0
  fi
  if command -v open >/dev/null 2>&1; then
    open "${url}"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "${url}" >/dev/null 2>&1 || true
  else
    echo "Open this URL in your browser:"
    echo "  ${url}"
  fi
}

github_org_registration_available() {
  local org="$1"
  if ! command -v gh >/dev/null 2>&1; then
    return 1
  fi
  gh api "orgs/${org}" --jq .login >/dev/null 2>&1
}

RHDH_HOST="$(resolve_rhdh_host)"
RHDH_URL="https://${RHDH_HOST}"
CALLBACK_URL="${RHDH_URL}/api/auth/github/handler/frame"
APP_NAME="${GITHUB_OAUTH_APP_NAME:-PE201 Developer Hub CI}"
APP_NAME="${APP_NAME:0:34}"

create_oauth_app_manual() {
  local register_url="https://github.com/settings/applications/new"
  if github_org_registration_available "${WORKSHOP_GITHUB_ORG}"; then
    register_url="https://github.com/organizations/${WORKSHOP_GITHUB_ORG}/settings/applications/new"
  fi

  cat <<EOF
GitHub does not provide an API to create legacy OAuth Apps automatically.
Opening the OAuth App registration form for you.

Fill in:
  Application name: ${APP_NAME}
  Homepage URL:     ${RHDH_URL}
  Authorization callback URL:
    ${CALLBACK_URL}

After you click "Register application", copy the Client ID and generate a
Client secret on the next page.
EOF

  open_url "${register_url}"

  read -r -p "Paste GitHub OAuth Client ID: " client_id
  read -r -s -p "Paste GitHub OAuth Client secret: " client_secret
  echo ""

  if [[ -z "${client_id}" || -z "${client_secret}" ]]; then
    echo "Client ID and Client secret are required." >&2
    exit 1
  fi

  upsert_workshop_env "AUTH_GITHUB_CLIENT_ID" "${client_id}"
  upsert_workshop_env "AUTH_GITHUB_CLIENT_SECRET" "${client_secret}"

  local app_url="https://github.com/settings/applications/${client_id}"
  if github_org_registration_available "${WORKSHOP_GITHUB_ORG}"; then
    app_url="https://github.com/organizations/${WORKSHOP_GITHUB_ORG}/settings/applications/${client_id}"
  fi

  echo ""
  echo "Saved AUTH_GITHUB_CLIENT_ID and AUTH_GITHUB_CLIENT_SECRET to ${WORKSHOP_ENV_FILE}"
  echo "GitHub OAuth App settings:"
  echo "  ${app_url}"
}

create_github_app_via_manifest() {
  local manifest_redirect="http://127.0.0.1:${MANIFEST_PORT}/github-manifest/callback"
  local register_base="https://github.com/settings/apps/new"
  if github_org_registration_available "${WORKSHOP_GITHUB_ORG}"; then
    register_base="https://github.com/organizations/${WORKSHOP_GITHUB_ORG}/settings/apps/new"
  fi

  local manifest_json register_url code_file conversion_json
  manifest_json="$(python3 - <<PY
import json
print(json.dumps({
    "name": "${APP_NAME}",
    "url": "${RHDH_URL}",
    "redirect_url": "${manifest_redirect}",
    "callback_urls": ["${CALLBACK_URL}"],
    "public": False,
    "request_oauth_on_install": True,
    "default_permissions": {
        "metadata": "read",
        "contents": "read",
        "actions": "read"
    },
    "default_events": []
}, separators=(",", ":")))
PY
)"

  register_url="${register_base}?manifest=$(python3 - <<PY
import urllib.parse
print(urllib.parse.quote('''${manifest_json}'''))
PY
)"

  code_file="$(mktemp)"
  trap 'rm -f "${code_file}"' EXIT

  cat <<EOF
Creating a GitHub App via the manifest flow (OAuth client credentials for Developer Hub).

Developer Hub callback URL:
  ${CALLBACK_URL}

When the browser opens, review the app details and click "Create GitHub App".
Waiting up to 10 minutes for GitHub to redirect back to this script...
EOF

  python3 - <<PY &
import json
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

CODE_FILE = "${code_file}"
PORT = ${MANIFEST_PORT}

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/github-manifest/callback":
            self.send_response(404)
            self.end_headers()
            return
        params = urllib.parse.parse_qs(parsed.query)
        code = (params.get("code") or [""])[0]
        with open(CODE_FILE, "w", encoding="utf-8") as handle:
            handle.write(code)
        body = b"<html><body><h1>GitHub App created</h1><p>You can close this tab and return to the terminal.</p></body></html>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        threading.Thread(target=self.server.shutdown, daemon=True).start()

    def log_message(self, fmt, *args):
        return

server = HTTPServer(("127.0.0.1", PORT), Handler)
server.serve_forever()
PY
  local server_pid=$!

  open_url "${register_url}"

  local deadline=$((SECONDS + 600))
  while [[ ! -s "${code_file}" ]]; do
    if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
      wait "${server_pid}" || true
      break
    fi
    if (( SECONDS > deadline )); then
      kill "${server_pid}" >/dev/null 2>&1 || true
      wait "${server_pid}" >/dev/null 2>&1 || true
      echo "Timed out waiting for GitHub manifest callback." >&2
      exit 1
    fi
    sleep 1
  done

  wait "${server_pid}" >/dev/null 2>&1 || true

  local manifest_code
  manifest_code="$(tr -d '\n' <"${code_file}")"
  if [[ -z "${manifest_code}" ]]; then
    echo "No manifest code received from GitHub." >&2
    exit 1
  fi

  conversion_json="$(curl -fsSL -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/app-manifests/${manifest_code}/conversions")"

  local client_id client_secret app_url slug
  client_id="$(python3 - <<PY
import json, sys
print(json.load(sys.stdin)["client_id"])
PY
<<<"${conversion_json}")"
  client_secret="$(python3 - <<PY
import json, sys
print(json.load(sys.stdin)["client_secret"])
PY
<<<"${conversion_json}")"
  app_url="$(python3 - <<PY
import json, sys
print(json.load(sys.stdin)["html_url"])
PY
<<<"${conversion_json}")"
  slug="$(python3 - <<PY
import json, sys
print(json.load(sys.stdin)["slug"])
PY
<<<"${conversion_json}")"

  upsert_workshop_env "AUTH_GITHUB_CLIENT_ID" "${client_id}"
  upsert_workshop_env "AUTH_GITHUB_CLIENT_SECRET" "${client_secret}"

  echo ""
  echo "GitHub App created successfully."
  echo "Saved AUTH_GITHUB_CLIENT_ID and AUTH_GITHUB_CLIENT_SECRET to ${WORKSHOP_ENV_FILE}"
  echo ""
  echo "GitHub App definition:"
  echo "  ${app_url}"
  echo ""
  echo "Public app page:"
  echo "  https://github.com/apps/${slug}"
}

echo "Developer Hub URL: ${RHDH_URL}"
echo "OAuth callback URL: ${CALLBACK_URL}"
echo ""

case "${MODE}" in
  oauth)
    create_oauth_app_manual
    ;;
  manifest)
    create_github_app_via_manifest
    ;;
  *)
    echo "Unknown mode: ${MODE}. Use manifest or oauth." >&2
    exit 1
    ;;
esac

if [[ "${APPLY_CONFIG}" == "true" ]]; then
  echo ""
  echo "Applying credentials to Developer Hub..."
  # shellcheck disable=SC1091
  source "${WORKSHOP_ENV_FILE}"
  "${SCRIPTS_DIR}/setup-developer-hub-config.sh"
fi

echo ""
echo "Next steps:"
echo "  1. Configure scaffolder publish (GitHub PAT): ./scripts/setup-github-auth.sh --pat-only --open-pat-url"
echo "  2. Open the People Service CI tab in Developer Hub and click Authorize GitHub."
