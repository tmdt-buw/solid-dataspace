# UI/UX- und Sprachänderungen

Abgeschlossen am 26.09.2026. Die Änderungen wurden in den jeweiligen Quell-Repositories auf `main` lokal committed. Es wurde nichts gepusht oder veröffentlicht.

| Repository | `solid city tours ui / ux improvements` | `language improvements` |
| --- | --- | --- |
| solid-tours | `65f944f` | `73b1c23` |
| solid-dataspace-manager | `c3a21e5` | `a04a1de` |
| solid-data-manager | — | `491a306` |
| semantic-data-catalog | — | `95aa969` |
| solid-chatbot | — | `68e33a1` |
| solid-health-app | — | `1a9edd2` |
| environmental-monitoring | — | `b10bedf` |
| solid-health-questionnaire | — | `aed3c75` |

Die Sprachänderungen umfassen 45 Quell-, Test- und Dokumentationsdateien sowie vier bereits versionierte Katalog-Builddateien. Vollständige Commit-IDs und Dateilisten stehen in [commits.json](commits.json). Das Orchestrierungs-Repository `solid-dataspace` erhielt entsprechend seiner Repository-Vorgaben keinen Commit; die Prüfartefakte bleiben hier lokal.

## Verhalten

- **Pod Root**, **WebID**, **Inbox** und **Solid Data Manager** bleiben als technische Begriffe beziehungsweise App-Name erkennbar. Falsche Umlautkodierungen und unnatürliche deutsche Formulierungen wurden korrigiert.
- Datei- und Ordnernamen bleiben exakt erhalten: `settings`, `Settings`, `Profile` und `Sprache` werden auch beim Wechsel Deutsch → Englisch → Deutsch nicht verändert. Das Menü **Settings** darf weiterhin **Einstellungen** heißen.
- Ebenso geschützt sind Katalogtitel, Beschreibungen, RDF-Ergebnisse, Namen von Personen und Datenquellen, Sensornamen, Pfade und frei eingegebene Nachrichten. Die sechs DOM-Übersetzer berücksichtigen die Daten-Grenzen auch bei eingebundenen Apps.
- City Tours und Gesundheitsfragebogen behalten ihre eigene explizite Sprachsteuerung. Der Manager überschreibt ihre Inhalte nicht mehr durch seine zusätzliche DOM-Übersetzung.
- Aktionen, Tabellenüberschriften, Zugriffsstatus und Hinweise bei fehlenden Daten bleiben übersetzbar. Gespeicherte Pod-Ressourcen wurden weder umbenannt noch migriert.
- Die Grundsätze für weitere Texte sind in `solid-dataspace-manager/docs/localization.md` festgehalten. In PLASMA und im Sync-Worker waren keine entsprechenden Anpassungen an einer deutschen Oberfläche erforderlich.

## Prüfung

| Bereich | Bestandene Tests | Build |
| --- | ---: | --- |
| City Tours | 315 | TypeScript, App und Embed |
| Dataspace Manager | 37 | Produktionsbuild mit allen sechs aktualisierten lokalen Einbettungen |
| Data Manager | 21 | Embed |
| Semantic Data Catalog | 7 | Embed und Catalog-API |
| Chatbot-Frontend | 7 | Embed |
| Health App | 6 | Embed |
| Environmental Monitoring | 47 | TypeScript und App |
| Gesundheitsfragebogen | 74 | TypeScript, App, Embed und Typdeklarationen |
| **Gesamt** | **514** | **Alle erfolgreich** |

Die Tests prüfen unter anderem unveränderte Ressourcennamen, Original-URLs bei der Ordnernavigation, unveränderte RDF-Literale und IRIs sowie übersetzbare Leerzustände im Katalog. Die vollständigen City-Tours-, Fragebogen- und Umwelt-Testläufe sowie gezielte Tests der übrigen Apps wurden ausgeführt.

Die Browserprüfung lief in Edge mit dem echten Data-Manager-Quellcode und einem lokalen fiktiven Pod. Geprüft wurden Ordnernavigation, Deutsch → Englisch → Deutsch und alle sechs Übersetzer gegen dieselben Daten. Der Test-Pod erlaubte nur GET und HEAD. Es wurden keine echten Benutzer-Pods verändert. [Screenshot](../playwright/language-review/de-root.png).

Der Manager-Build enthält weiterhin die zuvor vorhandenen Hinweise zu Hook-Abhängigkeiten, einer unbenutzten Funktion und Bundle-Größe. Weitere bestehende Buildhinweise betreffen Browserslist, die Buffer-Auflösung und große Vite-Chunks. Es gab keine Buildfehler. [Manager-Buildprotokoll](manager-build.log).

Alle acht betroffenen Quell-Repositories sind nach den Commits sauber. Lokale Browser- und Testserver wurden beendet.
