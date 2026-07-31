# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions
correspond to git tags (`vX.Y.Z`).

## [1.1.0] - 2026-07-30

### Added
- `app_super_admin` and `app_jump_admin` group support in SSSD access filters for SSH login on every host.
- TLS configuration divergence: `sso` enforces cert validation, `jump-host` disables it. Shared `@simpleworkjs/ldap` makeClient must not impose a default.

## [1.0.0] - 2026-07-20

### Added
- Initial release with SSSD LDAP authentication, group-based access control, SSH key injection, and sudo privileges.