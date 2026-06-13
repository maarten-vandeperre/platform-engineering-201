function containsPlaceholder(value) {
  if (value === undefined || value === null) {
    return true;
  }
  const text = String(value);
  return text.includes('${') || text.includes('$%7B');
}

function deriveKeycloakUrlFromHostname(hostname) {
  const frontendMatch = hostname.match(/^people-frontend-([^.]+)\.(.+)$/);
  if (frontendMatch) {
    return `https://keycloak-${frontendMatch[1]}.${frontendMatch[2]}`;
  }

  const genericMatch = hostname.match(/^([^.]+)\.(.+)$/);
  if (genericMatch) {
    return `https://keycloak-${genericMatch[1]}.${genericMatch[2]}`;
  }

  return null;
}

export function resolveRuntimeConfig(rawConfig = window.__RUNTIME_CONFIG__ || {}) {
  let keycloakUrl = rawConfig.keycloakUrl || '';
  let keycloakRealm = rawConfig.keycloakRealm || 'workshop';
  let keycloakClientId = rawConfig.keycloakClientId || 'people-service';
  const oidcEnabled =
    rawConfig.oidcEnabled !== false && rawConfig.oidcEnabled !== 'false';

  if (containsPlaceholder(keycloakUrl) || !String(keycloakUrl).startsWith('http')) {
    const derived = deriveKeycloakUrlFromHostname(window.location.hostname);
    if (derived) {
      keycloakUrl = derived;
    }
  }

  if (containsPlaceholder(keycloakRealm)) {
    keycloakRealm = 'workshop';
  }

  if (containsPlaceholder(keycloakClientId)) {
    keycloakClientId = 'people-service';
  }

  if (!oidcEnabled) {
    return {
      keycloakUrl,
      keycloakRealm,
      keycloakClientId,
      oidcEnabled: false,
    };
  }

  if (!String(keycloakUrl).startsWith('http')) {
    throw new Error(
      `Invalid Keycloak URL "${keycloakUrl}". Run ./scripts/repair-people-app.sh`,
    );
  }

  return {
    keycloakUrl,
    keycloakRealm,
    keycloakClientId,
    oidcEnabled: true,
  };
}
