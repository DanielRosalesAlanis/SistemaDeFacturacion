-- =====================================================================
--  SISTEMA DE FACTURACIÓN DE SERVICIOS  ·  Modelo del Equipo 3
--  01_esquema.sql — DDL: esquema, tablas, restricciones e índices
--  SGBD: PostgreSQL 16+ (probado en 16.15 y en Amazon RDS 18.3) · UTF-8
--
--  Orden de carga:  01_esquema.sql → 02_procedimientos.sql → 03_datos.sql
--  Pruebas:         04_pruebas.sql
--  Automatizado:    scripts/cargar_bd.ps1  (o scripts/cargar_bd.sh)
--
--  ⚠ Este archivo BORRA y vuelve a crear el esquema facturacion.
--  Equivalencias de tipo del diagrama: INT [PK] → SERIAL · DATETIME → TIMESTAMP
-- =====================================================================

DROP SCHEMA IF EXISTS facturacion CASCADE;
CREATE SCHEMA facturacion;
SET search_path TO facturacion;

-- ---------------------------------------------------------------------
-- 1. categorias_servicio
-- ---------------------------------------------------------------------
CREATE TABLE categorias_servicio (
    id_categoria      SERIAL        PRIMARY KEY,
    nombre_categoria  VARCHAR(100)  NOT NULL UNIQUE,
    descripcion       VARCHAR(255),
    estado            BOOLEAN       NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 2. servicios
-- ---------------------------------------------------------------------
CREATE TABLE servicios (
    id_servicio      SERIAL         PRIMARY KEY,
    id_categoria     INT            NOT NULL REFERENCES categorias_servicio(id_categoria),
    codigo_servicio  VARCHAR(20)    NOT NULL UNIQUE,
    nombre_servicio  VARCHAR(150)   NOT NULL,
    descripcion      VARCHAR(255),
    precio_base      DECIMAL(10,2)  NOT NULL CHECK (precio_base > 0),
    unidad_medida    VARCHAR(30)    NOT NULL
                     CHECK (unidad_medida IN ('Servicio','Hora','Mes','Año','Evento')),
    estado           BOOLEAN        NOT NULL DEFAULT TRUE,
    fecha_creacion   TIMESTAMP      NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 3. caracteristicas  (diccionario de 50 especificaciones)
-- ---------------------------------------------------------------------
CREATE TABLE caracteristicas (
    id_caracteristica      SERIAL        PRIMARY KEY,
    nombre_caracteristica  VARCHAR(100)  NOT NULL UNIQUE,
    tipo_dato              VARCHAR(20)   NOT NULL
                           CHECK (tipo_dato IN ('TEXTO','ENTERO','DECIMAL','BOOLEANO','FECHA')),
    unidad                 VARCHAR(30),
    descripcion            VARCHAR(255)
);

-- ---------------------------------------------------------------------
-- 4. servicio_caracteristicas  (N:M con el valor concreto)
-- ---------------------------------------------------------------------
CREATE TABLE servicio_caracteristicas (
    id_servicio_caracteristica  SERIAL        PRIMARY KEY,
    id_servicio                 INT           NOT NULL REFERENCES servicios(id_servicio),
    id_caracteristica           INT           NOT NULL REFERENCES caracteristicas(id_caracteristica),
    valor                       VARCHAR(100)  NOT NULL,
    CONSTRAINT uq_servicio_caracteristica UNIQUE (id_servicio, id_caracteristica)
);

-- ---------------------------------------------------------------------
-- 5. empleados
-- ---------------------------------------------------------------------
CREATE TABLE empleados (
    id_empleado  SERIAL        PRIMARY KEY,
    nombre       VARCHAR(100)  NOT NULL,
    puesto       VARCHAR(50)   NOT NULL
                 CHECK (puesto IN ('Gerente','Facturista','Cajero','Auxiliar')),
    correo       VARCHAR(100)  NOT NULL UNIQUE,
    estado       BOOLEAN       NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 6. clientes  (apellido vacío para personas morales)
-- ---------------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente             SERIAL        PRIMARY KEY,
    nombre                 VARCHAR(100)  NOT NULL,
    apellido               VARCHAR(100),
    identificacion_fiscal  VARCHAR(20)   NOT NULL UNIQUE,
    correo                 VARCHAR(100)  NOT NULL,
    telefono               VARCHAR(20),
    direccion              VARCHAR(255),
    estado                 BOOLEAN       NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_clientes_rfc CHECK (identificacion_fiscal ~ '^[A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3}$')
);

-- ---------------------------------------------------------------------
-- 7. metodos_pago
-- ---------------------------------------------------------------------
CREATE TABLE metodos_pago (
    id_metodo_pago  SERIAL        PRIMARY KEY,
    nombre_metodo   VARCHAR(50)   NOT NULL UNIQUE,
    descripcion     VARCHAR(150),
    estado          BOOLEAN       NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 8. facturas  (encabezado)
-- ---------------------------------------------------------------------
CREATE TABLE facturas (
    id_factura         SERIAL         PRIMARY KEY,
    id_cliente         INT            NOT NULL REFERENCES clientes(id_cliente),
    id_empleado        INT            NOT NULL REFERENCES empleados(id_empleado),
    folio              VARCHAR(30)    NOT NULL UNIQUE,              -- F-000001
    fecha_emision      TIMESTAMP,                                    -- se llena al emitir
    fecha_vencimiento  TIMESTAMP,
    subtotal           DECIMAL(10,2)  NOT NULL DEFAULT 0 CHECK (subtotal  >= 0),
    impuestos          DECIMAL(10,2)  NOT NULL DEFAULT 0 CHECK (impuestos >= 0),
    total              DECIMAL(10,2)  NOT NULL DEFAULT 0 CHECK (total     >= 0),
    estado             VARCHAR(20)    NOT NULL DEFAULT 'BORRADOR'
                       CHECK (estado IN ('BORRADOR','EMITIDA','PAGADA','CANCELADA')),
    CONSTRAINT ck_facturas_fechas CHECK (fecha_vencimiento IS NULL OR fecha_vencimiento >= fecha_emision)
);

-- ---------------------------------------------------------------------
-- 9. detalle_factura  (guarda el precio histórico de la venta)
-- ---------------------------------------------------------------------
CREATE TABLE detalle_factura (
    id_detalle       SERIAL         PRIMARY KEY,
    id_factura       INT            NOT NULL REFERENCES facturas(id_factura) ON DELETE CASCADE,
    id_servicio      INT            NOT NULL REFERENCES servicios(id_servicio),
    cantidad         INT            NOT NULL CHECK (cantidad > 0),
    precio_unitario  DECIMAL(10,2)  NOT NULL CHECK (precio_unitario > 0),
    descuento        DECIMAL(10,2)  NOT NULL DEFAULT 0 CHECK (descuento >= 0),
    subtotal         DECIMAL(10,2)  NOT NULL,                       -- cantidad × precio − descuento
    CONSTRAINT ck_detalle_descuento CHECK (descuento <= cantidad * precio_unitario)
);

-- ---------------------------------------------------------------------
-- 10. pagos  (abonos; varios por factura)
-- ---------------------------------------------------------------------
CREATE TABLE pagos (
    id_pago         SERIAL         PRIMARY KEY,
    id_factura      INT            NOT NULL REFERENCES facturas(id_factura),
    id_metodo_pago  INT            NOT NULL REFERENCES metodos_pago(id_metodo_pago),
    fecha_pago      TIMESTAMP      NOT NULL DEFAULT now(),
    monto           DECIMAL(10,2)  NOT NULL CHECK (monto > 0),
    referencia      VARCHAR(50),
    estado          VARCHAR(20)    NOT NULL DEFAULT 'APLICADO'
                    CHECK (estado IN ('APLICADO','CANCELADO'))
);

-- Índices sobre llaves foráneas de consulta frecuente
CREATE INDEX ix_servicios_categoria  ON servicios(id_categoria);
CREATE INDEX ix_sc_caracteristica    ON servicio_caracteristicas(id_caracteristica);
CREATE INDEX ix_facturas_cliente     ON facturas(id_cliente);
CREATE INDEX ix_facturas_estado      ON facturas(estado);
CREATE INDEX ix_detalle_factura      ON detalle_factura(id_factura);
CREATE INDEX ix_pagos_factura        ON pagos(id_factura);

