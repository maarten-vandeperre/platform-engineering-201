import time

import pytest
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait


def _wait_for(driver, timeout, condition):
    return WebDriverWait(driver, timeout).until(condition)


def _sign_in_to_people_frontend(driver, config):
    driver.get(config["people_frontend_url"])
    _wait_for(
        driver,
        config["timeout"],
        lambda d: "keycloak" in d.current_url.lower()
        or "people crud" in d.find_element(By.TAG_NAME, "body").text.lower(),
    )
    if "keycloak" in driver.current_url.lower():
        _wait_for(
            driver,
            config["timeout"],
            EC.visibility_of_element_located((By.ID, "username")),
        )
        driver.find_element(By.ID, "username").send_keys(config["people_username"])
        driver.find_element(By.ID, "password").send_keys(config["people_password"])
        driver.find_element(By.ID, "kc-login").click()
        _wait_for(
            driver,
            config["timeout"],
            lambda d: "people crud" in d.find_element(By.TAG_NAME, "body").text.lower(),
        )


@pytest.mark.e2e
def test_people_frontend_crud(workshop_config, ready_stack, driver):
    config = workshop_config
    _sign_in_to_people_frontend(driver, config)

    unique_last_name = f"E2E-{int(time.time())}"
    driver.find_element(By.XPATH, "//label[contains(., 'First name')]/input").send_keys("Workshop")
    driver.find_element(By.XPATH, "//label[contains(., 'Last name')]/input").send_keys(unique_last_name)
    driver.find_element(By.XPATH, "//label[contains(., 'Age')]/input").send_keys("30")
    driver.find_element(By.XPATH, "//button[normalize-space(.)='Create']").click()

    _wait_for(
        driver,
        config["timeout"],
        lambda d: unique_last_name in d.find_element(By.TAG_NAME, "body").text,
    )
    assert "Authentication failed" not in driver.find_element(By.TAG_NAME, "body").text
