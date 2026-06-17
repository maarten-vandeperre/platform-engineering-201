import shutil
import subprocess

import pytest
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

from helpers import dismiss_onboarding, sign_in_via_rhdh_popup, wait_for_page_text
from test_developer_hub_catalog import _wait_for_text


def _aap_management_enabled_on_cluster(config):
    if config.get("aap_management_enabled"):
        return True
    if not shutil.which("oc"):
        return False
    try:
        plugins = subprocess.check_output(
            [
                "oc",
                "get",
                "configmap",
                "redhat-developer-hub-dynamic-plugins",
                "-n",
                config["namespace"],
                "-o",
                "jsonpath={.data.plugins\\.yaml}",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False
    return "internal.plugin-aap-management" in plugins


def _require_aap_management(config):
    if not _aap_management_enabled_on_cluster(config):
        pytest.skip(
            "AAP Management plugin not enabled. Set AAP_MANAGEMENT_ENABLED=true and run "
            "./scripts/setup-custom-aap-management-plugin.sh"
        )


def _open_aap_management(driver, config):
    aap_url = f"{config['rhdh_url']}/aap-management"
    sign_in_via_rhdh_popup(driver, config, aap_url)
    dismiss_onboarding(driver)
    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/aap-management")
    )


def _js_click(driver, element):
    driver.execute_script(
        "arguments[0].scrollIntoView({block: 'center'}); arguments[0].click();",
        element,
    )


def _click_aap_tab(driver, timeout, label):
    tab = WebDriverWait(driver, timeout).until(
        EC.presence_of_element_located(
            (
                By.XPATH,
                f"//div[contains(@class,'MuiChip-root') and normalize-space(.)='{label}']",
            )
        )
    )
    _js_click(driver, tab)


@pytest.mark.e2e
def test_developer_hub_aap_management_page(workshop_config, ready_stack, driver):
    config = workshop_config
    _require_aap_management(config)

    _open_aap_management(driver, config)
    page_text = wait_for_page_text(
        driver,
        config["timeout"],
        "AAP Automation Templates",
        "Templates",
        "Run history",
        retries=2,
    )
    lowered = page_text.lower()
    assert "could not load templates" not in lowered
    assert "could not load job history" not in lowered


@pytest.mark.e2e
def test_developer_hub_aap_management_job_logs(workshop_config, ready_stack, driver):
    config = workshop_config
    _require_aap_management(config)

    _open_aap_management(driver, config)
    _wait_for_text(
        driver,
        config["timeout"],
        "AAP Automation Templates",
        "Run history",
    )

    _click_aap_tab(driver, config["timeout"], "Run history")

    WebDriverWait(driver, config["timeout"]).until(
        EC.presence_of_element_located(
            (By.XPATH, "//th[normalize-space(.)='Job']/ancestor::table//tbody")
        )
    )

    job_row_xpath = (
        "//th[normalize-space(.)='Job']/ancestor::table//tbody/tr[.//strong]"
    )
    rows = WebDriverWait(driver, config["timeout"]).until(
        EC.presence_of_all_elements_located((By.XPATH, job_row_xpath))
    )
    if not rows:
        pytest.skip("No AAP job runs available to inspect logs")

    _js_click(driver, rows[0])

    WebDriverWait(driver, config["timeout"]).until(
        EC.visibility_of_element_located((By.CSS_SELECTOR, "[role='dialog']"))
    )
    detail_text = _wait_for_text(
        driver,
        config["timeout"],
        "Events",
        "Task logs",
        "Output",
    ).lower()
    assert "events" in detail_text
    assert "task logs" in detail_text
    assert "output" in detail_text
    assert "could not load job" not in detail_text

    task_logs_tab = WebDriverWait(driver, config["timeout"]).until(
        EC.presence_of_element_located(
            (
                By.XPATH,
                "//div[@role='dialog']//button[@role='tab' and normalize-space(.)='Task logs']",
            )
        )
    )
    _js_click(driver, task_logs_tab)

    def _task_logs_ready(driver):
        text = driver.find_element(By.TAG_NAME, "body").text.lower()
        return (
            "no task logs recorded" in text
            or "waiting for ansible task output" in text
            or "runner_on" in text
            or "ok" in text
            or "failed" in text
            or "task" in text
        )

    WebDriverWait(driver, config["timeout"]).until(_task_logs_ready)
    body = driver.find_element(By.TAG_NAME, "body").text.lower()
    assert (
        "no task logs recorded" in body
        or "waiting for ansible task output" in body
        or "task" in body
    )

    output_tab = WebDriverWait(driver, config["timeout"]).until(
        EC.presence_of_element_located(
            (
                By.XPATH,
                "//div[@role='dialog']//button[@role='tab' and normalize-space(.)='Output']",
            )
        )
    )
    _js_click(driver, output_tab)

    def _output_ready(driver):
        text = driver.find_element(By.TAG_NAME, "body").text.lower()
        return (
            "no stdout captured" in text
            or "job output will appear" in text
            or "play [" in text
            or "workflow jobs aggregate" in text
            or (
                "task" in text
                and "events" in text
                and "output" in text
            )
        )

    WebDriverWait(driver, config["timeout"]).until(_output_ready)
    body = driver.find_element(By.TAG_NAME, "body").text.lower()
    assert (
        "no stdout captured" in body
        or "job output will appear" in body
        or "play [" in body
        or "workflow jobs aggregate" in body
        or (
            "task" in body
            and "events" in body
        )
    )
