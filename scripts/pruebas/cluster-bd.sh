#!/bin/bash
# RUBRICA: Cluster de base de datos (15 pts)
source "$(dirname "$0")/comun.sh"
P=$(pxc_root)
estado() {
  for n in pxc1 pxc2 pxc3; do
    printf "   %s: " $n
    docker exec $n mysql -uroot -p"$P" -Nse "SHOW STATUS LIKE 'wsrep_cluster_size'; SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null | tr '\n' ' ' || true
    echo
  done
}
titulo "1. Estado del cluster (3 nodos sincronizados)"; estado

titulo "2. Replicacion sincrona: se escribe en pxc1 y se lee en pxc3"
docker exec pxc1 mysql -uroot -p"$P" -e "CREATE DATABASE IF NOT EXISTS prueba_sd; CREATE TABLE IF NOT EXISTS prueba_sd.t(id INT AUTO_INCREMENT PRIMARY KEY, txt VARCHAR(50)); INSERT INTO prueba_sd.t(txt) VALUES (CONCAT('escrito en pxc1 ', NOW()));" 2>/dev/null
docker exec pxc3 mysql -uroot -p"$P" -t -e "SELECT * FROM prueba_sd.t ORDER BY id DESC LIMIT 3;" 2>/dev/null

titulo "3. Usuarios de TinyCRM por cliente (leidos en pxc2)"
docker exec pxc2 mysql -uroot -p"$P" -t -e "SELECT 'A' cliente, username, email FROM tinycrm_cliente_a.users UNION ALL SELECT 'B', username, email FROM tinycrm_cliente_b.users;" 2>/dev/null

titulo "4. Cae el nodo escritor pxc1 mientras admin_a usa la aplicacion"
cliente /pruebas/carga.sh admin_a admin123 30 0.5 &
sleep 4; docker stop pxc1 > /dev/null; echo "   >>> pxc1 detenido"
wait
estado

titulo "5. pxc1 vuelve y se resincroniza solo (IST)"
docker start pxc1 > /dev/null
for i in $(seq 1 30); do
  sleep 5
  s=$(docker exec pxc1 mysql -uroot -p"$P" -Nse "SHOW STATUS LIKE 'wsrep_local_state_comment'" 2>/dev/null | awk '{print $2}')
  [ "$s" = "Synced" ] && break
done
estado
