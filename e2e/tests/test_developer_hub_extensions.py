import pytest
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

from helpers import dismiss_onboarding, sign_in_via_rhdh_popup
from test_developer_hub_catalog import _wait_for_text


@pytest.mark.e2e
def test_developer_hub_quarkus_techdocs(workshop_config, ready_stack, driver):
    config = workshop_config
    docs_url = f"{config['rhdh_url']}/catalog/default/component/quarkus-workshop-guide/docs"

    sign_in_via_rhdh_popup(driver, config, docs_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(EC.url_contains("/docs"))
    page_text = _wait_for_text(
        driver,
        config["timeout"],
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
    page_text = _wait_for_text(
        driver,
        config["timeout"],
        "Platform Architecture Decision Records",
        "ADR-001",
    )
    assert "keycloak" in page_text.lower() or "gitops" in page_text.lower()


@pytest.mark.e2e
def test_developer_hub_learning_paths(workshop_config, ready_stack, driver):
    config = workshop_config
    learning_paths_url = f"{config['rhdh_url']}/learning-paths"

    sign_in_via_rhdh_popup(driver, config, learning_paths_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("learning-paths")
    )
    page_text = _wait_for_text(
        driver,
        config["timeout"],
        "Developing with Quarkus",
    )
    assert "developers.redhat.com" in page_text.lower() or "quarkus" in page_text.lower()


@pytest.mark.e2e
def test_developer_hub_orchestrator_create_person_workflow(
    workshop_config, ready_stack, driver
):
    config = workshop_config
    orchestrator_url = f"{config['rhdh_url']}/orchestrator"

    sign_in_via_rhdh_popup(driver, config, orchestrator_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("orchestrator")
    )
    page_text = _wait_for_text(
        driver,
        config["timeout"],
        "Workflow Orchestrator",
    )
    lowered = page_text.lower()
    assert "enotfound" not in lowered
    assert "fetch failed" not in lowered
    assert "getaddrinfo" not in lowered
    assert (
        "workflows" in lowered
        or "all runs" in lowered
        or "create person" in lowered
        or "no workflows" in lowered
    )

    workflows_tab_url = (
        f"{config['rhdh_url']}/catalog/default/component/people-service/workflows"
    )
    driver.get(workflows_tab_url)
    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/workflows")
    )
    tab_text = _wait_for_text(driver, config["timeout"], "People Service").lower()
    assert "enotfound" not in tab_text
    assert "fetch failed" not in tab_text
    assert (
        "workflow" in tab_text
        or "orchestrator" in tab_text
        or "create person" in tab_text
    )
