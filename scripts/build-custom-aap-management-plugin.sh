#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/../custom-plugins/aap-management"
BUILD_DIR="${ROOT}/.build"

echo "Building AAP Management custom plugins..."

if ! command -v yarn >/dev/null 2>&1; then
  echo "yarn is required to build custom plugins." >&2
  exit 1
fi

cd "${ROOT}"
yarn install --immutable 2>/dev/null || yarn install
yarn build
yarn export

mkdir -p "${BUILD_DIR}/aap-plugins"

pack_plugin() {
  local workspace_dir="$1"
  local output_name="$2"
  local pack_dir="${BUILD_DIR}/aap-plugins/.pack-staging"
  rm -rf "${pack_dir}"
  mkdir -p "${pack_dir}"
  (
    cd "${workspace_dir}/dist-dynamic"
    # RHDH install-dynamic-plugins expects npm pack layout (package/ prefix), not a raw tar.
    COPYFILE_DISABLE=1 npm pack --pack-destination "${pack_dir}" >/dev/null
  )
  local packed
  packed="$(find "${pack_dir}" -maxdepth 1 -name '*.tgz' -print -quit)"
  if [[ -z "${packed}" ]]; then
    echo "npm pack did not produce an archive in ${workspace_dir}/dist-dynamic" >&2
    exit 1
  fi
  mv "${packed}" "${BUILD_DIR}/aap-plugins/${output_name}.tgz"
  rm -rf "${pack_dir}"
  python3 - <<PY
import base64, hashlib, pathlib
path = pathlib.Path("${BUILD_DIR}/aap-plugins/${output_name}.tgz")
digest = hashlib.sha512(path.read_bytes()).digest()
print(f"sha512-{base64.b64encode(digest).decode()}")
PY
}

BACKEND_INTEGRITY="$(pack_plugin "${ROOT}/plugins/aap-management-backend" plugin-aap-management-backend-dynamic)"
FRONTEND_INTEGRITY="$(pack_plugin "${ROOT}/plugins/aap-management" plugin-aap-management-dynamic)"

cat >"${BUILD_DIR}/integrity.env" <<EOF
export AAP_MGMT_BACKEND_INTEGRITY="${BACKEND_INTEGRITY}"
export AAP_MGMT_FRONTEND_INTEGRITY="${FRONTEND_INTEGRITY}"
EOF

echo "Built plugin archives in ${BUILD_DIR}/aap-plugins"
echo "  backend integrity:  ${BACKEND_INTEGRITY}"
echo "  frontend integrity: ${FRONTEND_INTEGRITY}"
