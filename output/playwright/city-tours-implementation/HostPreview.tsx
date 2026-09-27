import React, { useState } from 'react';
import { MemoryRouter } from '../../../../solid-dataspace-manager/node_modules/react-router-dom';
import Sidebar from '../../../../solid-dataspace-manager/src/components/Sidebar';
import RouteAwareLayout from '../../../../solid-dataspace-manager/src/components/RouteAwareLayout';
import { I18nProvider } from '../../../../solid-dataspace-manager/src/i18n';
import '../../../../solid-dataspace-manager/src/index.css';
import '../../../../solid-dataspace-manager/src/App.css';
import App from '../../../../solid-tours/src/App';

export default function HostPreview() {
  const [collapsed, setCollapsed] = useState(false);
  return <I18nProvider language="de"><MemoryRouter initialEntries={['/web/city-tours']}>
    <RouteAwareLayout className={`layout${collapsed ? ' layout--sidebar-collapsed' : ''}`}>
      <Sidebar webId="" collapsed={collapsed} onToggle={() => setCollapsed(!collapsed)} />
      <div className="main"><div className="container"><div className="route-content">
        <div className="city-tours-embed"><div className="city-tours-header toolbar--title"><div className="crumb">City Tours</div><span className="integrated-version">Lokale UI-Prüfung</span></div>
          <App embedded language="de" />
        </div>
      </div></div><footer className="app-footer">Lokale Prüfung der Original-Hostkomponenten · ohne Anmeldung</footer></div>
    </RouteAwareLayout>
  </MemoryRouter></I18nProvider>;
}
