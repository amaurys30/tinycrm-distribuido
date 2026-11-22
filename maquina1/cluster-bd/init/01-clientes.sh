#!/bin/bash
# Se ejecuta UNA sola vez en pxc1 al inicializar el cluster.
# pxc2 y pxc3 reciben todo por SST (copia completa) al unirse.
# Aislamiento: cada cliente tiene su propia BD y su propio usuario,
# con permisos SOLO sobre su BD.
"${mysql[@]}" <<-EOSQL
	CREATE DATABASE IF NOT EXISTS tinycrm_cliente_a CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
	CREATE DATABASE IF NOT EXISTS tinycrm_cliente_b CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

	CREATE USER IF NOT EXISTS 'tinycrm_a'@'%' IDENTIFIED WITH mysql_native_password BY '${DB_CLIENTE_A_PASSWORD}';
	GRANT ALL PRIVILEGES ON tinycrm_cliente_a.* TO 'tinycrm_a'@'%';

	CREATE USER IF NOT EXISTS 'tinycrm_b'@'%' IDENTIFIED WITH mysql_native_password BY '${DB_CLIENTE_B_PASSWORD}';
	GRANT ALL PRIVILEGES ON tinycrm_cliente_b.* TO 'tinycrm_b'@'%';

	-- Usuario sin privilegios que usa HAProxy (LB BD) para el health check
	CREATE USER IF NOT EXISTS 'haproxy_check'@'%' IDENTIFIED WITH mysql_native_password BY '';

	FLUSH PRIVILEGES;
EOSQL
