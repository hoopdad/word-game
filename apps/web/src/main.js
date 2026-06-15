import { getActiveAccount, isAuthenticated, login, logout, safeInitializeAuth } from './auth/client';
import { resolveRoute } from './router';
import packageJson from '../package.json';
import './styles.css';

const app = document.querySelector('#app');
const APP_VERSION = packageJson.version;

function renderLanding(blocked = false) {
  document.title = `Word Game v${APP_VERSION}`;
  app.innerHTML = `
    <main>
      <h1>Word Game <span class="version">v${APP_VERSION}</span></h1>
      <p>Public landing page for external users.</p>
      ${blocked ? '<p class="warning">Please sign in to access the app.</p>' : ''}
      <div class="actions">
        <button id="login">Login / Sign up</button>
        <a data-link href="/app">Open app</a>
      </div>
    </main>
  `;

  document.querySelector('#login')?.addEventListener('click', () => {
    login();
  });
}

function renderProtected() {
  const account = getActiveAccount();
  document.title = `Word Game v${APP_VERSION}`;

  app.innerHTML = `
    <main>
      <h1>Word Game App <span class="version">v${APP_VERSION}</span></h1>
      <p>Authenticated route.</p>
      <p>Signed in as: ${account?.username || 'unknown'}</p>
      <div class="actions">
        <a data-link href="/">Back to landing</a>
        <button id="logout">Logout</button>
      </div>
    </main>
  `;

  document.querySelector('#logout')?.addEventListener('click', () => {
    logout();
  });
}

function navigate(path) {
  window.history.pushState({}, '', path);
  render();
}

function setupNavigation() {
  document.addEventListener('click', (event) => {
    const link = event.target.closest('[data-link]');
    if (!link) {
      return;
    }

    event.preventDefault();
    navigate(link.getAttribute('href'));
  });

  window.addEventListener('popstate', () => {
    render();
  });
}

function render() {
  const match = resolveRoute(window.location.pathname, isAuthenticated());

  if (match.type === 'blocked') {
    window.history.replaceState({}, '', match.redirectTo);
    renderLanding(true);
    return;
  }

  if (match.type === 'protected') {
    renderProtected();
    return;
  }

  if (match.redirectTo) {
    window.history.replaceState({}, '', match.redirectTo);
  }

  renderLanding(false);
}

async function bootstrap() {
  await safeInitializeAuth();
  setupNavigation();
  render();
}

bootstrap();
