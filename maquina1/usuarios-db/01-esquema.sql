-- =====================================================================
-- BD central "Usuarios" (192.168.1.9) - Red DMZ
-- Registro global: que usuario pertenece a que cliente (tenant)
-- Escribe: Consumer   |   Lee: Middleware
-- =====================================================================
CREATE DATABASE IF NOT EXISTS usuarios CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE usuarios;

CREATE TABLE IF NOT EXISTS usuarios (
    id                BIGINT AUTO_INCREMENT PRIMARY KEY,
    username          VARCHAR(100) NOT NULL,
    email             VARCHAR(255),
    tenant            CHAR(1)      NOT NULL COMMENT 'A = Cliente A, B = Cliente B',
    tenant_usuario_id BIGINT       COMMENT 'id del usuario dentro de la BD del cliente',
    nombre            VARCHAR(100),
    apellido          VARCHAR(100),
    rol               VARCHAR(20),
    activo            TINYINT(1)   NOT NULL DEFAULT 1,
    creado_en         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actualizado_en    TIMESTAMP    NULL,
    UNIQUE KEY uk_username (username),
    UNIQUE KEY uk_email (email),
    KEY idx_tenant (tenant)
);

CREATE TABLE IF NOT EXISTS eventos_recibidos (
    id               BIGINT AUTO_INCREMENT PRIMARY KEY,
    tipo             VARCHAR(30),
    tenant           CHAR(1),
    username         VARCHAR(100),
    instancia_origen VARCHAR(50),
    resultado        VARCHAR(200),
    payload          TEXT,
    recibido_en      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

