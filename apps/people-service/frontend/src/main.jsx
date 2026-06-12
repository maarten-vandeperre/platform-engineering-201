import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.jsx';
import { initAuth } from './auth.js';
import './index.css';

async function bootstrap() {
  const root = ReactDOM.createRoot(document.getElementById('root'));

  try {
    const auth = await initAuth();
    root.render(
      <React.StrictMode>
        <App auth={auth} />
      </React.StrictMode>,
    );
  } catch (err) {
    root.render(
      <main className="container">
        <p className="error">Authentication failed: {err.message}</p>
      </main>,
    );
  }
}

bootstrap();
