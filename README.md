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
export ldap_host="ldap.internal.theta42.com"
export ldap_base_dn="dc=theta42,dc=com"

# Service account for LDAP binds
export ldap_bind_dn="cn=ldapclient service,ou=People,$ldap_base_dn"
export ldap_bind_password="your-service-account-password"

# SSO Manager integration (optional)
export sso_url="https://sso.theta42.com"
export sso_token="your-api-token"

# Location identifier for group naming (optional)
export ldap_location="718it"
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
| `ldap_location` | No | Location prefix for group names (e.g., `718it`). If omitted, group-based access control will not be configured |

#### Group configuration

The script uses two arrays to define which LDAP groups grant access:

```bash
ldap_access_groups=( "${ldap_location}_access" "${ldap_location}_$(hostname)_access" )
ldap_sudo_groups=( "${ldap_location}_admin" "${ldap_location}_$(hostname)_admin" )
```

This creates both location-wide and host-specific groups:
- `718it_access` - grants login access to all hosts in this location
- `718it_host_webserver01_access` - grants login access only to webserver01
- `718it_admin` - grants sudo privileges on all hosts
- `718it_host_webserver01_admin` - grants sudo privileges only on webserver01

If `ldap_location` is not set, these arrays will be empty and access control will be handled entirely by LDAP-side configuration.

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
  ldap.vars.theta42     # Example configuration for theta42
  files/
    sssd.conf.mo        # SSSD configuration template (Mustache)
    ldap-ssh-key.sh     # SSH AuthorizedKeysCommand script
    sudo-ldap.conf      # LDAP sudo configuration template
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

- [theta42/sso-manager-node](https://github.com/theta42/sso-manager-node) - Centralized SSO and LDAP management

## License

This project is provided as-is for internal use.
