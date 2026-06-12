import os
import sys
from pathlib import Path

import pytest
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager

sys.path.insert(0, str(Path(__file__).parent / "tests"))
from helpers import wait_for_backend_ready, wait_for_keycloak_ready, wait_for_rhdh_ready


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


@pytest.fixture(scope="session")
def workshop_config():
    namespace = _env("WORKSHOP_NAMESPACE", "rh-ee-mvandepe-dev")
    router_base = _env("CLUSTER_ROUTER_BASE", "apps.rm1.0a51.p1.openshiftapps.com")
    default_rhdh = f"https://redhat-developer-hub-{namespace}.{router_base}"
    default_backend = f"https://people-backend-{namespace}.{router_base}"
    default_frontend = f"https://people-frontend-{namespace}.{router_base}"
    default_keycloak = f"https://keycloak-{namespace}.{router_base}"
    return {
        "namespace": namespace,
        "rhdh_url": _env("RHDH_URL", default_rhdh).rstrip("/"),
        "people_backend_url": _env("PEOPLE_BACKEND_URL", default_backend).rstrip("/"),
        "people_frontend_url": _env("PEOPLE_FRONTEND_URL", default_frontend).rstrip("/"),
        "catalog_server_url": _env(
            "CATALOG_SERVER_URL",
            f"https://workshop-catalog-server-{namespace}.{router_base}",
        ).rstrip("/"),
        "keycloak_url": _env("KEYCLOAK_URL", default_keycloak).rstrip("/"),
        "keycloak_realm": _env("KEYCLOAK_REALM", "workshop"),
        "people_client_id": _env("KEYCLOAK_CLIENT_ID", "people-service"),
        "people_username": _env("PEOPLE_KEYCLOAK_USER", "user"),
        "people_password": _env("PEOPLE_KEYCLOAK_PASSWORD", "r3dh@t"),
        "username": _env("RHDH_KEYCLOAK_USER", "devhub"),
        "password": _env("RHDH_KEYCLOAK_PASSWORD", "r#dh@t"),
        "component": _env("RHDH_COMPONENT", "people-service"),
        "api_name": _env("RHDH_API", "people-rest-api"),
        "headless": _env("E2E_HEADLESS", "true").lower() in {"1", "true", "yes"},
        "timeout": int(_env("E2E_TIMEOUT_SECONDS", "180")),
    }


@pytest.fixture(scope="session")
def ready_stack(workshop_config):
    health = wait_for_backend_ready(workshop_config)
    wait_for_keycloak_ready(workshop_config)
    wait_for_rhdh_ready(workshop_config)
    return health


@pytest.fixture
def driver(workshop_config):
    options = Options()
    if workshop_config["headless"]:
        options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--window-size=1920,1080")
    options.add_argument("--ignore-certificate-errors")

    service = Service(ChromeDriverManager().install())
    browser = webdriver.Chrome(service=service, options=options)
    browser.set_page_load_timeout(workshop_config["timeout"])
    browser.implicitly_wait(2)
    yield browser
    browser.quit()
