#!/bin/bash
# RUBRICA: Aislamiento entre clientes (10 pts)
source /pruebas/comun.sh
jarA=$(mktemp); jarB=$(mktemp)
login admin_a admin123 "$jarA" > /dev/null
login admin_b admin123 "$jarB" > /dev/null

titulo "1. Usuarios visibles para admin_a (solo debe ver el Cliente A)"
curl -s -b "$jarA" "$BASE/api/users" | jq -r '(.users // .data // .)[]? | "   \(.username)  <\(.email)>"'
titulo "2. Usuarios visibles para admin_b (solo debe ver el Cliente B)"
curl -s -b "$jarB" "$BASE/api/users" | jq -r '(.users // .data // .)[]? | "   \(.username)  <\(.email)>"'

titulo "3. Ataque: admin_a cambia su cookie de cliente a 'B' (cookie falsificada)"
sesionA=$(grep TINYCRM_SESSIONID "$jarA" | awk '{print $7}')
code=$(curl -s -o /tmp/r.json -w '%{http_code}' \
  -H "Cookie: TINYCRM_SESSIONID=$sesionA; TINY_CLIENTE=B|admin_a|00000000000000000000000000000000" \
  "$BASE/api/sistema/info")
echo "   HTTP $code -> $(cat /tmp/r.json)"
[ "$code" = "401" ] && ok "Cookie manipulada rechazada por el Middleware (firma HMAC invalida)"

titulo "4. Ataque: usar la sesion de A contra la infraestructura de B"
cookieB=$(grep TINY_CLIENTE "$jarB" | awk '{print $7}')
code=$(curl -s -o /tmp/r.json -w '%{http_code}' \
  -H "Cookie: TINYCRM_SESSIONID=$sesionA; TINY_CLIENTE=$cookieB" "$BASE/api/auth/me")
echo "   HTTP $code -> $(cat /tmp/r.json)"
[ "$code" = "401" ] && ok "La sesion del Cliente A no existe en la BD del Cliente B"

titulo "5. Registro anonimo con dominio ajeno a los clientes"
registrar "intruso" "intruso@gmail.com" "x" | jq -c .
