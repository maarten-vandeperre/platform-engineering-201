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
