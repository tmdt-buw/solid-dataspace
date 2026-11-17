# Lokale Entwicklung: Health App, City Tours und Sync-Worker

Dieser Modus startet veröffentlichte Docker-Images und aktiviert lokale Entwicklung
gezielt für die Health App, City Tours und den Data-Connection-Sync-Worker. Die
eingebetteten Ansichten von Health App und City Tours im Dataspace Manager
übernehmen ebenfalls die lokalen Builds. Andere Apps
werden nicht lokal installiert oder gebaut. Ein GitHub-NPM-Token ist dafür nicht nötig.

## Voraussetzungen

- Docker mit **Compose ab 2.24.4** (`docker compose version`).
- Aktuelle Checkouts dieser Repositories nebeneinander:

```text
repos/
  solid-dataspace/
  solid-health-app/
  solid-tours/
  solid-data-connection-sync-worker/
```

Manager und Gateway verwenden veröffentlichte Images. Ein Manager-Checkout ist
nicht nötig. Der lokale Login leitet direkt zum Solid-Anbieter weiter; der
produktive Kontodialog mit Server-Handoff wird hier nicht verwendet.
Abweichende Quellcode-Ordner lassen sich über `HEALTH_SOURCE`, `CITY_TOURS_SOURCE` und `WORKER_SOURCE`
einstellen. Pfade sind relativ zu `solid-dataspace` oder absolut.
Unter Windows funktionieren Pfade mit `/`.

Bei einem bereits vorhandenen lokalen Dev-Stack diesen zuerst mit genau seiner
bisherigen Compose-Konfiguration stoppen. Keine Volumes löschen. Niemals die
folgenden lokalen Befehle gegen einen bestehenden Server-Projektnamen ausführen.

## Einmal einrichten

Im Repository `solid-dataspace` `.env.local.example` nach `.env.local` kopieren.
Die Datei ist von Git ausgeschlossen. Unter PowerShell:

```powershell
Copy-Item .env.local.example .env.local
```

Unter Linux/macOS:

```sh
cp .env.local.example .env.local
```

Für die Oberfläche sowie Health-App- und City-Tours-Entwicklung genügen die Standardwerte. Öffnen:
**http://localhost:8080**. Immer `localhost` verwenden, nicht die IP-Adresse.
Der Port lässt sich mit `LOCAL_HTTP_PORT` ändern. Die Portfreigabe bindet nur an
`127.0.0.1`, nicht an das lokale Netzwerk.

## Starten

Nur veröffentlichte Apps, ohne lokale Codeänderungen:

```sh
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml pull
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml up -d
```

Health App, City Tours und Worker lokal entwickeln, andere Apps als fertige Images:

```sh
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml -f docker-compose.dev.yml up -d
```

`docker-compose.dev.yml` ist jetzt eine **Ergänzung** und wird mit beiden Basisdateien
verwendet. Nicht mehr allein mit `-f docker-compose.dev.yml` starten.
`--build` ist für diesen Modus nicht nötig.

Die erste Installation der Health-, City-Tours- und Worker-Abhängigkeiten braucht Zeit. Sie
bleiben in eigenen Volumes und werden erst bei geändertem `package.json`, Lockfile
oder Node-Laufzeit neu installiert. Der Manager verwendet die schon im Image
vorhandenen Abhängigkeiten. Er startet, sobald der erste lokale Health-Build bereit
ist und City Tours seinen ersten Embed-Build bereitstellt. Caddy und die übrigen
Apps müssen darauf nicht warten.

- Health App integriert: `/web/solid-health-app`
- Health App eigenständig: `/solid-health-app/`
- City Tours integriert: `/web/city-tours`
- City Tours eigenständig: `/city-tours/`
- Data Connection: `/data-connection`
- Katalog: `/catalog/`
- Worker-Status: `/sync-worker/health`

Änderungen am Health- oder City-Tours-Quellcode bauen das jeweilige Embed-Paket neu. Der Manager übernimmt das
Paket und startet seinen Entwicklungsserver neu; das kann einige Sekunden dauern.
Die eigenständigen Ansichten nutzen ihre eigenen Entwicklungsserver. City Tours
prüft Dateiänderungen auch auf Docker-Desktop-Laufwerken regelmäßig. Der Worker
startet bei Änderungen seiner geladenen JavaScript-Dateien automatisch neu.
Das Katalog-Paket für City Tours wird einmalig aus dem ausgewählten Manager-Image
in ein eigenes lokales Volume übernommen. Es muss nicht aus GitHub Packages geladen
oder aus dem Katalog-Quellcode gebaut werden. Die Paketversion muss zum Lockfile
von City Tours passen. Bei einer Versionsabweichung zeigt der Start die erwartete
und vorhandene Version; Checkouts und Manager-Image gemeinsam aktualisieren.
Die Installation verändert weder `package.json` noch `package-lock.json` im Checkout.

Nach Änderungen an Abhängigkeiten die betroffenen Container neu starten. Während
Entwicklungsserver neu kompilieren, kann kurz eine Lade- oder Proxy-Meldung erscheinen.

## Worker mit einem Test-Pod verwenden

Für tatsächliche Synchronisation in `.env.local` ergänzen:

```dotenv
LOCAL_ISSUER=https://solid-community-server.tmdt.info
SOLID_SYNC_WORKER_WEBID=https://YOUR-PROVIDER/YOUR-TEST-WORKER/profile/card#me
SOLID_SYNC_WORKER_CLIENT_ID=YOUR-CLIENT-ID
SOLID_SYNC_WORKER_CLIENT_SECRET=YOUR-CLIENT-SECRET
```

Die Testidentität wird beim Solid-Anbieter angelegt, nicht in Docker Compose:

1. Beim gewünschten Anbieter ein eigenes Testkonto mit Pod erstellen und dessen WebID aus dem Profil übernehmen. Die WebID ist nicht zwingend aus der Storage-Adresse ableitbar.
2. In der Kontoverwaltung des Anbieters Client-Zugangsdaten für genau diese WebID erstellen. Bei Community Solid Server erfolgt dies über dessen Kontoverwaltung; Bezeichnung und Verfügbarkeit hängen von der Serverversion ab. Anbieter ohne den unterstützten Dienstzugang können nicht allein durch Eintragen eines Browser-Passworts verwendet werden.
3. Client-ID und Client-Secret ausschließlich in der lokalen, nicht versionierten `.env.local` speichern. Ein Browser-Passwort, Google-OAuth-Zugang oder NPM-Token ersetzt diese Werte nicht.
4. Im lokal gestarteten Dataspace mit dem Eigentümer des Test-Pods anmelden und Data Connection einrichten. Nur die benötigten Verbindungs- und Zielordner für die konfigurierte Worker-WebID freigeben. Bei Importvorlagen deren gesonderte Pod-Zugangsdaten und den erfolgreichen Vorschautest beachten.
5. Zuerst eine einzelne Verbindung mit synthetischen Daten und eigenem Testziel prüfen. Erst danach deren automatische Ausführung einschalten. Gemeinsame Server-Testimporte bleiben dadurch unverändert.

Issuer, WebID und Client-Zugangsdaten müssen zur eigenen Solid-Testidentität passen.
Die Anwendung lokal zu starten erzeugt keinen lokalen Pod. Die Browser-Anmeldung
und der Worker greifen auf den gewählten externen Test-Pod zu. Die notwendigen
Pod-Rechte werden wie üblich in Data Connection eingerichtet. Ohne Worker-Zugang
bleibt die UI benutzbar; Synchronisation kann dann noch keine Pod-Daten schreiben.

Der lokale Modus setzt `DATASPACE_ID=test` und `WORKER_CONNECTION_NAMESPACE=test`
passend zusammen. Eigene Test-Pods verwenden: derselbe Namensraum allein trennt
zwei Entwickler nicht, wenn sie denselben Pod benutzen. Bestehende Server-Imports
werden nicht übernommen. Die lokale Datenbank startet leer. Statistik- und
Umweltszenario-Jobs bleiben deaktiviert. Neu eingerichtete lokale Verbindungen
können nach ihrer Aktivierung in den ausgewählten Test-Pod schreiben.

Zwei zufällige Schlüssel werden einmalig im projektbezogenen `local_secrets`-Volume
erzeugt: für Worker-Anfragen und für gespeicherte Zugangsdaten. Bei Neustarts bleiben
sie erhalten. Die Signaturprüfung und Solid-Anmeldung sind auch lokal aktiv.
`LOCAL_ADMIN_WEBIDS_JSON` kann die eigene Test-WebID für lokale Importvorlagen
berechtigen, z.B. `["https://provider.example/alice/profile/card#me"]`.
Die Server-Admin-Area samt Deployment-Controller ist nicht Teil dieses lokalen Modus.

## PLASMA und weitere Dienste zuschalten

Für PLASMA sind weder ein zusätzlicher Quellcode-Checkout noch Java-Builds nötig.
Konfigurationen und hochgeladene Ontologien erhalten eigene lokale Volumes.
In `.env.local` `LOCAL_PLASMA_ENABLED=true` setzen und starten:

```sh
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml -f docker-compose.dev.yml --profile plasma up -d
```

PLASMA ist danach unter `/plasma/modelings` und im Manager erreichbar. Vorher normal
mit Solid anmelden. Die veröffentlichten `son1i/plasma-*`-Images verwenden den
existierenden Tag `sha-7ae77d7baab4`, nicht `latest` oder `1.8.1`.
Sie sind derzeit für amd64 gebaut; auf ARM-Rechnern ist Emulation erforderlich.
MariaDB, Fuseki und PLASMA-Speicher liegen in eigenen lokalen Volumes.

Auf einem Laptop mit 8 GB RAM PLASMA nur zuschalten, wenn es für den Test benötigt
wird. Fertige Images vermeiden Builds, reduzieren aber nicht den gesamten
Arbeitsspeicherbedarf der laufenden Dienste.

Weitere optionale Profile:

- `--profile search`: Katalog-Backend, Indexer und Fuseki für semantische Suche.
- `--profile node-red`: Node-RED; zusätzlich `LOCAL_NODERED_ENABLED=true` setzen.

Profile lassen sich kombinieren. Die Navigationseinstellung allein startet keinen
Container. Um einen optionalen Dienst wieder abzuschalten, ihn mit derselben
Profilkonfiguration gezielt stoppen oder den lokalen Stack herunterfahren.

## Lokaler Katalog und Cache

Für öffentliche Katalogdaten `LOCAL_REGISTRY_URL` auf die gewünschte Registry setzen.
Um deren öffentliche Metadaten lokal zu cachen, zusätzlich:

```dotenv
LOCAL_PUBLIC_CACHE_ENABLED=true
LOCAL_REGISTRIES_JSON=[{"id":"test","label":"Local development","url":"https://YOUR-POD/public/registry/"}]
```

Die URL muss mit `LOCAL_REGISTRY_URL` übereinstimmen. Ohne konfigurierte Registry
werden keine Server-Registries im lokalen Worker automatisch gecacht.
Die Runtime-Konfiguration wird lokal unter `/config.js` und
`/semantic-data-catalog/env.js` bereitgestellt. Für semantische Suche zusätzlich das
Profil `search` einschalten. Es werden nur öffentliche Metadaten indexiert.

## Prüfen, stoppen und Fehler finden

```sh
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml -f docker-compose.dev.yml config --quiet
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml -f docker-compose.dev.yml ps
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml -f docker-compose.dev.yml logs --tail 100 solid-health-app city-tours local-catalog-package solid-dataspace-manager solid-data-connection-sync-worker access-gateway
```

`config --quiet` prüft ohne Ausgabe von Zugangsdaten. Für Angaben zur RAM-Auslastung
`docker stats` verwenden. `unhealthy` nach einer langen Erstinstallation anhand der
Logs prüfen; fehlgeschlagene npm-Downloads und Speichermangel sind unterschiedliche
Ursachen. Die Health-App- und City-Tours-Checks geben der ersten Installation bis zu 20 Minuten Zeit.

Stoppen, ohne Daten oder Schlüssel zu löschen:

```sh
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml -f docker-compose.dev.yml --profile plasma --profile search --profile node-red down
```

**Kein `down -v` verwenden**, wenn lokale Verbindungen, Schlüssel oder PLASMA-Daten
behalten werden sollen. Standard-Projektname ist `solid-dataspace-local`. Für eine
zweite lokale Umgebung einen anderen `-p`-Namen und HTTP-Port verwenden.

Zum Aktualisieren der Konfiguration das Repository `solid-dataspace` aktualisieren.
Manager und Gateway benötigen mindestens den Stand 0.4.17; für City Tours muss
der Manager zusätzlich die Katalog-Version des aktuellen City-Tours-Checkouts enthalten.
Images mit `pull` aktualisieren und danach
mit denselben Compose-Dateien wieder `up -d` ausführen. Für reproduzierbare Tests
lassen sich Manager, Worker und Gateway über `LOCAL_MANAGER_IMAGE`,
`LOCAL_WORKER_IMAGE` und `LOCAL_GATEWAY_IMAGE` auf einen bestimmten Digest festlegen.

## Meldung „This login origin is not allowed“

Diese Meldung kommt von der zusätzlichen Server-Anmeldeweiterleitung. Sie akzeptiert
nur die freigegebenen Dataspace-Serveradressen. Lokal soll die normale OIDC-Anmeldung
beim Solid-Anbieter verwendet werden; dazu wird keine Freigabe von `localhost` auf
dem produktiven Pod-Server benötigt.

Die Umgebung mit allen drei oben genannten Compose-Dateien öffnen, über
`http://localhost:8080` beziehungsweise den eingestellten `LOCAL_HTTP_PORT`.
Unter `/config.js` muss `loginMode: "oidc"` gesetzt sein. Fehlt dieser Eintrag,
wird vermutlich eine andere Compose-Konfiguration oder der Manager direkt geöffnet.
Ein aktuelles Manager-Image verwendet auf Loopback-Adressen zusätzlich unabhängig
von dieser Einstellung den Provider-Login. Bereits lokal gespeicherte Images werden
nicht allein durch `up -d` aktualisiert: vorher `pull` mit denselben Compose-Dateien
aufrufen und anschließend den Browser neu laden.
