#!/bin/bash
set -e

# Pull in the mustache template library for bash
source lib/mo

if [ ! -f ./ldap.vars ]; then
    echo "ldap.vars file not found!"
    echo "Please copy ldap.vars.template to ldap.vars and edit it."
    exit 1
fi

source ldap.vars
export current_host=$(hostname)

echo "--- Starting LDAP to SSSD Migration ---"

echo "1. Cleaning up old LDAP configuration and packages..."

# 1. Remove old packages (libnss-ldap, libpam-ldap, sudo-ldap, nscd, etc.)
DEBIAN_FRONTEND=noninteractive apt purge -y libnss-ldap libpam-ldap nscd sudo-ldap nslcd

# Preserve ldap-utils if it's still useful for general LDAP querying
# apt purge -y ldap-utils

# 2. Clean up old configuration files
echo "  - Removing old configuration files..."
rm -f /etc/pam_ldap.conf
rm -f /etc/ldap/ldap.conf
rm -f /etc/ldap.conf
rm -f /etc/sudo-ldap.conf

# 3. Revert nsswitch.conf entries related to 'ldap'
echo "  - Reverting /etc/nsswitch.conf entries for 'ldap'..."
sed -i '/passwd:/ s/ ldap//' /etc/nsswitch.conf
sed -i '/group:/ s/ ldap//' /etc/nsswitch.conf
# You might want to review other services like 'shadow' or 'hosts' if they also had 'ldap'
# For example: sed -i '/shadow:/ s/ ldap//' /etc/nsswitch.conf

# 4. Clean up PAM configurations
echo "  - Cleaning up old PAM configurations..."
# Disable 'ldap' in pam-auth-update if it was enabled directly
pam-auth-update --remove ldap

# Remove specific common-password modifications made by the old script
# The old script removed 'use_authtok'. Let's ensure a clean state if SSSD needs a different one.
# It's generally safer to restore from a backup or let the new SSSD setup configure PAM.
# For simplicity, we'll rely on the new sssd pam module to set things correctly.
sed -i '/session required pam_mkhomedir.so skel=\/etc\/skel umask=077/d' /etc/pam.d/common-session

# Ensure nscd is stopped and disabled if it wasn't purged
systemctl stop nscd || true
systemctl disable nscd || true

echo "Cleanup complete."
echo "--- Installing New SSSD Configuration ---"

# Install SSSD and required tools
# We use sssd-ldap for the backend and libnss-sss/libpam-sss for the system hooks
DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt install -y sudo sssd sssd-ldap libnss-sss libpam-sss ldap-utils libsss-sudo curl libsasl2-modules-gssapi-mit

# Create the SSSD configuration from template
mkdir -p /etc/sssd
echo "  - Creating /etc/sssd/sssd.conf from template..."
cat files/sssd.conf.mo | mo > /etc/sssd/sssd.conf
chmod 600 /etc/sssd/sssd.conf

# Ensure nsswitch uses sss for passwd, group, and sudoers
echo "  - Updating /etc/nsswitch.conf for SSSD..."
sed -i 's/^passwd:.*/passwd:         files sss/' /etc/nsswitch.conf
sed -i 's/^group:.*/group:          files sss/' /etc/nsswitch.conf
if ! grep -q "sudoers:" /etc/nsswitch.conf; then
    echo "sudoers:        files sss" >> /etc/nsswitch.conf
else
    sed -i 's/^sudoers:.*/sudoers:        files sss/' /etc/nsswitch.conf
fi

# Enable home directory creation (this should already be handled by pam-auth-update)
# Double-check this line if it causes issues; pam-auth-update should configure /etc/pam.d/common-session
# pam-auth-update --enable mkhomedir

# Restart SSSD
echo "  - Restarting and enabling SSSD service..."
systemctl restart sssd
systemctl enable sssd

# --- Maintain Custom SSH Key Script ---
echo "  - Setting up custom SSH key script..."
cat files/ldap-ssh-key.sh | mo > /usr/local/bin/ldap-ssh-key
chmod +x /usr/local/bin/ldap-ssh-key

# Update SSHD config if not already present
echo "  - Configuring SSHD for LDAP SSH keys..."
if ! grep -q "AuthorizedKeysCommand /usr/local/bin/ldap-ssh-key" /etc/ssh/sshd_config; then
    echo "AuthorizedKeysCommand /usr/local/bin/ldap-ssh-key" >> /etc/ssh/sshd_config
    echo "AuthorizedKeysCommandUser nobody" >> /etc/ssh/sshd_config
    systemctl restart sshd
else
    # If the lines exist, just ensure sshd is restarted in case it wasn't earlier
    systemctl restart sshd
fi

echo "  - Enabling sssd-sudo socket..."
systemctl enable --now sssd-sudo.socket

# --- SSO Group Creation API Calls ---
if [[ -v sso_token ]]; then
    echo "  - Registering host groups via API..."
    # (Existing curl logic remains here)
    curl "${sso_url}/api/group/" \
        -H "auth-token: ${sso_token}" \
        -H "content-type: application/json; charset=UTF-8" \
        --data-binary "{\"name\":\"host_${current_host}_access\",\"description\":\"Access for $current_host\"}"
    curl "${sso_url}/api/group/" \
        -H "auth-token: ${sso_token}" \
        -H "content-type: application/json; charset=UTF-8" \
        --data-binary "{\"name\":\"host_${current_host}_admin\",\"description\":\"sudo for $current_host\"}"
fi

echo "--- SSSD Migration Complete! ---"
echo "Please verify authentication and user access."
