import pytest

from helpers import http_get


@pytest.mark.e2e
def test_keycloak_is_reachable(workshop_config):
    config = workshop_config
    realm_url = f"{config['keycloak_url']}/realms/{config['keycloak_realm']}"
    status, body = http_get(realm_url)
    assert status == 200, (
        f"Keycloak is not reachable at {realm_url} (HTTP {status}). "
        "Run ./scripts/repair-keycloak.sh"
    )
    assert "application is not available" not in body.lower()
    assert "issuer" in body.lower() or "realm" in body.lower()
