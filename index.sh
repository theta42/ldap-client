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
DEBIAN_FRONTEND=noninteractive apt install -y sssd sssd-ldap libnss-sss libpam-sss ldap-utils libsss-sudo curl libsasl2-modules-gssapi-mit

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

# --- SSO Group Creation API Calls ---
if [[ -v sso_token ]]; then
    echo "Registering host groups via API..."
    # (Existing curl logic remains here)
fi
