#!/bin/bash
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: no convertir rutas /...
# Apaga la Maquina 1 en orden seguro para el cluster de BD
# (pxc1 se apaga de ultimo -> queda marcado para re-crear el cluster).
cd "$(dirname "$0")/../maquina1"
docker compose stop firewall dns middleware tinycrm-a2 tinycrm-b2 tinycrm-a1 tinycrm-b1 \
  lb-cliente-a lb-cliente-b consumer broker usuarios-db lb-bd
docker compose stop pxc3; docker compose stop pxc2; docker compose stop pxc1
docker compose down
echo ">> Para borrar TODOS los datos: docker compose down -v (en maquina1/)"
