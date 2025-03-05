#!/bin/bash

ldapsearch -H "{{ldap_host}}" \
  -D "{{ldap_bind_dn}}" \
  -w "{{ldap_bind_password}}" \
  -b "ou=People,{{ldap_base_dn}}" \
  "(&(uid=$1)(|(memberof=cn=host_access,ou=Groups,{{ldap_base_dn}})(memberof=cn=host_{{current_host}}_access,ou=Groups,{{ldap_base_dn}})))" \
  '*' | sed -n '/^ /{H;d};/sshPublicKey:/x;$g;s/\n *//g;s/sshPublicKey: //gp'
  