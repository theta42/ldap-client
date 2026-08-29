#!/bin/bash
set -e
source ./lib/mo

if [ ! -f ./ldap.vars ]; then
    echo "ldap.vars file not found!"
    exit 1
fi

source ./ldap.vars
export current_host=$(hostname)

# Contract G-5 slug rule: lower | [^a-z0-9]+ -> "-" | trim "-". The directory
# creates group/resource names with this exact rule (bootstrap.js slugify), so
# the enrollment side must derive the same slugs itself -- otherwise any
# non-slug location/hostname silently locks the host out of every group (H11).
slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g'
}
export ldap_location_slug="$(slugify "${ldap_location}")"
export current_host_slug="$(slugify "${current_host}")"

# The access-group list is derived from the (slugified) location + host, the
# same convention sssd.conf.mo's ldap_access_filter and the SSO group model use.
ldap_access_groups=( "site_${ldap_location_slug}_hosts_access" "site_${ldap_location_slug}_host_${current_host_slug}_access" "god_admin" )

# Install SSSD and required tools
DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt install -y sudo sssd sssd-ldap libnss-sss libpam-sss ldap-utils libsss-sudo curl libsasl2-modules-gssapi-mit

# Back up nsswitch.conf before any cutover so a failed SSSD bring-up can be
# rolled back instead of leaving the host unable to resolve local logins (M32).
cp /etc/nsswitch.conf /etc/nsswitch.conf.bak

# Create the SSSD configuration from template.
# --fail-not-set (M32): abort on an unset var instead of silently rendering it
# empty, which previously produced a broken/unreachable config. umask 0077 closes
# the window in which the rendered file (it carries the bind password) is
# world-readable before we chmod it.
mkdir -p /etc/sssd
(umask 0077; cat files/sssd.conf.mo | mo --fail-not-set > /etc/sssd/sssd.conf)
chmod 600 /etc/sssd/sssd.conf

# Start SSSD and confirm it comes up BEFORE cutting nsswitch over to it, so a bad
# config or unreachable LDAP can't lock us out of local accounts. Roll back the
# nsswitch backup on failure (M32).
if command -v sssctl >/dev/null 2>&1; then
    sssctl config-check >/dev/null 2>&1 || {
        echo "sssd config-check failed -- restoring nsswitch from backup" >&2
        cp /etc/nsswitch.conf.bak /etc/nsswitch.conf
        exit 1
    }
fi
systemctl restart sssd || {
    echo "sssd failed to start -- restoring nsswitch from backup" >&2
    cp /etc/nsswitch.conf.bak /etc/nsswitch.conf
    exit 1
}
sleep 1
systemctl is-active --quiet sssd || {
    echo "sssd not active -- restoring nsswitch from backup" >&2
    cp /etc/nsswitch.conf.bak /etc/nsswitch.conf
    systemctl restart sssd || true
    exit 1
}

# Now that SSSD is up, point nsswitch at it for passwd, group, and sudoers.
sed -i 's/^passwd:.*/passwd:         files sss/' /etc/nsswitch.conf
sed -i 's/^group:.*/group:          files sss/' /etc/nsswitch.conf
if ! grep -q "sudoers:" /etc/nsswitch.conf; then
    echo "sudoers:        files sss" >> /etc/nsswitch.conf
else
    sed -i 's/^sudoers:.*/sudoers:        files sss/' /etc/nsswitch.conf
fi

# Enable home directory creation
pam-auth-update --enable mkhomedir

systemctl enable sssd

# --- Maintain Custom SSH Key Script ---
# The bind password is stored in a root:nogroup 0640 file the script reads via
# `ldapsearch -y` (C4) -- never baked into the world-readable script or passed
# via argv (-w), which previously exposed it to every local process.
printf '%s' "$ldap_bind_password" > /etc/ldap-ssh-key.pass
chown root:nogroup /etc/ldap-ssh-key.pass
chmod 0640 /etc/ldap-ssh-key.pass

(umask 0077; cat files/ldap-ssh-key.sh | mo --fail-not-set > /usr/local/bin/ldap-ssh-key)
chmod +x /usr/local/bin/ldap-ssh-key

# Update SSHD config if not already present. Guard on BOTH the command and the
# user (M32): a half-applied or diverging config (command set but user missing,
# or pointing at a different user) is reconciled rather than skipped.
needs_ssh_restart=false
if ! grep -q "^AuthorizedKeysCommand /usr/local/bin/ldap-ssh-key" /etc/ssh/sshd_config; then
    echo "AuthorizedKeysCommand /usr/local/bin/ldap-ssh-key" >> /etc/ssh/sshd_config
    needs_ssh_restart=true
fi
if ! grep -q "^AuthorizedKeysCommandUser nobody" /etc/ssh/sshd_config; then
    echo "AuthorizedKeysCommandUser nobody" >> /etc/ssh/sshd_config
    needs_ssh_restart=true
fi
if [[ "$needs_ssh_restart" == "true" ]]; then
    systemctl restart ssh
fi

# The native LDAP sudo provider / sssd-sudo.socket are intentionally NOT enabled
# (H12, design-gap D5): the directory does not scope sudoRole per-host, so
# enabling them would grant every account ALL/ALL = universal root.

# Only self-register when a real API token is provided. sso_token is optional
# (ldap.vars ships it empty); `[[ -v ]]` is true even for an empty/declared var,
# so an empty token used to POST /api/directory-admin/resources and get a
# misleading "Invalid Credentials, login failed" (the SSO can't authenticate an
# empty Bearer). The stack host is already seeded by the bootstrap, so an empty
# token must skip, not fail.
if [[ -n "${sso_token:-}" ]]; then
    echo "Registering host in Directory Graph via API..."

    # Collect Host Information
    host_ip=$(hostname -I | awk '{print $1}')

    # Get MAC address of the default route interface
    default_iface=$(ip route show default | awk '/default/ {print $5}')
    host_mac=""
    if [[ -n "$default_iface" ]]; then
        host_mac=$(cat "/sys/class/net/$default_iface/address" 2>/dev/null || echo "")
    fi

    # Get OS and Kernel details (stripping quotes to be JSON safe)
    os_name=$(source /etc/os-release && echo "$PRETTY_NAME" | sed 's/"//g')
    kernel_ver=$(uname -r)

    # Build the registration payload with real JSON encoding -- never by
    # interpolating values into a JSON string (M33). Prefer jq, then python3,
    # then node; each escapes embedded quotes/newlines correctly.
    payload=""
    if command -v jq >/dev/null 2>&1; then
        payload=$(jq -nc \
            --arg name "$current_host" \
            --arg slug "host_${current_host_slug}" \
            --arg parent "$ldap_location_slug" \
            --arg ip "$host_ip" \
            --arg mac "$host_mac" \
            --arg os "$os_name" \
            --arg kernel "$kernel_ver" \
            '{name:$name,slug:$slug,kind:"host"}
             + (if $parent != "" then {parentSlug:("site_"+$parent)} else {} end)
             + {description:"Auto-registered Linux host",metadata:{ip:$ip,macAddress:$mac,os:$os,kernel:$kernel,subType:"linux"}}')
    elif command -v python3 >/dev/null 2>&1; then
        payload=$(python3 - "$current_host" "host_${current_host_slug}" "$ldap_location_slug" "$host_ip" "$host_mac" "$os_name" "$kernel_ver" <<'PY'
import json, sys
name, slug, parent, ip, mac, os_name, kernel = sys.argv[1:8]
obj = {"name": name, "slug": slug, "kind": "host"}
if parent:
    obj["parentSlug"] = "site_" + parent
obj["description"] = "Auto-registered Linux host"
obj["metadata"] = {"ip": ip, "macAddress": mac, "os": os_name, "kernel": kernel, "subType": "linux"}
print(json.dumps(obj), end="")
PY
)
    elif command -v node >/dev/null 2>&1; then
        payload=$(node -e '
var a = process.argv.slice(1);
var obj = {name:a[0], slug:a[1], kind:"host"};
if (a[2]) obj.parentSlug = "site_" + a[2];
obj.description = "Auto-registered Linux host";
obj.metadata = {ip:a[3], macAddress:a[4], os:a[5], kernel:a[6], subType:"linux"};
process.stdout.write(JSON.stringify(obj));
' "$current_host" "host_${current_host_slug}" "$ldap_location_slug" "$host_ip" "$host_mac" "$os_name" "$kernel_ver")
    fi

    if [[ -z "$payload" ]]; then
        echo "  WARNING: no jq/python3/node available to build registration payload -- skipping" >&2
    else
        # curl -f fails on HTTP 4xx/5xx; capture the code and body so a failed
        # registration is reported rather than printed as success (L9/M32).
        reg_file=$(mktemp)
        http_code=$(curl -fsS -o "$reg_file" -w '%{http_code}' \
            "${sso_url}/api/directory-admin/resources" \
            -H "Authorization: Bearer ${sso_token}" \
            -H "content-type: application/json; charset=UTF-8" \
            --data-binary "$payload") || http_code="000"
        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            echo "  Host registered with Directory (HTTP ${http_code})."
        else
            echo "  WARNING: host registration failed (HTTP ${http_code}): $(head -c 512 "$reg_file")" >&2
        fi
        rm -f "$reg_file"
    fi
fi

echo "--- SSSD Migration Complete! ---"
echo "Please verify authentication and user access."
