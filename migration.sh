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

./index.sh
