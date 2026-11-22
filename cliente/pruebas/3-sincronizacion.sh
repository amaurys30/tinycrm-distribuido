#!/bin/bash
# RUBRICA: Sincronizacion de usuarios (10) + Broker de mensajes (10)
source /pruebas/comun.sh
sufijo=$(date +%s)
for par in "A:clientea.com" "B:clienteb.com"; do
  IFS=: read -r cliente dominio <<< "$par"
  u="usuario_${cliente,,}_$sufijo"
  titulo "Registro de $u <$u@$dominio> (debe crearse en el Cliente $cliente)"
  registrar "$u" "$u@$dominio" "clave123" | jq -c '{success, message}'
  nota "Esperando a que el evento pase por Broker -> Consumer -> BD Usuarios..."
  for i in $(seq 1 10); do
    sleep 1
    jar=$(mktemp)
    if login "$u" "clave123" "$jar" | jq -e .success > /dev/null 2>&1; then
      t=$(info "$jar" | jq -r .tenant)
      ok "$u ya esta en el registro central (${i}s) y el Middleware lo envia al Cliente $t"
      break
    fi
    [ "$i" = 10 ] && falla "$u no aparecio en el registro central"
  done
done
nota "Ver en Maquina 1: ./scripts/ver-registro-usuarios.sh"
