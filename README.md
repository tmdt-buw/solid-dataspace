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

The central worker aggregates separate download-event containers for the four deployed catalog
instances. With the default `STATISTICS_POD_BASE_URL`, the configured layout is:

| Catalog instance | Event container |
| --- | --- |
| Test | `events/catalog-instances/test/downloads/` |
| DACE | `events/catalog-instances/dace/downloads/` |
| Stadt Wuppertal | `events/catalog-instances/stadt-wuppertal/downloads/` |
| TimberConnect | `events/catalog-instances/timberconnect/downloads/` |

`STATISTICS_EVENT_SOURCES_JSON` supplies the worker with an `id`, display `label`, and absolute leaf
LDP-container `url` for each source. Leave it blank in the root `.env` to let Compose derive all four
URLs from `STATISTICS_POD_BASE_URL`; keep that base URL's trailing slash when overriding it. If the
JSON is set explicitly, update its absolute URLs whenever the Pod base URL changes.

Each catalog deployment must write both its embedded and standalone catalog events to the matching
container by setting `APP_STATISTICS_EVENTS_URL` on the Manager and `STATISTICS_EVENTS_URL` on the
standalone catalog frontend. This root stack represents the Test instance and defaults both clients
to its dedicated container; `STATISTICS_EVENTS_URL` overrides that default. The central worker is
the only worker required and needs read/write access to all four containers.
`STATISTICS_INCLUDE_LEGACY_EVENT_SOURCE=true` additionally reads the former `events/downloads/`
container during migration; set it to `false` after every catalog writes to its dedicated container
and all legacy events have passed the desired reporting window.

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

### Test server deployment below `/plasma`

`docker-compose.solid-dataspace-test.yml` is the complete Test-instance stack, including PLASMA. Deploy its content
as `/srv/solid-dataspace-test/docker-compose.yml`; no Compose overlay, `COMPOSE_FILE`, or `.env` is required. The
project name, PLASMA image tag, public manager URL, service aliases, and service configuration are fixed in the file.

Before its first start, replace the three `REPLACE_BEFORE_FIRST_START_*` password values near the top with different,
long random values. Because this intentionally keeps the credentials in the single Compose file, do not commit the
server copy and restrict it to the server administrator:

```shell
chmod 600 /srv/solid-dataspace-test/docker-compose.yml
cd /srv/solid-dataspace-test
docker compose config --quiet
docker compose pull
docker compose up -d
```

The central Caddy instance must add this route inside the existing Test-instance host block, before the manager
fallback:

```caddyfile
redir /plasma /plasma/ 308
route /plasma/* {
    uri strip_prefix /plasma

    @plasmaSms path /api/sms /api/sms/*
    reverse_proxy @plasmaSms solid-dataspace-test-plasma-sms:8181

    @plasmaDps path /api/dps /api/dps/*
    reverse_proxy @plasmaDps solid-dataspace-test-plasma-dps:8182

    reverse_proxy solid-dataspace-test-plasma-frontend:80
}
```

The manager image must include runtime support for `APP_PLASMA_URL`; setting a `REACT_APP_*` variable on an already
built React image does not change its bundle. Do not expose MariaDB, Fuseki, SMS, or DPS through host ports, and never
use `docker compose down -v` for an instance containing persistent PLASMA data.

## License

This repository is licensed under the Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Citation

If you use this repository, please cite it using the metadata in [CITATION.cff](CITATION.cff).

## Attribution

Developed by the Institute for Technologies and Management of Digital Transformation (TMDT), University of Wuppertal.
