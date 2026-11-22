#!/bin/bash
# Usuarios de BD con minimo privilegio (claves tomadas del .env).
# Usa el cliente mysql directamente: funciona tanto si el entrypoint
# "ejecuta" como si "carga" este archivo (en Windows aparece ejecutable).
mysql --protocol=socket -uroot -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL
	CREATE USER IF NOT EXISTS 'middleware'@'%' IDENTIFIED BY '${MIDDLEWARE_DB_PASSWORD}';
	GRANT SELECT ON usuarios.usuarios TO 'middleware'@'%';
	CREATE USER IF NOT EXISTS 'consumer'@'%' IDENTIFIED BY '${CONSUMER_DB_PASSWORD}';
	GRANT SELECT, INSERT, UPDATE, DELETE ON usuarios.* TO 'consumer'@'%';
	FLUSH PRIVILEGES;
EOSQL
