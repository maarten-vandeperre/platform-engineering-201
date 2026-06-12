import pytest

from helpers import get_keycloak_token, http_json


@pytest.mark.e2e
def test_backend_and_database_are_ready(ready_stack):
    health = ready_stack
    assert health["status"] == "UP"
    checks = health.get("checks") or []
    db_checks = [check for check in checks if "database" in check.get("name", "").lower()]
    assert db_checks, f"Expected database health check in response: {health}"
    assert all(check.get("status") == "UP" for check in db_checks), db_checks


@pytest.mark.e2e
def test_people_crud_api(workshop_config, ready_stack):
    config = workshop_config
    token = get_keycloak_token(config)
    headers = {"Authorization": f"Bearer {token}"}

    status, created = http_json(
        "POST",
        f"{config['people_backend_url']}/api/people",
        headers=headers,
        payload={"firstName": "E2E", "lastName": "Tester", "age": 42},
    )
    assert status == 201
    person_id = created["id"]
    assert created["firstName"] == "E2E"

    status, people = http_json(
        "GET",
        f"{config['people_backend_url']}/api/people",
        headers=headers,
    )
    assert status == 200
    assert any(person["id"] == person_id for person in people)

    status, updated = http_json(
        "PUT",
        f"{config['people_backend_url']}/api/people/{person_id}",
        headers=headers,
        payload={"firstName": "E2E", "lastName": "Updated", "age": 43},
    )
    assert status == 200
    assert updated["lastName"] == "Updated"

    status, _ = http_json(
        "DELETE",
        f"{config['people_backend_url']}/api/people/{person_id}",
        headers=headers,
    )
    assert status == 204
