#!/bin/sh
# =====================================================================
# Genera la "Autoridad Certificadora" del proyecto (Tiny CA) y el
# certificado HTTPS de www.tiny.com firmado por ella.
#   tiny-ca.crt  -> se instala en los navegadores de los Actores (confianza)
#   tiny.crt/key -> los usa el Firewall (nginx) en el puerto 443
# Uso (desde la carpeta del proyecto, PowerShell):
#   docker run --rm -v "${PWD}\certificados:/certs" alpine:3.20 sh -c "apk add -q openssl && tr -d '\r' < /certs/generar-certificados.sh | sh"
# =====================================================================
set -e
cd /certs 2>/dev/null || cd "$(dirname "$0")"

# 1) Autoridad certificadora del proyecto (10 anios)
openssl req -x509 -new -nodes -newkey rsa:2048 -sha256 -days 3650 \
  -keyout tiny-ca.key -out tiny-ca.crt \
  -subj "/C=CO/O=CECAR Sistemas Distribuidos/CN=Tiny CA (Proyecto SD 2026-2)" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"

# 2) Certificado del sitio www.tiny.com (2 anios), firmado por la CA
openssl req -new -nodes -newkey rsa:2048 -sha256 \
  -keyout tiny.key -out tiny.csr \
  -subj "/C=CO/O=ACME - Pepito Plus/CN=www.tiny.com"
cat > tiny.ext <<'EXT'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
authorityKeyIdentifier=keyid,issuer
subjectKeyIdentifier=hash
extendedKeyUsage=serverAuth
subjectAltName=DNS:www.tiny.com,DNS:tiny.com
EXT
openssl x509 -req -in tiny.csr -CA tiny-ca.crt -CAkey tiny-ca.key -CAcreateserial \
  -out tiny.crt -days 825 -sha256 -extfile tiny.ext
rm -f tiny.csr tiny.ext tiny-ca.srl
echo ">> Certificados generados:"; ls -l
