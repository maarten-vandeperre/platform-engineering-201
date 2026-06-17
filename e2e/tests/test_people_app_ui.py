import time

import pytest
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

from helpers import http_get


def _wait_for(driver, timeout, condition):
    return WebDriverWait(driver, timeout).until(condition)


def _assert_no_broken_keycloak_url(driver):
    url = driver.current_url
    body = driver.find_element(By.TAG_NAME, "body").text
    assert "${" not in url
    assert "$%7B" not in url
    assert "414 Request-URI Too Large" not in body
    assert "Request-URI Too Large" not in body


def _sign_in_to_people_frontend(driver, config):
    driver.get(config["people_frontend_url"])
    deadline = time.time() + config["timeout"]
    while time.time() < deadline:
        _assert_no_broken_keycloak_url(driver)
        if "people crud" in driver.find_element(By.TAG_NAME, "body").text.lower():
            return
        if "keycloak" in driver.current_url.lower():
            break
        time.sleep(1)
    else:
        pytest.fail(f"People frontend did not redirect or load: {driver.current_url}")

    if "keycloak" in driver.current_url.lower():
        assert "keycloak-" in driver.current_url.lower()
        try:
            _wait_for(
                driver,
                config["timeout"],
                EC.visibility_of_element_located((By.ID, "username")),
            )
        except Exception:
            body = driver.find_element(By.TAG_NAME, "body").text[:500]
            pytest.fail(
                "Keycloak login form did not load for People frontend. "
                f"URL={driver.current_url} body={body}"
            )
        driver.find_element(By.ID, "username").clear()
        driver.find_element(By.ID, "username").send_keys(config["people_username"])
        driver.find_element(By.ID, "password").clear()
        driver.find_element(By.ID, "password").send_keys(config["people_password"])
        driver.find_element(By.ID, "kc-login").click()
        _wait_for(
            driver,
            config["timeout"],
            lambda d: "people crud" in d.find_element(By.TAG_NAME, "body").text.lower(),
        )


def _fill_person_form(driver, first_name, last_name, age):
    values = {
        "First name": first_name,
        "Last name": last_name,
        "Age": str(age),
    }
    for label, value in values.items():
        field = driver.find_element(By.XPATH, f"//label[contains(., '{label}')]/input")
        field.click()
        field.clear()
        field.send_keys(value)


def _update_last_name_and_age(driver, last_name, age):
    last_field = driver.find_element(By.XPATH, "//label[contains(., 'Last name')]/input")
    age_field = driver.find_element(By.XPATH, "//label[contains(., 'Age')]/input")
    last_field.click()
    last_field.clear()
    last_field.send_keys(last_name)
    age_field.click()
    age_field.clear()
    age_field.send_keys(str(age))


def _wait_for_table_cell(driver, timeout, text):
    return _wait_for(
        driver,
        timeout,
        EC.presence_of_element_located(
            (By.XPATH, f"//section[.//h2[normalize-space(.)='People']]//td[contains(., '{text}')]")
        ),
    )


def _assert_no_error_banner(driver):
    errors = driver.find_elements(By.CSS_SELECTOR, ".error")
    for element in errors:
        message = element.text.strip()
        if message:
            pytest.fail(f"Unexpected UI error: {message}")


@pytest.mark.e2e
def test_frontend_runtime_config_has_no_placeholders(workshop_config):
    config = workshop_config
    status, body = http_get(f"{config['people_frontend_url']}/config.js")
    assert status == 200
    assert "${" not in body, f"Unresolved placeholders in config.js: {body}"
    assert "keycloakUrl:" in body
    assert "https://keycloak-" in body


@pytest.mark.e2e
def test_people_frontend_login_redirect(workshop_config, ready_stack, driver):
    config = workshop_config
    driver.get(config["people_frontend_url"])
    deadline = time.time() + 30
    while time.time() < deadline:
        _assert_no_broken_keycloak_url(driver)
        if "keycloak" in driver.current_url.lower() or "people crud" in driver.find_element(By.TAG_NAME, "body").text.lower():
            break
        time.sleep(1)
    if "keycloak" in driver.current_url.lower():
        assert config["namespace"] in driver.current_url or "keycloak-" in driver.current_url


@pytest.mark.e2e
def test_people_frontend_crud(workshop_config, ready_stack, driver):
    config = workshop_config
    _sign_in_to_people_frontend(driver, config)

    unique_last_name = f"E2E-{int(time.time())}"
    _fill_person_form(driver, "Workshop", unique_last_name, 30)
    driver.find_element(By.XPATH, "//form//button[@type='submit' and normalize-space(.)='Create']").click()
    _wait_for_table_cell(driver, config["timeout"], unique_last_name)
    _assert_no_error_banner(driver)

    row = driver.find_element(
        By.XPATH,
        f"//section[.//h2[normalize-space(.)='People']]//tr[td[contains(., '{unique_last_name}')]]",
    )
    row.find_element(By.XPATH, ".//button[normalize-space(.)='Edit']").click()
    _wait_for(
        driver,
        config["timeout"],
        EC.text_to_be_present_in_element(
            (By.XPATH, "//section[.//h2[normalize-space(.)='Add person' or normalize-space(.)='Edit person']]//h2"),
            "Edit person",
        ),
    )

    updated_last_name = f"{unique_last_name}-updated"
    _update_last_name_and_age(driver, updated_last_name, 31)
    driver.find_element(By.XPATH, "//form//button[@type='submit' and normalize-space(.)='Update']").click()
    _wait_for(
        driver,
        config["timeout"],
        EC.invisibility_of_element_located((By.XPATH, "//section[.//h2[normalize-space(.)='People']]//p[normalize-space(.)='Loading...']")),
    )
    _wait_for_table_cell(driver, config["timeout"], updated_last_name)
    _assert_no_error_banner(driver)

    row = driver.find_element(
        By.XPATH,
        f"//section[.//h2[normalize-space(.)='People']]//tr[td[contains(., '{updated_last_name}')]]",
    )
    row.find_element(By.XPATH, ".//button[normalize-space(.)='Delete']").click()

    _wait_for(
        driver,
        config["timeout"],
        lambda d: not d.find_elements(
            By.XPATH,
            f"//section[.//h2[normalize-space(.)='People']]//td[contains(., '{updated_last_name}')]",
        ),
    )
