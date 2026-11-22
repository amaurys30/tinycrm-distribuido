# =====================================================================
# Genera la Tiny CA y el certificado HTTPS de www.tiny.com (PowerShell).
# Ejecutar UNA vez en el PORTATIL 1, desde la carpeta raiz del proyecto:
#   powershell -ExecutionPolicy Bypass -File .\certificados\generar-certificados.ps1
# Luego copien la carpeta "certificados" completa al PORTATIL 2.
# Usa un contenedor con openssl: no hace falta instalar nada en Windows.
# =====================================================================
$carpeta = Join-Path $PSScriptRoot ""
docker run --rm -v "${carpeta}:/certs" alpine:3.20 sh -c "apk add -q openssl && tr -d '\r' < /certs/generar-certificados.sh | sh"
