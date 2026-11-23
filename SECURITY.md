# Security Policy

## Local-First Privacy Architecture

- **100% On-Device Media Processing**: XShot performs screen capture, scrolling stitching, Apple Vision OCR text extraction, automatic secret/privacy redaction (API keys, emails, phone numbers, IPs, cards), and Metal GPU video compositing **entirely on your Mac**.
- **Zero Media Uploads / Zero Telemetry**: XShot never uploads screenshots, recordings, webcam tracks, or recognized OCR text to external servers.
- **Optional Network Connections Only**:
  - **Software Updates**: Queries GitHub Releases (`api.github.com/repos/zsai001/xshot/releases`) for new versions and verifies SHA-256 checksums + bundle code signatures before applying seamless in-place updates.
  - **XTags Account Sign-In (Optional)**: Connects to `api.xtags.top` only when you explicitly sign in with your XTags account to unlock seamless background auto-updates. Session tokens are stored locally with strict `0600` user-only permissions.

## Reporting a Vulnerability

If you discover a security vulnerability in **XShot**, please **do not** open a public GitHub issue with exploit details.

Instead, report it privately via GitHub Security Advisories on this repository so maintainers can verify and patch the issue responsibly before public disclosure.
