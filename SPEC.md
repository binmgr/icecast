# icecast — Project Rule Overrides

Overrides for rules that conflict with this project's design.
AI.md > SPEC.md > global ~/.claude/CLAUDE.md.

---

## Local source patch

Global project rules prefer unmodified upstream source. Icecast has no setting for the public port in generated playlists and ignores a portless `Host` header, so the build applies the patches in `docker/patches/` before compiling. `build-icecast` stops on any patch that fails to apply; update the patch when upstream changes the surrounding code. Do not drop the patch without replacing the proxy-safe playlist behavior.

---

## Toolchain container

Global conventions prescribe language-specific toolchain images
(`golang:alpine`, `rust:alpine`, `node:alpine`, etc.). This project
has no such language runtime. The toolchain is the custom build
environment image:

```
ghcr.io/binmgr/icecast:build
```

All compilation runs inside this image. Invocation pattern:

```bash
docker run --rm -it --name icecast-XXXX \
  --platform=linux/<arch> \
  -v /output:/output \
  ghcr.io/binmgr/icecast:build \
  build-icecast <arch>
```

The image is rebuilt quarterly (or on `docker/Dockerfile.build` change)
via `.github/workflows/build-env-image.yml`. Never substitute a generic
Alpine or language image — the pre-compiled static deps (Speex,
librhash, libigloo) exist only inside `ghcr.io/binmgr/icecast:build`.
