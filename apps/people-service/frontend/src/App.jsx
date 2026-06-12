import { useEffect, useState } from 'react';
import {
  createPerson,
  deletePerson,
  fetchPeople,
  updatePerson,
} from './api.js';
import { isAuthEnabled, logout } from './auth.js';

const emptyForm = { firstName: '', lastName: '', age: '' };

export default function App({ auth }) {
  const [people, setPeople] = useState([]);
  const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  async function loadPeople() {
    setLoading(true);
    setError('');
    try {
      setPeople(await fetchPeople());
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadPeople();
  }, []);

  function startEdit(person) {
    setEditingId(person.id);
    setForm({
      firstName: person.firstName,
      lastName: person.lastName,
      age: String(person.age),
    });
  }

  function resetForm() {
    setEditingId(null);
    setForm(emptyForm);
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setError('');
    const payload = {
      firstName: form.firstName,
      lastName: form.lastName,
      age: Number(form.age),
    };

    try {
      if (editingId) {
        await updatePerson(editingId, payload);
      } else {
        await createPerson(payload);
      }
      resetForm();
      await loadPeople();
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleDelete(id) {
    setError('');
    try {
      await deletePerson(id);
      if (editingId === id) {
        resetForm();
      }
      await loadPeople();
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <main className="container">
      <header className="header-row">
        <div>
          <h1>People CRUD</h1>
          <p>Quarkus + PostgreSQL + React + Keycloak workshop demo</p>
        </div>
        {isAuthEnabled() && (
          <div className="auth-bar">
            <span>Signed in as {auth?.username}</span>
            <button type="button" className="secondary" onClick={logout}>
              Log out
            </button>
          </div>
        )}
      </header>

      {error && <p className="error">{error}</p>}

      <section className="card">
        <h2>{editingId ? 'Edit person' : 'Add person'}</h2>
        <form onSubmit={handleSubmit} className="form-grid">
          <label>
            First name
            <input
              value={form.firstName}
              onChange={(e) => setForm({ ...form, firstName: e.target.value })}
              required
            />
          </label>
          <label>
            Last name
            <input
              value={form.lastName}
              onChange={(e) => setForm({ ...form, lastName: e.target.value })}
              required
            />
          </label>
          <label>
            Age
            <input
              type="number"
              min="0"
              max="150"
              value={form.age}
              onChange={(e) => setForm({ ...form, age: e.target.value })}
              required
            />
          </label>
          <div className="actions">
            <button type="submit">{editingId ? 'Update' : 'Create'}</button>
            {editingId && (
              <button type="button" className="secondary" onClick={resetForm}>
                Cancel
              </button>
            )}
          </div>
        </form>
      </section>

      <section className="card">
        <h2>People</h2>
        {loading ? (
          <p>Loading...</p>
        ) : people.length === 0 ? (
          <p>No people yet. Add the first one above.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>First name</th>
                <th>Last name</th>
                <th>Age</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {people.map((person) => (
                <tr key={person.id}>
                  <td>{person.firstName}</td>
                  <td>{person.lastName}</td>
                  <td>{person.age}</td>
                  <td className="row-actions">
                    <button type="button" onClick={() => startEdit(person)}>
                      Edit
                    </button>
                    <button
                      type="button"
                      className="danger"
                      onClick={() => handleDelete(person.id)}
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </main>
  );
}
