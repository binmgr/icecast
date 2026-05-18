# icecast — Project Rule Overrides

Overrides for rules that conflict with this project's design.
AI.md > SPEC.md > global ~/.claude/CLAUDE.md.

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
