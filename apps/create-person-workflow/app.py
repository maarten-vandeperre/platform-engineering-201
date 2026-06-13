import json
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx
import psycopg2
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator

app = FastAPI(title="Create Person Workflow")

WORKFLOW_ID = "create-person"
WORKFLOW_VERSION = "1.0"
WORKFLOW_NAME = "Create Person in People API"
WORKFLOW_DESCRIPTION = (
    "Collects first name, last name, and age, then creates a person via the People REST API"
)
PROCESS_STATE_ACTIVE = 1
PROCESS_STATE_COMPLETED = 2
PROCESS_STATE_ABORTED = 4

SCHEMAS_DIR = Path(__file__).parent / "schemas"
INPUT_SCHEMA_PATH = SCHEMAS_DIR / "create-person.input-schema.json"
OUTPUT_SCHEMA_PATH = SCHEMAS_DIR / "create-person.output-schema.json"
INPUT_SCHEMA = json.loads(INPUT_SCHEMA_PATH.read_text(encoding="utf-8"))
OUTPUT_SCHEMA = json.loads(OUTPUT_SCHEMA_PATH.read_text(encoding="utf-8"))


class PersonInput(BaseModel):
    firstName: str = Field(min_length=1)
    lastName: str = Field(min_length=1)
    age: int = Field(ge=0, le=150)


class WorkflowRunRequest(BaseModel):
    """Accepts flat workflow input or Orchestrator execute payload."""

    model_config = ConfigDict(extra="ignore")

    firstName: str = Field(min_length=1)
    lastName: str = Field(min_length=1)
    age: int = Field(ge=0, le=150)

    @staticmethod
    def _parse_nested_payload(value: Any) -> dict[str, Any] | None:
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except json.JSONDecodeError:
                return None
        return value if isinstance(value, dict) else None

    @model_validator(mode="before")
    @classmethod
    def unwrap_orchestrator_payload(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data

        # Orchestrator backend wraps form values in workflowdata before POSTing
        # to the workflow service URL (see SonataFlowService.executeWorkflow).
        workflow_data = cls._parse_nested_payload(data.get("workflowdata"))
        if workflow_data is not None:
            return workflow_data

        # Alternate execute payloads (repair scripts / direct API calls).
        input_data = cls._parse_nested_payload(data.get("inputData"))
        if input_data is not None:
            return input_data

        return data

    def to_person_input(self) -> PersonInput:
        return PersonInput(
            firstName=self.firstName,
            lastName=self.lastName,
            age=self.age,
        )


def _keycloak_token() -> str:
    keycloak_host = os.environ["KEYCLOAK_HOST"]
    realm = os.environ["KEYCLOAK_REALM"]
    client_id = os.environ["KEYCLOAK_CLIENT_ID"]
    username = os.environ["KEYCLOAK_SERVICE_USER"]
    password = os.environ["KEYCLOAK_SERVICE_PASSWORD"]
    token_url = f"https://{keycloak_host}/realms/{realm}/protocol/openid-connect/token"
    data = {
        "client_id": client_id,
        "username": username,
        "password": password,
        "grant_type": "password",
    }
    with httpx.Client(timeout=30.0, verify=False) as client:
        response = client.post(token_url, data=data)
        response.raise_for_status()
        payload = response.json()
        token = payload.get("access_token")
        if not token:
            raise HTTPException(status_code=502, detail="Keycloak token response missing access_token")
        return token


def _create_person(first_name: str, last_name: str, age: int, token: str) -> dict[str, Any]:
    backend_host = os.environ["PEOPLE_BACKEND_HOST"]
    url = f"https://{backend_host}/api/people"
    headers = {"Authorization": f"Bearer {token}"}
    body = {"firstName": first_name, "lastName": last_name, "age": age}
    with httpx.Client(timeout=30.0, verify=False) as client:
        response = client.post(url, json=body, headers=headers)
        if response.status_code >= 400:
            raise HTTPException(
                status_code=response.status_code,
                detail=response.text or "People API request failed",
            )
        return response.json()


def _db_connect():
    pghost = os.environ.get("PGHOST")
    if not pghost:
        return None
    return psycopg2.connect(
        host=pghost,
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ["PGPASSWORD"],
        dbname=os.environ.get("PGDATABASE", "sonataflow"),
    )


def _reserve_process_instance(
    instance_id: str,
    person: PersonInput,
    started_at: datetime,
) -> None:
    """Register the run in Data Index before external calls so Orchestrator can fetch it."""
    conn = _db_connect()
    if conn is None:
        raise HTTPException(
            status_code=503,
            detail="Data Index registration is not configured (PGHOST missing)",
        )

    variables = {
        "firstName": person.firstName,
        "lastName": person.lastName,
        "age": person.age,
    }
    try:
        with conn, conn.cursor() as cur:
            cur.execute('SET search_path TO "data-index-service"')
            cur.execute(
                """
                INSERT INTO processes (
                  id, process_id, version, process_name, state,
                  start_time, endpoint, variables
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s::jsonb)
                """,
                (
                    instance_id,
                    WORKFLOW_ID,
                    WORKFLOW_VERSION,
                    WORKFLOW_NAME,
                    PROCESS_STATE_ACTIVE,
                    started_at,
                    f"http://create-person-workflow:8080/{WORKFLOW_ID}",
                    json.dumps(variables),
                ),
            )
    finally:
        conn.close()


def _finalize_process_instance(
    instance_id: str,
    person: PersonInput,
    output: dict[str, Any],
    started_at: datetime,
    ended_at: datetime,
) -> None:
    conn = _db_connect()
    if conn is None:
        return

    variables = {
        "firstName": person.firstName,
        "lastName": person.lastName,
        "age": person.age,
        "output": output,
    }
    node_steps = [
        ("CreatePerson", "CreatePerson", "Operation"),
        ("Authenticate", "CreatePerson", "Action"),
        ("CreateRecord", "CreatePerson", "Action"),
    ]
    try:
        with conn, conn.cursor() as cur:
            cur.execute('SET search_path TO "data-index-service"')
            cur.execute(
                """
                UPDATE processes
                SET state = %s, end_time = %s, variables = %s::jsonb
                WHERE id = %s
                """,
                (PROCESS_STATE_COMPLETED, ended_at, json.dumps(variables), instance_id),
            )
            for index, (name, definition_id, node_type) in enumerate(node_steps):
                node_started = started_at
                node_ended = ended_at
                cur.execute(
                    """
                    INSERT INTO nodes (
                      id, process_instance_id, name, node_id, definition_id,
                      type, enter, exit
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (
                        f"{instance_id}-{name.lower()}",
                        instance_id,
                        name,
                        name,
                        definition_id,
                        node_type,
                        node_started,
                        node_ended,
                    ),
                )
    finally:
        conn.close()


def _abort_process_instance(instance_id: str, ended_at: datetime) -> None:
    conn = _db_connect()
    if conn is None:
        return
    try:
        with conn, conn.cursor() as cur:
            cur.execute('SET search_path TO "data-index-service"')
            cur.execute(
                """
                UPDATE processes
                SET state = %s, end_time = %s
                WHERE id = %s
                """,
                (PROCESS_STATE_ABORTED, ended_at, instance_id),
            )
    finally:
        conn.close()


def _register_process_instance(
    instance_id: str,
    person: PersonInput,
    output: dict[str, Any],
) -> None:
    pghost = os.environ.get("PGHOST")
    if not pghost:
        return

    now = datetime.now(timezone.utc).replace(tzinfo=None)
    variables = {
        "firstName": person.firstName,
        "lastName": person.lastName,
        "age": person.age,
        "output": output,
    }
    conn = psycopg2.connect(
        host=pghost,
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ["PGPASSWORD"],
        dbname=os.environ.get("PGDATABASE", "sonataflow"),
    )
    try:
        with conn, conn.cursor() as cur:
            cur.execute('SET search_path TO "data-index-service"')
            cur.execute(
                """
                INSERT INTO processes (
                  id, process_id, version, process_name, state,
                  start_time, end_time, endpoint, variables
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb)
                """,
                (
                    instance_id,
                    WORKFLOW_ID,
                    WORKFLOW_VERSION,
                    WORKFLOW_NAME,
                    2,
                    now,
                    now,
                    f"http://create-person-workflow:8080/{WORKFLOW_ID}",
                    json.dumps(variables),
                ),
            )
    finally:
        conn.close()


def _register_process_instance_safe(
    instance_id: str,
    person: PersonInput,
    output: dict[str, Any],
) -> None:
    try:
        _register_process_instance(instance_id, person, output)
    except Exception as exc:
        # Person creation already succeeded; log registration issues for operators.
        print(f"Warning: failed to register workflow instance in Data Index: {exc}")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/schemas/create-person.input-schema.json")
def input_schema() -> dict[str, Any]:
    return INPUT_SCHEMA


@app.get("/schemas/create-person.output-schema.json")
def output_schema() -> dict[str, Any]:
    return OUTPUT_SCHEMA


@app.get(f"/management/processes/{WORKFLOW_ID}")
def workflow_info() -> dict[str, Any]:
    return {
        "id": WORKFLOW_ID,
        "name": WORKFLOW_NAME,
        "version": WORKFLOW_VERSION,
        "description": WORKFLOW_DESCRIPTION,
        "inputSchema": INPUT_SCHEMA,
        "outputSchema": OUTPUT_SCHEMA,
    }


@app.post(f"/{WORKFLOW_ID}")
def run_workflow(payload: WorkflowRunRequest) -> dict[str, Any]:
    person = payload.to_person_input()
    token = _keycloak_token()
    created = _create_person(person.firstName, person.lastName, person.age, token)
    instance_id = str(uuid.uuid4())
    _register_process_instance_safe(instance_id, person, created)
    return {
        "id": instance_id,
        "definitionId": WORKFLOW_ID,
        "state": "COMPLETED",
        "output": created,
    }
