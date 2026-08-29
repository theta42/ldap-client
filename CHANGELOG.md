## [1.26.0] - 2026-08-29
- **Security (C4/H12/M32/M33):** the directory bind password is no longer baked into the world-readable SSH key script or passed on argv (`-w`). It is written to `/etc/ldap-ssh-key.pass` (mode `0640 root:nogroup`) and read via `ldapsearch -y`; the key script now uses `ldaps://` with a configurable `ldap_tls_reqcert` (default `demand`, `never` for loopback).
- **Security (H12):** removed the unconditional `sudoHost`/`sudoCommand` `ALL/ALL` `sudoRole` stamping on new accounts in `sso-manager-node` (`user_ldap.js`); the native SSSD `sudo_provider` and `sssd-sudo.socket` are intentionally not enabled until per-host `sudoRole` scoping exists (design-gap D5).
- **Fix (H11):** location/host names are now slugified (contract G-5) before use in `ldap_access_filter` and the directory registration payload, so non-slug names no longer cause silent total lockout.
- **Fix (M32):** `mo` renders with `--fail-not-set` (aborts on unset vars instead of silent empty values); `nsswitch.conf` is backed up before cutover with rollback if SSSD fails to come up; rendered configs are written under `umask 0077`; the SSHD block guards both `AuthorizedKeysCommand` and `AuthorizedKeysCommandUser`; registration uses `curl -f` with an HTTP-status check.
- **Fix (M33):** the directory registration payload is built with real JSON encoding (`jq` → `python3` → `node`), never by interpolating values into a JSON string.
- **Docs (L9):** README no longer claims "sudo via LDAP groups"; corrected to match the current (unscoped) state. `ldap_tls_reqcert` added to `ldap.vars` (operator + generated).

## [1.25.2] - 2026-08-23

## [1.25.1] - 2026-08-22
- Added docs/KNOWN_ISSUES.md for multi-site known limits and tradeoffs.
