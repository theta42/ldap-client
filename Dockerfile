# Test/dev image: a real SSSD+sshd downstream host, provisioned by this
# repo's own index.sh, for exercising jump-host's actual key-injection ->
# upstream-connect flow against a genuinely LDAP-joined machine (not just a
# container with a manually-dropped public key in authorized_keys).
#
# No systemd here (this is a plain container, not a VM) -- sssd and sshd are
# started directly by entrypoint.sh, same non-systemd pattern sso-manager-node's
# own Dockerfile.openldap uses for slapd. index.sh's systemctl calls are
# no-ops via the stub below; sssd/sshd are (re)started for real by the
# entrypoint that runs after it.
FROM ubuntu:22.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
		openssh-server sudo sssd sssd-ldap libnss-sss libpam-sss ldap-utils \
		libsss-sudo curl libsasl2-modules-gssapi-mit ca-certificates bash iproute2 \
	&& rm -rf /var/lib/apt/lists/*

# index.sh calls `systemctl restart/enable ...` several times; we run sssd/sshd
# ourselves in entrypoint.sh instead, so these just need to not fail the script.
RUN printf '#!/bin/sh\nexit 0\n' > /usr/bin/systemctl && chmod +x /usr/bin/systemctl

RUN mkdir -p /opt/ldap-client
COPY index.sh ldap.vars.template /opt/ldap-client/
COPY files/ /opt/ldap-client/files/
COPY lib/ /opt/ldap-client/lib/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /opt/ldap-client/index.sh /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
