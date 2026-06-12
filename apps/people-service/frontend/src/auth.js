import Keycloak from 'keycloak-js';

const config = window.__RUNTIME_CONFIG__ || {};
const oidcEnabled = config.oidcEnabled !== false && config.oidcEnabled !== 'false';

let keycloak;

export function isAuthEnabled() {
  return oidcEnabled;
}

export async function initAuth() {
  if (!oidcEnabled) {
    return { authenticated: true, username: 'dev' };
  }

  keycloak = new Keycloak({
    url: config.keycloakUrl,
    realm: config.keycloakRealm || 'workshop',
    clientId: config.keycloakClientId || 'people-service',
  });

  const authenticated = await keycloak.init({
    onLoad: 'login-required',
    checkLoginIframe: false,
    pkceMethod: 'S256',
  });

  return {
    authenticated,
    username: keycloak.tokenParsed?.preferred_username || keycloak.tokenParsed?.sub,
  };
}

export function getAccessToken() {
  if (!oidcEnabled) {
    return null;
  }
  return keycloak?.token;
}

export async function refreshTokenIfNeeded() {
  if (!oidcEnabled || !keycloak) {
    return;
  }
  try {
    await keycloak.updateToken(30);
  } catch {
    await keycloak.login();
  }
}

export function logout() {
  if (!oidcEnabled || !keycloak) {
    return;
  }
  keycloak.logout({ redirectUri: window.location.origin + window.location.pathname });
}
