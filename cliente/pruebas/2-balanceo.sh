#!/bin/bash
# RUBRICA: Balanceador de carga por cliente (10 pts)
# Uso: ./2-balanceo.sh [usuario] [clave] [peticiones]
source /pruebas/comun.sh
for u in ${1:-admin_a admin_b}; do
  jar=$(mktemp); login "$u" "${2:-admin123}" "$jar" > /dev/null
  N=${3:-20}
  titulo "$N peticiones de $u"
  for i in $(seq 1 "$N"); do info "$jar" | jq -r '"\(.cliente) -> \(.instancia)"'; done | sort | uniq -c
done
nota "Cada cliente reparte su trafico SOLO entre sus 2 instancias (round-robin)."
