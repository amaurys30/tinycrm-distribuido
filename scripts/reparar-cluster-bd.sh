#!/bin/bash
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: no convertir rutas /...
# Si TODOS los nodos se apagaron abruptamente (corte de luz, VM cerrada),
# ninguno queda "seguro" para re-crear el cluster. Este script marca a pxc1
# como nodo de arranque (safe_to_bootstrap: 1) y levanta todo de nuevo.
cd "$(dirname "$0")/../maquina1"
docker compose stop pxc3 pxc2 pxc1
docker run --rm -v tiny-maquina1_pxc1-datos:/datos alpine:3.20 \
  sed -i 's/^safe_to_bootstrap: *0/safe_to_bootstrap: 1/' /datos/grastate.dat
docker compose up -d
