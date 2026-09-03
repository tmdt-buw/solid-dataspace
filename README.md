# solid-dataspace

Orchestration and local infrastructure for the Solid dataspace development environment.

## Usage statistics

The statistics implementation remains database-free: human activity is stored in each user's
private Pod area, anonymous catalog events and aggregated snapshots are stored below the configured
`STATISTICS_POD_BASE_URL`, and the existing connection sync worker performs aggregation. Its SQLite
database remains limited to connection synchronization.

Use [`.env.example`](.env.example) as a reference and merge the missing settings into `.env`. Retain
the existing worker WebID and set fresh client credentials for that account.
`STATISTICS_HMAC_SECRET` is mandatory when statistics are enabled and must be an independent random
secret of at least 32 bytes. Set `STATISTICS_ENABLED=true` only after that secret and the existing
worker credentials are configured. Never commit `.env`.

The initial statistics administrator is configured as:

```text
https://solid-community-server.tmdt.info/solidtestpod/profile/card#me
```

Additional administrators are supplied through `STATISTICS_ADMIN_WEBIDS_JSON`. The same value is
passed to the Manager and worker. After signing in with an administrator WebID, open the statistics
dashboard and initialize the Pod structure once. This owner-authorized step grants the
existing worker identity access to the statistics subtree; no additional Solid account is created.

The dashboard route and navigation item are available only to configured administrators. Pod ACLs,
not the hidden navigation item, enforce access to snapshots. User WebIDs are HMAC-pseudonymized by
the worker before a snapshot is written.

Catalog tracking is enabled both for the Manager embed and the standalone catalog. It records only
successful dataset downloads and semantic-model downloads. Dataset access-link clicks, direct Pod
requests, and automatic previews are intentionally not counted.

These download figures are operational usage indicators, not audit or billing records: anonymous
events are accepted from any authenticated Solid agent and therefore cannot prove that an action
originated from an unmodified catalog client.

### Catalog event sources

The central worker aggregates separate download-event containers for the five deployed catalog
instances. With the default `STATISTICS_POD_BASE_URL`, the configured layout is:

| Catalog instance | Event container |
| --- | --- |
| Test | `events/catalog-instances/test/downloads/` |
| Test 2 | `events/catalog-instances/test2/downloads/` |
| DACE | `events/catalog-instances/dace/downloads/` |
| Stadt Wuppertal | `events/catalog-instances/stadt-wuppertal/downloads/` |
| TimberConnect | `events/catalog-instances/timberconnect/downloads/` |

`STATISTICS_EVENT_SOURCES_JSON` supplies the worker with an `id`, display `label`, and absolute leaf
LDP-container `url` for each source. Leave it blank in the root `.env` to let Compose derive all five
URLs from `STATISTICS_POD_BASE_URL`; keep that base URL's trailing slash when overriding it. If the
JSON is set explicitly, update its absolute URLs whenever the Pod base URL changes.

Each catalog deployment writes both its embedded and standalone catalog events to the matching
container. Compose derives `APP_STATISTICS_EVENTS_URL` and the catalog's `STATISTICS_EVENTS_URL`
from `STATISTICS_POD_BASE_URL` plus the resolved instance ID. An explicitly configured
`STATISTICS_EVENTS_URL` overrides that derived URL for both clients. The central worker is
the only worker required and needs read/write access to all five containers.
`STATISTICS_INCLUDE_LEGACY_EVENT_SOURCE=true` additionally reads the former `events/downloads/`
container during migration; set it to `false` after every catalog writes to its dedicated container
and all legacy events have passed the desired reporting window.

### Instance-scoped Environmental Monitoring

Set `DATASPACE_ID` to the catalog registry ID represented by each deployed stack, for example
`stadt-wuppertal`, `dace`, `timberconnect`, `test`, or `test2`. Compose passes the same resolved
value to the Manager as `APP_DATASPACE_ID` and to the catalog as `STATISTICS_REGISTRY_CONTEXT`.
The embedded Environmental Monitoring app therefore requests only that instance's aggregate
partition.

The shared worker's `WORKER_ALLOWED_ORIGINS` must contain the public origin of every instance.
For the root Compose stack, configure the equivalent `SOLID_SYNC_WORKER_ALLOWED_ORIGINS` value.
In particular, include `https://solid-dataspace-test2.tmdt.info`; otherwise browser requests from
Test 2 are rejected before they can register data for aggregation.

For compatibility, existing deployments may still supply `STATISTICS_REGISTRY_CONTEXT` or the
deprecated `ENVIRONMENTAL_SCENARIO_DATASPACE_ID`; the precedence is `DATASPACE_ID`, then
`STATISTICS_REGISTRY_CONTEXT`, then `ENVIRONMENTAL_SCENARIO_DATASPACE_ID`. This same value also
selects the event container. If none is configured, the derived event URL uses the isolated
`__unconfigured__` partition and the Manager does not fall back to the worker's combined
cross-instance aggregate.

## Local PLASMA integration

The development stack includes the sibling repository at `../plasma`. PLASMA is embedded through the existing
**PLASMA** navigation entry and is also available directly at
[http://localhost/plasma/modelings](http://localhost/plasma/modelings).

Build the two Java service images once from this repository:

```shell
mvn -f ../plasma/pom.xml -U -pl components/semantic-modeling-service/service,components/data-processing-service/service -am package jib:dockerBuild -DskipTests
```

If the standalone PLASMA stack is running, stop it without deleting its volumes. The integrated stack reuses the same
MariaDB and Fuseki volumes.

```shell
docker compose -f ../plasma/docker-compose.local.yml --profile staging down
docker compose -f docker-compose.dev.yml up -d --build
```

Caddy remains the only public reverse proxy. PLASMA is mounted below `/plasma`; its frontend calls
`/plasma/api/sms` and `/plasma/api/dps`, while Caddy removes the prefix before forwarding requests to the services.
The optional PLASMA recommendation service is not required for manual semantic modeling and is not started.

### Server deployment files

Instance-specific Compose and Caddy copies are operational server material and are intentionally excluded through
`server/` in `.gitignore`. They must not be added by the coordinated release script. Keep credentials only in the
server-side `.env` files and validate each deployment with `docker compose config --quiet` before restarting it.

Use `DATASPACE_ID` to distinguish `test`, `test2`, `dace`, `stadt-wuppertal`, and `timberconnect`; no source-code fork
is required per instance. The existing central Caddy configuration already routes all five instances and the shared
worker. PLASMA remains mounted below `/plasma` in those server deployments.

The manager image must include runtime support for `APP_PLASMA_URL`; setting a `REACT_APP_*` variable on an already
built React image does not change its bundle. Do not expose MariaDB, Fuseki, SMS, or DPS through host ports, and never
use `docker compose down -v` for an instance containing persistent PLASMA data.

## Coordinated releases

Preview every version change, build, selected file, and publish target without modifying any repository:

```powershell
.\versioning-update.ps1 -WhatIf
```

The release stops when untracked files exist. After reviewing the preview, explicitly include intentional new files
with `-IncludeUntracked`; this is currently required for newly added source files. The real invocation updates exact
embed-package pins, builds the affected libraries, commits the selected paths, and pushes the Manager last:

```powershell
.\versioning-update.ps1 -IncludeUntracked
```

Mirror the resulting `main` branches to GitLab only after the GitHub release push succeeds. Its dry run validates all
configured checkouts and the explicit Questionnaire and PLASMA GitLab remotes:

```powershell
.\gitlab-update.ps1 -WhatIf
.\gitlab-update.ps1
```

## License

This repository is licensed under the Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Citation

If you use this repository, please cite it using the metadata in [CITATION.cff](CITATION.cff).

## Attribution

Developed by the Institute for Technologies and Management of Digital Transformation (TMDT), University of Wuppertal.
