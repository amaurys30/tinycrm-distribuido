# Cliente de linea de comandos para la red externa (curl + jq + pruebas)
FROM alpine:3.20
RUN apk add --no-cache bash curl jq bind-tools iputils
COPY pruebas/ /pruebas/
# Quitar finales de linea de Windows (CRLF) por si se editaron en Windows
RUN sed -i 's/\r$//' /pruebas/*.sh && chmod +x /pruebas/*.sh
WORKDIR /pruebas
CMD ["sleep", "infinity"]
