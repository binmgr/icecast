# icecast — Implementation Spec (THE HOW)

> **Read-only.** Project-specific values live in `IDEA.md`. Placeholders like `{project_name}`
> are resolved at runtime from `## Project variables` in `IDEA.md`.
> If AI.md and IDEA.md conflict, AI.md wins — fix IDEA.md.

---

## PART 0 — Identity

| Field | Value |
|-------|-------|
| Project | `{project_name}` |
| Org | `{project_org}` |
| Internal name (frozen) | `{internal_name}` |
| Internal org (frozen) | `{internal_org}` |
| Type | build-automation / upstream binary repackager |
| Upstream | `{upstream_repo}` |
| Registry | `{registry}/{image}` |

`internal_name` and `internal_org` are set once at project creation and **never changed**,
even if the project is renamed.

---

## PART 1 — Repository layout

```
icecast/
├── docker/
│   ├── Dockerfile.build        # Alpine build-environment image
│   ├── Dockerfile.runtime      # Two-stage Alpine runtime image
│   └── rootfs/
│       └── usr/local/bin/
│           └── entrypoint.sh   # Config generator; runs as tini child
├── .github/
│   ├── workflows/
│   │   ├── build-env-image.yml         # Rebuilds ghcr.io/{image}:build
│   │   ├── build-linux-binaries.yml    # Builds, releases, and pushes runtime image
│   │   └── security.yml                # truffleHog + Trivy scanning
│   ├── CODEOWNERS                      # Review requirements for security-sensitive paths
│   └── SECURITY.md                     # Vulnerability reporting policy
├── .gitea/
│   └── workflows/
│       ├── build-env-image.yml         # Gitea equivalent (local images only)
│       └── build-linux-binaries.yml    # Gitea release via API
├── AI.md                       # THE HOW (this file) — implementation spec
├── IDEA.md                     # THE WHAT — project description, variables, logic
├── CLAUDE.md                   # Short loader + rules pointing at AI.md and IDEA.md
├── README.md                   # Public documentation
├── LICENSE.md                  # GPL-2.0 + third-party attributions
├── renovate.json               # Renovate dependency updates (Actions + Docker base)
├── .dockerignore
└── .gitignore
```

**Forbidden at repo root:** `Dockerfile`, `docker-compose.yml`, `config/`, `data/`,
`build/`, `dist/`, `out/`, `vendor/`. See `~/.claude/memory/project_forbidden_files.md`.

---

## PART 2 — Build environment image (`docker/Dockerfile.build`)

### Base image

```dockerfile
FROM alpine:latest
ARG TARGETARCH
```

Rolling tag — never pinned. The quarterly scheduled rebuild keeps the environment
fresh. `TARGETARCH` is set by `docker buildx` for multi-arch builds.

### Alpine packages installed

All packages installed with `--no-cache`. Static variants (`*-static`) used wherever
Alpine provides them. Full install list:

```
autoconf automake build-base brotli-static bzip2 ca-certificates c-ares-dev
curl curl-dev curl-static file git libidn2-static libmaxminddb-dev
libmaxminddb-static libogg-dev libogg-static libpsl-static libtheora-dev
libtheora-static libtool libunistring-static libvorbis-dev libvorbis-static
libxml2-dev libxml2-static libxslt-dev libxslt-static linux-headers
nghttp2-static nghttp3-static openssl-dev openssl-libs-static pkgconf
python3 tar wget xz xz-dev xz-static zlib-dev zlib-static zstd-static
```

### Source-built dependencies

Built from source because Alpine does not provide a static package that satisfies
a fully static final link. **Build order is fixed** — libigloo requires librhash:

| # | Library | Source | Configure flags |
|---|---------|--------|-----------------|
| 1 | Speex 1.2.1 | `https://downloads.xiph.org/releases/speex/speex-1.2.1.tar.gz` | `--disable-shared --enable-static` |
| 2 | librhash 1.4.6 | `https://github.com/rhash/RHash/archive/refs/tags/v1.4.6.tar.gz` | `--enable-lib-static` |
| 3 | libigloo | `https://gitlab.xiph.org/xiph/icecast-libigloo.git` (HEAD, depth 1) | `--disable-shared --enable-static` |

arm64 constraint: `build_jobs=1` for all source builds to prevent OOM on QEMU runners.

### `build-icecast` entry point

Embedded into the image via a here-doc `COPY <<'EOF'` at
`/usr/local/bin/build-icecast` (mode 755). Callers invoke it as:

```
docker run --rm --platform=linux/<arch> -v /output:/output <image> build-icecast <arch>
```

The script:
1. Resolves `ARCH` from `$1` or `uname -m` if omitted
2. Rejects cross-arch requests (container arch must match requested arch)
3. Clones `https://github.com/xiph/Icecast-Server` (depth 1, recursive) into `/build`
4. Extracts `VERSION` from `configure.ac` via `sed`
5. Runs `autoreconf -fi` then `./configure` with all features enabled:
   - `--disable-shared --enable-static`
   - `--enable-yp --enable-ipv6`
   - `--with-ogg --with-theora --with-speex --with-curl --with-openssl --with-maxminddb`
   - `PKG_CONFIG="pkg-config --static"` to pull static link flags
   - `CFLAGS="-Os -fno-pie"` / `LDFLAGS="-L/usr/lib -no-pie"`
6. Builds with `AM_LDFLAGS="-all-static -static -no-pie"`
7. Strips the binary
8. Verifies `statically linked` or `static-pie linked` via `file`
9. Writes `icecast-linux-<arch>` and `VERSION` to `/output/`

### Final directives

```dockerfile
WORKDIR /workspace
CMD ["echo", "Usage: build-icecast [amd64|arm64]"]
```

`CMD` is documentation only — callers always pass `build-icecast` explicitly.

---

## PART 3 — Runtime image (`docker/Dockerfile.runtime`)

### Structure

Two-stage Alpine build:

**Stage `assets`** — fetches arch-independent upstream web/admin files:
```dockerfile
FROM alpine:latest AS assets
RUN apk add --no-cache git
RUN git clone --depth 1 https://github.com/xiph/Icecast-Server.git /src
```

**Stage 2 (runtime)** — minimal Alpine with tini and the static binary:
```dockerfile
FROM alpine:latest
ARG TARGETARCH
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF

# Static labels (names, URLs)
LABEL maintainer="..." org.opencontainers.image.vendor="binmgr" ...

# Dynamic labels (from ARGs)
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" ...

RUN apk add --no-cache bash tini tzdata
COPY icecast-linux-${TARGETARCH} /usr/local/bin/icecast
COPY --from=assets /src/web/   /usr/share/icecast/web/
COPY --from=assets /src/admin/ /usr/share/icecast/admin/
COPY docker/rootfs/ /
COPY docker/Dockerfile.runtime /root/Dockerfile
```

### User and permissions

```dockerfile
RUN addgroup -S icecast && adduser -S icecast -G icecast \
 && mkdir -p /etc/icecast /run/icecast /var/log/icecast \
 && chown -R icecast:icecast /etc/icecast /run/icecast /var/log/icecast \
 && chmod 755 /usr/local/bin/icecast /usr/local/bin/entrypoint.sh
USER icecast
EXPOSE 8000
```

Port 8000 does not require elevated privileges.

### Health check

```dockerfile
HEALTHCHECK --start-period=2m --interval=30s --timeout=10s --retries=3 \
    CMD bash -c "printf '' > /dev/tcp/127.0.0.1/${STREAM_PORT:-8000}" || exit 1
```

### Entrypoint chain

```dockerfile
ENTRYPOINT [ "/sbin/tini", "-p", "SIGTERM", "--", "/usr/local/bin/entrypoint.sh" ]
```

`tini` is PID 1. It spawns `entrypoint.sh`, which generates
`/etc/icecast/icecast.xml` then `exec`s `/usr/local/bin/icecast`.
Never override or bypass tini.

---

## PART 4 — `docker/rootfs/usr/local/bin/entrypoint.sh`

`#!/usr/bin/env bash` script with CasjaysDev script header (`# shellcheck shell=bash`,
version stamp, author block, `set -euo pipefail`).

Follows `tini → entrypoint.sh → icecast` chain. Final line:
`exec /usr/local/bin/icecast -c /etc/icecast/icecast.xml`

**What it does (in order):**
1. Applies defaults for all `ICECAST_*` / `STREAM_*` env vars (see PART 8)
2. Creates `/etc/icecast`, `/run/icecast`, `/var/log/icecast`,
   `/usr/share/icecast/web`, `/usr/share/icecast/admin`
3. XML-escapes every value via `__xml_escape()` — escapes `&`, `<`, `>`, `"`
4. Writes `/etc/icecast/icecast.xml` via `cat > ... <<XMLEOF`
5. `exec /usr/local/bin/icecast -c /etc/icecast/icecast.xml`

Logs directed to `-` (stdout) in the generated config — captured by Docker's
json-file driver. Never source credentials from files; read env vars only.

---

## PART 5 — CI/CD: GitHub Actions

### Workflow: `build-env-image.yml`

**Triggers:**
- `push` to `main`/`master` touching `docker/Dockerfile.build` or the workflow file
- Quarterly schedule: `0 0 1 */3 *`
- `workflow_dispatch`

**Permissions:** workflow-level `contents: read`; job-level `packages: write`

**Concurrency:** `group: ${{ github.workflow }}-${{ github.ref }}`, `cancel-in-progress: true`

**Job: `build`** steps (all `uses:` SHA-pinned):
1. `actions/checkout`
2. `docker/setup-qemu-action` — platforms `amd64,arm64`
3. `docker/setup-buildx-action`
4. `docker/login-action` — registry `ghcr.io`, password `GITHUB_TOKEN`
5. `docker/build-push-action` — file `docker/Dockerfile.build`,
   platforms `linux/amd64,linux/arm64`, push `true`,
   tag `{registry}/{image}:build`,
   cache: registry ref `{registry}/{image}:build-cache` (mode=max)

---

### Workflow: `build-linux-binaries.yml`

**Triggers:**
- `push` to `main`/`master` touching `docker/Dockerfile.runtime` only
  *(never the workflow file itself — that caused a race before the build image existed)*
- Monthly schedule: `0 0 1 * *`
- `workflow_run` on "Build Environment Image" `completed` with `conclusion == 'success'`
  on `main`/`master`
- `workflow_dispatch`

**Permissions:** workflow-level `contents: read`

**Concurrency:** `group: ${{ github.workflow }}-${{ github.ref }}`, `cancel-in-progress: false`
*(never cancel a release in flight)*

**Job: `build`** (matrix: `amd64`, `arm64`; `fail-fast: false`)
- Permissions: `packages: read`
- Steps:
  1. `docker/setup-qemu-action`
  2. `docker/login-action`
  3. `docker run --rm --platform=linux/<arch> -v "${RUNNER_TEMP}/icecast-output:/output" {registry}/{image}:build build-icecast <arch>`
  4. `actions/upload-artifact` — name `icecast-linux-<arch>`, paths binary + `VERSION`, `retention-days: 30`

**Job: `release`** (needs: build)
- Permissions: `contents: write`, `packages: write`, `id-token: write`, `attestations: write`
- Steps:
  1. `actions/checkout`
  2. `actions/download-artifact` — merge all into `artifacts/`
  3. Extract `VERSION` from `artifacts/VERSION`
  4. Compute `YYMM` tag via `date -u +'%y%m'`
  5. Assemble `release/`: copy binaries, `chmod +x`, compute `SHA256SUMS.txt`
  6. `gh release delete "v<VERSION>" --yes --cleanup-tag || true`
  7. `gh release create "v<VERSION>"` — upload all `release/*`
  8. `docker/setup-buildx-action` + `docker/login-action`
  9. `cp release/icecast-linux-* .`
  10. `docker/build-push-action` — context `.`, file `docker/Dockerfile.runtime`,
      platforms `linux/amd64,linux/arm64`,
      build-args `VERSION`, `BUILD_DATE`, `VCS_REF`,
      tags `latest`, `<VERSION>`, `<YYMM>`

---

### Workflow: `security.yml`

**Triggers:** `push` to `main`/`master`, `pull_request`, weekly schedule `0 3 * * 1`

**Permissions:** workflow-level `contents: read`

**Job: `secrets`** — `trufflesecurity/trufflehog` with `--only-verified`; no `base`/`head`
inputs (action auto-detects range from the GitHub event).

**Job: `trivy`** — pulls `ghcr.io/binmgr/icecast:latest` and runs Trivy with
`--exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed`. Skips gracefully if no
image has been published yet.

---

### Renovate (`renovate.json`)

Renovate (AGPL-3.0, free) — never Dependabot. Weekly schedule (Monday before 06:00 UTC).
Managers: `github-actions` (covers `.github/workflows/` and `.gitea/workflows/`) with
`pinDigests: true` so action upgrades land as full commit SHAs; `dockerfile` for
`docker/Dockerfile.*`. The `alpine` base image is intentionally disabled — rolling
`alpine:latest` is project policy. Vulnerability alerts are enabled and labelled
`security`.

---

### SHA pinning requirement

All `uses:` references **must** be pinned to a full commit SHA — tags forbidden.
Current pins (all node24 runtimes):

| Action | Tag | SHA |
|--------|-----|-----|
| `actions/checkout` | v6.0.2 | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| `actions/upload-artifact` | v7.0.1 | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| `actions/download-artifact` | v8.0.1 | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` |
| `docker/setup-qemu-action` | v4.0.0 | `ce360397dd3f832beb865e1373c09c0e9f86d70a` |
| `docker/setup-buildx-action` | v4.0.0 | `4d04d5d9486b7bd6fa91e7baf45bbb4f8b9deedd` |
| `docker/login-action` | v4.1.0 | `4907a6ddec9925e35a0a9e82d7399ccc52663121` |
| `docker/build-push-action` | v7.1.0 | `bcafcacb16a39f128d818304e6c9c0c18556b85f` |
| `trufflesecurity/trufflehog` | v3.95.3 | `37b77001d0174ebec2fcca2bd83ff83a6d45a3ab` |

---

## PART 6 — CI/CD: Gitea Actions

### Workflow: `build-env-image.yml`

**Triggers:** `push` to `main`/`master` touching `docker/Dockerfile.build` or the
Gitea workflow file; quarterly schedule `0 0 1 */3 *`; `workflow_dispatch`.

**Differences from GitHub:**
- No GHCR push — images built locally: `local/icecast:build-amd64` / `:build-arm64`
- Each arch is a separate `docker buildx build --load` step
- No `docker/login-action`, no registry cache

### Workflow: `build-linux-binaries.yml`

**Triggers:** monthly schedule `0 0 1 * *`; `workflow_dispatch` only.
*(No push trigger — Gitea has no `workflow_run` equivalent, no race risk.)*

**Differences from GitHub:**
- Builds env image locally before running it (no pull from GHCR)
- Uses `GITEA_TOKEN` secret for all API calls
- Release created via `curl` POST to `/api/v1/repos/{REPOSITORY}/releases`
- Assets uploaded via `curl -F attachment=@<file>`
- No Docker image push to GHCR
- `SERVER_URL` / `REPOSITORY` resolved from `gitea.*` context with `github.*` fallback

---

## PART 7 — Release format

| Item | Convention |
|------|------------|
| Git tag | `v<VERSION>` — `VERSION` extracted from upstream `configure.ac`; no `v` in the value |
| Release title | `Icecast <VERSION>` |
| Release notes | `"Static Icecast binaries for Linux amd64 and arm64"` |
| Binary names | `icecast-linux-amd64`, `icecast-linux-arm64` |
| Checksum file | `SHA256SUMS.txt` (output of `sha256sum`) |
| Docker tags | `latest`, `<VERSION>`, `<YYMM>` — pushed together in one `build-push-action` call |

`VERSION` is never stored in this repository — extracted from upstream at build time.
The `release.txt` / `version.txt` convention does **not** apply to this project.

---

## PART 8 — Runtime environment variables

All variables are optional; defaults apply. `entrypoint.sh` generates
`/etc/icecast/icecast.xml` from these at container start and XML-escapes all values.

| Variable | Default | `icecast.xml` field |
|----------|---------|---------------------|
| `ICECAST_HOSTNAME` | `localhost` | `<hostname>` |
| `ICECAST_LOCATION` | `Earth` | `<location>` |
| `ICECAST_ADMIN_USERNAME` | `admin` | `<authentication><admin-user>` |
| `ICECAST_ADMIN_PASSWORD` | `changeme` | `<authentication><admin-password>` |
| `ICECAST_ADMIN_EMAIL` | `{admin_user}@{hostname}` | `<admin>` |
| `ICECAST_SOURCE_PASSWORD` | `$STREAM_PASSWORD` → `changeme` | `<authentication><source-password>` |
| `ICECAST_RELAY_PASSWORD` | `$STREAM_PASSWORD` → `changeme` | `<authentication><relay-password>` |
| `ICECAST_MAX_CLIENTS` | `100` | `<limits><clients>` |
| `ICECAST_MAX_SOURCES` | `2` | `<limits><sources>` |
| `STREAM_PORT` | `8000` | `<listen-socket><port>` |
| `STREAM_PASSWORD` | *(none)* | Legacy fallback for `SOURCE_` and `RELAY_` passwords |
| `TZ` | *(system)* | Container timezone via tzdata |

Logs → stdout (`-`), captured by Docker json-file driver.
Container user: `icecast:icecast` (non-root). Port 8000 requires no root privileges.

---

## PART 9 — Conventions and rules

### Files

- `docker/Dockerfile.build` — build-environment image; embedded `build-icecast` script
- `docker/Dockerfile.runtime` — two-stage runtime image (assets → Alpine)
- `docker/rootfs/usr/local/bin/entrypoint.sh` — config generator; mode 755 always
- No `Dockerfile` at the repo root — ever
- Workflow files only in `.github/workflows/` and `.gitea/workflows/`

### Docker

- All images use `alpine:latest` — rolling, never pinned
- Every `docker run` in CI must include `--rm`
- Build containers are stateless; `/output` is the only volume mount
- No secrets, credentials, or `.env` values baked into any image
- Startup chain: `tini → entrypoint.sh → icecast` — never override or bypass tini

### Secrets

- `GITHUB_TOKEN` — auto-injected; used only for GHCR push and `gh` CLI
- `GITEA_TOKEN` — repository secret; used only for Gitea API calls
- Never hardcode tokens, passwords, or registry credentials in any file

### Build artifacts

`binaries/`, `output/`, `artifacts/`, `release/` are gitignored and never committed.

### Spec conflict resolution

AI.md wins over IDEA.md on any conflict. Fix IDEA.md to match AI.md.

---

## PART 10 — Compliance schedule

| When | Action |
|------|--------|
| Session start | Read AI.md completely |
| Before each task | Re-read relevant PART(s) |
| Every 3–5 changes | Verify against spec |
| Before task completion | Full compliance check across all PARTs |
| When uncertain | Re-read the relevant PART; never guess |
