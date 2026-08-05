#!/bin/bash
set -e
source lib/mo

if [ ! -f ./ldap.vars ]; then
    echo "ldap.vars file not found!"
    exit 1
fi

source ldap.vars
export current_host=$(hostname)

# Install SSSD and required tools
# We use sssd-ldap for the backend and libnss-sss/libpam-sss for the system hooks
DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt install -y sudo sssd sssd-ldap libnss-sss libpam-sss ldap-utils libsss-sudo curl libsasl2-modules-gssapi-mit

# Create the SSSD configuration from template
mkdir -p /etc/sssd
cat files/sssd.conf.mo | mo > /etc/sssd/sssd.conf
chmod 600 /etc/sssd/sssd.conf

# Ensure nsswitch uses sss for passwd, group, and sudoers
sed -i 's/^passwd:.*/passwd:         files sss/' /etc/nsswitch.conf
sed -i 's/^group:.*/group:          files sss/' /etc/nsswitch.conf
if ! grep -q "sudoers:" /etc/nsswitch.conf; then
    echo "sudoers:        files sss" >> /etc/nsswitch.conf
else
    sed -i 's/^sudoers:.*/sudoers:        files sss/' /etc/nsswitch.conf
fi

# Enable home directory creation
pam-auth-update --enable mkhomedir

# Restart SSSD
systemctl restart sssd
systemctl enable sssd

# --- Maintain Custom SSH Key Script ---
cat files/ldap-ssh-key.sh | mo > /usr/local/bin/ldap-ssh-key
chmod +x /usr/local/bin/ldap-ssh-key

# Update SSHD config if not already present
if ! grep -q "AuthorizedKeysCommand /usr/local/bin/ldap-ssh-key" /etc/ssh/sshd_config; then
    echo "AuthorizedKeysCommand /usr/local/bin/ldap-ssh-key" >> /etc/ssh/sshd_config
    echo "AuthorizedKeysCommandUser nobody" >> /etc/ssh/sshd_config
    systemctl restart ssh
fi

systemctl enable --now sssd-sudo.socket

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
    
    parent_field=""
    if [[ -n "$ldap_location" ]]; then
        parent_field="\"parentSlug\":\"site_${ldap_location}\","
    fi

    # Post to Directory API with metadata payload
    curl -sS "${sso_url}/api/directory-admin/resources" \
      -H "Authorization: Bearer ${sso_token}" \
      -H "content-type: application/json; charset=UTF-8" \
      --data-binary "{\"name\":\"${current_host}\",\"slug\":\"host_${current_host}\",\"kind\":\"host\",${parent_field}\"description\":\"Auto-registered Linux host\",\"metadata\":{\"ip\":\"${host_ip}\",\"macAddress\":\"${host_mac}\",\"os\":\"${os_name}\",\"kernel\":\"${kernel_ver}\",\"subType\":\"linux\"}}"
fi

echo "--- SSSD Migration Complete! ---"
echo "Please verify authentication and user access."