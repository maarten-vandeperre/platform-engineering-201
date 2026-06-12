import pytest

from helpers import assert_openapi_response, http_get


@pytest.mark.e2e
def test_backend_openapi_is_public(workshop_config, ready_stack):
    config = workshop_config
    status, body = http_get(f"{config['people_backend_url']}/q/openapi")
    assert status == 200
    assert_openapi_response(body)


@pytest.mark.e2e
def test_frontend_openapi_is_reachable(workshop_config, ready_stack):
    config = workshop_config
    for path in ("/q/openapi", "/openapi.yaml", "/openapi.json"):
        status, body = http_get(f"{config['people_frontend_url']}{path}")
        assert status == 200, f"{path} returned HTTP {status}"
        assert_openapi_response(body)


@pytest.mark.e2e
def test_catalog_server_serves_openapi_and_tech_radar(workshop_config):
    catalog_base = workshop_config["catalog_server_url"]

    status, entities = http_get(f"{catalog_base}/entities.yaml")
    assert status == 200
    assert "people-rest-api" in entities

    status, openapi = http_get(f"{catalog_base}/people-api.yaml")
    assert status == 200
    assert_openapi_response(openapi)

    status, radar = http_get(f"{catalog_base}/tech-radar.json")
    assert status == 200
    assert "quarkus" in radar.lower()
    assert "entries" in radar
