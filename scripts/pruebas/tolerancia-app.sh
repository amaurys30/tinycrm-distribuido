#!/bin/bash
# RUBRICA: Tolerancia a fallos (15 pts) - cae una instancia de aplicacion
# Uso: ./tolerancia-app.sh [a|b]
source "$(dirname "$0")/comun.sh"
C=${1:-a}
titulo "Trafico continuo de admin_$C mientras se APAGA tinycrm-${C}1"
cliente /pruebas/carga.sh "admin_$C" admin123 30 0.5 &
sleep 5
titulo ">>> docker stop tinycrm-${C}1  (simulando caida)"; docker stop "tinycrm-${C}1" > /dev/null
wait
titulo ">>> docker start tinycrm-${C}1 (recuperacion; HAProxy lo reincorpora solo)"
docker start "tinycrm-${C}1" > /dev/null
echo "Vea el panel del LB: http://<IP-maquina1>:$([ "$C" = a ] && echo 8404 || echo 8405)"
