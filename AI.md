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
│   └── Dockerfile.build        # Alpine build-environment image definition
├── .github/
│   └── workflows/
│       ├── build-env-image.yml     # Rebuilds ghcr.io/{image}:build
│       └── build-linux-binaries.yml  # Builds & releases static binaries
├── .gitea/
│   └── workflows/
│       ├── build-env-image.yml     # Gitea equivalent (local images only)
│       └── build-linux-binaries.yml  # Gitea release via API
├── AI.md                       # THE HOW (this file) — read-only
├── IDEA.md                     # THE WHAT — project description, variables, logic
├── CLAUDE.md                   # Short loader pointing at AI.md and IDEA.md
├── README.md                   # Public documentation
├── LICENSE.md                  # GPL-2.0 + third-party attributions
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

arm64 constraint: `build_jobs=1` for all source builds to avoid OOM on QEMU runners.

### `build-icecast` entry point

Embedded into the image via a here-doc `COPY <<'EOF'` at
`/usr/local/bin/build-icecast` (mode 755). It is the sole `CMD`-replacement for
the container — callers invoke it explicitly:

```
docker run --rm --platform=linux/<arch> -v /output:/output <image> build-icecast <arch>
```

The script:
1. Resolves `ARCH` from `$1` or `uname -m` if omitted
2. Rejects cross-arch requests (container must match requested arch)
3. Clones `https://github.com/xiph/Icecast-Server` (depth 1, recursive)
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

### `WORKDIR`

Set to `/workspace` after all build steps complete. The build script uses `/build`
as its working directory internally.

### `CMD`

```
CMD ["echo", "Usage: build-icecast [amd64|arm64]"]
```

The CMD is documentation only — callers always pass `build-icecast` explicitly.

---

## PART 3 — CI/CD: GitHub Actions

### Workflow: `build-env-image.yml`

**Triggers:**
- `push` to `main`/`master` touching `docker/Dockerfile.build` or the workflow file
- Quarterly schedule: `0 0 1 */3 *`
- Manual `workflow_dispatch`

**Job: `build`**
- Runner: `ubuntu-latest`
- Permissions: `packages: write`
- Steps:
  1. `actions/checkout` (SHA-pinned)
  2. `docker/setup-qemu-action` — platforms `amd64,arm64`
  3. `docker/setup-buildx-action`
  4. `docker/login-action` — registry `ghcr.io`, username `github.actor`, password `GITHUB_TOKEN`
  5. `docker/build-push-action` — context `.`, file `docker/Dockerfile.build`,
     platforms `linux/amd64,linux/arm64`, push `true`,
     tag `{registry}/{image}:build`,
     cache via registry `{registry}/{image}:build-cache` (mode=max)

### Workflow: `build-linux-binaries.yml`

**Triggers:**
- `push` to `main`/`master` touching `docker/Dockerfile.runtime` only — never the
  workflow file itself (that caused a race where the binary job fired before the
  build image was ready)
- Monthly schedule: `0 0 1 * *`
- `workflow_run` on "Build Environment Image" completed on `main`/`master` with
  `conclusion == 'success'`
- Manual `workflow_dispatch`

**Job: `build` (matrix: amd64, arm64)**
- Runner: `ubuntu-latest`
- Permissions: `packages: read`
- `fail-fast: false`
- Steps:
  1. `docker/setup-qemu-action`
  2. `docker/login-action` (read-only pull)
  3. Run container: `docker run --rm --platform=linux/<arch> -v "${RUNNER_TEMP}/icecast-output:/output" {registry}/{image}:build build-icecast <arch>`
  4. `actions/upload-artifact` — name `icecast-linux-<arch>`, paths binary + `VERSION`

**Job: `release`** (needs: build)
- Runner: `ubuntu-latest`
- Permissions: `contents: write`, `packages: write`
- Steps:
  1. `actions/checkout`
  2. `actions/download-artifact` — merge all into `artifacts/`
  3. Extract `VERSION` from `artifacts/VERSION`
  4. Compute `YYMM` tag via `date -u +'%y%m'`
  5. Assemble `release/`: copy binaries, `chmod +x`, compute `SHA256SUMS.txt`
  6. Delete existing release/tag `v<VERSION>` if present (`gh release delete`)
  7. Create release `v<VERSION>` with title `Icecast <VERSION>` and upload all files
  8. `docker/setup-buildx-action` + `docker/login-action`
  9. Copy binaries to context root, then `docker/build-push-action`:
     - platforms `linux/amd64,linux/arm64`
     - tags: `latest`, `<VERSION>`, `<YYMM>`

### SHA pinning requirement

All `uses:` references to third-party actions **must** be pinned to a full commit SHA.
Tags (`@v4`, `@v3`, etc.) are forbidden. Example compliant form:

```yaml
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4
```

---

## PART 4 — CI/CD: Gitea Actions

### Workflow: `build-env-image.yml`

**Triggers:** same as GitHub equivalent except the path filter references
`.gitea/workflows/build-env-image.yml`.

**Differences from GitHub version:**
- No GHCR push — images are built locally (`local/icecast:build-amd64`, `:build-arm64`)
- Each arch is a separate `docker buildx build --load` step, not a single multi-arch push
- No `docker/login-action` step
- No cache configuration

### Workflow: `build-linux-binaries.yml`

**Triggers:** push touching the Gitea workflow file, monthly schedule (`0 0 1 * *`),
`workflow_dispatch`.

**Differences from GitHub version:**
- Builds env image locally (no pull from GHCR) before running it
- Uses `GITEA_TOKEN` secret for API calls
- Release created via `curl` to the Gitea API (`/api/v1/repos/{REPOSITORY}/releases`)
- Assets uploaded via `curl -F attachment=@<file>`
- No Docker image push to GHCR
- `SERVER_URL` and `REPOSITORY` resolved from `gitea.*` context with `github.*` fallback

---

## PART 5 — Release format

| Item | Convention |
|------|------------|
| Git tag | `v<VERSION>` where `<VERSION>` comes from upstream `configure.ac` |
| Release title | `Icecast <VERSION>` |
| Release notes | `"Static Icecast binaries"` (single line, no changelog) |
| Binary names | `icecast-linux-amd64`, `icecast-linux-arm64` |
| Checksum file | `SHA256SUMS.txt` (SHA-256, BSD-style output from `sha256sum`) |
| VERSION file | Plain text, upstream version string, no `v` prefix |
| Docker tags | `latest`, `<VERSION>`, `<YYMM>` — all pushed in the same build step |

---

## PART 6 — Conventions and rules

### Files

- `docker/Dockerfile.build` is the build-environment image definition.
- `docker/Dockerfile.runtime` is the minimal `FROM scratch` runtime image that embeds
  the static binary. No Dockerfile lives at the repo root.
- All workflow files live in `.github/workflows/` and `.gitea/workflows/`.
  No other workflow or CI config belongs at the repo root.

### Docker

- Build images use `alpine:latest` — rolling, never pinned.
- Every `docker run` in CI must include `--rm`.
- Build containers are stateless; `/output` is the only volume mount.
- Do not store credentials, source code, or config inside the image beyond what the
  `build-icecast` script needs.

### Secrets

- `GITHUB_TOKEN` — injected automatically; used only for GHCR auth and `gh` CLI.
- `GITEA_TOKEN` — must be set as a repository secret; used only for Gitea API calls.
- Never hardcode tokens, passwords, or registry credentials in any file.

### Versioning

- `VERSION` is extracted from upstream `configure.ac` at build time; it is never
  stored in this repository.
- The `release.txt` / `version.txt` convention does **not** apply here because the
  version is not owned by this project.

### Spelling and grammar

Fix clear spelling and grammar errors in any file being edited. Never alter
technical identifiers, upstream names, or intentional abbreviations.

### No build artifacts committed

`binaries/`, `output/`, `artifacts/`, `release/` directories are never committed.
Add them to `.gitignore` if they appear locally.

---

## PART 7 — Compliance schedule

| When | Action |
|------|--------|
| Session start | Read AI.md completely |
| Before each task | Re-read relevant parts |
| Every 3–5 changes | Verify against this spec |
| Before task completion | Full compliance check |
| When uncertain | Re-read this spec; never guess |
