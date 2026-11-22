# Certificados HTTPS (no se suben a GitHub)

Esta carpeta guarda el certificado de `www.tiny.com` que usa el Firewall en el puerto 443 y la autoridad certificadora del proyecto ("Tiny CA") en la que confían los navegadores de los actores. Las claves privadas **no se suben al repositorio** (ver `.gitignore`).

**Generarlos** (una vez, en el portátil 1, desde la raíz del proyecto):

```powershell
powershell -ExecutionPolicy Bypass -File .\certificados\generar-certificados.ps1
```

Se crean `tiny-ca.crt`, `tiny-ca.key`, `tiny.crt` y `tiny.key`. Después **copien esta carpeta completa al portátil 2** (los actores necesitan `tiny-ca.crt`).

Si regeneran los certificados con el sistema encendido: en el portátil 1, `docker compose up -d --force-recreate firewall dns`; en el portátil 2, `docker compose up -d --force-recreate`.
