# Security Policy

## Supported Versions

Only the most recent release is supported with security fixes. Older tags are
not patched — update to the latest release.

| Version | Supported |
|---------|-----------|
| latest  | ✅ |
| older   | ❌ |

## Reporting a Vulnerability

**Do not file a public GitHub issue for security vulnerabilities.**

Report vulnerabilities privately by email to: **casjay@yahoo.com**

Please include:
- A description of the vulnerability and its impact
- Steps to reproduce or a proof-of-concept
- Affected versions / architectures
- Any suggested remediation if known

### Response Timeline

- **Acknowledgement**: within 48 hours
- **Initial assessment**: within 7 days
- **Patch / advisory**: within 90 days of confirmation

We follow coordinated disclosure. We will credit reporters in the release notes
unless anonymity is requested.

## Scope

This repository contains only build scripts, CI/CD workflows, and a runtime
Docker image for [Icecast](https://github.com/xiph/Icecast-Server). Vulnerabilities
in Icecast itself should be reported upstream to the
[Xiph.Org project](https://gitlab.xiph.org/xiph/icecast-server/-/issues).

Security issues in scope here:
- Secrets or credentials accidentally committed to this repo
- Vulnerabilities in the Docker image or entrypoint script
- CI/CD pipeline supply-chain issues
- Insecure defaults in the generated `icecast.xml`
