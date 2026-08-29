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
# TLS certificate verification for the LDAPS connection. "never" disables
# hostname verification (acceptable only for loopback/self-signed dev, e.g. the
# co-located stack host); "demand" enforces it. Set in ldap.vars so the operator
# can match the deployment's cert posture — see C4/H12.
ldap_tls_reqcert = {{ldap_tls_reqcert}}

ldap_default_bind_dn = {{ldap_bind_dn}}
ldap_default_authtok_type = password
ldap_default_authtok = {{ldap_bind_password}}

# Sudo settings
# Sudo via the native LDAP provider is intentionally NOT enabled (design-gap D5):
# the directory does not scope sudoRole per-host, so enabling sudo_provider would
# hand every account sudoHost/sudoCommand ALL/ALL = universal root (H12 landmine).
# The sssd-sudo.socket is likewise not started in index.sh. A scoped sudoRole
# mechanism is required before this can be safely wired up.
# (All of the following were active pre-H12 and are preserved as comments.)
# sudo_provider = ldap
# ldap_sudo_search_base = {{ldap_base_dn}}
# ldap_sudo_full_refresh_interval = 900
# ldap_sudo_smart_refresh_interval = 300
# NOTE: ldap_sudo_search_filter is rejected by SSSD 2.6.3's ini validator
# ("not allowed in section domain/default") -- it isn't a real sssd-ldap(5)
# option on this version, so it's commented out rather than silently no-op'd.
# Sudo scoping to <location>_admin / <location>_host_<hostname>_admin needs a
# different mechanism (native LDAP sudoRole entries, most likely) -- separate
# follow-up, doesn't block SSH login/access-filter testing below.
# ldap_sudo_search_filter = (|(memberOf=cn={{ldap_location_slug}}_admin,ou=groups,{{ldap_base_dn}})(memberOf=cn={{ldap_location_slug}}_host_{{current_host_slug}}_admin,ou=groups,{{ldap_base_dn}}))

# Access control: only allow users in the site's all-hosts aggregate
# (site_<location>_hosts_access), this host's own access group
# (site_<location>_host_<hostname>_access), or god_admin (super admins get SSH
# login on every host, same as they get admin in the SSO manager/proxy/jump-host
# web UIs -- see files/ldap-ssh-key.sh for the matching AuthorizedKeysCommand-
# side check).
#
# The god_admin clause is what keeps super-admin login working against a
# directory that does not resolve nesting server-side (the nestgroup overlay),
# or where god_admin isn't (yet) nested into the host's groups.
access_provider = ldap
ldap_access_order = filter
# NOTE: location/host names are slugified (contract G-5: lower |
# [^a-z0-9]+ -> "-" | trim "-") to match the directory's actual group slugs.
ldap_access_filter = (|(memberof=cn=site_{{ldap_location_slug}}_hosts_access,ou=groups,{{ldap_base_dn}})(memberof=cn=site_{{ldap_location_slug}}_host_{{current_host_slug}}_access,ou=groups,{{ldap_base_dn}})(memberof=cn=god_admin,ou=groups,{{ldap_base_dn}}))

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
