#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_FILE="${WORKFLOW_FILE:-/workflow/create-person.sw.yaml}"
WORKFLOW_SERVICE_URL="${WORKFLOW_SERVICE_URL:-http://create-person-workflow:8080}"
WORKFLOW_ENDPOINT="${WORKFLOW_ENDPOINT:-${WORKFLOW_SERVICE_URL}/create-person}"
PGHOST="${PGHOST:-redhat-developer-hub-postgresql}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-sonataflow}"

if [[ ! -f "${WORKFLOW_FILE}" ]]; then
  echo "Workflow definition not found at ${WORKFLOW_FILE}" >&2
  exit 1
fi

SOURCE_SQL="$(sed "s/'/''/g" "${WORKFLOW_FILE}")"
METADATA_JSON="{\"kogito.service.url\": \"${WORKFLOW_SERVICE_URL}\"}"

psql -h "${PGHOST}" -U "${PGUSER}" -d "${PGDATABASE}" -v ON_ERROR_STOP=1 <<EOSQL
SET search_path TO "data-index-service";
DELETE FROM definitions_annotations WHERE process_id = 'create-person';
DELETE FROM definitions WHERE id = 'create-person';
INSERT INTO definitions (id, version, name, type, source, endpoint, description, metadata)
VALUES (
  'create-person',
  '1.0',
  'Create Person in People API',
  'SW',
  convert_to('${SOURCE_SQL}', 'UTF8'),
  '${WORKFLOW_ENDPOINT}',
  'Creates a person in the People REST API using first name, last name, and age',
  '${METADATA_JSON}'::jsonb
);
INSERT INTO definitions_annotations (annotation, process_id, process_version)
VALUES ('workflow-type/infrastructure', 'create-person', '1.0');
EOSQL

COUNT="$(psql -h "${PGHOST}" -U "${PGUSER}" -d "${PGDATABASE}" -Atqc 'SET search_path TO "data-index-service"; SELECT count(*) FROM definitions WHERE id = '\''create-person'\'';')"
if [[ "${COUNT}" != "1" ]]; then
  echo "create-person workflow not found in Data Index after registration" >&2
  exit 1
fi

echo "Registered create-person workflow in Data Index."
