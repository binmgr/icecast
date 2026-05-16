## Project description

`icecast` is a CI/CD build automation project for the **binmgr** organisation.
It fetches the upstream [Icecast](https://github.com/xiph/Icecast-Server) streaming-media
server source on every run and compiles it into **fully static Linux binaries** for
`amd64` and `arm64` — no shared libraries, no runtime dependencies, drop-and-run on any
Linux distribution.

Beyond the bare binary, the project also ships a **Docker runtime image** with a
config-generating entrypoint: all Icecast settings are driven by environment variables
(`ICECAST_*` / `STREAM_*`), making it a drop-in replacement for `libretime/icecast` and
compatible with `zerg13/ices` source clients.

## Project variables

```
project_name:     icecast
project_org:      binmgr
internal_name:    icecast
internal_org:     binmgr
upstream_repo:    https://github.com/xiph/Icecast-Server
upstream_license: GPL-2.0
registry:         ghcr.io
image:            ghcr.io/binmgr/icecast
build_image_tag:  build
```

## Business logic

### Artifacts produced

| Artifact | Description |
|----------|-------------|
| `icecast-linux-amd64` | Fully static Icecast binary for x86_64 Linux |
| `icecast-linux-arm64` | Fully static Icecast binary for aarch64 Linux |
| `SHA256SUMS.txt` | SHA-256 checksums of both binaries |
| `VERSION` | Upstream Icecast version string extracted from `configure.ac` |
| `ghcr.io/binmgr/icecast:build` | Reusable multi-arch Alpine build environment |
| `ghcr.io/binmgr/icecast:<version>` | Runtime image with entrypoint and web/admin UI |
| `ghcr.io/binmgr/icecast:<yymm>` | Same image tagged with year-month of the build |
| `ghcr.io/binmgr/icecast:latest` | Alias for the most recent version tag |

### Features compiled into every binary

All optional features enabled — no feature gating:

- Ogg Vorbis, Theora video, Speex codec streaming
- TLS/SSL via OpenSSL
- YP directory listing via libcurl
- XML/XSLT configuration via libxml2 + libxslt
- GeoIP lookups via libmaxminddb
- IPv6 support
- Web-based administration interface

### Dependency sourcing

| Library | Source |
|---------|--------|
| zlib, libogg, libvorbis, libtheora, OpenSSL, libcurl, libxml2, libxslt, libmaxminddb | Alpine Linux static packages (`*-static`) |
| Speex 1.2.1 | Source tarball from `downloads.xiph.org` |
| librhash 1.4.6 | Source tarball from `github.com/rhash/RHash` |
| libigloo | Git HEAD from `gitlab.xiph.org/xiph/icecast-libigloo` |
| Icecast | Git HEAD from `github.com/xiph/Icecast-Server` |

### Build environment image

`ghcr.io/binmgr/icecast:build` is a multi-arch Alpine image that:
- Pre-installs all Alpine static packages
- Pre-compiles Speex → librhash → libigloo (order is fixed; libigloo requires librhash)
- Embeds the `build-icecast [amd64|arm64]` script as the container entry point
- Is rebuilt quarterly (or on `docker/Dockerfile.build` change) and registry-cached

### Runtime image and entrypoint

`ghcr.io/binmgr/icecast:<version>` is a two-stage Alpine image:
- **Stage `assets`**: clones upstream to obtain the `web/` and `admin/` interface files
  (XSLT, HTML, JS) without compiling anything
- **Stage 2**: Alpine + bash + tini + tzdata; copies the static binary, web/admin
  files, and `docker/rootfs/` overlay; creates a non-root `icecast:icecast` user

At container start, `tini → entrypoint.sh → icecast`:
- `entrypoint.sh` reads `ICECAST_*` / `STREAM_*` env vars, XML-escapes all values,
  and writes `/etc/icecast/icecast.xml`
- Icecast logs go to stdout (captured by Docker json-file driver)

### Runtime environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ICECAST_HOSTNAME` | `localhost` | Server hostname in config and HTTP responses |
| `ICECAST_LOCATION` | `Earth` | Location string in directory listings |
| `ICECAST_ADMIN_USERNAME` | `admin` | Admin web UI username |
| `ICECAST_ADMIN_PASSWORD` | `changeme` | Admin web UI password |
| `ICECAST_ADMIN_EMAIL` | `{admin_user}@{hostname}` | Admin contact shown in listings |
| `ICECAST_SOURCE_PASSWORD` | `$STREAM_PASSWORD` → `changeme` | Source client auth |
| `ICECAST_RELAY_PASSWORD` | `$STREAM_PASSWORD` → `changeme` | Relay client auth |
| `ICECAST_MAX_CLIENTS` | `100` | Maximum simultaneous listeners |
| `ICECAST_MAX_SOURCES` | `2` | Maximum simultaneous source streams |
| `STREAM_PORT` | `8000` | TCP port Icecast listens on |
| `STREAM_PASSWORD` | *(none)* | Legacy fallback for source and relay passwords |
| `TZ` | system | Container timezone (tzdata) |

### Release flow

1. Build environment image is available (quarterly rebuild or on `docker/Dockerfile.build` change)
2. A container runs `build-icecast <arch>` natively for each target architecture
3. Binary is stripped, verified statically linked, written to `/output/` with `VERSION`
4. `SHA256SUMS.txt` is computed over both binaries
5. GitHub / Gitea release created (or re-created) as `v<VERSION>` with all artifacts
6. Runtime Docker image built via two-stage `docker/Dockerfile.runtime` and pushed to GHCR
   with tags `latest`, `<VERSION>`, `<YYMM>`

### CI platforms

| Platform | Triggers | Notes |
|----------|----------|-------|
| GitHub Actions | `workflow_run` (after env-image succeeds), monthly schedule, push to `docker/Dockerfile.runtime`, `workflow_dispatch` | Pushes images to GHCR; creates GitHub release via `gh` CLI |
| Gitea Actions | Monthly schedule, `workflow_dispatch` | Builds images locally; creates Gitea release via API; no GHCR push |

### Security posture

- No secrets stored in source; `GITHUB_TOKEN` / `GITEA_TOKEN` injected by CI runtime
- All upstream source fetched over HTTPS
- All third-party GitHub Actions pinned to full commit SHA — tags forbidden
- Automated secret scanning via truffleHog on every push and pull request
- Automated container vulnerability scanning via Trivy; critical/high CVE = build failure
- Dependabot automates weekly updates for GitHub Actions and Docker base images
- Registry images tagged by version and YYMM; `latest` is always an alias, never sole tag
- `SHA256SUMS.txt` in every release for end-user verification
- Runtime container runs as non-root `icecast:icecast` user
- No credentials baked into any image; all secrets injected at runtime via env vars
- `SECURITY.md` defines private vulnerability reporting; `CODEOWNERS` gates security-sensitive paths
