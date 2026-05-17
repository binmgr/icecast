# Icecast — Static Binary Builds & Docker Image

Automated builds of fully static [Icecast](https://github.com/xiph/Icecast-Server) streaming media server binaries for Linux (amd64/arm64), plus a ready-to-run Docker image driven entirely by environment variables.

## What is Icecast?

Icecast is a streaming media server that supports Ogg Vorbis, Opus, WebM, and MP3 audio streams. It can be used to create an internet radio station, a private jukebox, or many things in between.

## Features Compiled In

All optional features are enabled — no feature gating:

- ✅ Ogg Vorbis, Theora video, Speex codec streaming
- ✅ TLS/SSL (OpenSSL)
- ✅ YP directory listing (libcurl)
- ✅ XML/XSLT configuration (libxml2 + libxslt)
- ✅ GeoIP lookups (libmaxminddb)
- ✅ IPv6 support
- ✅ Web-based administration interface

Every binary is fully statically linked — no shared libraries, no runtime dependencies, drop-and-run on any Linux distribution.

---

## Docker Image

```bash
docker run --rm -it \
  -p 8000:8000 \
  -e ICECAST_SOURCE_PASSWORD=mysecret \
  -e ICECAST_ADMIN_PASSWORD=adminpass \
  ghcr.io/binmgr/icecast:latest
```

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

The entrypoint generates `/etc/icecast/icecast.xml` from these variables on every start. Icecast logs to stdout.

### Image Tags

| Tag | Description |
|-----|-------------|
| `latest` | Most recent release |
| `2.5.0` | Specific upstream version |
| `2505` | Year-month of build (YYMM) |

### Compatible Source Clients

The Docker image is a drop-in replacement for `libretime/icecast` and is compatible with `zerg13/ices` source clients.

---

## Static Binary Downloads

See [Releases](../../releases) for pre-built binaries.

Each release includes:

| File | Description |
|------|-------------|
| `icecast-linux-amd64` | Static binary for x86_64 Linux |
| `icecast-linux-arm64` | Static binary for aarch64 Linux |
| `SHA256SUMS.txt` | SHA-256 checksums for verification |

### Quick Start

```bash
# Download for your architecture
wget https://github.com/binmgr/icecast/releases/latest/download/icecast-linux-amd64

# Make executable
chmod +x icecast-linux-amd64

# Run with a config file
./icecast-linux-amd64 -c /path/to/icecast.xml
```

### Verify Integrity

```bash
wget https://github.com/binmgr/icecast/releases/latest/download/SHA256SUMS.txt
sha256sum -c SHA256SUMS.txt --ignore-missing
```

### Supported Platforms

Any Linux distribution on x86_64 or aarch64 — Debian, Ubuntu, RHEL/CentOS/Rocky, Alpine, Arch, and others.

---

## Configuration

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

```bash
./icecast-linux-amd64 -c icecast.xml
```

### Command-Line Options

```
Usage: icecast [options]
  -c <file>    Specify configuration file
  -v           Display version and build information
  -b           Run in background (daemon mode)
```

---

## Build System

### CI Platforms

| Platform | Triggers | Notes |
|----------|----------|-------|
| **GitHub Actions** | `workflow_run` (after env image), monthly schedule, `Dockerfile.runtime` push, `workflow_dispatch` | Pushes images to GHCR; creates GitHub releases |
| **Gitea Actions** | Monthly schedule, `workflow_dispatch` | Builds images locally; creates Gitea releases via API |

### Workflows

| File | Purpose |
|------|---------|
| `.github/workflows/build-env-image.yml` | Build and push `ghcr.io/binmgr/icecast:build` (quarterly + on Dockerfile.build change) |
| `.github/workflows/build-linux-binaries.yml` | Build static binaries, create GitHub release, push runtime image |
| `.github/workflows/security.yml` | truffleHog secret scanning + Trivy container vulnerability scan |

### How It Works

1. **Build environment image** — `ghcr.io/binmgr/icecast:build` is a multi-arch Alpine image with all static libraries pre-compiled (Speex → librhash → libigloo, in that order). Rebuilt quarterly or when `docker/Dockerfile.build` changes.
2. **Binary build** — A container runs `build-icecast <arch>` natively for each target architecture. The script clones Icecast from upstream, compiles with all features enabled, strips the binary, and verifies static linking before writing to `/output/`.
3. **Verification** — Both binaries are checked for static linking and the amd64 binary is executed to confirm it runs before anything is published.
4. **Release** — GitHub / Gitea release created as `v<VERSION>` with both binaries and `SHA256SUMS.txt`.
5. **Runtime image** — Two-stage `docker/Dockerfile.runtime`: stage `assets` fetches the upstream web/admin UI files; final stage is Alpine + tini + static binary + entrypoint.

### Local Build

Pull the pre-built environment image from GHCR:

```bash
docker pull ghcr.io/binmgr/icecast:build

# Build for amd64
mkdir -p output
docker run --rm -it --name icecast-build \
  --platform=linux/amd64 \
  -v "$(pwd)/output:/output" \
  ghcr.io/binmgr/icecast:build \
  build-icecast amd64

# Build for arm64 (requires QEMU or native arm64 host)
docker run --rm -it --name icecast-build \
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

## Troubleshooting

**Binary won't execute**
```bash
chmod +x icecast-linux-*
uname -m  # Must be x86_64 (amd64) or aarch64 (arm64)
```

**Port already in use**
```bash
sudo lsof -i :8000
# Change port in icecast.xml or stop the conflicting process
```

**Permission denied on log/web directories**
Icecast needs write access to the log directory and read access to the web and admin roots. Either run as a user with those permissions or adjust ownership.

---

## Security

To report a vulnerability privately, see [SECURITY.md](.github/SECURITY.md).

For issues with Icecast itself, report to [upstream](https://gitlab.xiph.org/xiph/icecast-server/issues).
For issues with these builds or the Docker image, open an [issue](../../issues) here.

---

## Credits & License

- **Icecast**: [Xiph.Org Foundation](https://www.xiph.org/) — GPL-2.0
- **Build workflow**: MIT License

### Links

- [Upstream Icecast source](https://github.com/xiph/Icecast-Server)
- [Official Icecast documentation](https://icecast.org/docs/)
- [Icecast.org](https://icecast.org/)
