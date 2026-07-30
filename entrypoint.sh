#!/bin/bash
# Container entrypoint: trust the local dev stack's self-signed LDAPS cert,
# run index.sh against the mounted ldap.vars, then start sssd + sshd directly
# (no systemd/init system in a plain container -- see the Dockerfile comment).
set -e

if [ -f /config/ldap-ca.crt ]; then
	cp /config/ldap-ca.crt /usr/local/share/ca-certificates/theta-local-ldap.crt
	update-ca-certificates
fi

if [ ! -f /config/ldap.vars ]; then
	echo "entrypoint: /config/ldap.vars not mounted -- copy ldap.vars.template and fill it in" >&2
	exit 1
fi
cp /config/ldap.vars /opt/ldap-client/ldap.vars

cd /opt/ldap-client
./index.sh

ssh-keygen -A
mkdir -p /run/sshd

sssd -i &
exec /usr/sbin/sshd -D -e
