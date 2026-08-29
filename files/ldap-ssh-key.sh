#!/bin/bash
export LDAPTLS_REQCERT="{{ldap_tls_reqcert}}"
ldapsearch -H "ldaps://{{ldap_host}}" \
  -D "{{ldap_bind_dn}}" \
  -y /etc/ldap-ssh-key.pass \
  -b "ou=people,{{ldap_base_dn}}" \
  "(&(uid=$1)(|{{#ldap_access_groups}}(memberof=cn={{.}},ou=groups,{{ldap_base_dn}}){{/ldap_access_groups}}))" \
  '*' | sed -n '/^ /{H;d};/sshPublicKey:/x;$g;s/\n *//g;s/sshPublicKey: //gp'
