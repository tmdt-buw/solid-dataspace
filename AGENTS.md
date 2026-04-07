# Repository Guidance

## Core Context
- Read `repos.yaml` before making cross-repo assumptions.
- Do not create commits in `solid-dataspace` unless the requested change is limited to `docker-compose`, `Caddyfile`, or manifest files.

## Solid Reference Context
- For Solid-specific implementation work, use the documents in `solid/` as default background context for Tim Berners-Lee's Solid ecosystem.
- Load only the relevant files for the task instead of reading the whole folder every time.
- Prefer these references when designing or reviewing Solid protocol, server, auth, ACL, or architecture behavior:
  - `solid/protocol.md`
  - `solid/servers.md`
  - `solid/solid-oidc.md`
  - `solid/webacl.md`
  - `solid/solidos.md`
- Treat `solid/` as implementation guidance and conceptual background. Project code and official specs still take precedence when they conflict.
