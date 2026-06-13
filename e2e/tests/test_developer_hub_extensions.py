import shutil
import subprocess
import time
import uuid

import pytest
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import WebDriverWait

from helpers import dismiss_onboarding, sign_in_via_rhdh_popup
from test_developer_hub_catalog import _wait_for_text


def _fill_create_person_workflow_form(driver, first_name, last_name, age):
    for field_id, value in [
        ("root_firstName", first_name),
        ("root_lastName", last_name),
        ("root_age", str(age)),
    ]:
        field = driver.find_element(By.ID, field_id)
        field.click()
        field.clear()
        field.send_keys(value)


def _click_button(driver, label):
    driver.find_element(By.XPATH, f"//button[normalize-space(.)='{label}']").click()


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
def test_developer_hub_orchestrator_all_runs(
    workshop_config, ready_stack, driver
):
    config = workshop_config
    instances_url = f"{config['rhdh_url']}/orchestrator/instances"

    sign_in_via_rhdh_popup(driver, config, instances_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/orchestrator/instances")
    )
    page_text = _wait_for_text(
        driver,
        config["timeout"],
        "Workflow Orchestrator",
    )
    lowered = page_text.lower()
    assert "validation error" not in lowered
    assert "fieldundefined" not in lowered
    assert "field 'executionsummary'" not in lowered
    assert "all runs" in lowered or "instances" in lowered


@pytest.mark.e2e
def test_developer_hub_orchestrator_create_person_input_form(
    workshop_config, ready_stack, driver
):
    config = workshop_config
    execute_url = (
        f"{config['rhdh_url']}/orchestrator/workflows/create-person/execute"
    )

    sign_in_via_rhdh_popup(driver, config, execute_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/workflows/create-person/execute")
    )
    page_text = _wait_for_text(
        driver,
        config["timeout"],
        "Create Person in People API",
        "Run workflow",
    )
    lowered = page_text.lower()
    assert "missing json schema for input form" not in lowered
    assert "first name" in lowered
    assert "last name" in lowered
    assert "age" in lowered


@pytest.mark.e2e
def test_developer_hub_entity_relations_graph(workshop_config, ready_stack, driver):
    config = workshop_config
    dependencies_url = (
        f"{config['rhdh_url']}/catalog/default/component/"
        f"{config['component']}/dependencies"
    )
    graph_page_url = f"{config['rhdh_url']}/catalog-graph"

    sign_in_via_rhdh_popup(driver, config, dependencies_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/dependencies")
    )
    dependencies_text = _wait_for_text(
        driver,
        config["timeout"],
        "People Service",
        "Dependencies",
    )
    lowered = dependencies_text.lower()
    assert "relations" in lowered
    assert "view graph" in lowered
    assert "people platform" in lowered or "people rest api" in lowered

    driver.get(graph_page_url)
    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/catalog-graph")
    )
    graph_text = _wait_for_text(
        driver,
        config["timeout"],
        "Relations",
    ).lower()
    assert "validation error" not in graph_text
    assert "failed to load" not in graph_text


@pytest.mark.e2e
def test_developer_hub_orchestrator_create_person_workflow_execution(
    workshop_config, ready_stack, driver
):
    config = workshop_config
    execute_url = (
        f"{config['rhdh_url']}/orchestrator/workflows/create-person/execute"
    )
    unique_last_name = f"Orchestrator-{uuid.uuid4().hex[:8]}"

    sign_in_via_rhdh_popup(driver, config, execute_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/workflows/create-person/execute")
    )
    _wait_for_text(
        driver,
        config["timeout"],
        "Create Person in People API",
        "Run workflow",
    )

    _fill_create_person_workflow_form(
        driver,
        first_name="E2E",
        last_name=unique_last_name,
        age=37,
    )
    _click_button(driver, "Next")

    review_text = _wait_for_text(
        driver,
        config["timeout"],
        "Review",
        unique_last_name,
    ).lower()
    assert "first name" in review_text
    assert "last name" in review_text
    assert "age" in review_text

    _click_button(driver, "Run")

    deadline = time.time() + config["timeout"]
    last_body = ""
    while time.time() < deadline:
        last_body = driver.find_element(By.TAG_NAME, "body").text
        lowered = last_body.lower()
        if "422" in lowered or "unprocessable entity" in lowered:
            pytest.fail(
                "Create-person workflow returned HTTP 422. "
                "Rebuild the workflow image with ./scripts/repair-orchestrator.sh"
            )
        if "exceeded maximum number of retries" in lowered:
            pytest.fail(
                "Orchestrator could not fetch the workflow instance from Data Index. "
                "Rebuild with ./scripts/repair-orchestrator.sh"
            )
        if "error:" in lowered and "create-person-workflow" in lowered:
            pytest.fail(f"Workflow execution failed: {last_body[:500]}")
        if "completed" in lowered or "success" in lowered:
            break
        if "/orchestrator/instances/" in driver.current_url:
            break
        time.sleep(2)
    else:
        pytest.fail(
            "Timed out waiting for create-person workflow success. "
            f"Last page text: {last_body[:500]}"
        )


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
        "create person" in lowered
        or "people api" in lowered
    )

    workflows_tab_url = (
        f"{config['rhdh_url']}/catalog/default/component/people-service/workflows"
    )
    driver.get(workflows_tab_url)
    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/workflows")
    )
    tab_text = _wait_for_text(
        driver,
        config["timeout"],
        "People Service",
        "Workflows",
    ).lower()
    assert "enotfound" not in tab_text
    assert "fetch failed" not in tab_text
    assert "workflows" in tab_text
    assert "create person" in tab_text or "create-person" in tab_text


def _assert_github_scaffolder_plugin_loaded(config):
    if not shutil.which("oc"):
        pytest.skip("oc CLI not available; skipping scaffolder plugin check")
    logs = subprocess.check_output(
        [
            "oc",
            "logs",
            "-n",
            config["namespace"],
            "-l",
            "app.kubernetes.io/name=developer-hub",
            "-c",
            "install-dynamic-plugins",
            "--tail=500",
        ],
        text=True,
        stderr=subprocess.STDOUT,
    )
    assert (
        "backstage-plugin-scaffolder-backend-module-github-dynamic"
        in logs
    ), (
        "GitHub scaffolder backend plugin was not installed. "
        "Enable it in manifests/gitops/developer-hub/dynamic-plugins-rhdh.yaml "
        "and run ./scripts/setup-developer-hub-config.sh"
    )
    assert "Successfully installed dynamic plugin ./dynamic-plugins/dist/backstage-plugin-scaffolder-backend-module-github-dynamic" in logs


@pytest.mark.e2e
def test_developer_hub_scaffolder_template_and_github_publish_action(
    workshop_config, ready_stack, driver
):
    config = workshop_config
    template_url = (
        f"{config['rhdh_url']}/create/templates/default/"
        "quarkus-react-postgres-openshift"
    )

    _assert_github_scaffolder_plugin_loaded(config)

    sign_in_via_rhdh_popup(driver, config, template_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/quarkus-react-postgres-openshift")
    )
    page_text = _wait_for_text(
        driver,
        config["timeout"],
        "Quarkus + React + PostgreSQL on OpenShift",
    )
    lowered = page_text.lower()
    assert "quarkus" in lowered
    assert "component name" in lowered
    assert "not registered" not in lowered


def _lightspeed_enabled_on_cluster(config):
    if not shutil.which("oc"):
        return config.get("lightspeed_enabled", False)
    try:
        containers = subprocess.check_output(
            [
                "oc",
                "get",
                "deployment",
                "redhat-developer-hub",
                "-n",
                config["namespace"],
                "-o",
                "jsonpath={.spec.template.spec.containers[*].name}",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return config.get("lightspeed_enabled", False)
    return "llama-stack" in containers.split()


def _assert_lightspeed_plugin_loaded(config):
    if not shutil.which("oc"):
        pytest.skip("oc CLI not available; skipping Lightspeed plugin check")
    logs = subprocess.check_output(
        [
            "oc",
            "logs",
            "-n",
            config["namespace"],
            "-l",
            "app.kubernetes.io/name=developer-hub",
            "-c",
            "install-dynamic-plugins",
            "--tail=800",
        ],
        text=True,
        stderr=subprocess.STDOUT,
    )
    assert "red-hat-developer-hub-backstage-plugin-lightspeed" in logs, (
        "Lightspeed plugin was not installed. Set LIGHTSPEED_ENABLED=true in workshop.env "
        "and run ./scripts/setup-developer-hub-config.sh"
    )


@pytest.mark.e2e
def test_developer_hub_lightspeed_sidecars(workshop_config, ready_stack):
    config = workshop_config
    if not _lightspeed_enabled_on_cluster(config):
        pytest.skip(
            "Developer Lightspeed not enabled (set LIGHTSPEED_ENABLED=true and "
            "OPENAI_API_KEY, then ./scripts/setup-developer-hub-lightspeed.sh)"
        )

    assert _lightspeed_enabled_on_cluster(config)
    for container in ("llama-stack", "lightspeed-core", "init-rag-data"):
        if container == "init-rag-data":
            result = subprocess.run(
                [
                    "oc",
                    "get",
                    "deployment",
                    "redhat-developer-hub",
                    "-n",
                    config["namespace"],
                    "-o",
                    f"jsonpath={{.spec.template.spec.initContainers[?(@.name=='{container}')].name}}",
                ],
                capture_output=True,
                text=True,
            )
            assert result.stdout.strip() == container, f"missing init container {container}"
        else:
            containers = subprocess.check_output(
                [
                    "oc",
                    "get",
                    "deployment",
                    "redhat-developer-hub",
                    "-n",
                    config["namespace"],
                    "-o",
                    "jsonpath={.spec.template.spec.containers[*].name}",
                ],
                text=True,
            )
            assert container in containers.split()


@pytest.mark.e2e
def test_developer_hub_lightspeed_plugin_and_page(workshop_config, ready_stack, driver):
    config = workshop_config
    if not _lightspeed_enabled_on_cluster(config):
        pytest.skip(
            "Developer Lightspeed not enabled (set LIGHTSPEED_ENABLED=true and "
            "OPENAI_API_KEY, then ./scripts/setup-developer-hub-lightspeed.sh)"
        )

    _assert_lightspeed_plugin_loaded(config)

    lightspeed_url = f"{config['rhdh_url']}/lightspeed"
    sign_in_via_rhdh_popup(driver, config, lightspeed_url)
    dismiss_onboarding(driver)

    WebDriverWait(driver, config["timeout"]).until(
        EC.url_contains("/lightspeed")
    )
    page_text = _wait_for_text(
        driver,
        config["timeout"],
        "Lightspeed",
        "Developer Hub",
    )
    lowered = page_text.lower()
    assert "lightspeed" in lowered or "assistant" in lowered or "chat" in lowered
    assert "not registered" not in lowered
