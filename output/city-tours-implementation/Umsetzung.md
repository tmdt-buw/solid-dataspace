# City Tours: UI-/UX-Überarbeitung und Katalogkorrekturen

Stand: 26. September 2026. Die Änderungen liegen in den tatsächlichen Schwester-Repositories `solid-tours` und `solid-dataspace-manager`. Das Orchestrierungs-Repository enthält hier nur Analyse- und Prüfnachweise. Es wurden keine Commits, Veröffentlichungen oder Änderungen an produktiven Pod-Daten vorgenommen.

## Umgesetzt

| Bereich | Ergebnis |
| --- | --- |
| Katalogübernahme und Import | Ein unberührter neuer Entwurf blockiert den ersten Dateiimport und die erste Katalogübernahme nicht mehr. Tatsächliche Änderungen lösen eine Entscheidung zwischen Speichern, Verwerfen und Abbrechen aus. „Speichern und fortfahren“ setzt mit dem aktualisierten Zustand fort. |
| Katalogvorschau | Explizite, per Tastatur und Touch bedienbare Vorschau; sie bleibt beim Bewegen des Zeigers oder Fokus erhalten. Die Karte kennzeichnet und schließt die Vorschau gezielt. Übernommene Touren werden ausgewählt. |
| Katalogzustände | Suche, Distanzfilter, erneutes Laden, lokale Fehleranzeige und Hinweise zu teilweise fehlgeschlagenen oder begrenzten Ergebnissen. Eigene beziehungsweise bereits übernommene Touren werden von einem wirklich leeren Katalog unterschieden. Späte Antworten eines früheren Kontos oder Ladevorgangs ersetzen keine aktuellen Ergebnisse. |
| Bedeutung einer Übernahme | Die Oberfläche erklärt die private Kopie, die fehlende automatische Synchronisierung mit der Quelle und die fehlenden GPX-Zeitdaten einer Katalogvorlage. Die vorhandene Herkunftsreferenz bleibt erhalten. |
| Arbeitsbereich | Vier getrennte Bereiche: Meine Touren, Entdecken, Aktivitäten und Freigaben. Suche und Sortierung für eigene Touren. Die Abschlussaktion steht bei der ausgewählten Tour. |
| Mobile Nutzung | Umschaltung zwischen Liste und Karte bei begrenzter Breite; keine auf null zusammengedrückte Karte. Einklappbare Manager-Navigation auf Smartphones. Die pauschale Skalierung auf 70 Prozent entfällt. |
| Karteneditor | Sichtbarer erster Punkt sowie Start- und Endpunkt. Stabiler Ausschnitt beim Zeichnen, ausdrückliche Aktion „Route anzeigen“, Zeichenmodus mit Pause und Rückgängig einschließlich Wiederherstellung einer geleerten Route. Pfeiltasten bewegen die Karte; Enter setzt im Zeichenmodus einen Punkt in ihrer Mitte. |
| Schutz von Änderungen | Sichtbarer Speicherstatus, Entscheidung vor appinternem Entwurfswechsel, Import, Übernahme und eigenständigem Logout sowie Warnung bei Neuladen und Linknavigation. Während des Speicherns ist ein Tourwechsel gesperrt. |
| Aktivitäten | Datum, Heute/Gestern und explizite Auswahl zwischen Gehen und Radfahren im Abschlussdialog. Datumfehler am Feld. GPX-Zeitwerte und geschätzte Werte werden verständlich gekennzeichnet; Berechnungsannahmen sind vor dem Speichern sichtbar. |
| Dialoge und Tastatur | Gemeinsamer nativer modaler Dialog mit inaktivem Hintergrund einschließlich Manager, Fokusbegrenzung, Escape und Rückkehr zum Auslöser. Dateiimport über eine echte Schaltfläche. Sichtbare Fokuszustände. |
| Freigaben | Öffentliche Routenvorlagen und Datenspenden werden getrennt dargestellt. Vor einer Spende zeigt eine Vorschau die enthaltenen Aktivitäten und erläutert geschützte Daten, öffentliche Metadaten und die separate Zugriffsfreigabe. |
| Spendenstatus | Anzeige der im festen Snapshot enthaltenen und später hinzugekommenen Aktivitäten. Verweis auf `/notifications` zur Verwaltung von Anfragen. Keine unbelegte Behauptung über Zugriffserteilung oder Verarbeitung im Monitoring. Widerruf erläutert Aktualisierungsverzögerung und bereits heruntergeladene Kopien. |
| Einstieg | Private Einrichtung mit zwei Hinweisen ohne öffentliche Identität, Inbox-Provisionierung oder Registry-Registrierung. Öffentliches Teilen erhält einen eigenen Einrichtungsschritt. Bestehende Einrichtungsnachweise bleiben lesbar; neue private Nachweise verwenden Schema 3. |
| Gestaltung und Struktur | Bessere Lesbarkeit, größere Hauptaktionen, ruhigere Panels, deutsche Manager-Navigation. Karte, Katalog und Dialog sind als eigene Komponenten aus der Hauptkomponente herausgelöst. |

Die bisherige Prüfung von Berechtigungen, konkurrierenden Schreibvorgängen, Publikationszuständen und Rückabwicklung bleibt bestehen. Veröffentlichungen erfolgen weiterhin nur über ausdrückliche Aktionen.

## Prüfung

| Prüfung | Ergebnis |
| --- | --- |
| City Tours: vollständige Vitest-Suite | **315 von 315 Tests erfolgreich**, [JSON-Protokoll](final-city-tours-tests.json). |
| Manager: Navigation, RouteAwareLayout, Layoutkompatibilität und Sprache | **50 von 50 Tests erfolgreich** in vier Testsuiten, [JSON-Protokoll](final-manager-tests.json). |
| City Tours: `npm run build` | TypeScript-Prüfung, eigenständige App und Embed-Paket erfolgreich. |
| Manager: Produktionsbuild | Erfolgreich mit dem neu gebauten City-Tours-Paket. Verbleibende ESLint-Hinweise betreffen unveränderte Komponenten; beide Builds melden große JavaScript-Bundles. |
| Git | `git diff --check` in beiden geänderten Repositories erfolgreich. |
| Browser | Isolierter Edge-Browser, echte Komponenten und echte Leaflet-Karte; lokale Gastdaten mit der vorhandenen Beispieltour „Beyenburger Stausee Rundweg A2“. |
| Dialog im Manager | Nativer Modalzustand aktiv; 24 Tab-Schritte ohne Fokus außerhalb; Escape schließt und stellt den Fokus auf „Als absolviert eintragen“ zurück. |
| Einstieg | Login sowie private und öffentliche Einrichtung bei 320 und 1440 Pixeln ohne horizontales Überlaufen. Private Einrichtung: zwei Checkboxen, keine öffentlichen Identitätsfelder. |

Gemessene Manager-Kartenansicht bei 900 Pixeln Fensterhöhe:

| Fensterbreite | Kartenbreite | Horizontales Überlaufen | Überlappung geprüfter Kartensteuerungen |
| ---: | ---: | --- | --- |
| 320 px | 302 px | Nein | Nein |
| 390 px | 372 px | Nein | Nein |
| 768 px | 478 px | Nein | Nein |
| 1024 px | 734 px | Nein | Nein |
| 1440 px | 790 px | Nein | Nein |

Die Messung umfasst Legende, Routeninformationen und „Route anzeigen“. [Messprotokoll](../playwright/city-tours-implementation/layout-results.txt), [Smartphone](../playwright/city-tours-implementation/manager-map-320.png), [Desktop](../playwright/city-tours-implementation/manager-map-1440.png), [Abschlussdialog](../playwright/city-tours-implementation/manager-completion-desktop.png), [Privater Einstieg](../playwright/city-tours-implementation/onboarding-320.png).

Für die Integration wurden lokal veraltete installierte Pakete mit den bereits in den Projektdateien festgelegten Versionen abgeglichen: Catalog SDK 0.8.77 und City Tours 0.1.14. Dafür wurden vorhandene beziehungsweise neu erstellte lokale Builds verwendet. Paketversionen und Lockfiles wurden nicht geändert; es wurde nichts in eine Registry hochgeladen.

## Grenzen und Reproduktion

Die Solid-Speicher-, ACL-, Katalog- und Rückabwicklungsabläufe sind durch automatisierte Tests abgedeckt. Ein vollständiger Durchlauf mit realem Login, echten Pod-Schreibzugriffen, öffentlichem Katalogeintrag und Worker-Zugriffsanfrage wurde nicht durchgeführt. Auch eine vollständige Prüfung anderer eingebetteter Apps sowie aller Browser und assistiven Technologien steht aus. Die Größen- und bestehenden Buildwarnungen sind keine abgeschlossene Performanceoptimierung.

Ortsuche und Routingdienst waren in der Analyse als spätere Erweiterungen eingeordnet. Ebenso wurden kein automatisches Speichern öffentlich geteilter Touren und kein vollständiger Umbau aller Dataspace-Anwendungen ergänzt.

Die lokale Prüfhülle verwendet direkt die Originaldateien. Start aus dem Orchestrierungs-Repository:

```powershell
node output/playwright/city-tours-implementation/server.mjs
```

Unter `http://127.0.0.1:4306/` stehen die Gastansicht und die Varianten `?screen=host`, `?screen=login`, `?screen=onboarding` und `?screen=sharing-setup` bereit. Die beiden Einrichtungsvarianten verwenden fiktive Daten und speichern nichts. `measure.cjs`, `focus.cjs` und `entry-checks.cjs` dokumentieren die Browserprüfungen.

Quellcode: [City Tours](C:/Users/hoelk/source/repos/solid-dataspace/solid-tours/src/App.tsx), [Katalog](C:/Users/hoelk/source/repos/solid-dataspace/solid-tours/src/RouteCatalog.tsx), [Karte](C:/Users/hoelk/source/repos/solid-dataspace/solid-tours/src/TourMap.tsx), [Dialog](C:/Users/hoelk/source/repos/solid-dataspace/solid-tours/src/Modal.tsx), [Manager-Navigation](C:/Users/hoelk/source/repos/solid-dataspace/solid-dataspace-manager/src/components/Sidebar.jsx). Die aktualisierte [City-Tours-Dokumentation](C:/Users/hoelk/source/repos/solid-dataspace/solid-tours/README.md) beschreibt das Verhalten und nennt die verwendeten offiziellen Referenzen.
