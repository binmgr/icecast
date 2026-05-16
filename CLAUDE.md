# icecast — Claude loader

See **[AI.md](AI.md)** for the implementation spec (THE HOW).
See **[IDEA.md](IDEA.md)** for the project description, variables, and business logic (THE WHAT).

If AI.md and IDEA.md conflict, **AI.md wins** — fix IDEA.md to match.

---

## Quick rules for this project

**Files**
- No `Dockerfile` at the repo root — ever. Runtime image lives at `docker/Dockerfile.runtime`
- Workflow files only in `.github/workflows/` and `.gitea/workflows/`
- `docker/rootfs/` is the container filesystem overlay — keep it tidy

**Docker images**
- Base image is always `alpine:latest` — rolling, never pinned
- Startup chain is `tini → entrypoint.sh → icecast` — never bypass tini
- All `docker run` calls in CI must include `--rm`

**Build order**
- Source deps compile in this fixed order: **Speex → librhash → libigloo**
  (libigloo requires librhash; reversing it breaks the build)

**GitHub Actions**
- Every `uses:` must be pinned to a full commit SHA — no `@v4`, `@main`, or tags
- Current SHAs are in AI.md PART 5. Update the table there whenever a pin changes
- `build-linux-binaries.yml` must never list itself in its own `paths:` push trigger —
  that caused a race condition where the binary build fired before the build image existed

**Secrets**
- `GITHUB_TOKEN` is the only GitHub secret needed — never hardcode credentials
- `GITEA_TOKEN` is the only Gitea secret needed — injected at runtime only

**Releases**
- `VERSION` is extracted from upstream `configure.ac` at build time — never stored here
- Release tag format: `v<VERSION>`; Docker tags: `latest`, `<VERSION>`, `<YYMM>`

**Gitea vs GitHub**
- Gitea workflow has **no push trigger** — schedule and dispatch only
- Gitea builds the env image locally before using it (no GHCR pull)
- Gitea releases use `curl` to the Gitea API — no `gh` CLI, no GHCR push
