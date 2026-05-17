# Icecast

Automated builds of fully static [Icecast](https://github.com/xiph/Icecast-Server) streaming media server binaries for Linux (amd64/arm64), plus a ready-to-run Docker image driven entirely by environment variables. No shared libraries, no runtime dependencies — drop-and-run on any Linux distribution.

---

## 📦 Install

Download the latest release from [GitHub Releases](https://github.com/binmgr/icecast/releases/latest).

### Linux

| Arch | Binary |
|------|--------|
| amd64 | `icecast-linux-amd64` |
| arm64 | `icecast-linux-arm64` |

```bash
# Detect arch automatically
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
curl -LSsf "https://github.com/binmgr/icecast/releases/latest/download/icecast-linux-${ARCH}" \
  -o /usr/local/bin/icecast && chmod +x /usr/local/bin/icecast
```

**Verify integrity:**

```bash
curl -LSsf https://github.com/binmgr/icecast/releases/latest/download/SHA256SUMS.txt \
  | sha256sum -c --ignore-missing
```

**Run with a config file:**

```bash
icecast -c /path/to/icecast.xml
```

---

## 🐳 Docker

```bash
docker run --rm -it \
  -p 8000:8000 \
  -e ICECAST_SOURCE_PASSWORD=mysecret \
  -e ICECAST_ADMIN_PASSWORD=adminpass \
  ghcr.io/binmgr/icecast:latest
```

The entrypoint generates `/etc/icecast/icecast.xml` from environment variables on every start. Logs go to stdout.

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ICECAST_HOSTNAME` | `localhost` | Server hostname in config and HTTP responses |
| `ICECAST_LOCATION` | `Earth` | Location string in directory listings |
| `ICECAST_ADMIN_USERNAME` | `admin` | Admin web UI username |
| `ICECAST_ADMIN_PASSWORD` | `changeme` | Admin web UI password |
| `ICECAST_ADMIN_EMAIL` | `{admin}@{hostname}` | Admin contact shown in listings |
| `ICECAST_SOURCE_PASSWORD` | `$STREAM_PASSWORD` → `changeme` | Source client auth |
| `ICECAST_RELAY_PASSWORD` | `$STREAM_PASSWORD` → `changeme` | Relay client auth |
| `ICECAST_MAX_CLIENTS` | `100` | Maximum simultaneous listeners |
| `ICECAST_MAX_SOURCES` | `2` | Maximum simultaneous source streams |
| `STREAM_PORT` | `8000` | TCP port Icecast listens on |
| `STREAM_PASSWORD` | *(none)* | Legacy fallback for source and relay passwords |
| `TZ` | system | Container timezone |

### Image Tags

| Tag | Description |
|-----|-------------|
| `latest` | Most recent release |
| `2.5.0` | Specific upstream version |
| `2505` | Year-month of build (YYMM) |

The image is a drop-in replacement for `libretime/icecast` and compatible with `zerg13/ices` source clients.

---

## ⚙️ Configuration

All optional features are compiled in — no feature gating:

- ✅ Ogg Vorbis, Theora video, Speex codec streaming
- ✅ TLS/SSL (OpenSSL)
- ✅ YP directory listing (libcurl)
- ✅ XML/XSLT configuration (libxml2 + libxslt)
- ✅ GeoIP lookups (libmaxminddb)
- ✅ IPv6 support
- ✅ Web-based administration interface

### Config File

Create an `icecast.xml` file. See the [upstream example](https://github.com/xiph/Icecast-Server/blob/master/conf/icecast.xml.dist) for all options. Minimal working config:

```xml
<icecast>
    <limits>
        <clients>100</clients>
        <sources>2</sources>
    </limits>

    <authentication>
        <!-- Change these before exposing to the internet -->
        <source-password>changeme</source-password>
        <admin-user>admin</admin-user>
        <admin-password>changeme</admin-password>
    </authentication>

    <hostname>localhost</hostname>
    <listen-socket>
        <port>8000</port>
    </listen-socket>

    <paths>
        <basedir>/usr/share/icecast</basedir>
        <logdir>/var/log/icecast</logdir>
        <webroot>/usr/share/icecast/web</webroot>
        <adminroot>/usr/share/icecast/admin</adminroot>
    </paths>

    <logging>
        <accesslog>access.log</accesslog>
        <errorlog>error.log</errorlog>
        <loglevel>3</loglevel>
    </logging>
</icecast>
```

### Command-Line Options

```
icecast -c <file>   Specify configuration file
icecast -v          Display version and build information
icecast -b          Run in background (daemon mode)
```

---

## 🛠️ Development

### CI Platforms

| Platform | Triggers | Notes |
|----------|----------|-------|
| **GitHub Actions** | `workflow_run` (after env image), monthly schedule, `Dockerfile.runtime` push, `workflow_dispatch` | Pushes images to GHCR; creates GitHub releases |
| **Gitea Actions** | Monthly schedule, `workflow_dispatch` | Builds images locally; creates Gitea releases via API |

### Workflows

| File | Purpose |
|------|---------|
| `.github/workflows/build-env-image.yml` | Build and push `ghcr.io/binmgr/icecast:build` (quarterly + on `Dockerfile.build` change) |
| `.github/workflows/build-linux-binaries.yml` | Build static binaries, verify them, create GitHub release, push runtime image |
| `.github/workflows/security.yml` | truffleHog secret scanning + Trivy container vulnerability scan |

### How It Works

1. **Build environment image** — `ghcr.io/binmgr/icecast:build` is a multi-arch Alpine image with all static libraries pre-compiled (Speex → librhash → libigloo, in that order). Rebuilt quarterly or when `docker/Dockerfile.build` changes.
2. **Binary build** — A container runs `build-icecast <arch>` natively for each target. Clones upstream, compiles with all features, strips and verifies static linking, writes to `/output/`.
3. **Verification** — Both binaries are checked for static linking and the amd64 binary is executed before anything is published.
4. **Release** — GitHub / Gitea release created as `v<VERSION>` with both binaries and `SHA256SUMS.txt`.
5. **Runtime image** — Two-stage `docker/Dockerfile.runtime`: stage `assets` fetches upstream web/admin UI files; final stage is Alpine + tini + static binary + entrypoint.

### Local Build

```bash
# Pull the pre-built environment image
docker pull ghcr.io/binmgr/icecast:build

# Build for amd64
mkdir -p output
docker run --rm -it --name icecast-local \
  --platform=linux/amd64 \
  -v "$(pwd)/output:/output" \
  ghcr.io/binmgr/icecast:build \
  build-icecast amd64

# Build for arm64 (requires QEMU or native arm64 host)
docker run --rm -it --name icecast-local \
  --platform=linux/arm64 \
  -v "$(pwd)/output:/output" \
  ghcr.io/binmgr/icecast:build \
  build-icecast arm64
```

Or build the environment image yourself:

```bash
docker build -f docker/Dockerfile.build -t ghcr.io/binmgr/icecast:build .
```

### Approximate Build Times

| Target | Time |
|--------|------|
| Linux amd64 | ~5–10 min |
| Linux arm64 | ~8–15 min (QEMU on x86 runner) |

---

## 🔒 Security

To report a vulnerability privately, see [SECURITY.md](.github/SECURITY.md).

For issues with Icecast itself, report to [upstream](https://gitlab.xiph.org/xiph/icecast-server/issues).
For issues with these builds or the Docker image, open an [issue](../../issues).

---

## 📄 License

- **Icecast**: GPL-2.0 — see [LICENSE.md](LICENSE.md)
- **Build workflow**: MIT License

[Upstream Icecast source](https://github.com/xiph/Icecast-Server) · [Official Icecast docs](https://icecast.org/docs/) · [Icecast.org](https://icecast.org/)
