import time
from urllib.parse import quote

import pytest
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait


def _wait_for(driver, timeout, condition):
    return WebDriverWait(driver, timeout).until(condition)


def _assert_no_keycloak_client_error(driver):
    body = driver.find_element(By.TAG_NAME, "body").text.lower()
    assert "client not found" not in body
    assert "invalid parameter: redirect_uri" not in body


def _sign_in_via_keycloak(driver, config):
    username = _wait_for(
        driver,
        config["timeout"],
        EC.visibility_of_element_located((By.ID, "username")),
    )
    password = driver.find_element(By.ID, "password")
    username.clear()
    username.send_keys(config["username"])
    password.clear()
    password.send_keys(config["password"])
    driver.find_element(By.ID, "kc-login").click()


def _sign_in_via_rhdh_popup(driver, config, return_url):
    driver.get(return_url)
    time.sleep(5)
    if not driver.find_elements(By.XPATH, "//button[normalize-space(.)='Sign In']"):
        return

    main_window = driver.current_window_handle
    driver.find_element(By.XPATH, "//button[normalize-space(.)='Sign In']").click()
    _wait_for(driver, config["timeout"], lambda d: len(d.window_handles) > 1)

    popup = next(h for h in driver.window_handles if h != main_window)
    driver.switch_to.window(popup)
    _assert_no_keycloak_client_error(driver)
    _sign_in_via_keycloak(driver, config)
    _wait_for(driver, 60, lambda d: len(d.window_handles) == 1)
    driver.switch_to.window(main_window)
    driver.get(return_url)
    time.sleep(5)


def _dismiss_onboarding(driver):
    hide = driver.find_elements(By.XPATH, "//button[contains(., 'Hide')]")
    if hide:
        hide[0].click()
        time.sleep(1)


def _open_component_tab(driver, tab_name):
    tab = driver.find_elements(
        By.XPATH,
        f"//a[contains(@href,'/{tab_name.lower()}') and contains(., '{tab_name}')]",
    )
    if tab:
        tab[0].click()
        time.sleep(10)


def _assert_kubernetes_view(page_text):
    lowered = page_text.lower()
    assert "problem retrieving kubernetes objects" not in lowered
    assert "select a sign-in method" not in lowered
    assert "openshift" in lowered
    assert "pod" in lowered
    assert "your clusters" in lowered or "pods" in lowered

    workshop_workloads = ("people-postgres", "people-backend", "people-frontend")
    error_markers = (
        "back-off",
        "failed to start",
        "does not have minimum availability",
        "crashloop",
        "restarting failed",
    )
    for workload in workshop_workloads:
        if workload not in lowered:
            continue
        for marker in error_markers:
            if marker in lowered:
                pytest.fail(
                    f"{workload} is unhealthy in Developer Hub Kubernetes view"
                )


@pytest.mark.e2e
def test_keycloak_oidc_client_is_registered(driver, workshop_config):
    config = workshop_config
    auth_url = (
        f"{config['rhdh_url']}/api/auth/oidc/start"
        f"?env=production&redirectUrl={quote(config['rhdh_url'] + '/', safe='')}"
    )
    driver.get(auth_url)
    _wait_for(driver, config["timeout"], lambda d: "keycloak" in d.current_url.lower())
    _assert_no_keycloak_client_error(driver)
    _wait_for(
        driver,
        config["timeout"],
        EC.visibility_of_element_located((By.ID, "username")),
    )


@pytest.mark.e2e
def test_developer_hub_login_and_topology(workshop_config, ready_stack, driver):
    config = workshop_config
    kubernetes_url = (
        f"{config['rhdh_url']}/catalog/default/component/"
        f"{config['component']}/kubernetes"
    )
    topology_url = (
        f"{config['rhdh_url']}/catalog/default/component/"
        f"{config['component']}/topology"
    )

    _sign_in_via_rhdh_popup(driver, config, kubernetes_url)
    _dismiss_onboarding(driver)
    _open_component_tab(driver, "Kubernetes")

    try:
        _wait_for(
            driver,
            config["timeout"],
            lambda d: "kubernetes" in d.current_url,
        )
    except TimeoutException:
        pytest.fail(f"Did not reach Kubernetes tab: {driver.current_url}")

    deadline = time.time() + config["timeout"]
    page_text = ""
    while time.time() < deadline:
        page_text = driver.find_element(By.TAG_NAME, "body").text
        lowered = page_text.lower()
        if "openshift" in lowered and "pod" in lowered:
            break
        time.sleep(2)
    else:
        pytest.fail(
            "Kubernetes view did not show cluster data. "
            f"URL={driver.current_url}"
        )

    assert "client not found" not in page_text.lower()
    _assert_kubernetes_view(page_text)

    driver.get(topology_url)
    time.sleep(15)
    topology_text = driver.find_element(By.TAG_NAME, "body").text.lower()
    assert "topology" in driver.current_url
    assert "select a sign-in method" not in topology_text
    assert "problem retrieving kubernetes objects" not in topology_text
