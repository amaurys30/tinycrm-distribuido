#!/bin/bash
# RUBRICA: Middleware y enrutamiento por cliente (15 pts)
source /pruebas/comun.sh
titulo "1. Resolucion DNS de www.tiny.com (DNS del portatil 1 -> IP del portatil 1)"
dig +short www.tiny.com | sed 's/^/   www.tiny.com -> /'

for par in "admin_a:admin123:A" "admin_b:admin123:B"; do
  IFS=: read -r u p esperado <<< "$par"
  jar=$(mktemp)
  titulo "2. Login de $u (deberia ir al Cliente $esperado)"
  login "$u" "$p" "$jar" | jq -c '{success, message, usuario: .user.username}'
  r=$(info "$jar"); echo "$r" | jq .
  [ "$(echo "$r" | jq -r .tenant)" = "$esperado" ] && ok "$u fue enrutado al Cliente $esperado" \
                                                    || falla "$u NO fue enrutado al Cliente $esperado"
  nota "Cabeceras de la respuesta:"
  curl -s -D - -o /dev/null -b "$jar" "$BASE/api/sistema/info" | grep -iE '^(x-cliente|x-servidor|x-firewall|x-middleware)'
done

titulo "3. Usuario inexistente es rechazado por el Middleware"
login "no_existe" "x" /dev/null | jq -c .
