import React from 'react';
import { createRoot } from 'react-dom/client';
import App from '../../../../solid-tours/src/App';
import CityToursOnboarding from '../../../../solid-tours/src/CityToursOnboarding';

const screen = new URLSearchParams(location.search).get('screen');
const HostPreview = screen === 'host' ? (await import('./HostPreview')).default : null;
if (screen === 'login' || screen === 'onboarding' || screen === 'sharing-setup') {
  await import('../../../../solid-tours/src/standalone.css');
}
createRoot(document.getElementById('root')!).render(
  HostPreview ? <HostPreview /> : screen === 'onboarding' || screen === 'sharing-setup' ? (
    <div className="city-tours-app city-tours-app--onboarding city-tours-app--standalone">
      <CityToursOnboarding context="standalone" mode={screen === 'sharing-setup' ? 'publishing' : 'private'} language="de" podRoot="https://example.test/demo/"
        registryOptions={[{ label: 'Beispiel-Registry', url: 'https://example.test/registry/' }]}
        configuredPublicRegistries={[]} infrastructureReady={false} profileReady={false}
        profilePublisher="" profileContactEmail="" busy={false} onComplete={() => {}} />
    </div>
  ) : screen === 'login' ? <App language="de" /> : <App embedded language="de" />
);
