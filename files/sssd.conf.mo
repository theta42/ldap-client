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
# Filter for sudo access: global host_admin OR host-specific admin
ldap_sudo_full_refresh_interval = 900
ldap_sudo_smart_refresh_interval = 300
ldap_sudo_search_filter = (|(memberOf=cn={{location}}host_admin,ou=groups,dc=theta42,dc=com)(memberOf=cn={{location}}host_{hostname}_admin,ou=groups,dc=theta42,dc=com))

# Access control: only allow users in host_access or host_{hostname}_access
access_provider = ldap
ldap_access_order = filter
ldap_access_filter = (|(memberof=cn={{location}}host_access,ou=groups,{{ldap_base_dn}})(memberof=cn={{location}}host_{{current_host}}_access,ou=groups,{{ldap_base_dn}}))

# Mapping
ldap_user_search_base = ou=people,{{ldap_base_dn}}
ldap_group_search_base = ou=groups,{{ldap_base_dn}}
ldap_user_member_of = memberOf

# Cache settings
cache_credentials = True
enumerate = False
