#!/bin/bash
# RUBRICA: Broker de mensajes (10) - comunicacion ASINCRONA y desacoplada
source "$(dirname "$0")/comun.sh"
titulo "1. Cola y consumidores"
docker exec broker rabbitmqctl -q list_queues name messages consumers
titulo "2. Se detiene el Consumer y se registra un usuario nuevo"
docker stop consumer > /dev/null
u="async_$(date +%s)"
cliente sh -c ". /pruebas/comun.sh; registrar $u $u@clienteb.com clave123 | jq -c ."
sleep 2
titulo "3. El evento queda guardado en la cola (nadie lo ha consumido)"
docker exec broker rabbitmqctl -q list_queues name messages consumers
titulo "4. Vuelve el Consumer y procesa el evento pendiente"
docker start consumer > /dev/null; sleep 6
docker exec broker rabbitmqctl -q list_queues name messages consumers
"$(dirname "$0")/../ver-registro-usuarios.sh" | grep -E "username|$u"
