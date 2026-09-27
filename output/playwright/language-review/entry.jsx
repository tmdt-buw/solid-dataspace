import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { I18nProvider as ManagerLanguage, applyDocumentTranslations as manager } from '../../../../solid-dataspace-manager/src/i18n';
import { I18nProvider as DataLanguage, applyDocumentTranslations as data } from '../../../../solid-data-manager/src/i18n';
import { applyDocumentTranslations as catalog } from '../../../../semantic-data-catalog/frontend/src/i18n';
import { applyDocumentTranslations as chatbot } from '../../../../solid-chatbot/frontend/src/i18n';
import { applyDocumentTranslations as health } from '../../../../solid-health-app/src/i18n';
import { applyDocumentTranslations as environmental } from '../../../../environmental-monitoring/src/i18n';
import DataManager from '../../../../solid-data-manager/src/components/DataManager';
import '../../../../solid-data-manager/src/App.css';

function Review() {
  const [language, setLanguage] = useState('de');
  const [check, setCheck] = useState('');
  const verify = () => {
    const names = () => Array.from(document.querySelectorAll('.file-name-text, #protected-name')).map(node => node.textContent);
    const before = names();
    for (const translate of [manager, data, catalog, chatbot, health, environmental]) translate(language);
    setCheck(JSON.stringify(before) === JSON.stringify(names()) ? 'Alle sechs Übersetzer lassen die Daten unverändert.' : 'Fehler: Ein Datenwert wurde übersetzt.');
  };
  return <ManagerLanguage language={language}>
    <header style={{ padding: 16, display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap' }}>
      <strong>Lokale Sprachprüfung mit fiktivem Pod</strong>
      <button onClick={() => setLanguage('de')}>Deutsch auswählen</button>
      <button onClick={() => setLanguage('en')}>Englisch auswählen</button>
      <button onClick={verify}>Übersetzungsschutz prüfen</button>
      <span>Settings</span>
      <span id="protected-name" translate="no">Settings · WebID · Pod Root · Sprache</span>
      <span role="status">{check}</span>
    </header>
    <DataLanguage language={language}><DataManager webId="http://127.0.0.1:4307/pod/profile/card#me" /></DataLanguage>
  </ManagerLanguage>;
}
createRoot(document.getElementById('root')).render(<Review />);
