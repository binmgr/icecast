# Icecast - Static Binary Builds

Automated builds of static [Icecast](https://github.com/xiph/Icecast-Server) server binaries for **Linux** (amd64/arm64).

## What is Icecast?

Icecast is a streaming media server which currently supports Ogg Vorbis, Opus, WebM, and MP3 audio streams. It can be used to create an Internet radio station or a privately running jukebox and many things in between.

### Key Features

- Stream Ogg Vorbis, Opus, WebM, and MP3
- Theora video streaming
- Web-based administration interface
- Icecast directory listing support (YP)
- Stream authentication
- On-demand file serving
- Virtual hosting support
- Multiple mount points
- Detailed statistics and logging
- Customizable with XSLT

## Features in These Builds

All optional features are compiled in:

- ✅ XML configuration (libxml2, libxslt)
- ✅ Ogg Vorbis streaming (libvorbis)
- ✅ Theora video streaming (libtheora)
- ✅ Speex codec support (libspeex)
- ✅ TLS/SSL support (OpenSSL)
- ✅ YP directory support (libcurl)
- ✅ GeoIP location lookups (libmaxminddb)
- ✅ IPv6 support
- ✅ Authentication and admin interface

### Static Binaries

Built as fully static Linux binaries on Alpine Linux:

**Static (built-in)**:
- All codec libraries (Vorbis, Theora, Speex)
- XML processing (libxml2, libxslt)
- SSL/TLS support (OpenSSL)
- HTTP client (libcurl)
- GeoIP lookups (libmaxminddb)
- All dependencies

## Downloads

See [Releases](../../releases) for downloads.

### Available Builds

Each release includes binaries for:

| Platform | Architectures | Notes |
|----------|---------------|-------|
| **Linux** | amd64, arm64 | Fully static |

Plus:
- **SHA256SUMS.txt** - Checksums for verification

## Quick Start

### Linux

```bash
# Download the appropriate binary for your architecture
wget https://github.com/binmgr/icecast/releases/latest/download/icecast-linux-amd64

# Make it executable
chmod +x icecast-linux-amd64

# Rename for convenience (optional)
mv icecast-linux-amd64 icecast

# Run (needs config file)
./icecast -c /path/to/icecast.xml
```

### Verify Integrity (Optional)

```bash
# Download checksums
wget https://github.com/binmgr/icecast/releases/latest/download/SHA256SUMS.txt

# Verify
sha256sum -c SHA256SUMS.txt --ignore-missing
```

## Configuration

Create an `icecast.xml` configuration file. See the [upstream example](https://github.com/xiph/Icecast-Server/blob/master/conf/icecast.xml.dist):

```xml
<icecast>
    <limits>
        <clients>100</clients>
        <sources>2</sources>
        <queue-size>524288</queue-size>
        <client-timeout>30</client-timeout>
        <header-timeout>15</header-timeout>
        <source-timeout>10</source-timeout>
        <burst-on-connect>1</burst-on-connect>
        <burst-size>65535</burst-size>
    </limits>

    <authentication>
        <source-password>hackme</source-password>
        <admin-user>admin</admin-user>
        <admin-password>hackme</admin-password>
    </authentication>

    <hostname>localhost</hostname>
    <listen-socket>
        <port>8000</port>
    </listen-socket>

    <fileserve>1</fileserve>

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

Then run:

```bash
./icecast -c icecast.xml
```

## Command-Line Options

```
Usage: icecast [options]
Options:
  -c <file>    Specify configuration file
  -v           Display version and build information
  -b           Run in background (daemon mode)
```

## Build System

This repository contains two GitHub Actions workflows: [.github/workflows/build-env-image.yml](.github/workflows/build-env-image.yml) maintains the reusable Linux build image, and [.github/workflows/build-linux-binaries.yml](.github/workflows/build-linux-binaries.yml) builds and releases the static Linux binaries.

The Linux builds run inside the reusable `ghcr.io/binmgr/icecast:build` image, which is produced from [docker/Dockerfile.build](docker/Dockerfile.build).

### How It Works

1. **Triggers**: The build environment image refreshes on push, quarterly schedule, or manual dispatch; binary releases run on workflow dispatch, direct workflow changes, or after the environment image finishes successfully
2. **Build image**: Uses a reusable Alpine-based build container published as `ghcr.io/binmgr/icecast:build`
3. **Dependencies**: Alpine static packages are reused where possible; Speex, librhash, and libigloo are built from source for a fully static link
4. **Architectures**: GitHub Actions runs the build container as `linux/amd64` and `linux/arm64`, so each binary is built natively for its target architecture
5. **Release**: Automatic GitHub release with versioned binaries, checksums, and multi-arch container tags

### What Gets Built

**From Alpine packages:**
- zlib, libogg, libvorbis, libtheora (core codecs)
- OpenSSL (TLS/SSL)
- libcurl and its static link dependencies (HTTP client / YP)
- libxml2, libxslt (XML/XSLT)
- libmaxminddb (GeoIP lookups)
- All standard build tools and compilers

**Built from source:**
- speex (static library)
- librhash (hash functions)
- libigloo (Icecast common framework)
- Icecast (with all features enabled)

### Build Times

Approximate build times per platform:
- **Linux amd64**: ~5-10 minutes
- **Linux arm64**: ~8-15 minutes

## Platform Compatibility

### Supported

- **Linux (any distribution)**: x86_64, aarch64
  - Debian/Ubuntu
  - RHEL/CentOS/Rocky/Alma/Fedora
  - Alpine
  - Arch
  - Any other Linux distribution

## Troubleshooting

### Binary won't execute

```bash
# Make sure it's executable
chmod +x icecast-linux-*

# Check architecture matches your system
uname -m  # Should be x86_64 or aarch64
```

### Configuration file errors

Check your `icecast.xml`:
- Paths exist and are writable
- Ports are not in use
- Valid XML syntax

### Port already in use

```bash
# Check what's using port 8000
sudo lsof -i :8000

# Kill the process or change the port in icecast.xml
```

### Permission denied errors

Icecast needs permissions for:
- Log directory (specified in config)
- Web root directory
- Admin root directory

Either run as root or adjust file permissions.

## Credits

- **Icecast original**: [Xiph.Org Foundation](https://www.xiph.org/)
- **Static builds**: This repository

## License

- **Icecast**: GPL-2.0 (see [LICENSE.md](LICENSE.md))
- **Build workflow**: MIT License

## Links

- [Upstream Icecast source](https://github.com/xiph/Icecast-Server)
- [Official Icecast documentation](https://icecast.org/docs/)
- [Icecast.org](https://icecast.org/)

## Support

For issues with:
- **Icecast itself**: Report to [upstream](https://gitlab.xiph.org/xiph/icecast-server/issues)
- **These builds**: Report to [this repository](../../issues)

## Local Testing with Docker

Test builds locally using the repository's reusable build image.

### Quick Start

**Build the reusable environment image:**
```bash
docker build -f docker/Dockerfile.build -t icecast-build .
```

**Build Icecast (Linux amd64):**
```bash
mkdir -p output
docker run --rm --platform=linux/amd64 -v "$(pwd)/output:/output" icecast-build build-icecast amd64
```

**Build Icecast (Linux arm64):**
```bash
mkdir -p output
docker run --rm --platform=linux/arm64 -v "$(pwd)/output:/output" icecast-build build-icecast arm64
```

### Expected Build Times

| Build | Time | Notes |
|-------|------|-------|
| Linux amd64 | ~5-10 min | Native build inside the reusable container |
| Linux arm64 | ~8-15 min | Native arm64 container build, typically via QEMU on x86 runners |

The reusable build image keeps release builds consistent and ensures both architectures are produced from the same dependency set.
