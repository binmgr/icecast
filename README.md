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

Built with [musl libc](https://musl.libc.org/) on Alpine Linux:

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
| **Linux** | x86_64, aarch64 | Fully static (musl libc) |

Plus:
- **Source archive** (`icecast-X.X.X-src.tar.gz`) - No VCS files
- **SHA256SUMS.txt** - Checksums for verification

## Quick Start

### Linux

```bash
# Download the appropriate binary for your architecture
wget https://github.com/YOUR-USERNAME/icecast/releases/latest/download/icecast-linux-x86_64

# Make it executable
chmod +x icecast-linux-x86_64

# Rename for convenience (optional)
mv icecast-linux-x86_64 icecast

# Run (needs config file)
./icecast -c /path/to/icecast.xml
```

### Verify Integrity (Optional)

```bash
# Download checksums
wget https://github.com/YOUR-USERNAME/icecast/releases/latest/download/SHA256SUMS.txt

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

This repository contains only the GitHub Actions workflow for automated builds. All build logic is inline in [.github/workflows/build.yml](.github/workflows/build.yml).

### How It Works

1. **Triggers**: Builds run on push to main/master, monthly on the 1st at 00:00 UTC, or manually
2. **Platform**: Uses [binmgr/toolchain](https://github.com/binmgr/toolchain) Docker image (Alpine/musl)
3. **Dependencies**: Pre-installed in toolchain + librhash, libmaxminddb, and libigloo built from source
4. **Icecast**: Built with all features enabled
5. **Release**: Automatic GitHub release with version from upstream

### What Gets Built

**From [binmgr/toolchain](https://github.com/binmgr/toolchain) (pre-installed):**
- zlib, libogg, libvorbis, libtheora, libspeex (codecs)
- OpenSSL (TLS/SSL)
- libcurl (HTTP client)
- libxml2, libxslt (XML/XSLT)
- All standard build tools and compilers

**Built from source:**
- librhash (hash functions)
- libmaxminddb (GeoIP lookups)
- libigloo (Icecast common framework)
- Icecast (with all features enabled)

### Build Times

Approximate build times per platform:
- **Linux x86_64**: ~5-10 minutes (native)
- **Linux aarch64**: ~5-10 minutes (cross-compile)

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

Test builds locally using the [binmgr/toolchain](https://github.com/binmgr/toolchain) Docker image.

### Quick Start

**Pull the toolchain:**
```bash
docker pull ghcr.io/binmgr/toolchain:latest
```

**Build Icecast (Linux x86_64):**
```bash
docker run --rm -v $(pwd):/workspace ghcr.io/binmgr/toolchain:latest sh -c '
  # Run the build script (simplified example)
  cd /workspace
  # ... build commands from workflow ...
'
```

**Build for Linux ARM64 (cross-compile):**
```bash
docker run --rm -v $(pwd):/workspace ghcr.io/binmgr/toolchain:latest sh -c '
  export CC=aarch64-linux-gcc
  export CXX=aarch64-linux-g++
  # ... build commands ...
'
```

### Expected Build Times

| Build | Time | Notes |
|-------|------|-------|
| Linux x86_64 | ~5-10 min | Native build in container |
| Linux aarch64 | ~5-10 min | Cross-compile with pre-built toolchain |

The toolchain image dramatically reduces build times by providing all standard dependencies pre-installed.
