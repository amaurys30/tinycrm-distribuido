#!/bin/bash
export MSYS_NO_PATHCONV=1   # Git Bash en Windows: no convertir rutas /...
# Estado general (ejecutar en la Maquina 1)
cd "$(dirname "$0")/../maquina1"
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
echo; echo "== Cluster de BD =="
for n in pxc1 pxc2 pxc3; do
  printf "%s: " $n
  docker exec $n mysql -uroot -p"$(grep PXC_ROOT_PASSWORD .env | cut -d= -f2 | tr -d "\r")" -Nse \
   "SELECT CONCAT('tamano=',(SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='wsrep_cluster_size'),' estado=',(SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='wsrep_local_state_comment'))" 2>/dev/null || echo "caido"
done
echo; echo "== Cola del broker =="
docker exec broker rabbitmqctl -q list_queues name messages consumers 2>/dev/null
