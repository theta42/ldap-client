[sssd]
services = nss, pam, sudo
domains = default

[domain/default]
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap
sudo_provider = ldap

ldap_uri = ldap://{{ldap_host}}
ldap_search_base = {{ldap_base_dn}}
ldap_network_timeout = 3

ldap_bind_dn = {{ldap_bind_dn}}
ldap_bind_pw = {{ldap_bind_password}}

# Sudo settings
ldap_sudo_search_base = {{ldap_base_dn}}
# Filter for sudo access: global host_admin OR host-specific admin
ldap_sudo_full_refresh_interval = 900
ldap_sudo_smart_refresh_interval = 300

# Access control: only allow users in host_access or host_{hostname}_access
access_provider = ldap
ldap_access_order = filter
ldap_access_filter = (|(memberof=cn=host_access,ou=Groups,{{ldap_base_dn}})(memberof=cn=host_{{current_host}}_access,ou=Groups,{{ldap_base_dn}}))

# Mapping
ldap_user_search_base = ou=People,{{ldap_base_dn}}
ldap_group_search_base = ou=Groups,{{ldap_base_dn}}

# Cache settings
cache_credentials = True
enumerate = False
