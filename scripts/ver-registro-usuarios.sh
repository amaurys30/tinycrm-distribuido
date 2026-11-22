#!/bin/bash
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: no convertir rutas /...
# Muestra la BD central "Usuarios" y los ultimos eventos recibidos por el Consumer
cd "$(dirname "$0")/../maquina1"
P=$(grep USUARIOS_ROOT_PASSWORD .env | cut -d= -f2 | tr -d "\r")
docker exec usuarios-db mysql -uroot -p"$P" usuarios -t -e \
  "SELECT username, email, tenant AS cliente, rol, activo, creado_en FROM usuarios ORDER BY tenant, id;" 2>/dev/null
docker exec usuarios-db mysql -uroot -p"$P" usuarios -t -e \
  "SELECT recibido_en, tipo, tenant AS cliente, username, instancia_origen, resultado FROM eventos_recibidos ORDER BY id DESC LIMIT 10;" 2>/dev/null
