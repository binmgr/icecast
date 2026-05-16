# {project_name} — Implementation Spec (THE HOW)

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
{project_name}/
├── docker/
│   ├── Dockerfile.build        # Alpine build-environment image
│   ├── Dockerfile.runtime      # Two-stage Alpine runtime image
│   └── rootfs/
│       └── usr/local/bin/
│           └── entrypoint.sh   # Config generator; runs as tini child
├── .github/
│   └── workflows/
│       ├── build-env-image.yml         # Rebuilds ghcr.io/{image}:build
│       └── build-linux-binaries.yml    # Builds, releases, and pushes runtime image
├── .gitea/
│   └── workflows/
│       ├── build-env-image.yml         # Gitea equivalent (local images only)
│       └── build-linux-binaries.yml    # Gitea release via API
├── AI.md                       # THE HOW (this file) — read-only
├── IDEA.md                     # THE WHAT — project description, variables, logic
├── CLAUDE.md                   # Short loader pointing at AI.md and IDEA.md
├── README.md                   # Public documentation
├── LICENSE.md                  # GPL-2.0 + third-party attributions
├── .dockerignore
└── .gitignore
```

**Forbidden at repo root:** `Dockerfile`, `docker-compose.yml`, `config/`, `data/`,
`build/`, `dist/`, `out/`, `vendor/`. See `~/.claude/memory/project_forbidden_files.md`.

---

## PART 2 — Build environment image (`docker/Dockerfile.build`)

### Base image

```
FROM alpine:latest
```

Rolling tag — never pinned. The quarterly scheduled rebuild ensures the environment
stays fresh. `TARGETARCH` is set by `docker buildx` for multi-arch builds.

### Alpine packages installed

All packages are installed with `--no-cache`. Static variants (`*-static`) are
preferred wherever Alpine provides them. The full install list:

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

The following must be built from source because Alpine does not provide a static
package that satisfies a fully static final link:

| Library | Source | Configure flags |
|---------|--------|-----------------|
| Speex 1.2.1 | `https://downloads.xiph.org/releases/speex/speex-1.2.1.tar.gz` | `--disable-shared --enable-static` |
| librhash 1.4.6 | `https://github.com/rhash/RHash/archive/refs/tags/v1.4.6.tar.gz` | `--enable-lib-static` |
| libigloo | `https://gitlab.xiph.org/xiph/icecast-libigloo.git` (HEAD, depth 1) | `--disable-shared --enable-static` |

Build order is fixed: Speex → librhash → libigloo (libigloo requires librhash).

arm64 constraint: `build_jobs=1` for all source builds to avoid OOM on QEMU runners.

### `build-icecast` entry point

Embedded into the image via a here-doc `COPY <<'EOF'` at
`/usr/local/bin/build-icecast` (mode 755). Callers invoke it explicitly:

```
docker run --rm --platform=linux/<arch> -v /output:/output <image> build-icecast <arch>
```

The script:
1. Resolves `ARCH` from `$1` or `uname -m` if omitted
2. Rejects cross-arch requests (container must match requested arch)
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

### `WORKDIR` / `CMD`

`WORKDIR /workspace`. `CMD ["echo", "Usage: build-icecast [amd64|arm64]"]` is
documentation only — callers always pass `build-icecast` explicitly.

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
RUN apk add --no-cache bash tini tzdata
COPY icecast-linux-${TARGETARCH} /usr/local/bin/icecast
COPY --from=assets /src/web/   /usr/share/icecast/web/
COPY --from=assets /src/admin/ /usr/share/icecast/admin/
COPY docker/rootfs/ /
COPY docker/Dockerfile.runtime /root/Dockerfile
```

### User

A non-root `icecast:icecast` system user is created. Runtime dirs (`/etc/icecast`,
`/run/icecast`, `/var/log/icecast`) are owned by that user. `USER icecast` is set
before `EXPOSE`. Port 8000 does not require elevated privileges.

### Labels

Two `LABEL` blocks — static (names, URLs) and dynamic (version, date, revision
from `ARG VERSION`, `ARG BUILD_DATE`, `ARG VCS_REF`).

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

---

## PART 4 — `docker/rootfs/usr/local/bin/entrypoint.sh`

`#!/usr/bin/env bash` script with the CasjaysDev script header. Follows
`tini → entrypoint.sh → icecast` chain. Ends with `exec /usr/local/bin/icecast -c
/etc/icecast/icecast.xml`.

**What it does:**
1. Applies defaults for all `ICECAST_*` / `STREAM_*` env vars (see PART 8)
2. Creates `/etc/icecast`, `/run/icecast`, `/var/log/icecast`,
   `/usr/share/icecast/web`, `/usr/share/icecast/admin`
3. XML-escapes every value via `__xml_escape()` (`&`, `<`, `>`, `"` → entities)
4. Writes `/etc/icecast/icecast.xml` via here-doc
5. `exec /usr/local/bin/icecast -c /etc/icecast/icecast.xml`

Logs are directed to `-` (stdout) in the generated config and captured by
Docker's json-file driver. Never source credentials — read env vars only.

---

## PART 5 — CI/CD: GitHub Actions

### Workflow: `build-env-image.yml`

**Triggers:**
- `push` to `main`/`master` touching `docker/Dockerfile.build` or the workflow file
- Quarterly schedule: `0 0 1 */3 *`
- Manual `workflow_dispatch`

**Job: `build`**
- Runner: `ubuntu-latest` · Permissions: `packages: write`
- Steps (all `uses:` SHA-pinned):
  1. `actions/checkout`
  2. `docker/setup-qemu-action` — platforms `amd64,arm64`
  3. `docker/setup-buildx-action`
  4. `docker/login-action` — registry `ghcr.io`, password `GITHUB_TOKEN`
  5. `docker/build-push-action` — file `docker/Dockerfile.build`,
     platforms `linux/amd64,linux/arm64`, push `true`,
     tag `{registry}/{image}:build`,
     cache: registry ref `{registry}/{image}:build-cache` (mode=max)

### Workflow: `build-linux-binaries.yml`

**Triggers:**
- `push` to `main`/`master` touching `docker/Dockerfile.runtime` only
  *(never the workflow file — that caused a race before the build image was ready)*
- Monthly schedule: `0 0 1 * *`
- `workflow_run` on "Build Environment Image" completed with `conclusion == 'success'`
  on `main`/`master`
- Manual `workflow_dispatch`

**Job: `build` (matrix: amd64, arm64)**
- Runner: `ubuntu-latest` · Permissions: `packages: read` · `fail-fast: false`
- Steps:
  1. `docker/setup-qemu-action`
  2. `docker/login-action` (read pull)
  3. `docker run --rm --platform=linux/<arch> -v "${RUNNER_TEMP}/icecast-output:/output"
     {registry}/{image}:build build-icecast <arch>`
  4. `actions/upload-artifact` — name `icecast-linux-<arch>`, paths binary + `VERSION`

**Job: `release`** (needs: build)
- Runner: `ubuntu-latest` · Permissions: `contents: write`, `packages: write`
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
      build-args: `VERSION`, `BUILD_DATE`, `VCS_REF`,
      tags: `latest`, `<VERSION>`, `<YYMM>`

### SHA pinning requirement

All `uses:` references **must** be pinned to a full commit SHA — tags forbidden.
Current pins (update whenever actions are upgraded):

| Action | SHA | Tag |
|--------|-----|-----|
| `actions/checkout` | `34e114876b0b11c390a56381ad16ebd13914f8d5` | v4 |
| `actions/upload-artifact` | `ea165f8d65b6e75b540449e92b4886f43607fa02` | v4 |
| `actions/download-artifact` | `d3f86a106a0bac45b974a628896c90dbdf5c8093` | v4 |
| `docker/setup-qemu-action` | `c7c53464625b32c7a7e944ae62b3e17d2b600130` | v3 |
| `docker/setup-buildx-action` | `8d2750c68a42422c14e847fe6c8ac0403b4cbd6f` | v3 |
| `docker/login-action` | `c94ce9fb468520275223c153574b00df6fe4bcc9` | v3 |
| `docker/build-push-action` | `ca052bb54ab0790a636c9b5f226502c73d547a25` | v5 |

---

## PART 6 — CI/CD: Gitea Actions

### Workflow: `build-env-image.yml`

**Triggers:** `push` to `main`/`master` touching `docker/Dockerfile.build` or the
Gitea workflow file; quarterly schedule `0 0 1 */3 *`; `workflow_dispatch`.

**Differences from GitHub version:**
- No GHCR push — images built locally as `local/icecast:build-amd64` / `:build-arm64`
- Each arch is a separate `docker buildx build --load` step
- No `docker/login-action`, no registry cache

### Workflow: `build-linux-binaries.yml`

**Triggers:** monthly schedule `0 0 1 * *`; `workflow_dispatch` only.
*(No push trigger — Gitea has no `workflow_run` equivalent so no race risk.)*

**Differences from GitHub version:**
- Builds env image locally before running it (no pull from GHCR)
- Uses `GITEA_TOKEN` secret for all API calls
- Release created via `curl` to `/api/v1/repos/{REPOSITORY}/releases`
- Assets uploaded via `curl -F attachment=@<file>`
- No Docker image push to GHCR
- `SERVER_URL` / `REPOSITORY` resolved from `gitea.*` context with `github.*` fallback

---

## PART 7 — Release format

| Item | Convention |
|------|------------|
| Git tag | `v<VERSION>` — `VERSION` from upstream `configure.ac`, no `v` prefix in the file |
| Release title | `Icecast <VERSION>` |
| Release notes | `"Static Icecast binaries"` (single line) |
| Binary names | `icecast-linux-amd64`, `icecast-linux-arm64` |
| Checksum file | `SHA256SUMS.txt` (`sha256sum` output) |
| Docker tags | `latest`, `<VERSION>`, `<YYMM>` — pushed together |

`VERSION` is never stored in this repository — it is extracted from upstream at build time.
The `release.txt` / `version.txt` convention does not apply.

---

## PART 8 — Runtime environment variables

All variables are optional; defaults apply. `entrypoint.sh` generates
`/etc/icecast/icecast.xml` from these at container start and XML-escapes all values.

| Variable | Default | `icecast.xml` field |
|----------|---------|---------------------|
| `ICECAST_HOSTNAME` | `localhost` | `<hostname>` |
| `ICECAST_LOCATION` | `Earth` | `<location>` |
| `ICECAST_ADMIN_EMAIL` | `{admin_user}@{hostname}` | `<admin>` |
| `ICECAST_ADMIN_USERNAME` | `admin` | `<authentication><admin-user>` |
| `ICECAST_ADMIN_PASSWORD` | `changeme` | `<authentication><admin-password>` |
| `ICECAST_SOURCE_PASSWORD` | `$STREAM_PASSWORD` → `changeme` | `<authentication><source-password>` |
| `ICECAST_RELAY_PASSWORD` | `$STREAM_PASSWORD` → `changeme` | `<authentication><relay-password>` |
| `ICECAST_MAX_CLIENTS` | `100` | `<limits><clients>` |
| `ICECAST_MAX_SOURCES` | `2` | `<limits><sources>` |
| `STREAM_PORT` | `8000` | `<listen-socket><port>` |
| `STREAM_PASSWORD` | *(none)* | Legacy fallback for `SOURCE_` and `RELAY_` passwords |
| `TZ` | *(system)* | Container timezone via tzdata |

Logs → stdout (`-`), captured by Docker json-file driver.
Container user: `icecast:icecast` (non-root). Port 8000 requires no privileges.

---

## PART 9 — Conventions and rules

### Files

- `docker/Dockerfile.build` — build-environment image; embedded `build-icecast` script
- `docker/Dockerfile.runtime` — two-stage runtime image (assets → Alpine)
- `docker/rootfs/usr/local/bin/entrypoint.sh` — config generator; always executable
- No Dockerfile at the repo root
- Workflow files only in `.github/workflows/` and `.gitea/workflows/`

### Docker

- All images use `alpine:latest` — rolling, never pinned
- Every `docker run` in CI must include `--rm`
- Build containers are stateless; `/output` is the only volume mount
- No secrets, credentials, or `.env` values baked into any image
- Startup chain: `tini → entrypoint.sh → icecast` — never bypass tini

### Secrets

- `GITHUB_TOKEN` — auto-injected; used only for GHCR auth and `gh` CLI
- `GITEA_TOKEN` — repository secret; used only for Gitea API calls
- Never hardcode tokens, passwords, or registry credentials in any file

### No build artifacts committed

`binaries/`, `output/`, `artifacts/`, `release/` are never committed.

### Spelling and grammar

Fix clear errors in any file being edited. Never alter technical identifiers,
upstream names, or intentional abbreviations.

---

## PART 10 — Compliance schedule

| When | Action |
|------|--------|
| Session start | Read AI.md completely |
| Before each task | Re-read relevant parts |
| Every 3–5 changes | Verify against spec |
| Before task completion | Full compliance check |
| When uncertain | Re-read spec; never guess |
