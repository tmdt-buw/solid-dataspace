import React from 'react';
import { createRoot } from 'react-dom/client';
import App from '../../../../solid-tours/src/App';
import CityToursOnboarding from '../../../../solid-tours/src/CityToursOnboarding';

const screen = new URLSearchParams(location.search).get('screen');
if (screen === 'login' || screen === 'onboarding') {
  await import('../../../../solid-tours/src/standalone.css');
}
createRoot(document.getElementById('root')!).render(
  screen === 'onboarding' ? (
    <div className="city-tours-app city-tours-app--onboarding city-tours-app--standalone">
      <CityToursOnboarding context="standalone" language="de" podRoot="https://example.test/demo/"
        registryOptions={[{ label: 'Beispiel-Registry', url: 'https://example.test/registry/' }]}
        configuredPublicRegistries={[]} infrastructureReady={false} profileReady={false}
        profilePublisher="" profileContactEmail="" busy={false} onComplete={() => {}} />
    </div>
  ) : screen === 'login' ? <App language="de" /> : <App embedded language="de" />
);
