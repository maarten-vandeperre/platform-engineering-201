import time

import pytest
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

from helpers import dismiss_onboarding, open_entity_tab, sign_in_via_rhdh_popup


def _wait_for_text(driver, timeout, *needles):
    deadline = time.time() + timeout
    while time.time() < deadline:
        text = driver.find_element(By.TAG_NAME, "body").text
        lowered = text.lower()
        if all(needle.lower() in lowered for needle in needles):
            return text
        time.sleep(2)
    pytest.fail(
        "Expected page text not found. "
        f"URL={driver.current_url} needles={needles}"
    )


@pytest.mark.e2e
def test_developer_hub_api_catalog_listing(workshop_config, ready_stack, driver):
    config = workshop_config
    api_list_url = f"{config['rhdh_url']}/catalog?filters%5Bkind%5D=api"
    api_entity_url = (
        f"{config['rhdh_url']}/catalog/default/api/{config['api_name']}"
    )

    sign_in_via_rhdh_popup(driver, config, api_list_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("catalog")
    )
    page_text = _wait_for_text(driver, config["timeout"], "People REST API")
    assert config["api_name"].replace("-", " ") in page_text.lower() or "people rest api" in page_text.lower()

    driver.get(api_entity_url)
    entity_text = _wait_for_text(
        driver,
        config["timeout"],
        "People REST API",
        "openapi",
    )
    assert "people" in entity_text.lower()


@pytest.mark.e2e
def test_developer_hub_api_github_actions_ci_tab(workshop_config, ready_stack, driver):
    config = workshop_config
    api_entity_url = (
        f"{config['rhdh_url']}/catalog/default/api/{config['api_name']}"
    )
    ci_tab_url = f"{api_entity_url}/ci"

    sign_in_via_rhdh_popup(driver, config, api_entity_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains(f"/api/{config['api_name']}")
    )
    overview_text = _wait_for_text(driver, config["timeout"], "People REST API")
    assert "missing annotation" not in overview_text.lower()

    if not open_entity_tab(driver, "ci", "CI"):
        driver.get(ci_tab_url)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/ci")
    )
    ci_text = _wait_for_text(driver, config["timeout"], "People REST API")
    lowered = ci_text.lower()
    assert "missing annotation" not in lowered
    assert (
        "workflow" in lowered
        or "github" in lowered
        or "no workflow" in lowered
        or "actions" in lowered
        or "people service ci" in lowered
        or "build and push" in lowered
    )


@pytest.mark.e2e
def test_developer_hub_api_github_issues_tab(workshop_config, ready_stack, driver):
    config = workshop_config
    component_url = f"{config['rhdh_url']}/catalog/default/component/people-service"
    issues_tab_url = f"{component_url}/issues"

    sign_in_via_rhdh_popup(driver, config, component_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/component/people-service")
    )
    overview_text = _wait_for_text(driver, config["timeout"], "People Service")
    assert "missing annotation" not in overview_text.lower()

    if not open_entity_tab(driver, "issues", "Issues"):
        driver.get(issues_tab_url)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/issues")
    )
    issues_text = _wait_for_text(driver, config["timeout"], "People Service")
    lowered = issues_text.lower()
    assert "missing annotation" not in lowered
    assert "error in github-issues" not in lowered
    assert "invalid url" not in lowered
    assert "failed to construct" not in lowered
    assert (
        "hurray! no issues" in lowered
        or "#" in issues_text
        or "updated" in lowered
        or "created" in lowered
        or "open issues" in lowered
    )


@pytest.mark.e2e
def test_developer_hub_api_github_pull_requests_tab(
    workshop_config, ready_stack, driver
):
    config = workshop_config
    component_url = f"{config['rhdh_url']}/catalog/default/component/people-service"
    pull_requests_tab_url = f"{component_url}/pull-requests"

    sign_in_via_rhdh_popup(driver, config, component_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/component/people-service")
    )
    overview_text = _wait_for_text(driver, config["timeout"], "People Service")
    assert "missing annotation" not in overview_text.lower()

    if not open_entity_tab(driver, "pull-requests", "Pull Requests"):
        driver.get(pull_requests_tab_url)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/pull-requests")
    )
    pull_requests_text = _wait_for_text(driver, config["timeout"], "People Service")
    lowered = pull_requests_text.lower()
    assert "missing annotation" not in lowered
    assert "error in github" not in lowered
    assert "invalid url" not in lowered
    assert (
        "pull request" in lowered
        or "pull requests" in lowered
        or "github" in lowered
        or "no pull" in lowered
        or "merged" in lowered
        or "open" in lowered
    )


@pytest.mark.e2e
def test_developer_hub_tech_radar(workshop_config, ready_stack, driver):
    config = workshop_config
    radar_url = f"{config['rhdh_url']}/tech-radar"

    sign_in_via_rhdh_popup(driver, config, radar_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("tech-radar")
    )
    page_text = _wait_for_text(
        driver,
        config["timeout"],
        "Quarkus",
        "ADOPT",
    )
    assert "postgresql" in page_text.lower() or "openshift" in page_text.lower()
