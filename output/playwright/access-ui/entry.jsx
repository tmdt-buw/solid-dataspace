import React from 'react';
import { createRoot } from 'react-dom/client';
import Notifications from '../../../../solid-dataspace-manager/src/components/Notifications';
import DecisionInbox from '../../../../solid-dataspace-manager/src/components/DecisionInbox';
import { I18nProvider } from '../../../../solid-dataspace-manager/src/i18n';
import '../../../../solid-dataspace-manager/src/App.css';
import '../../../../solid-dataspace-manager/src/components/Sidebar.css';
import './fixture.css';
const params = new URLSearchParams(location.search);
const view = params.get('view') || 'requests';
const language = params.get('lang') || 'de';
function Review() {
  return <I18nProvider language={language}>
    <div className="fixture-bar" translate="no"><strong>Lokale UI-Prüfung · Beispieldaten</strong><a href="?view=requests">Requests</a><a href="?view=decisions">Decisions</a></div>
    <div className="layout">
      <aside className="sidebar fixture-nav" aria-label="Navigation">
        <div className="sb-brand"><strong>Solid Dataspace</strong></div>
        <div className="sb-section">General</div>
        <a className="sb-link" href="?view=requests">Solid Data Manager</a>
        <a className={'sb-link' + (view === 'requests' ? ' active' : '')} href="?view=requests">Access Requests</a>
        <a className={'sb-link' + (view === 'decisions' ? ' active' : '')} href="?view=decisions">Access Decisions</a>
      </aside>
      <div className="main"><main className="container"><div className="route-content">
        {view === 'decisions' ? <DecisionInbox webId="https://pod.example/alex/profile/card#me" /> : <Notifications webId="https://pod.example/alex/profile/card#me" />}
      </div></main></div>
    </div>
  </I18nProvider>;
}
createRoot(document.getElementById('root')).render(<Review />);
