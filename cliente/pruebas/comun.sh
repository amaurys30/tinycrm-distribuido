#!/bin/bash
# Funciones comunes para las pruebas (se ejecutan desde la RED EXTERNA:
# DNS 192.168.0.1 -> Firewall -> Middleware -> LB del cliente -> TinyCRM)
BASE="${BASE:-http://www.tiny.com}"
VERDE='\033[0;32m'; ROJO='\033[0;31m'; AMARILLO='\033[1;33m'; AZUL='\033[0;36m'; NC='\033[0m'

titulo() { echo -e "\n${AZUL}==== $* ====${NC}"; }
ok()     { echo -e "${VERDE}[OK]${NC} $*"; }
falla()  { echo -e "${ROJO}[FALLA]${NC} $*"; }
nota()   { echo -e "${AMARILLO}-->${NC} $*"; }

# login <usuario> <clave> <archivo_cookies>  -> imprime respuesta JSON
login() {
  curl -s -c "$3" -b "$3" -H 'Content-Type: application/json' \
       -d "{\"username\":\"$1\",\"password\":\"$2\",\"rememberMe\":false}" \
       "$BASE/api/auth/login"
}

# info <archivo_cookies> -> JSON con cliente, instancia y nodo de BD
info() {
  curl -s -b "$1" -c "$1" "$BASE/api/sistema/info"
}

# registrar <username> <email> <clave> [archivo_cookies]
registrar() {
  local jar="${4:-/dev/null}"
  curl -s -b "$jar" -H 'Content-Type: application/json' \
       -d "{\"username\":\"$1\",\"email\":\"$2\",\"password\":\"$3\",\"firstName\":\"Prueba\",\"lastName\":\"SD\"}" \
       "$BASE/api/auth/register"
}
