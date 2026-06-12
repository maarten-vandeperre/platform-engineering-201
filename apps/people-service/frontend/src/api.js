import { getAccessToken, isAuthEnabled, refreshTokenIfNeeded } from './auth.js';

const API_BASE = import.meta.env.VITE_API_BASE || '';

async function authHeaders(extra = {}) {
  const headers = { ...extra };
  if (isAuthEnabled()) {
    await refreshTokenIfNeeded();
    const token = getAccessToken();
    if (token) {
      headers.Authorization = `Bearer ${token}`;
    }
  }
  return headers;
}

async function handleResponse(response, action) {
  if (response.status === 401 || response.status === 403) {
    throw new Error('Not authorized. Sign in with a user that has people-crud permissions.');
  }
  if (!response.ok) {
    throw new Error(`Failed to ${action}`);
  }
  if (response.status === 204) {
    return null;
  }
  return response.json();
}

export async function fetchPeople() {
  const response = await fetch(`${API_BASE}/api/people`, {
    headers: await authHeaders(),
  });
  return handleResponse(response, 'load people');
}

export async function createPerson(person) {
  const response = await fetch(`${API_BASE}/api/people`, {
    method: 'POST',
    headers: await authHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(person),
  });
  return handleResponse(response, 'create person');
}

export async function updatePerson(id, person) {
  const response = await fetch(`${API_BASE}/api/people/${id}`, {
    method: 'PUT',
    headers: await authHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(person),
  });
  return handleResponse(response, 'update person');
}

export async function deletePerson(id) {
  const response = await fetch(`${API_BASE}/api/people/${id}`, {
    method: 'DELETE',
    headers: await authHeaders(),
  });
  return handleResponse(response, 'delete person');
}
