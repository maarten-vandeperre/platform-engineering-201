import json
import ssl
import urllib.error
import urllib.parse
import urllib.request


def _ssl_context():
    return ssl._create_unverified_context()


def http_get(url, headers=None, timeout=30):
    request = urllib.request.Request(url, headers=headers or {}, method="GET")
    with urllib.request.urlopen(request, timeout=timeout, context=_ssl_context()) as response:
        body = response.read().decode("utf-8")
        return response.status, body


def http_json(method, url, headers=None, payload=None, timeout=30):
    data = None
    req_headers = dict(headers or {})
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        req_headers.setdefault("Content-Type", "application/json")
    request = urllib.request.Request(url, data=data, headers=req_headers, method=method)
    with urllib.request.urlopen(request, timeout=timeout, context=_ssl_context()) as response:
        body = response.read().decode("utf-8")
        return response.status, json.loads(body) if body else {}


def get_keycloak_token(config):
    keycloak_url = config["keycloak_url"]
    data = urllib.parse.urlencode(
        {
            "client_id": config["people_client_id"],
            "username": config["people_username"],
            "password": config["people_password"],
            "grant_type": "password",
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"{keycloak_url}/realms/{config['keycloak_realm']}/protocol/openid-connect/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30, context=_ssl_context()) as response:
        payload = json.loads(response.read().decode("utf-8"))
    token = payload.get("access_token")
    if not token:
        raise AssertionError(
            f"Failed to obtain Keycloak token: {payload.get('error_description', payload)}"
        )
    return token


def wait_for_keycloak_ready(config, timeout_seconds=300):
    import time

    deadline = time.time() + timeout_seconds
    url = (
        f"{config['keycloak_url']}/realms/{config['keycloak_realm']}"
        "/.well-known/openid-configuration"
    )
    last_error = "Keycloak not ready"

    while time.time() < deadline:
        try:
            status, body = http_get(url)
            if status == 200 and "issuer" in body.lower():
                return
            if "application is not available" in body.lower():
                last_error = (
                    "Keycloak route returns OpenShift 'Application is not available' "
                    "(deployment scaled to 0). Run ./scripts/ensure-workshop-platform.sh"
                )
            else:
                last_error = f"Keycloak OIDC metadata HTTP {status}: {body[:200]}"
        except (urllib.error.URLError, TimeoutError) as exc:
            last_error = str(exc)
        time.sleep(5)

    raise AssertionError(last_error)


def wait_for_rhdh_ready(config, timeout_seconds=300):
    import time
    from urllib.parse import quote

    deadline = time.time() + timeout_seconds
    origin = quote(config["rhdh_url"], safe="")
    url = (
        f"{config['rhdh_url']}/api/auth/oidc/start"
        f"?env=production&flow=popup&origin={origin}"
    )
    last_error = "Developer Hub auth not ready"

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(
        NoRedirect,
        urllib.request.HTTPSHandler(context=_ssl_context()),
    )

    while time.time() < deadline:
        try:
            request = urllib.request.Request(url, method="GET")
            try:
                with opener.open(request, timeout=15) as response:
                    status = response.status
                    body = response.read().decode("utf-8", errors="replace")
            except urllib.error.HTTPError as exc:
                status = exc.code
                body = exc.read().decode("utf-8", errors="replace")

            if status in {302, 303}:
                return
            if status == 500 and "5432" in body:
                last_error = (
                    "Developer Hub cannot reach its PostgreSQL database "
                    "(ECONNREFUSED :5432). Run ./scripts/repair-developer-hub.sh"
                )
            elif status == 500:
                last_error = f"Developer Hub OIDC start failed: {body[:200]}"
            elif "application is not available" in body.lower():
                last_error = (
                    "Keycloak is not serving requests during Developer Hub login. "
                    "Run ./scripts/ensure-workshop-platform.sh"
                )
            else:
                last_error = f"OIDC start returned HTTP {status}: {body[:200]}"
        except (urllib.error.URLError, TimeoutError) as exc:
            last_error = str(exc)
        time.sleep(5)

    raise AssertionError(last_error)


def wait_for_backend_ready(config, timeout_seconds=300):
    import time

    deadline = time.time() + timeout_seconds
    last_error = "backend not ready"
    url = f"{config['people_backend_url']}/q/health/ready"
    while time.time() < deadline:
        try:
            status, body = http_get(url)
            if status != 200:
                last_error = f"HTTP {status}"
                time.sleep(5)
                continue
            health = json.loads(body)
            if health.get("status") == "UP":
                checks = health.get("checks") or []
                db_checks = [
                    check
                    for check in checks
                    if "database" in check.get("name", "").lower()
                ]
                if db_checks and any(check.get("status") != "UP" for check in db_checks):
                    last_error = f"database check not UP: {db_checks}"
                else:
                    return health
            last_error = f"health status={health.get('status')}"
        except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as exc:
            last_error = str(exc)
        time.sleep(5)
    raise AssertionError(
        "Backend did not become ready: "
        f"{last_error}. Run ./scripts/repair-people-app.sh after logging in with oc."
    )


def assert_openapi_response(body):
    lowered = body.lower()
    assert "openapi:" in lowered or '"openapi"' in lowered
    assert "people" in lowered


def sign_in_via_rhdh_popup(driver, config, return_url):
    import time

    from selenium.webdriver.common.by import By
    from selenium.webdriver.support import expected_conditions as EC
    from selenium.webdriver.support.ui import WebDriverWait

    driver.get(return_url)
    time.sleep(5)
    if not driver.find_elements(By.XPATH, "//button[normalize-space(.)='Sign In']"):
        return

    main_window = driver.current_window_handle
    driver.find_element(By.XPATH, "//button[normalize-space(.)='Sign In']").click()
    WebDriverWait(driver, config["timeout"]).until(lambda d: len(d.window_handles) > 1)

    popup = next(h for h in driver.window_handles if h != main_window)
    driver.switch_to.window(popup)
    body = driver.find_element(By.TAG_NAME, "body").text.lower()
    assert "client not found" not in body
    assert "invalid parameter: redirect_uri" not in body
    assert "application is not available" not in body, (
        "Keycloak is down (scaled to 0). Run ./scripts/ensure-workshop-platform.sh"
    )

    username = WebDriverWait(driver, config["timeout"]).until(
        EC.visibility_of_element_located((By.ID, "username"))
    )
    password = driver.find_element(By.ID, "password")
    username.clear()
    username.send_keys(config["username"])
    password.clear()
    password.send_keys(config["password"])
    driver.find_element(By.ID, "kc-login").click()
    WebDriverWait(driver, 60).until(lambda d: len(d.window_handles) == 1)
    driver.switch_to.window(main_window)
    driver.get(return_url)
    time.sleep(5)


def dismiss_onboarding(driver):
    import time

    from selenium.webdriver.common.by import By

    hide = driver.find_elements(By.XPATH, "//button[contains(., 'Hide')]")
    if hide:
        hide[0].click()
        time.sleep(1)


def open_entity_tab(driver, tab_path, tab_label=None):
    """Open a catalog entity tab by route suffix (e.g. ci, kubernetes)."""
    import time

    from selenium.webdriver.common.by import By

    label = tab_label or tab_path
    xpath = (
        f"//a[contains(@href,'/{tab_path}') "
        f"and (contains(., '{label}') or @aria-label='{label}')]"
    )
    tabs = driver.find_elements(By.XPATH, xpath)
    if not tabs:
        xpath = f"//a[contains(@href,'/{tab_path}')]"
        tabs = driver.find_elements(By.XPATH, xpath)
    if tabs:
        tabs[0].click()
        time.sleep(5)
        return True
    return False
