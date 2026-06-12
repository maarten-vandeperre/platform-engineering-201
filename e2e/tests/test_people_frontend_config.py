import pytest

from helpers import http_get


@pytest.mark.e2e
def test_frontend_runtime_config(workshop_config):
    config = workshop_config
    status, body = http_get(f"{config['people_frontend_url']}/config.js")
    assert status == 200
    assert "${" not in body, f"Unresolved placeholders in config.js: {body}"
    assert "keycloakUrl:" in body
    assert config["keycloak_url"] in body or config["namespace"] in body
