## Project description

`{project_name}` is a CI/CD build automation project for the **binmgr** organisation.
It fetches the upstream [Icecast](https://github.com/xiph/Icecast-Server) streaming-media
server source on every run and compiles it into **fully static Linux binaries** for
`amd64` and `arm64` — no shared libraries, no runtime dependencies, drop-and-run on any
Linux distribution.

The project ships nothing of its own logic. Its value is reproducibility, provenance, and
convenience: a single GitHub / Gitea release holds checksummed binaries and a matching
multi-arch Docker image so operators can use Icecast without touching a package manager.

## Project variables

```
project_name:   icecast
project_org:    binmgr
internal_name:  icecast
internal_org:   binmgr
upstream_repo:  https://github.com/xiph/Icecast-Server
upstream_license: GPL-2.0
registry:       ghcr.io
image:          ghcr.io/binmgr/icecast
build_image_tag: build
```

## Business logic

### What is produced

| Artifact | Description |
|----------|-------------|
| `icecast-linux-amd64` | Fully static Icecast binary for x86_64 Linux |
| `icecast-linux-arm64` | Fully static Icecast binary for aarch64 Linux |
| `SHA256SUMS.txt` | SHA-256 checksums of both binaries |
| `VERSION` | Upstream Icecast version string (e.g. `2.5.0`) |
| `ghcr.io/binmgr/icecast:build` | Reusable Alpine build environment (multi-arch, `docker/Dockerfile.build`) |
| `ghcr.io/binmgr/icecast:<version>` | Runtime image embedding the static binary |
| `ghcr.io/binmgr/icecast:<yymm>` | Same image tagged with year-month of the build |
| `ghcr.io/binmgr/icecast:latest` | Alias for the most recent version tag |

### Features compiled into every binary

All optional Icecast features are enabled — no feature gating:

- Ogg Vorbis, Theora video, Speex codec support
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
| Speex | Source tarball from `downloads.xiph.org` |
| librhash | Source tarball from `github.com/rhash/RHash` |
| libigloo | Git clone from `gitlab.xiph.org/xiph/icecast-libigloo` |
| Icecast | Git clone (latest `main`) from `github.com/xiph/Icecast-Server` |

### Build environment image

`ghcr.io/binmgr/icecast:build` is a **reusable, multi-arch Alpine image** that:
- Pre-installs all Alpine static packages
- Pre-compiles Speex, librhash, and libigloo from source
- Embeds the `build-icecast [amd64|arm64]` entry point script
- Is rebuilt quarterly (or on Dockerfile change) and cached in the registry

### Release flow

1. Build environment image is available (built separately or pulled from registry)
2. A container runs `build-icecast <arch>` natively for each target architecture
3. Binary is stripped, verified `statically linked`, and written to `/output/`
4. `VERSION` is extracted from upstream `configure.ac`
5. `SHA256SUMS.txt` is computed over both binaries
6. A GitHub / Gitea release is created (or re-created) as `v<VERSION>`
7. All artifacts are uploaded to the release
8. A Docker runtime image is built from the release binaries and pushed to GHCR

### CI platforms

| Platform | Trigger | Notes |
|----------|---------|-------|
| GitHub Actions | push to main/master, `workflow_run` after build-env, `workflow_dispatch` | Pushes images to GHCR; creates GitHub release via `gh` CLI |
| Gitea Actions | push to main/master, monthly schedule, `workflow_dispatch` | Builds images locally (`local/icecast:build-*`); creates Gitea release via API |

### Trust boundaries and security posture

- No secrets stored in source; `GITHUB_TOKEN` / `GITEA_TOKEN` injected by the CI runtime
- All upstream source fetched over HTTPS; no package checksums pinned (upstream Alpine security model)
- Registry images tagged by version and YYMM, never `latest`-only
- `SHA256SUMS.txt` in every release allows end-users to verify downloads
- GitHub Actions third-party steps must be pinned to full commit SHA (see AI.md)
