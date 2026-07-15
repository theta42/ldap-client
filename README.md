# LDAP Client

Bash-based SSSD LDAP authentication client for Ubuntu/Debian systems. Integrates with [theta42/sso-manager-node](https://github.com/theta42/sso-manager-node) for centralized user management, group-based access control, and SSH key distribution.

## Overview

This script automates the configuration of SSSD (System Security Services Daemon) to provide:

- LDAP authentication against a central directory
- Group-based access control (only authorized users can log in)
- Sudo privileges via LDAP groups
- SSH public key retrieval from LDAP for key-based authentication
- Automatic home directory creation for LDAP users
- Optional registration of host-specific groups via the SSO Manager API

## Prerequisites

- Ubuntu or Debian system with root access
- Network connectivity to your LDAP server (LDAPS on port 636)
- LDAP service account credentials
- CA certificates for LDAP TLS validation
- (Optional) SSO Manager instance for group API registration

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/theta42/ldap-client.git
cd ldap-client
```

### 2. Create configuration

Copy the template configuration file:

```bash
cp ldap.vars.template ldap.vars
```

### 3. Configure variables

Edit `ldap.vars` with your environment settings:

```bash
# LDAP server settings
export ldap_host="ldap.internal.example.com"
export ldap_base_dn="dc=example,dc=com"

# Service account for LDAP binds (a plain user, not the admin DN --
# see sso-manager-node's docs/ldap.md "Direct-bind service accounts")
export ldap_bind_dn="cn=ldapclient,ou=People,$ldap_base_dn"
export ldap_bind_password="your-service-account-password"

# SSO Manager integration (optional)
export sso_url="https://sso.example.com"
export sso_token="your-api-token"

# Location identifier for group naming (optional) -- e.g. a site or
# datacenter name if you run this against more than one location
export ldap_location="mylocation"
```

#### Variable descriptions

| Variable | Required | Description |
|----------|----------|-------------|
| `ldap_host` | Yes | LDAP server hostname |
| `ldap_base_dn` | Yes | Base DN for LDAP searches |
| `ldap_bind_dn` | Yes | DN of the service account for LDAP binds |
| `ldap_bind_password` | Yes | Password for the service account |
| `sso_url` | No | Base URL of the SSO Manager API |
| `sso_token` | No | API authentication token for SSO Manager |
| `ldap_location` | No | Location prefix for group names (e.g., `nyc`, `dc1`) if you run this against more than one site. If omitted, the group names fall back to unprefixed `_access`/`_admin` (see *Group naming* below) |

#### Group naming

Login access and sudo are both group-based, using one consistent naming
scheme across `files/sssd.conf.mo` (the actual enforcement — SSSD's
`ldap_access_filter` / `ldap_sudo_search_filter`), `files/ldap-ssh-key.sh`
(which SSH keys get served), and the groups `index.sh` auto-creates via the
SSO Manager API:

- `<location>_access` — grants login access to **all** hosts in this location
- `<location>_host_<hostname>_access` — grants login access only to `<hostname>`
- `<location>_admin` — grants sudo on **all** hosts in this location
- `<location>_host_<hostname>_admin` — grants sudo only on `<hostname>`

e.g. with `ldap_location="mylocation"` on a host named `webserver01`:
`mylocation_access`, `mylocation_host_webserver01_access`, `mylocation_admin`,
`mylocation_host_webserver01_admin`.

`ldap_access_groups` in `ldap.vars` (used only by `ldap-ssh-key.sh`, to decide
who gets an SSH key served) must use this same scheme — the template already
does. If `ldap_location` is left empty, the filters fall back to `_access` /
`_host_<hostname>_access` / etc. (no location prefix) — set `ldap_location`
for anything beyond a single-location setup.

### 4. Run the installation script

```bash
sudo ./index.sh
```

The script will:

1. Install required packages (sssd, sssd-ldap, libnss-sss, libpam-sss, ldap-utils, libsss-sudo)
2. Generate and deploy the SSSD configuration
3. Configure NSS to use SSS for passwd, group, and sudoers lookups
4. Enable automatic home directory creation via PAM
5. Deploy the SSH AuthorizedKeysCommand script
6. Configure SSHD to retrieve keys from LDAP
7. (Optional) Register host-specific groups with the SSO Manager API
8. Start and enable the SSSD service

## Post-installation verification

### Test LDAP user lookup

```bash
getent passwd <ldap-username>
```

### Test group membership

```bash
getent group <group-name>
```

### Test sudo access

```bash
sudo -l -U <ldap-username>
```

### Test SSH key retrieval

```bash
/usr/local/bin/ldap-ssh-key <ldap-username>
```

### Check SSSD status

```bash
systemctl status sssd
journalctl -u sssd -f
```

### Verify authentication

```bash
su - <ldap-username>
```

## File structure

```
ldap-client/
  index.sh              # Main installation script
  ldap.vars.template    # Configuration template (copy to ldap.vars)
  files/
    sssd.conf.mo        # SSSD configuration template (Mustache) -- also
                         # configures SSSD's native LDAP sudo provider
    ldap-ssh-key.sh     # SSH AuthorizedKeysCommand script
  lib/
    mo                  # Mustache template processor
```

## How it works

### Authentication flow

1. User attempts to log in via SSH or console
2. PAM/SSSD queries LDAP for user credentials
3. If user is in an authorized access group, authentication proceeds
4. Home directory is created automatically on first login (via pam_mkhomedir)

### SSH key distribution

1. SSHD calls `/usr/local/bin/ldap-ssh-key` with the username
2. The script queries LDAP for the user's `sshPublicKey` attribute
3. Keys are returned to SSHD for authentication
4. This allows SSH key management through the central directory

### Sudo integration

SSSD is configured with an LDAP sudo provider that:
- Searches for sudo rules in the LDAP directory
- Filters rules based on group membership
- Refreshes rules every 15 minutes (full) or 5 minutes (smart)

### SSO Manager integration

When `sso_token` is configured, the script automatically creates host-specific groups in the SSO Manager:

- `<location>_host_<hostname>_access` - for login access
- `<location>_host_<hostname>_admin` - for sudo privileges

This allows you to manage host-specific access through the SSO Manager web interface.

## Troubleshooting

### SSSD not starting

Check the configuration syntax:

```bash
sssd --genconf-only
```

Review logs:

```bash
journalctl -u sssd -f
```

### Users cannot authenticate

1. Verify LDAP connectivity:
   ```bash
   ldapsearch -H ldaps://<ldap_host> -b "<ldap_base_dn>" -D "<bind_dn>" -W
   ```

2. Check group membership in LDAP

3. Verify the `ldap_access_filter` in `/etc/sssd/sssd.conf`

### SSH keys not working

1. Test the key retrieval script directly:
   ```bash
   /usr/local/bin/ldap-ssh-key <username>
   ```

2. Verify `sshPublicKey` attribute exists in LDAP

3. Check SSHD configuration:
   ```bash
   sshd -T | grep authorizedkeys
   ```

### Sudo rules not applying

1. Check sudo provider configuration in `/etc/sssd/sssd.conf`

2. Verify sudo rules exist in LDAP with correct host and group filters

3. Force SSSD refresh:
   ```bash
   sssctl cache-expire --group
   systemctl restart sssd
   ```

## Security considerations

- The LDAP bind password in `ldap.vars` should have restricted filesystem permissions
- SSSD configuration (`/etc/sssd/sssd.conf`) is set to mode 600
- LDAPS (TLS) is required for LDAP connections
- The SSH key script runs as the `nobody` user for minimal privilege

## Related projects

- [theta42/sso-manager-node](https://github.com/theta42/sso-manager-node) — Centralized SSO and LDAP management. See its
  [Connecting a 3rd-party app or container](https://theta42.github.io/sso-manager-node/ldap.html#connecting-a-3rd-party-app-or-container)
  docs if you just need one application to bind LDAP, rather than full host login/SSH/sudo.

## License

MIT License — see [LICENSE](LICENSE).
