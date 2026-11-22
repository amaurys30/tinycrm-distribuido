#!/bin/bash
# Genera trafico continuo con UNA sola sesion. Lo usan las pruebas de
# tolerancia a fallos (se tumba una instancia o un nodo de BD en medio).
# Uso: ./carga.sh <usuario> <clave> <peticiones> <intervalo_seg>
source /pruebas/comun.sh
jar=$(mktemp); login "$1" "$2" "$jar" > /dev/null
ok_n=0; err_n=0
for i in $(seq 1 "$3"); do
  r=$(curl -s -w '\n%{http_code}' -b "$jar" -c "$jar" -m 10 "$BASE/api/sistema/info")
  code=$(echo "$r" | tail -1); cuerpo=$(echo "$r" | head -n -1)
  if [ "$code" = "200" ]; then
    ok_n=$((ok_n+1))
    printf "#%02d %s  %s\n" "$i" "$code" "$(echo "$cuerpo" | jq -r '"cliente=\(.tenant) instancia=\(.instancia) nodoBD=\(.nodoBD)"')"
  else
    err_n=$((err_n+1)); printf "#%02d %s  ERROR\n" "$i" "$code"
  fi
  sleep "$4"
done
titulo "Resumen: $ok_n exitosas, $err_n fallidas (misma sesion todo el tiempo)"
