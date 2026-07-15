[sssd]
config_file_version = 2
domains = default

[domain/default]
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap

ldap_uri = ldaps://{{ldap_host}}
ldap_search_base = {{ldap_base_dn}}
ldap_id_use_start_tls = true
ldap_tls_cacert = /etc/ssl/certs/ca-certificates.crt

ldap_bind_dn = {{ldap_bind_dn}}
ldap_bind_pw = {{ldap_bind_password}}

# Sudo settings
sudo_provider = ldap
ldap_sudo_search_base = {{ldap_base_dn}}
# Filter for sudo access: location-wide <location>_admin OR host-specific
# <location>_host_<hostname>_admin -- matches the groups index.sh registers
# via the SSO Manager API and the naming documented in the README.
ldap_sudo_full_refresh_interval = 900
ldap_sudo_smart_refresh_interval = 300
ldap_sudo_search_filter = (|(memberOf=cn={{ldap_location}}_admin,ou=groups,{{ldap_base_dn}})(memberOf=cn={{ldap_location}}_host_{{current_host}}_admin,ou=groups,{{ldap_base_dn}}))

# Access control: only allow users in <location>_access or
# <location>_host_<hostname>_access.
access_provider = ldap
ldap_access_order = filter
ldap_access_filter = (|(memberof=cn={{ldap_location}}_access,ou=groups,{{ldap_base_dn}})(memberof=cn={{ldap_location}}_host_{{current_host}}_access,ou=groups,{{ldap_base_dn}}))

# Mapping
ldap_user_search_base = ou=people,{{ldap_base_dn}}
ldap_group_search_base = ou=groups,{{ldap_base_dn}}
ldap_user_member_of = memberOf

# Cache settings
cache_credentials = True
enumerate = False
