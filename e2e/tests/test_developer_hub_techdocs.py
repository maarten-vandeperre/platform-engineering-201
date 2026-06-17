import pytest
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

from helpers import dismiss_onboarding, sign_in_via_rhdh_popup, wait_for_techdocs_page


@pytest.mark.e2e
def test_developer_hub_quarkus_techdocs(workshop_config, ready_stack, driver):
    config = workshop_config
    docs_url = f"{config['rhdh_url']}/catalog/default/component/quarkus-workshop-guide/docs"

    sign_in_via_rhdh_popup(driver, config, docs_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(EC.url_contains("/docs"))
    page_text = wait_for_techdocs_page(
        driver,
        config,
        "Quarkus Workshop Guide",
        "Getting started",
    )
    assert "rest api" in page_text.lower() or "persistence" in page_text.lower()


@pytest.mark.e2e
def test_developer_hub_adr_techdocs(workshop_config, ready_stack, driver):
    config = workshop_config
    docs_url = (
        f"{config['rhdh_url']}/catalog/default/component/platform-architecture-records/docs"
    )

    sign_in_via_rhdh_popup(driver, config, docs_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(EC.url_contains("/docs"))
    page_text = wait_for_techdocs_page(
        driver,
        config,
        "Platform Architecture Decision Records",
        "ADR-001",
    )
    assert "keycloak" in page_text.lower() or "gitops" in page_text.lower()
