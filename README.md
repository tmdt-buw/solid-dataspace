# Solid Dataspace

Solid Dataspace brings independent Solid applications together behind one web interface. Users keep files, catalog metadata and application data in their Solid Pods. The Dataspace Manager supplies navigation, authentication, profiles and administration; the Data Connection Sync Worker runs configured imports and maintains derived public caches.

This repository contains orchestration, local development helpers, deployment profiles and coordinated release scripts. Start here to run the complete application environment. Individual application repositories document their standalone builds and APIs.

## Local quickstart

Install Docker with Compose **2.24.4 or newer**. Clone this repository, then run these commands from its root:

```sh
cp .env.local.example .env.local
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml pull
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml up -d
```

Open **http://localhost:8080**. On PowerShell, use `Copy-Item .env.local.example .env.local` for the first command. Use `localhost`, rather than a LAN address. `LOCAL_HTTP_PORT` changes the port.

This starts published application images, the access gateway and a local Sync Worker. PLASMA, the semantic-search backend/indexer/Fuseki and Node-RED are optional profiles. No GitHub NPM token is needed for this mode. The local mode does not create a Pod server, a Solid account, populated catalogs or existing import definitions. The server deployment controller and Admin Area backend are not included.

The [local development guide](LOCAL_DEVELOPMENT.md) covers all settings, optional services, verification, troubleshooting and stopping without deleting volumes. [`.env.local.example`](.env.local.example) is the appropriate starting point for a laptop; the root `.env.example` and server Compose files contain deployment-specific and legacy settings.

## Develop selected applications

Place checkouts of `solid-health-app`, `solid-city-tours` (directory name `solid-tours`) and `solid-data-connection-sync-worker` beside this repository, as described in the local guide. Override their paths with `HEALTH_SOURCE`, `CITY_TOURS_SOURCE` and `WORKER_SOURCE` when needed.

```sh
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml -f docker-compose.dev.yml up -d
```

Only Health App, City Tours and Worker dependencies/builds run locally; the remaining applications use published images. The Manager also receives the locally built Health App and City Tours embeds. `docker-compose.dev.yml` is an override, not a complete standalone Compose file. Checkouts and the selected Manager image must contain compatible embed-package versions.

## Worker identity, registry and data

For actual synchronization, use a separate test service identity and set:

```dotenv
LOCAL_ISSUER=https://your-solid-provider.example
SOLID_SYNC_WORKER_WEBID=https://your-solid-provider.example/test-worker/profile/card#me
SOLID_SYNC_WORKER_CLIENT_ID=
SOLID_SYNC_WORKER_CLIENT_SECRET=
```

Create the test account/Pod at your chosen provider, obtain client credentials for that same WebID through the provider's account interface, and grant only the intended Pod access through Data Connection. The [identity setup section](LOCAL_DEVELOPMENT.md#worker-mit-einem-test-pod-verwenden) explains the distinction between a browser login and worker credentials. Existing production credentials must not be copied into a developer environment. Some providers do not offer the server-to-server authentication flow used by the worker.

Without these credentials the UI can open, but worker synchronization cannot access protected Pod resources. Local request/encryption keys are generated in a dedicated Docker volume. Preserve that volume alongside the worker database when retaining local connections.

For catalog data, configure `LOCAL_REGISTRY_URL`. Enable local caching with `LOCAL_PUBLIC_CACHE_ENABLED=true` and matching `LOCAL_REGISTRIES_JSON`. Registry membership controls catalog discovery; Pod permissions still control access. A visible catalog entry does not grant access to its data. Urban Data Explorer currently has its own curated Stadt-Wuppertal selection and is not switched to another registry by this setting.

The local namespace is `test`, and the local worker starts with its own empty state. Newly created connections can write when explicitly enabled. This differs from the shared Test server, whose migrated automatic imports remain paused until deliberately activated for a controlled test.

## Applications and services

| Repository | Responsibility | Dataspace route |
| --- | --- | --- |
| [Solid Dataspace Manager](https://github.com/hoelk-f/solid-dataspace-manager) | Login, profiles, access requests/decisions, Data Connection, Admin Area | `/` |
| [Solid Data Manager](https://github.com/hoelk-f/solid-data-manager) | Pod files, folders, previews and sharing | `/solid-data-manager/`, Manager home `/` |
| [Semantic Data Catalog](https://github.com/hoelk-f/semantic-data-catalog) | Pod-based DCAT datasets, series, API descriptions and discovery | `/catalog/`, `/web/catalog` |
| [Urban Data Explorer](https://github.com/hoelk-f/urban-data-explorer) | Curated Wuppertal map layers and Python transformations | `/urban-data-explorer/`, `/web/urban-data-explorer` |
| [Health App](https://github.com/hoelk-f/solid-health-app) | Personal health metrics and Google Fit import interface | `/solid-health-app/`, `/web/solid-health-app` |
| [Health Questionnaire](https://github.com/hoelk-f/solid-health-questionnaire) | Questionnaire and private Pod persistence | `/solid-health-questionnaire/`, `/web/solid-health-questionnaire` |
| [City Tours](https://github.com/hoelk-f/solid-city-tours) | Activities, routes and controlled data donations | `/city-tours/`, `/web/city-tours` |
| [Data Connection Sync Worker](https://github.com/hoelk-f/solid-data-connection-sync-worker) | HTTP/REST, streams, provider imports, caches and public data queries | `/sync-worker/` |
| [PLASMA integration](https://github.com/hoelk-f/plasma) | Semantic modeling, with separate workspace storage | `/plasma/modelings` |

Routes depend on the selected deployment configuration and image versions. Legacy `environmental-monitoring` routes and service/configuration identifiers remain for compatibility. [repos.yaml](repos.yaml) is the repository mapping used by the release tools.

Pod documents are authoritative. Public metadata/data caches and Fuseki are derived views. The worker uses SQLite for operational state, schedules and histories of runs; the catalog is not stored in SQL. PLASMA separately uses MariaDB and Fuseki for its own modeling workspace.

## Optional services

Add `--profile plasma`, `--profile search` or `--profile node-red` to the same Compose command before `up -d`. Enable the PLASMA/Node-RED navigation entries with `LOCAL_PLASMA_ENABLED=true` or `LOCAL_NODERED_ENABLED=true`. The local guide lists image requirements and configuration; the three `son1i/plasma-*` images use the tag specified by `LOCAL_PLASMA_TAG`, not a presumed `latest` tag.

Semantic search indexes public DCAT metadata and linked semantic models in Fuseki. See the catalog's [semantic-search documentation](https://github.com/hoelk-f/semantic-data-catalog/blob/main/SEMANTIC_SEARCH.md). Public Pod data queries are a separate worker API, documented in [PUBLIC_DATA_API.md](https://github.com/hoelk-f/solid-data-connection-sync-worker/blob/main/PUBLIC_DATA_API.md). Neither service proxies private files to anonymous callers.

## Server topology and profiles

The managed deployment uses **one production stack** and **one live Test stack**. Stadt Wuppertal, DACE and TimberConnect are host-selected production profiles, not three separate copies of every app. Test 2 is retired; `test2` in old data or compatibility defaults is not an instruction to start another stack.

- [config/profiles](https://github.com/hoelk-f/solid-dataspace/tree/main/config/profiles) defines branding, domains, registry selection, visible/enabled applications and administrators.
- [config/apps.yaml](https://github.com/hoelk-f/solid-dataspace/blob/main/config/apps.yaml) defines the application catalog.
- The Manager's Admin Area edits supported profile settings through authenticated API/controller services. Its [administration guide](https://github.com/hoelk-f/solid-dataspace-manager/blob/main/admin-service/README.md) explains roles, activation and rollback.
- Each environment has its own worker/state. Production profile domains route to their production stack; Test routes to its own stack. Node-RED and PLASMA workspaces remain separate where configured.
- Server `docker-compose.prod.yml` and `docker-compose.test.yml` use operator-provisioned files, networks and secrets. They are not portable laptop quickstarts. The `server/` directory is excluded from releases.

Statistics are an optional part of the Admin Area. Configure event sources and registries for the active profiles, service-account permissions and an independent `STATISTICS_HMAC_SECRET` before enabling collection. Old event containers may be retained for history without running their former instances. Detailed statistics and donation contracts are in the worker README.

## Verification and releases

Validate local configuration without printing secrets or starting containers:

```sh
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml config --quiet
docker compose --env-file .env.local -f docker-compose.yml -f docker-compose.local.yml ps
```

Coordinate application releases using the existing scripts:

```powershell
.\versioning-update.ps1 -WhatIf
.\versioning-update.ps1 -IncludeUntracked
```

Review selected files before the real invocation; `-IncludeUntracked` includes intentional new files. The script updates embed-package pins, builds affected libraries and pushes coordinated changes, with the Manager last. Wait for the GitHub image/package workflows for those exact commits before running the server update scripts. Profile or routing changes also require the configuration activation path; changing an image alone does not regenerate Caddy routes.

Use the existing GitLab and TMDT-BUW synchronization scripts for the configured mirrors after the release succeeds. A documentation-only update does not require restarting applications. Keep secrets and operational backups out of commits. Preserve persistent volumes and keep shared Test imports paused during normal updates.

## License, citation and attribution

Licensed under Apache-2.0. See [LICENSE](LICENSE), [NOTICE](NOTICE) and [CITATION.cff](CITATION.cff). Individual applications and PLASMA retain their own licenses. Developed at the Institute for Technologies and Management of Digital Transformation (TMDT), University of Wuppertal.
