#!/bin/bash
# Pruebas que se ejecutan en el PORTATIL 1 con Git Bash.
# Evita que Git Bash convierta rutas como /pruebas/x.sh en C:/Program Files/Git/...
export MSYS_NO_PATHCONV=1
# Ejecuta un comando en un cliente efimero conectado a la red externa del
# portatil 1, donde www.tiny.com es el firewall (192.168.0.1)
cliente() {
  docker run --rm --network red_externa --add-host www.tiny.com:192.168.0.1 tiny-cliente:1.0 "$@"
}
M1="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../maquina1" && pwd)"
pxc_root() { grep PXC_ROOT_PASSWORD "$M1/.env" | cut -d= -f2 | tr -d '\r'; }
titulo() { echo -e "\n\033[0;36m==== $* ====\033[0m"; }
