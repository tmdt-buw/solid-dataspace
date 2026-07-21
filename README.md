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

## License

This repository is licensed under the Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Citation

If you use this repository, please cite it using the metadata in [CITATION.cff](CITATION.cff).

## Attribution

Developed by the Institute for Technologies and Management of Digital Transformation (TMDT), University of Wuppertal.
