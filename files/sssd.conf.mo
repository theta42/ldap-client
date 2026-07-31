[sssd]
config_file_version = 2
domains = default
# Without an explicit services= list, SSSD 2.6.3 (Ubuntu 22.04) starts only
# the backend (sssd_be) -- no nss/pam responder processes -- so
# `getent passwd <ldap-user>` silently fails even though the domain itself is
# online and reachable. Not obvious from any error message; found by noticing
# `ps aux` showed sssd_be running but no sssd_nss/sssd_pam.
services = nss, pam

[domain/default]
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap

ldap_uri = ldaps://{{ldap_host}}
ldap_search_base = {{ldap_base_dn}}
ldap_tls_cacert = /etc/ssl/certs/ca-certificates.crt
# A self-signed dev/test LDAP cert's CN/SAN is usually the site's public
# hostname (e.g. localtest.me), not the internal docker-network name used in
# ldap_uri above (e.g. sso-manager) -- so strict hostname verification fails
# even though the CA itself is trusted (see ldap_tls_cacert above). Same
# already-accepted tradeoff theta-env's own bootstrap.js makes for this exact
# cert (LDAPTLS_REQCERT=never). A real deployment with a cert matching its
# actual LDAP hostname wouldn't need this.
ldap_tls_reqcert = never

ldap_default_bind_dn = {{ldap_bind_dn}}
ldap_default_authtok_type = password
ldap_default_authtok = {{ldap_bind_password}}

# Sudo settings
sudo_provider = ldap
ldap_sudo_search_base = {{ldap_base_dn}}
ldap_sudo_full_refresh_interval = 900
ldap_sudo_smart_refresh_interval = 300
# NOTE: ldap_sudo_search_filter is rejected by SSSD 2.6.3's ini validator
# ("not allowed in section domain/default") -- it isn't a real sssd-ldap(5)
# option on this version, so it's commented out rather than silently no-op'd.
# Sudo scoping to <location>_admin / <location>_host_<hostname>_admin needs a
# different mechanism (native LDAP sudoRole entries, most likely) -- separate
# follow-up, doesn't block SSH login/access-filter testing below.
# ldap_sudo_search_filter = (|(memberOf=cn={{ldap_location}}_admin,ou=groups,{{ldap_base_dn}})(memberOf=cn={{ldap_location}}_host_{{current_host}}_admin,ou=groups,{{ldap_base_dn}}))

# Access control: only allow users in <location>_access,
# <location>_host_<hostname>_access, or the cross-app app_super_admin group
# (super admins get SSH login on every host, same as they get admin in the
# SSO manager/proxy/jump-host web UIs -- see files/ldap-ssh-key.sh for the
# matching AuthorizedKeysCommand-side check).
#
# The app_super_admin clause is kept even though the SSO now nests
# app_super_admin into each resource's _admin group (and _admin into _access),
# which already covers it transitively: the clause is what keeps super-admin
# login working against a directory that predates that nesting, or one whose
# server does not resolve nesting at all.
access_provider = ldap
ldap_access_order = filter
ldap_access_filter = (|(memberof=cn={{ldap_location}}_access,ou=groups,{{ldap_base_dn}})(memberof=cn={{ldap_location}}_host_{{current_host}}_access,ou=groups,{{ldap_base_dn}})(memberof=cn=app_super_admin,ou=groups,{{ldap_base_dn}}))

# Nested groups.
#
# The SSO Manager's bundled slapd carries the `nestgroup` overlay, which makes
# (memberOf=) searches match through nested groups server-side -- so the
# ldap_access_filter above is already transitive there, and a user who reaches
# <location>_host_<hostname>_access via an intermediate group (a team/role
# group, or app_super_admin nested into the resource's _admin group) is
# admitted without listing them on every host group.
#
# This directive covers the other case: an external/stock OpenLDAP, where no
# 2.6.x release ships nestgroup and the server returns only direct membership.
# SSSD then walks the chain itself, up to this depth. Harmless when the server
# already expands (the walk simply finds nothing further); the default of 2 is
# raised to 5 so a role-of-roles arrangement still resolves.
ldap_group_nesting_level = 5

# Mapping
ldap_user_search_base = ou=people,{{ldap_base_dn}}
ldap_group_search_base = ou=groups,{{ldap_base_dn}}
ldap_user_member_of = memberOf

# Cache settings
cache_credentials = True
enumerate = False
