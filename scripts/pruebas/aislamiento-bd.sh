#!/bin/bash
# RUBRICA: Aislamiento (10) - a nivel de datos: el usuario de BD del
# Cliente A no puede leer la BD del Cliente B (y viceversa)
source "$(dirname "$0")/comun.sh"
A=$(grep DB_CLIENTE_A_PASSWORD "$M1/.env" | cut -d= -f2 | tr -d "\r")
titulo "tinycrm_a leyendo SU base de datos"
docker exec pxc1 mysql -utinycrm_a -p"$A" -e "SELECT COUNT(*) usuarios_A FROM tinycrm_cliente_a.users" 2>/dev/null
titulo "tinycrm_a intentando leer la base de datos del Cliente B"
docker exec pxc1 mysql -utinycrm_a -p"$A" -e "SELECT * FROM tinycrm_cliente_b.users" 2>&1 | grep -v Warning
titulo "Desde la red externa NO se alcanza ningun servicio interno (solo el firewall)"
for destino in 192.168.1.5:8080 192.168.1.6:8080 192.168.2.1:3306; do
  cliente sh -c "curl -s -m 3 -o /dev/null http://$destino && echo '   $destino ALCANZABLE (mal)' || echo '   $destino inalcanzable (bien)'"
done
