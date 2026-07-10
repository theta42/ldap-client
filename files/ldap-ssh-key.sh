#!/bin/bash

ldapsearch -H "ldap://{{ldap_host}}" \
  -D "{{ldap_bind_dn}}" \
  -w "{{ldap_bind_password}}" \
  -b "ou=People,{{ldap_base_dn}}" \
  "(&(uid=$1)(|{{#ldap_access_groups}}(memberof={{.}},ou=Groups,{{ldap_base_dn}}){{/ldap_access_groups}}))" \
  '*' | sed -n '/^ /{H;d};/sshPublicKey:/x;$g;s/\n *//g;s/sshPublicKey: //gp'
  