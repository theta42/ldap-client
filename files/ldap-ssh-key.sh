#!/bin/bash

ldapsearch -H "ldap://10.1.0.55" \
  -D "cn=ldapclient service,ou=People,dc=theta42,dc=com" \
  -w "1lovebyte" \
  -b "ou=People,dc=theta42,dc=com" \
  "(&(uid=$1)(|(memberof=cn=host_access,ou=Groups,dc=theta42,dc=com)(memberof=cn=host_ldap-client-test_access,ou=Groups,dc=theta42,dc=com)))" \
  '*' | sed -n '/^ /{H;d};/sshPublicKey:/x;$g;s/\n *//g;s/sshPublicKey: //gp'
  