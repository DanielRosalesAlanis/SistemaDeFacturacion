-- =====================================================================
--  SISTEMA DE FACTURACIÓN DE SERVICIOS — SCRIPT COMPLETO
--  Modelo del Equipo 3 · PostgreSQL 16
--
--  Ejecutar:   createdb facturacion_db
--              psql -d facturacion_db -f facturacion_completo.sql
--              psql -d facturacion_db -f facturacion_pruebas.sql
--
--  Contenido:  Parte 1  10 tablas (las del diagrama del equipo)
--              Parte 2  13 procedimientos almacenados, 3 funciones, 5 vistas
--              Parte 3  10 categorías, 100 servicios, 50 características,
--                       1,220 valores servicio-característica, 20 clientes,
--                       4 empleados, 5 métodos de pago, 6 facturas de ejemplo
-- =====================================================================

-- =====================================================================
-- =====================================================================
--  SISTEMA DE FACTURACIÓN DE SERVICIOS  ·  Modelo del Equipo 3
--  SGBD: PostgreSQL 16   ·   Codificación: UTF-8
--  Parte 1: ESQUEMA (10 tablas, mismos nombres y campos del diagrama)
--  Equivalencias de tipo: INT [PK] → SERIAL · DATETIME → TIMESTAMP
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

-- =====================================================================
--  Parte 2: PROCEDIMIENTOS ALMACENADOS (13), FUNCIÓN DE SALDO Y VISTAS
--  Las reglas de negocio (RN-xx) viven aquí. La aplicación sólo llama
--  CALL facturacion.sp_xxx(...). Si una regla falla se lanza EXCEPTION
--  con su código y toda la operación se revierte.
-- =====================================================================
SET search_path TO facturacion;

-- Tasa de IVA única del sistema
CREATE OR REPLACE FUNCTION fn_tasa_iva() RETURNS DECIMAL
LANGUAGE sql IMMUTABLE AS $$ SELECT 0.16::DECIMAL $$;

-- Saldo de una factura = total − pagos APLICADOS (no se guarda: se calcula)
CREATE OR REPLACE FUNCTION fn_saldo_factura(p_id_factura INT) RETURNS DECIMAL
LANGUAGE sql STABLE
SET search_path = facturacion, pg_catalog AS $$
    SELECT f.total - coalesce((SELECT sum(p.monto) FROM pagos p
                                WHERE p.id_factura = f.id_factura AND p.estado = 'APLICADO'), 0)
      FROM facturas f WHERE f.id_factura = p_id_factura
$$;

-- Valida que el empleado esté activo y tenga uno de los puestos indicados
CREATE OR REPLACE FUNCTION fn_empleado_puede(p_id_empleado INT, p_puestos TEXT[]) RETURNS BOOLEAN
LANGUAGE sql STABLE
SET search_path = facturacion, pg_catalog AS $$
    SELECT EXISTS (SELECT 1 FROM empleados
                    WHERE id_empleado = p_id_empleado AND estado AND puesto = ANY (p_puestos))
$$;

-- ---------------------------------------------------------------------
-- SP01  Alta de cliente
--   RN-01 Identificación fiscal (RFC) con formato válido: 12 morales / 13 físicas
--   RN-02 RFC no duplicado
--   RN-03 Correo válido; persona física (RFC de 13) requiere apellido
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_cliente(
    p_nombre      VARCHAR,
    p_apellido    VARCHAR,
    p_rfc         VARCHAR,
    p_correo      VARCHAR,
    p_telefono    VARCHAR,
    p_direccion   VARCHAR,
    INOUT p_id_cliente INT DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE v_rfc VARCHAR := upper(trim(p_rfc));
BEGIN
    IF v_rfc !~ '^[A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3}$' THEN
        RAISE EXCEPTION 'RN-01: RFC % con formato inválido', v_rfc;
    END IF;
    IF EXISTS (SELECT 1 FROM clientes WHERE identificacion_fiscal = v_rfc) THEN
        RAISE EXCEPTION 'RN-02: El RFC % ya está registrado', v_rfc;
    END IF;
    IF coalesce(p_correo,'') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
        RAISE EXCEPTION 'RN-03: Correo electrónico inválido';
    END IF;
    IF length(v_rfc) = 13 AND coalesce(trim(p_apellido),'') = '' THEN
        RAISE EXCEPTION 'RN-03: Una persona física requiere apellido';
    END IF;

    INSERT INTO clientes(nombre, apellido, identificacion_fiscal, correo, telefono, direccion)
    VALUES (trim(p_nombre), nullif(trim(p_apellido),''), v_rfc, lower(p_correo), p_telefono, p_direccion)
    RETURNING id_cliente INTO p_id_cliente;
END $$;

-- ---------------------------------------------------------------------
-- SP02  Alta de servicio
--   RN-04 Código único; la categoría existe y está activa
--   RN-05 Precio > 0 y unidad de medida válida
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_servicio(
    p_id_categoria  INT,
    p_codigo        VARCHAR,
    p_nombre        VARCHAR,
    p_descripcion   VARCHAR,
    p_precio        DECIMAL,
    p_unidad        VARCHAR,
    INOUT p_id_servicio INT DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM servicios WHERE codigo_servicio = upper(p_codigo)) THEN
        RAISE EXCEPTION 'RN-04: El código de servicio % ya existe', p_codigo;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM categorias_servicio WHERE id_categoria = p_id_categoria AND estado) THEN
        RAISE EXCEPTION 'RN-04: La categoría % no existe o está inactiva', p_id_categoria;
    END IF;
    IF p_precio IS NULL OR p_precio <= 0 THEN
        RAISE EXCEPTION 'RN-05: El precio debe ser mayor a cero';
    END IF;
    IF p_unidad NOT IN ('Servicio','Hora','Mes','Año','Evento') THEN
        RAISE EXCEPTION 'RN-05: Unidad de medida % no válida', p_unidad;
    END IF;

    INSERT INTO servicios(id_categoria, codigo_servicio, nombre_servicio, descripcion,
                          precio_base, unidad_medida)
    VALUES (p_id_categoria, upper(p_codigo), p_nombre, p_descripcion, round(p_precio,2), p_unidad)
    RETURNING id_servicio INTO p_id_servicio;
END $$;

-- ---------------------------------------------------------------------
-- SP03  Asignar (o actualizar) el valor de una característica
--   RN-06 El valor respeta el tipo_dato de la característica
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_asignar_caracteristica(
    p_id_servicio       INT,
    p_id_caracteristica INT,
    p_valor             VARCHAR)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    v_tipo  VARCHAR;
    v_valor VARCHAR := trim(p_valor);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM servicios WHERE id_servicio = p_id_servicio) THEN
        RAISE EXCEPTION 'El servicio % no existe', p_id_servicio;
    END IF;
    SELECT tipo_dato INTO v_tipo FROM caracteristicas WHERE id_caracteristica = p_id_caracteristica;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La característica % no existe', p_id_caracteristica;
    END IF;
    IF coalesce(v_valor,'') = '' THEN
        RAISE EXCEPTION 'RN-06: El valor no puede ir vacío';
    END IF;

    IF    v_tipo = 'ENTERO'   AND v_valor !~ '^-?[0-9]+$' THEN
        RAISE EXCEPTION 'RN-06: "%" no es un entero', v_valor;
    ELSIF v_tipo = 'DECIMAL'  AND v_valor !~ '^-?[0-9]+(\.[0-9]+)?$' THEN
        RAISE EXCEPTION 'RN-06: "%" no es un decimal', v_valor;
    ELSIF v_tipo = 'BOOLEANO' AND upper(v_valor) NOT IN ('SI','NO') THEN
        RAISE EXCEPTION 'RN-06: "%" debe ser SI o NO', v_valor;
    ELSIF v_tipo = 'FECHA'    AND v_valor !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
        RAISE EXCEPTION 'RN-06: "%" no es una fecha AAAA-MM-DD', v_valor;
    END IF;

    INSERT INTO servicio_caracteristicas(id_servicio, id_caracteristica, valor)
    VALUES (p_id_servicio, p_id_caracteristica,
            CASE WHEN v_tipo = 'BOOLEANO' THEN upper(v_valor) ELSE v_valor END)
    ON CONFLICT (id_servicio, id_caracteristica) DO UPDATE SET valor = EXCLUDED.valor;
END $$;

-- ---------------------------------------------------------------------
-- SP04  Cambio de precio base
--   RN-07 Precio nuevo > 0 y distinto del actual
--   RN-08 Una variación mayor a ±30 % sólo la autoriza un Gerente
--   (Las facturas existentes conservan su precio_unitario.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_actualizar_precio(
    p_id_servicio INT,
    p_precio      DECIMAL,
    p_id_empleado INT)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE v_actual DECIMAL;
BEGIN
    SELECT precio_base INTO v_actual FROM servicios WHERE id_servicio = p_id_servicio FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El servicio % no existe', p_id_servicio;
    END IF;
    IF p_precio IS NULL OR p_precio <= 0 OR round(p_precio,2) = v_actual THEN
        RAISE EXCEPTION 'RN-07: Precio nuevo inválido o igual al actual';
    END IF;
    IF abs(p_precio - v_actual) / v_actual > 0.30
       AND NOT fn_empleado_puede(p_id_empleado, ARRAY['Gerente']) THEN
        RAISE EXCEPTION 'RN-08: Variación de % %% requiere autorización de un Gerente',
              round(abs(p_precio - v_actual) / v_actual * 100, 1);
    END IF;
    UPDATE servicios SET precio_base = round(p_precio,2) WHERE id_servicio = p_id_servicio;
END $$;

-- ---------------------------------------------------------------------
-- SP05  Activar / desactivar un servicio (baja lógica, nunca DELETE)
--   RN-09 No se desactiva si está en una factura en BORRADOR;
--         no se activa si su categoría está inactiva
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cambiar_estado_servicio(
    p_id_servicio INT,
    p_estado      BOOLEAN)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM servicios WHERE id_servicio = p_id_servicio) THEN
        RAISE EXCEPTION 'El servicio % no existe', p_id_servicio;
    END IF;
    IF NOT p_estado AND EXISTS (
           SELECT 1 FROM detalle_factura d JOIN facturas f USING (id_factura)
            WHERE d.id_servicio = p_id_servicio AND f.estado = 'BORRADOR') THEN
        RAISE EXCEPTION 'RN-09: El servicio está en facturas en borrador';
    END IF;
    IF p_estado AND NOT EXISTS (
           SELECT 1 FROM servicios s JOIN categorias_servicio c USING (id_categoria)
            WHERE s.id_servicio = p_id_servicio AND c.estado) THEN
        RAISE EXCEPTION 'RN-09: La categoría del servicio está inactiva';
    END IF;
    UPDATE servicios SET estado = p_estado WHERE id_servicio = p_id_servicio;
END $$;

-- ---------------------------------------------------------------------
-- SP06  Crear factura (encabezado en BORRADOR)
--   RN-10 Cliente activo; empleado activo con puesto Facturista o Gerente
--   RN-11 Folio consecutivo F-000001, sin huecos ni duplicados (bloqueo)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_crear_factura(
    p_id_cliente  INT,
    p_id_empleado INT,
    INOUT p_id_factura INT DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE v_num INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM clientes WHERE id_cliente = p_id_cliente AND estado) THEN
        RAISE EXCEPTION 'RN-10: El cliente % no existe o está inactivo', p_id_cliente;
    END IF;
    IF NOT fn_empleado_puede(p_id_empleado, ARRAY['Facturista','Gerente']) THEN
        RAISE EXCEPTION 'RN-10: El empleado % no puede facturar', p_id_empleado;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('folio_facturas'));   -- un folio a la vez
    SELECT coalesce(max(substring(folio FROM 3)::INT), 0) + 1 INTO v_num FROM facturas;

    INSERT INTO facturas(id_cliente, id_empleado, folio)
    VALUES (p_id_cliente, p_id_empleado, 'F-' || lpad(v_num::TEXT, 6, '0'))
    RETURNING id_factura INTO p_id_factura;
END $$;

-- ---------------------------------------------------------------------
-- SP07  Recalcular totales
--   RN-15 subtotal = Σ detalle.subtotal; impuestos = subtotal × 16 %;
--         total = subtotal + impuestos
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_recalcular_totales(p_id_factura INT)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE v_sub DECIMAL;
BEGIN
    SELECT coalesce(sum(subtotal),0) INTO v_sub FROM detalle_factura WHERE id_factura = p_id_factura;
    UPDATE facturas
       SET subtotal  = v_sub,
           impuestos = round(v_sub * fn_tasa_iva(), 2),
           total     = v_sub + round(v_sub * fn_tasa_iva(), 2)
     WHERE id_factura = p_id_factura;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La factura % no existe', p_id_factura;
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- SP08  Agregar concepto a la factura
--   RN-12 Sólo facturas en BORRADOR se modifican
--   RN-13 Servicio activo, cantidad > 0, precio tomado del catálogo
--   RN-14 Descuento entre 0 y 50 % del importe del renglón
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_agregar_detalle(
    p_id_factura    INT,
    p_id_servicio   INT,
    p_cantidad      INT,
    p_descuento_pct DECIMAL DEFAULT 0,
    INOUT p_id_detalle INT DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    v_estado  VARCHAR;
    v_precio  DECIMAL;
    v_desc    DECIMAL;
BEGIN
    SELECT estado INTO v_estado FROM facturas WHERE id_factura = p_id_factura FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La factura % no existe', p_id_factura;
    ELSIF v_estado <> 'BORRADOR' THEN
        RAISE EXCEPTION 'RN-12: La factura está %; sólo se modifica en BORRADOR', v_estado;
    END IF;
    SELECT precio_base INTO v_precio FROM servicios WHERE id_servicio = p_id_servicio AND estado;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'RN-13: El servicio % no existe o está inactivo', p_id_servicio;
    END IF;
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'RN-13: La cantidad debe ser mayor a cero';
    END IF;
    IF coalesce(p_descuento_pct,0) < 0 OR p_descuento_pct > 50 THEN
        RAISE EXCEPTION 'RN-14: El descuento debe estar entre 0 y 50 %%';
    END IF;

    v_desc := round(p_cantidad * v_precio * coalesce(p_descuento_pct,0) / 100, 2);
    INSERT INTO detalle_factura(id_factura, id_servicio, cantidad, precio_unitario, descuento, subtotal)
    VALUES (p_id_factura, p_id_servicio, p_cantidad, v_precio, v_desc,
            round(p_cantidad * v_precio, 2) - v_desc)
    RETURNING id_detalle INTO p_id_detalle;

    CALL sp_recalcular_totales(p_id_factura);
END $$;

-- ---------------------------------------------------------------------
-- SP09  Quitar concepto
--   RN-12 Sólo en BORRADOR
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_eliminar_detalle(p_id_detalle INT)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    v_id_factura INT;
    v_estado     VARCHAR;
BEGIN
    SELECT f.id_factura, f.estado INTO v_id_factura, v_estado
      FROM detalle_factura d JOIN facturas f USING (id_factura)
     WHERE d.id_detalle = p_id_detalle;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El concepto % no existe', p_id_detalle;
    ELSIF v_estado <> 'BORRADOR' THEN
        RAISE EXCEPTION 'RN-12: La factura está %; sólo se modifica en BORRADOR', v_estado;
    END IF;
    DELETE FROM detalle_factura WHERE id_detalle = p_id_detalle;
    CALL sp_recalcular_totales(v_id_factura);
END $$;

-- ---------------------------------------------------------------------
-- SP10  Emitir factura
--   RN-16 Al menos un concepto y total > 0
--   RN-17 fecha_emision = ahora; fecha_vencimiento = emisión + días de crédito (0 a 90)
--   RN-18 No se emite a un cliente con facturas vencidas y saldo pendiente
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_emitir_factura(
    p_id_factura   INT,
    p_dias_credito INT DEFAULT 30)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE v_f facturas%ROWTYPE;
BEGIN
    SELECT * INTO v_f FROM facturas WHERE id_factura = p_id_factura FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La factura % no existe', p_id_factura;
    ELSIF v_f.estado <> 'BORRADOR' THEN
        RAISE EXCEPTION 'RN-12: La factura ya está %', v_f.estado;
    END IF;
    CALL sp_recalcular_totales(p_id_factura);
    SELECT * INTO v_f FROM facturas WHERE id_factura = p_id_factura;
    IF v_f.total <= 0 OR NOT EXISTS (SELECT 1 FROM detalle_factura WHERE id_factura = p_id_factura) THEN
        RAISE EXCEPTION 'RN-16: La factura no tiene conceptos o su total es cero';
    END IF;
    IF p_dias_credito IS NULL OR p_dias_credito NOT BETWEEN 0 AND 90 THEN
        RAISE EXCEPTION 'RN-17: Los días de crédito deben estar entre 0 y 90';
    END IF;
    IF EXISTS (SELECT 1 FROM facturas
                WHERE id_cliente = v_f.id_cliente AND estado = 'EMITIDA'
                  AND fecha_vencimiento < now() AND fn_saldo_factura(id_factura) > 0) THEN
        RAISE EXCEPTION 'RN-18: El cliente tiene facturas vencidas con saldo pendiente';
    END IF;

    UPDATE facturas
       SET estado = 'EMITIDA',
           fecha_emision = now(),
           fecha_vencimiento = now() + make_interval(days => p_dias_credito)
     WHERE id_factura = p_id_factura;
END $$;

-- ---------------------------------------------------------------------
-- SP11  Registrar pago (abono)
--   RN-19 Sólo facturas EMITIDAS; empleado Cajero o Gerente
--   RN-20 Método de pago activo
--   RN-21 0 < monto ≤ saldo pendiente
--   RN-22 Saldo en cero → la factura pasa a PAGADA
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_pago(
    p_id_factura     INT,
    p_id_metodo_pago INT,
    p_monto          DECIMAL,
    p_referencia     VARCHAR,
    p_id_empleado    INT,
    INOUT p_id_pago  INT DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    v_estado VARCHAR;
    v_saldo  DECIMAL;
BEGIN
    SELECT estado INTO v_estado FROM facturas WHERE id_factura = p_id_factura FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La factura % no existe', p_id_factura;
    ELSIF v_estado <> 'EMITIDA' THEN
        RAISE EXCEPTION 'RN-19: No se puede abonar a una factura %', v_estado;
    END IF;
    IF NOT fn_empleado_puede(p_id_empleado, ARRAY['Cajero','Gerente']) THEN
        RAISE EXCEPTION 'RN-19: El empleado % no puede registrar pagos', p_id_empleado;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM metodos_pago WHERE id_metodo_pago = p_id_metodo_pago AND estado) THEN
        RAISE EXCEPTION 'RN-20: El método de pago % no existe o está inactivo', p_id_metodo_pago;
    END IF;
    v_saldo := fn_saldo_factura(p_id_factura);
    IF p_monto IS NULL OR p_monto <= 0 OR p_monto > v_saldo THEN
        RAISE EXCEPTION 'RN-21: Monto % inválido (saldo %)', p_monto, v_saldo;
    END IF;

    INSERT INTO pagos(id_factura, id_metodo_pago, monto, referencia)
    VALUES (p_id_factura, p_id_metodo_pago, round(p_monto,2), p_referencia)
    RETURNING id_pago INTO p_id_pago;

    IF fn_saldo_factura(p_id_factura) = 0 THEN
        UPDATE facturas SET estado = 'PAGADA' WHERE id_factura = p_id_factura;
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- SP12  Cancelar un pago (p.ej. cheque rebotado o captura errónea)
--   RN-23 Sólo un Gerente; el pago pasa a CANCELADO (no se borra) y,
--         si la factura estaba PAGADA, regresa a EMITIDA
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancelar_pago(
    p_id_pago     INT,
    p_id_empleado INT)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    v_id_factura INT;
    v_estado     VARCHAR;
BEGIN
    SELECT id_factura, estado INTO v_id_factura, v_estado FROM pagos WHERE id_pago = p_id_pago FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El pago % no existe', p_id_pago;
    ELSIF v_estado <> 'APLICADO' THEN
        RAISE EXCEPTION 'RN-23: El pago ya está %', v_estado;
    END IF;
    IF NOT fn_empleado_puede(p_id_empleado, ARRAY['Gerente']) THEN
        RAISE EXCEPTION 'RN-23: Sólo un Gerente puede cancelar pagos';
    END IF;
    UPDATE pagos SET estado = 'CANCELADO' WHERE id_pago = p_id_pago;
    UPDATE facturas SET estado = 'EMITIDA' WHERE id_factura = v_id_factura AND estado = 'PAGADA';
END $$;

-- ---------------------------------------------------------------------
-- SP13  Cancelar factura
--   RN-24 Sólo EMITIDA, sin pagos APLICADOS, y la cancela un Gerente
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancelar_factura(
    p_id_factura  INT,
    p_id_empleado INT)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE v_estado VARCHAR;
BEGIN
    SELECT estado INTO v_estado FROM facturas WHERE id_factura = p_id_factura FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La factura % no existe', p_id_factura;
    ELSIF v_estado <> 'EMITIDA' THEN
        RAISE EXCEPTION 'RN-24: Sólo se cancela una factura EMITIDA (está %)', v_estado;
    END IF;
    IF EXISTS (SELECT 1 FROM pagos WHERE id_factura = p_id_factura AND estado = 'APLICADO') THEN
        RAISE EXCEPTION 'RN-24: La factura tiene pagos aplicados; cancélelos primero';
    END IF;
    IF NOT fn_empleado_puede(p_id_empleado, ARRAY['Gerente']) THEN
        RAISE EXCEPTION 'RN-24: Sólo un Gerente puede cancelar facturas';
    END IF;
    UPDATE facturas SET estado = 'CANCELADA' WHERE id_factura = p_id_factura;
END $$;

-- =====================================================================
--  VISTAS DE REPORTE
-- =====================================================================

-- V1 Catálogo: servicio, categoría y número de características
CREATE OR REPLACE VIEW vw_catalogo_servicios AS
SELECT s.codigo_servicio, s.nombre_servicio, c.nombre_categoria, s.precio_base,
       s.unidad_medida, s.estado, count(sc.id_caracteristica) AS num_caracteristicas
  FROM servicios s
  JOIN categorias_servicio c USING (id_categoria)
  LEFT JOIN servicio_caracteristicas sc USING (id_servicio)
 GROUP BY s.id_servicio, c.nombre_categoria
 ORDER BY s.codigo_servicio;

-- V2 Ficha técnica de cada servicio
CREATE OR REPLACE VIEW vw_ficha_servicio AS
SELECT s.codigo_servicio, s.nombre_servicio, k.nombre_caracteristica, sc.valor, k.unidad
  FROM servicio_caracteristicas sc
  JOIN servicios s       USING (id_servicio)
  JOIN caracteristicas k USING (id_caracteristica)
 ORDER BY s.codigo_servicio, k.id_caracteristica;

-- V3 Facturas con cliente, empleado, saldo y días de atraso
CREATE OR REPLACE VIEW vw_facturas AS
SELECT f.id_factura, f.folio,
       trim(c.nombre || ' ' || coalesce(c.apellido,'')) AS cliente,
       c.identificacion_fiscal AS rfc, e.nombre AS empleado,
       f.fecha_emision, f.fecha_vencimiento, f.subtotal, f.impuestos, f.total,
       CASE WHEN f.estado = 'CANCELADA' THEN 0 ELSE fn_saldo_factura(f.id_factura) END AS saldo,
       CASE WHEN f.estado = 'EMITIDA' AND f.fecha_vencimiento < now()
            THEN extract(day FROM now() - f.fecha_vencimiento)::INT ELSE 0 END AS dias_atraso,
       f.estado
  FROM facturas f
  JOIN clientes c  USING (id_cliente)
  JOIN empleados e USING (id_empleado)
 ORDER BY f.id_factura;

-- V4 Ventas netas por categoría (facturas emitidas o pagadas)
CREATE OR REPLACE VIEW vw_ventas_categoria AS
SELECT c.nombre_categoria,
       count(DISTINCT f.id_factura) AS facturas,
       sum(d.subtotal)              AS venta_neta,
       round(sum(d.subtotal) * fn_tasa_iva(), 2) AS impuestos
  FROM detalle_factura d
  JOIN facturas f            USING (id_factura)
  JOIN servicios s           USING (id_servicio)
  JOIN categorias_servicio c USING (id_categoria)
 WHERE f.estado IN ('EMITIDA','PAGADA')
 GROUP BY c.nombre_categoria
 ORDER BY venta_neta DESC;

-- V5 Cobranza por método de pago (pagos aplicados)
CREATE OR REPLACE VIEW vw_cobranza_metodo AS
SELECT m.nombre_metodo, count(p.id_pago) AS pagos, coalesce(sum(p.monto),0) AS cobrado
  FROM metodos_pago m
  LEFT JOIN pagos p ON p.id_metodo_pago = m.id_metodo_pago AND p.estado = 'APLICADO'
 GROUP BY m.id_metodo_pago
 ORDER BY cobrado DESC;

-- =====================================================================
--  Parte 3: DATOS INICIALES (catálogos + escenarios de prueba)
--  Los servicios y sus características se cargan con los SP para que
--  pasen por las mismas validaciones que usará la aplicación.
-- =====================================================================
SET search_path TO facturacion;

INSERT INTO empleados(nombre, puesto, correo) VALUES
  ('Laura Méndez Ríos',    'Gerente',    'laura.mendez@facturacion.mx'),
  ('Ana Torres Vega',      'Facturista', 'ana.torres@facturacion.mx'),
  ('Carlos Ruiz Pineda',   'Cajero',     'carlos.ruiz@facturacion.mx'),
  ('Diego Salas Ortega',   'Auxiliar',   'diego.salas@facturacion.mx');

INSERT INTO metodos_pago(nombre_metodo, descripcion, estado) VALUES
  ('Efectivo',             'Pago en caja',                                  TRUE),
  ('Transferencia SPEI',   'Transferencia electrónica interbancaria',       TRUE),
  ('Tarjeta de crédito',   'Cargo a tarjeta de crédito por terminal',       TRUE),
  ('Tarjeta de débito',    'Cargo a tarjeta de débito por terminal',        TRUE),
  ('Cheque nominativo',    'Cheque a nombre de la empresa (suspendido)',    FALSE);

INSERT INTO categorias_servicio(nombre_categoria, descripcion) VALUES
  ('Desarrollo de Software', 'Construcción y mantenimiento de aplicaciones'),
  ('Nube y Hosting', 'Infraestructura en la nube, servidores y dominios'),
  ('Soporte Técnico', 'Mesa de ayuda y mantenimiento de equipos'),
  ('Redes y Telecomunicaciones', 'Cableado, enlaces y equipos de red'),
  ('Ciberseguridad', 'Evaluación y protección de activos de información'),
  ('Datos y Analítica', 'Bases de datos, BI y analítica'),
  ('Capacitación', 'Cursos y talleres para empresas'),
  ('Consultoría', 'Consultoría de negocio y tecnología'),
  ('Diseño y Marketing Digital', 'Identidad gráfica y presencia digital'),
  ('Servicios Administrativos y Contables', 'Contabilidad, nómina y trámites fiscales');

-- Las características de opciones fijas se guardan como TEXTO y sus
-- opciones válidas quedan en la descripción.
INSERT INTO caracteristicas(nombre_caracteristica, tipo_dato, unidad, descripcion) VALUES
  /*  1 */ ('Modalidad', 'TEXTO', NULL, 'Forma de prestación del servicio. Opciones: Presencial, Remoto, Híbrido'),
  /*  2 */ ('Tipo de cobro', 'TEXTO', NULL, 'Periodicidad con que se factura. Opciones: Único, Mensual, Anual, Por hora, Por evento'),
  /*  3 */ ('Tiempo de entrega', 'ENTERO', 'días', 'Días hábiles para entregar o activar'),
  /*  4 */ ('Garantía', 'ENTERO', 'días', 'Días de garantía posteriores a la entrega'),
  /*  5 */ ('Requiere contrato', 'BOOLEANO', NULL, 'Si exige contrato firmado'),
  /*  6 */ ('Nivel de servicio (SLA)', 'TEXTO', NULL, 'Nivel de compromiso de servicio. Opciones: Básico, Estándar, Premium'),
  /*  7 */ ('Horario de atención', 'TEXTO', NULL, 'Cobertura horaria. Opciones: 8x5, 12x6, 24x7'),
  /*  8 */ ('Vigencia de la tarifa', 'FECHA', NULL, 'Fecha hasta la que se respeta el precio'),
  /*  9 */ ('Lenguaje principal', 'TEXTO', NULL, 'Lenguaje o framework base'),
  /* 10 */ ('Plataforma', 'TEXTO', NULL, 'Plataforma destino. Opciones: Web, Móvil, Escritorio, Multiplataforma'),
  /* 11 */ ('Horas estimadas', 'ENTERO', 'horas', 'Esfuerzo estimado'),
  /* 12 */ ('Incluye código fuente', 'BOOLEANO', NULL, 'Entrega del código al cliente'),
  /* 13 */ ('Metodología', 'TEXTO', NULL, 'Metodología de trabajo. Opciones: Scrum, Kanban, Cascada'),
  /* 14 */ ('Almacenamiento', 'ENTERO', 'GB', 'Espacio en disco'),
  /* 15 */ ('Memoria RAM', 'ENTERO', 'GB', 'Memoria asignada'),
  /* 16 */ ('Núcleos vCPU', 'ENTERO', 'núcleos', 'Procesadores virtuales'),
  /* 17 */ ('Transferencia mensual', 'ENTERO', 'GB', 'Tráfico incluido por mes'),
  /* 18 */ ('Disponibilidad garantizada', 'DECIMAL', '%', 'Uptime comprometido'),
  /* 19 */ ('Tiempo de respuesta', 'ENTERO', 'horas', 'Horas máximas para atender un ticket'),
  /* 20 */ ('Incidentes incluidos', 'ENTERO', 'tickets', 'Tickets incluidos por periodo'),
  /* 21 */ ('Equipos cubiertos', 'ENTERO', 'equipos', 'Número de equipos en póliza'),
  /* 22 */ ('Incluye refacciones', 'BOOLEANO', NULL, 'Si las piezas están incluidas'),
  /* 23 */ ('Ancho de banda', 'ENTERO', 'Mbps', 'Velocidad del enlace o red'),
  /* 24 */ ('Nodos de red', 'ENTERO', 'nodos', 'Puntos de red instalados o administrados'),
  /* 25 */ ('Tipo de enlace', 'TEXTO', NULL, 'Medio de transmisión. Opciones: Fibra, Cobre, Inalámbrico, Satelital'),
  /* 26 */ ('IP fija', 'BOOLEANO', NULL, 'Incluye dirección IP pública fija'),
  /* 27 */ ('Norma de referencia', 'TEXTO', NULL, 'Marco de seguridad aplicado. Opciones: ISO 27001, NIST, PCI DSS, OWASP'),
  /* 28 */ ('Activos evaluados', 'ENTERO', 'activos', 'Servidores, apps o equipos revisados'),
  /* 29 */ ('Incluye informe ejecutivo', 'BOOLEANO', NULL, 'Reporte para dirección'),
  /* 30 */ ('Frecuencia de escaneo', 'TEXTO', NULL, 'Periodicidad de revisiones. Opciones: Única, Mensual, Trimestral'),
  /* 31 */ ('Volumen de datos', 'ENTERO', 'GB', 'Datos procesados'),
  /* 32 */ ('Fuentes de datos', 'ENTERO', 'fuentes', 'Sistemas origen integrados'),
  /* 33 */ ('Herramienta BI', 'TEXTO', NULL, 'Herramienta de visualización. Opciones: Power BI, Tableau, Looker, Metabase'),
  /* 34 */ ('Frecuencia de actualización', 'TEXTO', NULL, 'Refresco de datos. Opciones: Diaria, Semanal, Mensual, Tiempo real'),
  /* 35 */ ('Duración del curso', 'ENTERO', 'horas', 'Horas de instrucción'),
  /* 36 */ ('Participantes máximos', 'ENTERO', 'personas', 'Cupo por grupo'),
  /* 37 */ ('Incluye constancia', 'BOOLEANO', NULL, 'Constancia de participación'),
  /* 38 */ ('Nivel del curso', 'TEXTO', NULL, 'Nivel de dificultad. Opciones: Básico, Intermedio, Avanzado'),
  /* 39 */ ('Registro STPS DC-3', 'BOOLEANO', NULL, 'Emite constancia DC-3'),
  /* 40 */ ('Entregables', 'ENTERO', 'documentos', 'Documentos entregados'),
  /* 41 */ ('Sesiones de seguimiento', 'ENTERO', 'sesiones', 'Reuniones incluidas'),
  /* 42 */ ('Área de negocio', 'TEXTO', NULL, 'Área de la empresa atendida'),
  /* 43 */ ('Consultores asignados', 'ENTERO', 'personas', 'Tamaño del equipo consultor'),
  /* 44 */ ('Propuestas de diseño', 'ENTERO', 'propuestas', 'Opciones presentadas'),
  /* 45 */ ('Rondas de revisión', 'ENTERO', 'rondas', 'Cambios incluidos'),
  /* 46 */ ('Redes sociales gestionadas', 'ENTERO', 'redes', 'Cuentas administradas'),
  /* 47 */ ('Formato de entrega', 'TEXTO', NULL, 'Formato final. Opciones: PDF, PNG, SVG, MP4, Fuentes editables'),
  /* 48 */ ('Régimen fiscal atendido', 'TEXTO', NULL, 'Régimen del contribuyente. Opciones: 601, 603, 612, 626'),
  /* 49 */ ('Declaraciones incluidas', 'ENTERO', 'declaraciones', 'Declaraciones por periodo'),
  /* 50 */ ('Empleados en nómina', 'ENTERO', 'empleados', 'Trabajadores procesados');

-- 100 servicios (10 por categoría) dados de alta con SP02 y sus
-- características asignadas con SP03 (8 comunes + 3 a 5 específicas).
DO $$
DECLARE v_id INT;
BEGIN
  -- ===== Categoría 1: Desarrollo de Software =====
  CALL sp_registrar_servicio(1, 'SRV-001', 'Desarrollo de sitio web corporativo', 'Desarrollo de sitio web corporativo. Construcción y mantenimiento de aplicaciones.', 35000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '30');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 9, 'PHP/Laravel');
  CALL sp_asignar_caracteristica(v_id, 10, 'Web');
  CALL sp_asignar_caracteristica(v_id, 11, '120');
  CALL sp_asignar_caracteristica(v_id, 12, 'SI');
  CALL sp_asignar_caracteristica(v_id, 13, 'Scrum');
  CALL sp_registrar_servicio(1, 'SRV-002', 'Desarrollo de tienda en línea', 'Desarrollo de tienda en línea. Construcción y mantenimiento de aplicaciones.', 68000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '45');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 9, 'JavaScript/React');
  CALL sp_asignar_caracteristica(v_id, 10, 'Web');
  CALL sp_asignar_caracteristica(v_id, 11, '260');
  CALL sp_asignar_caracteristica(v_id, 12, 'SI');
  CALL sp_asignar_caracteristica(v_id, 13, 'Scrum');
  CALL sp_registrar_servicio(1, 'SRV-003', 'Aplicación móvil Android/iOS', 'Aplicación móvil Android/iOS. Construcción y mantenimiento de aplicaciones.', 120000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '90');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 9, 'Kotlin/Swift');
  CALL sp_asignar_caracteristica(v_id, 10, 'Móvil');
  CALL sp_asignar_caracteristica(v_id, 11, '480');
  CALL sp_asignar_caracteristica(v_id, 12, 'SI');
  CALL sp_asignar_caracteristica(v_id, 13, 'Scrum');
  CALL sp_registrar_servicio(1, 'SRV-004', 'Sistema web a la medida', 'Sistema web a la medida. Construcción y mantenimiento de aplicaciones.', 95000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '75');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 9, 'C#/.NET');
  CALL sp_asignar_caracteristica(v_id, 10, 'Web');
  CALL sp_asignar_caracteristica(v_id, 11, '380');
  CALL sp_asignar_caracteristica(v_id, 12, 'SI');
  CALL sp_asignar_caracteristica(v_id, 13, 'Scrum');
  CALL sp_registrar_servicio(1, 'SRV-005', 'API REST de integración', 'API REST de integración. Construcción y mantenimiento de aplicaciones.', 42000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '30');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 9, 'Node.js');
  CALL sp_asignar_caracteristica(v_id, 10, 'Multiplataforma');
  CALL sp_asignar_caracteristica(v_id, 11, '160');
  CALL sp_asignar_caracteristica(v_id, 12, 'SI');
  CALL sp_asignar_caracteristica(v_id, 13, 'Kanban');
  CALL sp_registrar_servicio(1, 'SRV-006', 'Mantenimiento evolutivo de software', 'Mantenimiento evolutivo de software. Construcción y mantenimiento de aplicaciones.', 950, 'Hora', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por hora');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 9, 'Java/Spring');
  CALL sp_asignar_caracteristica(v_id, 10, 'Multiplataforma');
  CALL sp_asignar_caracteristica(v_id, 11, '1');
  CALL sp_asignar_caracteristica(v_id, 12, 'NO');
  CALL sp_asignar_caracteristica(v_id, 13, 'Kanban');
  CALL sp_registrar_servicio(1, 'SRV-007', 'Migración de sistema heredado', 'Migración de sistema heredado. Construcción y mantenimiento de aplicaciones.', 78000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '60');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 9, 'Python/Django');
  CALL sp_asignar_caracteristica(v_id, 10, 'Web');
  CALL sp_asignar_caracteristica(v_id, 11, '300');
  CALL sp_asignar_caracteristica(v_id, 12, 'SI');
  CALL sp_asignar_caracteristica(v_id, 13, 'Cascada');
  CALL sp_registrar_servicio(1, 'SRV-008', 'Pruebas de calidad (QA) de software', 'Pruebas de calidad (QA) de software. Construcción y mantenimiento de aplicaciones.', 18500, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '15');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 9, 'Selenium/Cypress');
  CALL sp_asignar_caracteristica(v_id, 10, 'Multiplataforma');
  CALL sp_asignar_caracteristica(v_id, 11, '80');
  CALL sp_asignar_caracteristica(v_id, 12, 'SI');
  CALL sp_asignar_caracteristica(v_id, 13, 'Kanban');
  CALL sp_registrar_servicio(1, 'SRV-009', 'Landing page promocional', 'Landing page promocional. Construcción y mantenimiento de aplicaciones.', 9500, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 9, 'HTML/CSS');
  CALL sp_asignar_caracteristica(v_id, 10, 'Web');
  CALL sp_asignar_caracteristica(v_id, 11, '40');
  CALL sp_asignar_caracteristica(v_id, 12, 'SI');
  CALL sp_asignar_caracteristica(v_id, 13, 'Cascada');
  CALL sp_registrar_servicio(1, 'SRV-010', 'Desarrollo de bot conversacional', 'Desarrollo de bot conversacional. Construcción y mantenimiento de aplicaciones.', 27000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '25');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 9, 'Python/Rasa');
  CALL sp_asignar_caracteristica(v_id, 10, 'Multiplataforma');
  CALL sp_asignar_caracteristica(v_id, 11, '110');
  CALL sp_asignar_caracteristica(v_id, 12, 'SI');
  CALL sp_asignar_caracteristica(v_id, 13, 'Scrum');
  -- ===== Categoría 2: Nube y Hosting =====
  CALL sp_registrar_servicio(2, 'SRV-011', 'Hosting compartido básico', 'Hosting compartido básico. Infraestructura en la nube, servidores y dominios.', 149, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 14, '10');
  CALL sp_asignar_caracteristica(v_id, 15, '1');
  CALL sp_asignar_caracteristica(v_id, 16, '1');
  CALL sp_asignar_caracteristica(v_id, 17, '100');
  CALL sp_asignar_caracteristica(v_id, 18, '99.5');
  CALL sp_registrar_servicio(2, 'SRV-012', 'Hosting compartido empresarial', 'Hosting compartido empresarial. Infraestructura en la nube, servidores y dominios.', 399, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 14, '50');
  CALL sp_asignar_caracteristica(v_id, 15, '2');
  CALL sp_asignar_caracteristica(v_id, 16, '1');
  CALL sp_asignar_caracteristica(v_id, 17, '500');
  CALL sp_asignar_caracteristica(v_id, 18, '99.9');
  CALL sp_registrar_servicio(2, 'SRV-013', 'Servidor virtual privado (VPS) 2 vCPU', 'Servidor virtual privado (VPS) 2 vCPU. Infraestructura en la nube, servidores y dominios.', 890, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 14, '80');
  CALL sp_asignar_caracteristica(v_id, 15, '4');
  CALL sp_asignar_caracteristica(v_id, 16, '2');
  CALL sp_asignar_caracteristica(v_id, 17, '2000');
  CALL sp_asignar_caracteristica(v_id, 18, '99.9');
  CALL sp_registrar_servicio(2, 'SRV-014', 'Servidor virtual privado (VPS) 8 vCPU', 'Servidor virtual privado (VPS) 8 vCPU. Infraestructura en la nube, servidores y dominios.', 2890, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 14, '320');
  CALL sp_asignar_caracteristica(v_id, 15, '16');
  CALL sp_asignar_caracteristica(v_id, 16, '8');
  CALL sp_asignar_caracteristica(v_id, 17, '5000');
  CALL sp_asignar_caracteristica(v_id, 18, '99.95');
  CALL sp_registrar_servicio(2, 'SRV-015', 'Servidor dedicado', 'Servidor dedicado. Infraestructura en la nube, servidores y dominios.', 6500, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '3');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 14, '1000');
  CALL sp_asignar_caracteristica(v_id, 15, '64');
  CALL sp_asignar_caracteristica(v_id, 16, '16');
  CALL sp_asignar_caracteristica(v_id, 17, '10000');
  CALL sp_asignar_caracteristica(v_id, 18, '99.99');
  CALL sp_registrar_servicio(2, 'SRV-016', 'Registro de dominio .com.mx', 'Registro de dominio .com.mx. Infraestructura en la nube, servidores y dominios.', 520, 'Año', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Anual');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 14, '1');
  CALL sp_asignar_caracteristica(v_id, 15, '1');
  CALL sp_asignar_caracteristica(v_id, 16, '1');
  CALL sp_asignar_caracteristica(v_id, 17, '10');
  CALL sp_asignar_caracteristica(v_id, 18, '99.9');
  CALL sp_registrar_servicio(2, 'SRV-017', 'Certificado SSL empresarial', 'Certificado SSL empresarial. Infraestructura en la nube, servidores y dominios.', 2400, 'Año', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Anual');
  CALL sp_asignar_caracteristica(v_id, 3, '2');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 14, '1');
  CALL sp_asignar_caracteristica(v_id, 15, '1');
  CALL sp_asignar_caracteristica(v_id, 16, '1');
  CALL sp_asignar_caracteristica(v_id, 17, '10');
  CALL sp_asignar_caracteristica(v_id, 18, '99.9');
  CALL sp_registrar_servicio(2, 'SRV-018', 'Respaldo en la nube', 'Respaldo en la nube. Infraestructura en la nube, servidores y dominios.', 690, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 14, '500');
  CALL sp_asignar_caracteristica(v_id, 15, '2');
  CALL sp_asignar_caracteristica(v_id, 16, '1');
  CALL sp_asignar_caracteristica(v_id, 17, '200');
  CALL sp_asignar_caracteristica(v_id, 18, '99.9');
  CALL sp_registrar_servicio(2, 'SRV-019', 'Correo corporativo por buzón', 'Correo corporativo por buzón. Infraestructura en la nube, servidores y dominios.', 85, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 14, '25');
  CALL sp_asignar_caracteristica(v_id, 15, '1');
  CALL sp_asignar_caracteristica(v_id, 16, '1');
  CALL sp_asignar_caracteristica(v_id, 17, '50');
  CALL sp_asignar_caracteristica(v_id, 18, '99.9');
  CALL sp_registrar_servicio(2, 'SRV-020', 'Migración a la nube', 'Migración a la nube. Infraestructura en la nube, servidores y dominios.', 32000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '20');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 14, '200');
  CALL sp_asignar_caracteristica(v_id, 15, '8');
  CALL sp_asignar_caracteristica(v_id, 16, '4');
  CALL sp_asignar_caracteristica(v_id, 17, '1000');
  CALL sp_asignar_caracteristica(v_id, 18, '99.95');
  -- ===== Categoría 3: Soporte Técnico =====
  CALL sp_registrar_servicio(3, 'SRV-021', 'Póliza de soporte mensual básica', 'Póliza de soporte mensual básica. Mesa de ayuda y mantenimiento de equipos.', 2500, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 19, '8');
  CALL sp_asignar_caracteristica(v_id, 20, '10');
  CALL sp_asignar_caracteristica(v_id, 21, '10');
  CALL sp_asignar_caracteristica(v_id, 22, 'NO');
  CALL sp_registrar_servicio(3, 'SRV-022', 'Póliza de soporte mensual premium', 'Póliza de soporte mensual premium. Mesa de ayuda y mantenimiento de equipos.', 7800, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 19, '2');
  CALL sp_asignar_caracteristica(v_id, 20, '99');
  CALL sp_asignar_caracteristica(v_id, 21, '50');
  CALL sp_asignar_caracteristica(v_id, 22, 'SI');
  CALL sp_registrar_servicio(3, 'SRV-023', 'Soporte técnico por evento', 'Soporte técnico por evento. Mesa de ayuda y mantenimiento de equipos.', 650, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 19, '24');
  CALL sp_asignar_caracteristica(v_id, 20, '1');
  CALL sp_asignar_caracteristica(v_id, 21, '1');
  CALL sp_asignar_caracteristica(v_id, 22, 'NO');
  CALL sp_registrar_servicio(3, 'SRV-024', 'Mantenimiento preventivo de equipo de cómputo', 'Mantenimiento preventivo de equipo de cómputo. Mesa de ayuda y mantenimiento de equipos.', 450, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '2');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 19, '48');
  CALL sp_asignar_caracteristica(v_id, 20, '1');
  CALL sp_asignar_caracteristica(v_id, 21, '1');
  CALL sp_asignar_caracteristica(v_id, 22, 'NO');
  CALL sp_registrar_servicio(3, 'SRV-025', 'Mantenimiento correctivo de equipo de cómputo', 'Mantenimiento correctivo de equipo de cómputo. Mesa de ayuda y mantenimiento de equipos.', 750, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '3');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 19, '24');
  CALL sp_asignar_caracteristica(v_id, 20, '1');
  CALL sp_asignar_caracteristica(v_id, 21, '1');
  CALL sp_asignar_caracteristica(v_id, 22, 'SI');
  CALL sp_registrar_servicio(3, 'SRV-026', 'Instalación de sistema operativo', 'Instalación de sistema operativo. Mesa de ayuda y mantenimiento de equipos.', 550, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 19, '24');
  CALL sp_asignar_caracteristica(v_id, 20, '1');
  CALL sp_asignar_caracteristica(v_id, 21, '1');
  CALL sp_asignar_caracteristica(v_id, 22, 'NO');
  CALL sp_registrar_servicio(3, 'SRV-027', 'Mantenimiento de impresoras', 'Mantenimiento de impresoras. Mesa de ayuda y mantenimiento de equipos.', 600, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '2');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 19, '48');
  CALL sp_asignar_caracteristica(v_id, 20, '1');
  CALL sp_asignar_caracteristica(v_id, 21, '1');
  CALL sp_asignar_caracteristica(v_id, 22, 'SI');
  CALL sp_registrar_servicio(3, 'SRV-028', 'Mesa de ayuda remota', 'Mesa de ayuda remota. Mesa de ayuda y mantenimiento de equipos.', 4200, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 19, '4');
  CALL sp_asignar_caracteristica(v_id, 20, '50');
  CALL sp_asignar_caracteristica(v_id, 21, '30');
  CALL sp_asignar_caracteristica(v_id, 22, 'NO');
  CALL sp_registrar_servicio(3, 'SRV-029', 'Recuperación de información', 'Recuperación de información. Mesa de ayuda y mantenimiento de equipos.', 3200, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 19, '24');
  CALL sp_asignar_caracteristica(v_id, 20, '1');
  CALL sp_asignar_caracteristica(v_id, 21, '1');
  CALL sp_asignar_caracteristica(v_id, 22, 'NO');
  CALL sp_registrar_servicio(3, 'SRV-030', 'Soporte en sitio por hora', 'Soporte en sitio por hora. Mesa de ayuda y mantenimiento de equipos.', 480, 'Hora', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por hora');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 19, '4');
  CALL sp_asignar_caracteristica(v_id, 20, '1');
  CALL sp_asignar_caracteristica(v_id, 21, '1');
  CALL sp_asignar_caracteristica(v_id, 22, 'NO');
  -- ===== Categoría 4: Redes y Telecomunicaciones =====
  CALL sp_registrar_servicio(4, 'SRV-031', 'Instalación de cableado estructurado por nodo', 'Instalación de cableado estructurado por nodo. Cableado, enlaces y equipos de red.', 1150, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 23, '1000');
  CALL sp_asignar_caracteristica(v_id, 24, '1');
  CALL sp_asignar_caracteristica(v_id, 25, 'Cobre');
  CALL sp_asignar_caracteristica(v_id, 26, 'NO');
  CALL sp_registrar_servicio(4, 'SRV-032', 'Configuración de red LAN', 'Configuración de red LAN. Cableado, enlaces y equipos de red.', 6800, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '7');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 23, '1000');
  CALL sp_asignar_caracteristica(v_id, 24, '24');
  CALL sp_asignar_caracteristica(v_id, 25, 'Cobre');
  CALL sp_asignar_caracteristica(v_id, 26, 'NO');
  CALL sp_registrar_servicio(4, 'SRV-033', 'Instalación de red inalámbrica empresarial', 'Instalación de red inalámbrica empresarial. Cableado, enlaces y equipos de red.', 12500, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 23, '600');
  CALL sp_asignar_caracteristica(v_id, 24, '12');
  CALL sp_asignar_caracteristica(v_id, 25, 'Inalámbrico');
  CALL sp_asignar_caracteristica(v_id, 26, 'NO');
  CALL sp_registrar_servicio(4, 'SRV-034', 'Enlace dedicado de internet', 'Enlace dedicado de internet. Cableado, enlaces y equipos de red.', 4900, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '15');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 23, '200');
  CALL sp_asignar_caracteristica(v_id, 24, '1');
  CALL sp_asignar_caracteristica(v_id, 25, 'Fibra');
  CALL sp_asignar_caracteristica(v_id, 26, 'SI');
  CALL sp_registrar_servicio(4, 'SRV-035', 'Configuración de firewall perimetral', 'Configuración de firewall perimetral. Cableado, enlaces y equipos de red.', 8500, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 23, '1000');
  CALL sp_asignar_caracteristica(v_id, 24, '1');
  CALL sp_asignar_caracteristica(v_id, 25, 'Fibra');
  CALL sp_asignar_caracteristica(v_id, 26, 'SI');
  CALL sp_registrar_servicio(4, 'SRV-036', 'Instalación de conmutador IP', 'Instalación de conmutador IP. Cableado, enlaces y equipos de red.', 15000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 23, '100');
  CALL sp_asignar_caracteristica(v_id, 24, '20');
  CALL sp_asignar_caracteristica(v_id, 25, 'Cobre');
  CALL sp_asignar_caracteristica(v_id, 26, 'NO');
  CALL sp_registrar_servicio(4, 'SRV-037', 'Monitoreo de red', 'Monitoreo de red. Cableado, enlaces y equipos de red.', 3500, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '3');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 23, '1000');
  CALL sp_asignar_caracteristica(v_id, 24, '50');
  CALL sp_asignar_caracteristica(v_id, 25, 'Fibra');
  CALL sp_asignar_caracteristica(v_id, 26, 'NO');
  CALL sp_registrar_servicio(4, 'SRV-038', 'VPN corporativa', 'VPN corporativa. Cableado, enlaces y equipos de red.', 1800, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '3');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 23, '100');
  CALL sp_asignar_caracteristica(v_id, 24, '10');
  CALL sp_asignar_caracteristica(v_id, 25, 'Fibra');
  CALL sp_asignar_caracteristica(v_id, 26, 'SI');
  CALL sp_registrar_servicio(4, 'SRV-039', 'Certificación de cableado', 'Certificación de cableado. Cableado, enlaces y equipos de red.', 9500, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 23, '1000');
  CALL sp_asignar_caracteristica(v_id, 24, '48');
  CALL sp_asignar_caracteristica(v_id, 25, 'Cobre');
  CALL sp_asignar_caracteristica(v_id, 26, 'NO');
  CALL sp_registrar_servicio(4, 'SRV-040', 'Instalación de cámaras IP', 'Instalación de cámaras IP. Cableado, enlaces y equipos de red.', 2300, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 23, '100');
  CALL sp_asignar_caracteristica(v_id, 24, '4');
  CALL sp_asignar_caracteristica(v_id, 25, 'Cobre');
  CALL sp_asignar_caracteristica(v_id, 26, 'NO');
  -- ===== Categoría 5: Ciberseguridad =====
  CALL sp_registrar_servicio(5, 'SRV-041', 'Análisis de vulnerabilidades', 'Análisis de vulnerabilidades. Evaluación y protección de activos de información.', 22000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 27, 'OWASP');
  CALL sp_asignar_caracteristica(v_id, 28, '20');
  CALL sp_asignar_caracteristica(v_id, 29, 'SI');
  CALL sp_asignar_caracteristica(v_id, 30, 'Única');
  CALL sp_registrar_servicio(5, 'SRV-042', 'Prueba de penetración externa', 'Prueba de penetración externa. Evaluación y protección de activos de información.', 48000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '15');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 27, 'NIST');
  CALL sp_asignar_caracteristica(v_id, 28, '10');
  CALL sp_asignar_caracteristica(v_id, 29, 'SI');
  CALL sp_asignar_caracteristica(v_id, 30, 'Única');
  CALL sp_registrar_servicio(5, 'SRV-043', 'Auditoría de seguridad ISO 27001', 'Auditoría de seguridad ISO 27001. Evaluación y protección de activos de información.', 85000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '30');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 27, 'ISO 27001');
  CALL sp_asignar_caracteristica(v_id, 28, '50');
  CALL sp_asignar_caracteristica(v_id, 29, 'SI');
  CALL sp_asignar_caracteristica(v_id, 30, 'Única');
  CALL sp_registrar_servicio(5, 'SRV-044', 'Antivirus empresarial por equipo', 'Antivirus empresarial por equipo. Evaluación y protección de activos de información.', 120, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 27, 'NIST');
  CALL sp_asignar_caracteristica(v_id, 28, '1');
  CALL sp_asignar_caracteristica(v_id, 29, 'NO');
  CALL sp_asignar_caracteristica(v_id, 30, 'Mensual');
  CALL sp_registrar_servicio(5, 'SRV-045', 'Monitoreo de seguridad SOC', 'Monitoreo de seguridad SOC. Evaluación y protección de activos de información.', 18000, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 27, 'NIST');
  CALL sp_asignar_caracteristica(v_id, 28, '100');
  CALL sp_asignar_caracteristica(v_id, 29, 'SI');
  CALL sp_asignar_caracteristica(v_id, 30, 'Mensual');
  CALL sp_registrar_servicio(5, 'SRV-046', 'Capacitación en concientización de seguridad', 'Capacitación en concientización de seguridad. Evaluación y protección de activos de información.', 9800, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 27, 'ISO 27001');
  CALL sp_asignar_caracteristica(v_id, 28, '1');
  CALL sp_asignar_caracteristica(v_id, 29, 'NO');
  CALL sp_asignar_caracteristica(v_id, 30, 'Única');
  CALL sp_registrar_servicio(5, 'SRV-047', 'Plan de respuesta a incidentes', 'Plan de respuesta a incidentes. Evaluación y protección de activos de información.', 36000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '20');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 27, 'NIST');
  CALL sp_asignar_caracteristica(v_id, 28, '30');
  CALL sp_asignar_caracteristica(v_id, 29, 'SI');
  CALL sp_asignar_caracteristica(v_id, 30, 'Única');
  CALL sp_registrar_servicio(5, 'SRV-048', 'Gestión de parches', 'Gestión de parches. Evaluación y protección de activos de información.', 2800, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '2');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 27, 'NIST');
  CALL sp_asignar_caracteristica(v_id, 28, '50');
  CALL sp_asignar_caracteristica(v_id, 29, 'NO');
  CALL sp_asignar_caracteristica(v_id, 30, 'Mensual');
  CALL sp_registrar_servicio(5, 'SRV-049', 'Revisión de código seguro', 'Revisión de código seguro. Evaluación y protección de activos de información.', 26000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '12');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 27, 'OWASP');
  CALL sp_asignar_caracteristica(v_id, 28, '5');
  CALL sp_asignar_caracteristica(v_id, 29, 'SI');
  CALL sp_asignar_caracteristica(v_id, 30, 'Única');
  CALL sp_registrar_servicio(5, 'SRV-050', 'Análisis forense digital', 'Análisis forense digital. Evaluación y protección de activos de información.', 55000, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '15');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 27, 'NIST');
  CALL sp_asignar_caracteristica(v_id, 28, '3');
  CALL sp_asignar_caracteristica(v_id, 29, 'SI');
  CALL sp_asignar_caracteristica(v_id, 30, 'Única');
  -- ===== Categoría 6: Datos y Analítica =====
  CALL sp_registrar_servicio(6, 'SRV-051', 'Diseño de base de datos', 'Diseño de base de datos. Bases de datos, BI y analítica.', 24000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '15');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 31, '5');
  CALL sp_asignar_caracteristica(v_id, 32, '1');
  CALL sp_asignar_caracteristica(v_id, 33, 'Metabase');
  CALL sp_asignar_caracteristica(v_id, 34, 'Mensual');
  CALL sp_registrar_servicio(6, 'SRV-052', 'Administración de base de datos (DBA)', 'Administración de base de datos (DBA). Bases de datos, BI y analítica.', 9500, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '2');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 31, '200');
  CALL sp_asignar_caracteristica(v_id, 32, '3');
  CALL sp_asignar_caracteristica(v_id, 33, 'Metabase');
  CALL sp_asignar_caracteristica(v_id, 34, 'Diaria');
  CALL sp_registrar_servicio(6, 'SRV-053', 'Tablero de indicadores (dashboard)', 'Tablero de indicadores (dashboard). Bases de datos, BI y analítica.', 16500, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '12');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 31, '10');
  CALL sp_asignar_caracteristica(v_id, 32, '4');
  CALL sp_asignar_caracteristica(v_id, 33, 'Power BI');
  CALL sp_asignar_caracteristica(v_id, 34, 'Diaria');
  CALL sp_registrar_servicio(6, 'SRV-054', 'Proceso ETL de integración', 'Proceso ETL de integración. Bases de datos, BI y analítica.', 28000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '20');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 31, '50');
  CALL sp_asignar_caracteristica(v_id, 32, '6');
  CALL sp_asignar_caracteristica(v_id, 33, 'Power BI');
  CALL sp_asignar_caracteristica(v_id, 34, 'Diaria');
  CALL sp_registrar_servicio(6, 'SRV-055', 'Limpieza y depuración de datos', 'Limpieza y depuración de datos. Bases de datos, BI y analítica.', 12000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 31, '20');
  CALL sp_asignar_caracteristica(v_id, 32, '2');
  CALL sp_asignar_caracteristica(v_id, 33, 'Metabase');
  CALL sp_asignar_caracteristica(v_id, 34, 'Mensual');
  CALL sp_registrar_servicio(6, 'SRV-056', 'Modelo predictivo de ventas', 'Modelo predictivo de ventas. Bases de datos, BI y analítica.', 58000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '30');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 31, '30');
  CALL sp_asignar_caracteristica(v_id, 32, '3');
  CALL sp_asignar_caracteristica(v_id, 33, 'Tableau');
  CALL sp_asignar_caracteristica(v_id, 34, 'Semanal');
  CALL sp_registrar_servicio(6, 'SRV-057', 'Almacén de datos (data warehouse)', 'Almacén de datos (data warehouse). Bases de datos, BI y analítica.', 92000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '60');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 31, '500');
  CALL sp_asignar_caracteristica(v_id, 32, '8');
  CALL sp_asignar_caracteristica(v_id, 33, 'Looker');
  CALL sp_asignar_caracteristica(v_id, 34, 'Diaria');
  CALL sp_registrar_servicio(6, 'SRV-058', 'Reportes automatizados', 'Reportes automatizados. Bases de datos, BI y analítica.', 5400, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 31, '10');
  CALL sp_asignar_caracteristica(v_id, 32, '3');
  CALL sp_asignar_caracteristica(v_id, 33, 'Power BI');
  CALL sp_asignar_caracteristica(v_id, 34, 'Semanal');
  CALL sp_registrar_servicio(6, 'SRV-059', 'Optimización de consultas SQL', 'Optimización de consultas SQL. Bases de datos, BI y analítica.', 1100, 'Hora', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por hora');
  CALL sp_asignar_caracteristica(v_id, 3, '3');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 31, '100');
  CALL sp_asignar_caracteristica(v_id, 32, '1');
  CALL sp_asignar_caracteristica(v_id, 33, 'Metabase');
  CALL sp_asignar_caracteristica(v_id, 34, 'Mensual');
  CALL sp_registrar_servicio(6, 'SRV-060', 'Migración de base de datos', 'Migración de base de datos. Bases de datos, BI y analítica.', 38000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '20');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 31, '250');
  CALL sp_asignar_caracteristica(v_id, 32, '2');
  CALL sp_asignar_caracteristica(v_id, 33, 'Metabase');
  CALL sp_asignar_caracteristica(v_id, 34, 'Mensual');
  -- ===== Categoría 7: Capacitación =====
  CALL sp_registrar_servicio(7, 'SRV-061', 'Curso de Excel intermedio', 'Curso de Excel intermedio. Cursos y talleres para empresas.', 3800, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '7');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 35, '16');
  CALL sp_asignar_caracteristica(v_id, 36, '20');
  CALL sp_asignar_caracteristica(v_id, 37, 'SI');
  CALL sp_asignar_caracteristica(v_id, 38, 'Intermedio');
  CALL sp_asignar_caracteristica(v_id, 39, 'SI');
  CALL sp_registrar_servicio(7, 'SRV-062', 'Curso de Excel avanzado', 'Curso de Excel avanzado. Cursos y talleres para empresas.', 4800, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '7');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 35, '20');
  CALL sp_asignar_caracteristica(v_id, 36, '20');
  CALL sp_asignar_caracteristica(v_id, 37, 'SI');
  CALL sp_asignar_caracteristica(v_id, 38, 'Avanzado');
  CALL sp_asignar_caracteristica(v_id, 39, 'SI');
  CALL sp_registrar_servicio(7, 'SRV-063', 'Curso de programación en Python', 'Curso de programación en Python. Cursos y talleres para empresas.', 7500, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 35, '40');
  CALL sp_asignar_caracteristica(v_id, 36, '15');
  CALL sp_asignar_caracteristica(v_id, 37, 'SI');
  CALL sp_asignar_caracteristica(v_id, 38, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 39, 'SI');
  CALL sp_registrar_servicio(7, 'SRV-064', 'Curso de bases de datos SQL', 'Curso de bases de datos SQL. Cursos y talleres para empresas.', 6900, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 35, '30');
  CALL sp_asignar_caracteristica(v_id, 36, '15');
  CALL sp_asignar_caracteristica(v_id, 37, 'SI');
  CALL sp_asignar_caracteristica(v_id, 38, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 39, 'SI');
  CALL sp_registrar_servicio(7, 'SRV-065', 'Taller de facturación electrónica CFDI 4.0', 'Taller de facturación electrónica CFDI 4.0. Cursos y talleres para empresas.', 3200, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 35, '8');
  CALL sp_asignar_caracteristica(v_id, 36, '30');
  CALL sp_asignar_caracteristica(v_id, 37, 'SI');
  CALL sp_asignar_caracteristica(v_id, 38, 'Intermedio');
  CALL sp_asignar_caracteristica(v_id, 39, 'NO');
  CALL sp_registrar_servicio(7, 'SRV-066', 'Curso de Power BI', 'Curso de Power BI. Cursos y talleres para empresas.', 6200, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 35, '24');
  CALL sp_asignar_caracteristica(v_id, 36, '15');
  CALL sp_asignar_caracteristica(v_id, 37, 'SI');
  CALL sp_asignar_caracteristica(v_id, 38, 'Intermedio');
  CALL sp_asignar_caracteristica(v_id, 39, 'SI');
  CALL sp_registrar_servicio(7, 'SRV-067', 'Taller de ciberseguridad para usuarios', 'Taller de ciberseguridad para usuarios. Cursos y talleres para empresas.', 2900, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 35, '6');
  CALL sp_asignar_caracteristica(v_id, 36, '40');
  CALL sp_asignar_caracteristica(v_id, 37, 'SI');
  CALL sp_asignar_caracteristica(v_id, 38, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 39, 'NO');
  CALL sp_registrar_servicio(7, 'SRV-068', 'Curso de administración de proyectos', 'Curso de administración de proyectos. Cursos y talleres para empresas.', 8900, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '14');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 35, '40');
  CALL sp_asignar_caracteristica(v_id, 36, '20');
  CALL sp_asignar_caracteristica(v_id, 37, 'SI');
  CALL sp_asignar_caracteristica(v_id, 38, 'Intermedio');
  CALL sp_asignar_caracteristica(v_id, 39, 'SI');
  CALL sp_registrar_servicio(7, 'SRV-069', 'Diplomado en desarrollo web', 'Diplomado en desarrollo web. Cursos y talleres para empresas.', 24000, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '20');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 35, '120');
  CALL sp_asignar_caracteristica(v_id, 36, '25');
  CALL sp_asignar_caracteristica(v_id, 37, 'SI');
  CALL sp_asignar_caracteristica(v_id, 38, 'Avanzado');
  CALL sp_asignar_caracteristica(v_id, 39, 'SI');
  CALL sp_registrar_servicio(7, 'SRV-070', 'Capacitación en uso de ERP', 'Capacitación en uso de ERP. Cursos y talleres para empresas.', 11500, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Presencial');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 35, '20');
  CALL sp_asignar_caracteristica(v_id, 36, '15');
  CALL sp_asignar_caracteristica(v_id, 37, 'SI');
  CALL sp_asignar_caracteristica(v_id, 38, 'Intermedio');
  CALL sp_asignar_caracteristica(v_id, 39, 'SI');
  -- ===== Categoría 8: Consultoría =====
  CALL sp_registrar_servicio(8, 'SRV-071', 'Diagnóstico tecnológico empresarial', 'Diagnóstico tecnológico empresarial. Consultoría de negocio y tecnología.', 28000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '15');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 40, '3');
  CALL sp_asignar_caracteristica(v_id, 41, '2');
  CALL sp_asignar_caracteristica(v_id, 42, 'Dirección general');
  CALL sp_asignar_caracteristica(v_id, 43, '2');
  CALL sp_registrar_servicio(8, 'SRV-072', 'Plan estratégico de TI', 'Plan estratégico de TI. Consultoría de negocio y tecnología.', 65000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '30');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 40, '6');
  CALL sp_asignar_caracteristica(v_id, 41, '4');
  CALL sp_asignar_caracteristica(v_id, 42, 'Dirección de TI');
  CALL sp_asignar_caracteristica(v_id, 43, '3');
  CALL sp_registrar_servicio(8, 'SRV-073', 'Consultoría en transformación digital', 'Consultoría en transformación digital. Consultoría de negocio y tecnología.', 1800, 'Hora', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por hora');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 40, '1');
  CALL sp_asignar_caracteristica(v_id, 41, '1');
  CALL sp_asignar_caracteristica(v_id, 42, 'Operaciones');
  CALL sp_asignar_caracteristica(v_id, 43, '1');
  CALL sp_registrar_servicio(8, 'SRV-074', 'Levantamiento de procesos de negocio', 'Levantamiento de procesos de negocio. Consultoría de negocio y tecnología.', 32000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '20');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 40, '4');
  CALL sp_asignar_caracteristica(v_id, 41, '3');
  CALL sp_asignar_caracteristica(v_id, 42, 'Procesos');
  CALL sp_asignar_caracteristica(v_id, 43, '2');
  CALL sp_registrar_servicio(8, 'SRV-075', 'Selección e implementación de ERP', 'Selección e implementación de ERP. Consultoría de negocio y tecnología.', 120000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '90');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 40, '8');
  CALL sp_asignar_caracteristica(v_id, 41, '10');
  CALL sp_asignar_caracteristica(v_id, 42, 'Operaciones');
  CALL sp_asignar_caracteristica(v_id, 43, '4');
  CALL sp_registrar_servicio(8, 'SRV-076', 'Consultoría en protección de datos personales', 'Consultoría en protección de datos personales. Consultoría de negocio y tecnología.', 38000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '20');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 40, '4');
  CALL sp_asignar_caracteristica(v_id, 41, '3');
  CALL sp_asignar_caracteristica(v_id, 42, 'Jurídico');
  CALL sp_asignar_caracteristica(v_id, 43, '2');
  CALL sp_registrar_servicio(8, 'SRV-077', 'Evaluación de proveedores de TI', 'Evaluación de proveedores de TI. Consultoría de negocio y tecnología.', 18000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 40, '2');
  CALL sp_asignar_caracteristica(v_id, 41, '1');
  CALL sp_asignar_caracteristica(v_id, 42, 'Compras');
  CALL sp_asignar_caracteristica(v_id, 43, '1');
  CALL sp_registrar_servicio(8, 'SRV-078', 'Gestión de proyectos (PMO) externa', 'Gestión de proyectos (PMO) externa. Consultoría de negocio y tecnología.', 42000, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 40, '4');
  CALL sp_asignar_caracteristica(v_id, 41, '4');
  CALL sp_asignar_caracteristica(v_id, 42, 'PMO');
  CALL sp_asignar_caracteristica(v_id, 43, '2');
  CALL sp_registrar_servicio(8, 'SRV-079', 'Consultoría en cumplimiento fiscal digital', 'Consultoría en cumplimiento fiscal digital. Consultoría de negocio y tecnología.', 26000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '15');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 40, '3');
  CALL sp_asignar_caracteristica(v_id, 41, '2');
  CALL sp_asignar_caracteristica(v_id, 42, 'Finanzas');
  CALL sp_asignar_caracteristica(v_id, 43, '2');
  CALL sp_registrar_servicio(8, 'SRV-080', 'Plan de continuidad de negocio', 'Plan de continuidad de negocio. Consultoría de negocio y tecnología.', 54000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Híbrido');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '30');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 40, '5');
  CALL sp_asignar_caracteristica(v_id, 41, '4');
  CALL sp_asignar_caracteristica(v_id, 42, 'Dirección general');
  CALL sp_asignar_caracteristica(v_id, 43, '3');
  -- ===== Categoría 9: Diseño y Marketing Digital =====
  CALL sp_registrar_servicio(9, 'SRV-081', 'Diseño de logotipo', 'Diseño de logotipo. Identidad gráfica y presencia digital.', 6500, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 44, '3');
  CALL sp_asignar_caracteristica(v_id, 45, '3');
  CALL sp_asignar_caracteristica(v_id, 46, '0');
  CALL sp_asignar_caracteristica(v_id, 47, 'SVG');
  CALL sp_registrar_servicio(9, 'SRV-082', 'Manual de identidad corporativa', 'Manual de identidad corporativa. Identidad gráfica y presencia digital.', 18000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '20');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 44, '2');
  CALL sp_asignar_caracteristica(v_id, 45, '3');
  CALL sp_asignar_caracteristica(v_id, 46, '0');
  CALL sp_asignar_caracteristica(v_id, 47, 'PDF');
  CALL sp_registrar_servicio(9, 'SRV-083', 'Gestión de redes sociales', 'Gestión de redes sociales. Identidad gráfica y presencia digital.', 7900, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '3');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 44, '1');
  CALL sp_asignar_caracteristica(v_id, 45, '2');
  CALL sp_asignar_caracteristica(v_id, 46, '3');
  CALL sp_asignar_caracteristica(v_id, 47, 'PNG');
  CALL sp_registrar_servicio(9, 'SRV-084', 'Campaña de publicidad en buscadores', 'Campaña de publicidad en buscadores. Identidad gráfica y presencia digital.', 5500, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '3');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 44, '1');
  CALL sp_asignar_caracteristica(v_id, 45, '2');
  CALL sp_asignar_caracteristica(v_id, 46, '0');
  CALL sp_asignar_caracteristica(v_id, 47, 'PDF');
  CALL sp_registrar_servicio(9, 'SRV-085', 'Posicionamiento web SEO', 'Posicionamiento web SEO. Identidad gráfica y presencia digital.', 6800, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 44, '1');
  CALL sp_asignar_caracteristica(v_id, 45, '2');
  CALL sp_asignar_caracteristica(v_id, 46, '0');
  CALL sp_asignar_caracteristica(v_id, 47, 'PDF');
  CALL sp_registrar_servicio(9, 'SRV-086', 'Producción de video promocional', 'Producción de video promocional. Identidad gráfica y presencia digital.', 22000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '15');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 44, '2');
  CALL sp_asignar_caracteristica(v_id, 45, '2');
  CALL sp_asignar_caracteristica(v_id, 46, '0');
  CALL sp_asignar_caracteristica(v_id, 47, 'MP4');
  CALL sp_registrar_servicio(9, 'SRV-087', 'Diseño de interfaz UX/UI', 'Diseño de interfaz UX/UI. Identidad gráfica y presencia digital.', 26000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '15');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 44, '3');
  CALL sp_asignar_caracteristica(v_id, 45, '3');
  CALL sp_asignar_caracteristica(v_id, 46, '0');
  CALL sp_asignar_caracteristica(v_id, 47, 'Fuentes editables');
  CALL sp_registrar_servicio(9, 'SRV-088', 'Fotografía de producto', 'Fotografía de producto. Identidad gráfica y presencia digital.', 3500, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 44, '1');
  CALL sp_asignar_caracteristica(v_id, 45, '1');
  CALL sp_asignar_caracteristica(v_id, 46, '0');
  CALL sp_asignar_caracteristica(v_id, 47, 'PNG');
  CALL sp_registrar_servicio(9, 'SRV-089', 'Email marketing', 'Email marketing. Identidad gráfica y presencia digital.', 2900, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '3');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 44, '1');
  CALL sp_asignar_caracteristica(v_id, 45, '2');
  CALL sp_asignar_caracteristica(v_id, 46, '0');
  CALL sp_asignar_caracteristica(v_id, 47, 'PDF');
  CALL sp_registrar_servicio(9, 'SRV-090', 'Diseño de material impreso', 'Diseño de material impreso. Identidad gráfica y presencia digital.', 2400, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 44, '2');
  CALL sp_asignar_caracteristica(v_id, 45, '2');
  CALL sp_asignar_caracteristica(v_id, 46, '0');
  CALL sp_asignar_caracteristica(v_id, 47, 'PDF');
  -- ===== Categoría 10: Servicios Administrativos y Contables =====
  CALL sp_registrar_servicio(10, 'SRV-091', 'Contabilidad mensual persona moral', 'Contabilidad mensual persona moral. Contabilidad, nómina y trámites fiscales.', 4800, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 48, '601');
  CALL sp_asignar_caracteristica(v_id, 49, '12');
  CALL sp_asignar_caracteristica(v_id, 50, '0');
  CALL sp_registrar_servicio(10, 'SRV-092', 'Contabilidad mensual persona física', 'Contabilidad mensual persona física. Contabilidad, nómina y trámites fiscales.', 1800, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '5');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 48, '612');
  CALL sp_asignar_caracteristica(v_id, 49, '12');
  CALL sp_asignar_caracteristica(v_id, 50, '0');
  CALL sp_registrar_servicio(10, 'SRV-093', 'Declaración anual', 'Declaración anual. Contabilidad, nómina y trámites fiscales.', 3500, 'Año', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Anual');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 48, '612');
  CALL sp_asignar_caracteristica(v_id, 49, '1');
  CALL sp_asignar_caracteristica(v_id, 50, '0');
  CALL sp_registrar_servicio(10, 'SRV-094', 'Cálculo y timbrado de nómina', 'Cálculo y timbrado de nómina. Contabilidad, nómina y trámites fiscales.', 85, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '2');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 48, '601');
  CALL sp_asignar_caracteristica(v_id, 49, '0');
  CALL sp_asignar_caracteristica(v_id, 50, '1');
  CALL sp_registrar_servicio(10, 'SRV-095', 'Alta en el RFC y trámites SAT', 'Alta en el RFC y trámites SAT. Contabilidad, nómina y trámites fiscales.', 1500, 'Evento', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por evento');
  CALL sp_asignar_caracteristica(v_id, 3, '3');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Básico');
  CALL sp_asignar_caracteristica(v_id, 7, '8x5');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 48, '626');
  CALL sp_asignar_caracteristica(v_id, 49, '0');
  CALL sp_asignar_caracteristica(v_id, 50, '0');
  CALL sp_registrar_servicio(10, 'SRV-096', 'Auditoría contable', 'Auditoría contable. Contabilidad, nómina y trámites fiscales.', 45000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '30');
  CALL sp_asignar_caracteristica(v_id, 4, '90');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 48, '601');
  CALL sp_asignar_caracteristica(v_id, 49, '0');
  CALL sp_asignar_caracteristica(v_id, 50, '0');
  CALL sp_registrar_servicio(10, 'SRV-097', 'Gestión de cuentas por cobrar', 'Gestión de cuentas por cobrar. Contabilidad, nómina y trámites fiscales.', 6500, 'Mes', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Mensual');
  CALL sp_asignar_caracteristica(v_id, 3, '3');
  CALL sp_asignar_caracteristica(v_id, 4, '0');
  CALL sp_asignar_caracteristica(v_id, 5, 'SI');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 48, '601');
  CALL sp_asignar_caracteristica(v_id, 49, '0');
  CALL sp_asignar_caracteristica(v_id, 50, '0');
  CALL sp_registrar_servicio(10, 'SRV-098', 'Elaboración de estados financieros', 'Elaboración de estados financieros. Contabilidad, nómina y trámites fiscales.', 8500, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '10');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Estándar');
  CALL sp_asignar_caracteristica(v_id, 7, '12x6');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 48, '601');
  CALL sp_asignar_caracteristica(v_id, 49, '0');
  CALL sp_asignar_caracteristica(v_id, 50, '0');
  CALL sp_registrar_servicio(10, 'SRV-099', 'Asesoría fiscal por hora', 'Asesoría fiscal por hora. Contabilidad, nómina y trámites fiscales.', 1200, 'Hora', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Por hora');
  CALL sp_asignar_caracteristica(v_id, 3, '1');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 48, '612');
  CALL sp_asignar_caracteristica(v_id, 49, '0');
  CALL sp_asignar_caracteristica(v_id, 50, '0');
  CALL sp_registrar_servicio(10, 'SRV-100', 'Regularización fiscal', 'Regularización fiscal. Contabilidad, nómina y trámites fiscales.', 15000, 'Servicio', v_id);
  CALL sp_asignar_caracteristica(v_id, 1, 'Remoto');
  CALL sp_asignar_caracteristica(v_id, 2, 'Único');
  CALL sp_asignar_caracteristica(v_id, 3, '20');
  CALL sp_asignar_caracteristica(v_id, 4, '30');
  CALL sp_asignar_caracteristica(v_id, 5, 'NO');
  CALL sp_asignar_caracteristica(v_id, 6, 'Premium');
  CALL sp_asignar_caracteristica(v_id, 7, '24x7');
  CALL sp_asignar_caracteristica(v_id, 8, '2027-06-30');
  CALL sp_asignar_caracteristica(v_id, 48, '626');
  CALL sp_asignar_caracteristica(v_id, 49, '6');
  CALL sp_asignar_caracteristica(v_id, 50, '0');
END $$;

-- 20 clientes (15 personas morales y 5 físicas) dados de alta con SP01
DO $$
DECLARE v_id INT;
BEGIN
  CALL sp_registrar_cliente('Comercializadora del Valle de México SA de CV', NULL, 'CMA180315KJ2', 'compras@cvallemx.com', '5551234567', 'Av. Insurgentes Sur 1200, Col. del Valle, CDMX, CP 03100', v_id);
  CALL sp_registrar_cliente('Tecnologías Integrales del Norte SA de CV', NULL, 'TEC200110AB5', 'pagos@tinorte.mx', '8181112233', 'Av. Constitución 450, Centro, Monterrey, NL, CP 64000', v_id);
  CALL sp_registrar_cliente('Farmacias Regionales del Bajío SA de CV', NULL, 'FAR150722PQ8', 'cxp@farbajio.mx', '4771239876', 'Blvd. López Mateos 2300, León, Gto., CP 37000', v_id);
  CALL sp_registrar_cliente('Jorge', 'Gómez Martínez', 'GOMJ850412HT3', 'jorge.gomez@correo.mx', '3331234455', 'Calle Morelos 85, Guadalajara, Jal., CP 44100', v_id);
  CALL sp_registrar_cliente('Andrea', 'López Pérez', 'LOPA900823MN1', 'andrea.lopez@correo.mx', '2224455667', 'Av. Reforma 310, Puebla, Pue., CP 72000', v_id);
  CALL sp_registrar_cliente('Educación Superior Digital AC', NULL, 'EDU100505RT7', 'finanzas@esd.edu.mx', '4433219876', 'Av. Madero 1500, Morelia, Mich., CP 58000', v_id);
  CALL sp_registrar_cliente('Constructora Peninsular SA de CV', NULL, 'CON170918XY4', 'admin@cpeninsular.mx', '9991234567', 'Calle 60 No. 455, Mérida, Yuc., CP 97000', v_id);
  CALL sp_registrar_cliente('Alimentos Selectos de Occidente SA de CV', NULL, 'ALI190601GH9', 'proveedores@aso.mx', '3338889900', 'Av. Vallarta 3200, Zapopan, Jal., CP 45010', v_id);
  CALL sp_registrar_cliente('Transportes Rápidos del Golfo SA de CV', NULL, 'TRA160214LM3', 'facturas@trgolfo.mx', '2299876543', 'Av. Díaz Mirón 900, Veracruz, Ver., CP 91700', v_id);
  CALL sp_registrar_cliente('Hospital San Rafael SC', NULL, 'HOS210330CD6', 'contabilidad@hsr.mx', '4422334455', 'Av. Zaragoza 120, Querétaro, Qro., CP 76000', v_id);
  CALL sp_registrar_cliente('Sofía', 'Ramírez Sánchez', 'RAMS880115KL5', 'sofia.ramirez@correo.mx', '5598765432', 'Calle Durango 25, Roma Nte., CDMX, CP 06700', v_id);
  CALL sp_registrar_cliente('Distribuidora Ferretera Central SA de CV', NULL, 'DIS140808EF2', 'cxp@dfcentral.mx', '7221234567', 'Av. Hidalgo 700, Toluca, Edo. Méx., CP 50000', v_id);
  CALL sp_registrar_cliente('Agroindustrias de Sinaloa SPR de RL', NULL, 'AGR120420ST8', 'admon@agrosin.mx', '6671234567', 'Carretera a Navolato km 5, Culiacán, Sin., CP 80000', v_id);
  CALL sp_registrar_cliente('Hermanos Torres Muebles SA de CV', NULL, 'HER950707QW4', 'ventas@htmuebles.mx', '4491234567', 'Av. Convención 1914 No. 300, Aguascalientes, Ags., CP 20000', v_id);
  CALL sp_registrar_cliente('Daniel', 'Mercado Ruiz', 'MERD920302PL7', 'daniel.mercado@correo.mx', '9931234567', 'Calle Juárez 14, Villahermosa, Tab., CP 86000', v_id);
  CALL sp_registrar_cliente('Servicios Logísticos Integrados SA de CV', NULL, 'SER180912UV1', 'pagos@sli.mx', '5554433221', 'Av. Gustavo Baz 180, Tlalnepantla, Edo. Méx., CP 54060', v_id);
  CALL sp_registrar_cliente('Clínica Dental Sonrisa SC', NULL, 'CLI200225ZX3', 'admin@sonrisa.mx', '5552223344', 'Av. Ejército Nacional 500, Polanco, CDMX, CP 11000', v_id);
  CALL sp_registrar_cliente('Inmobiliaria Horizonte SA de CV', NULL, 'INM110630BN6', 'finanzas@horizonte.mx', '9981234567', 'Blvd. Kukulcán km 9, Cancún, Q. Roo, CP 77500', v_id);
  CALL sp_registrar_cliente('Laura', 'Vega Luna', 'VEGL870918RS2', 'laura.vega@correo.mx', '9511234567', 'Calle Alcalá 210, Oaxaca, Oax., CP 68000', v_id);
  CALL sp_registrar_cliente('Restaurantes La Tradición SA de CV', NULL, 'RES230115TY5', 'cxp@latradicion.mx', '7771234567', 'Av. Morelos Sur 80, Cuernavaca, Mor., CP 62000', v_id);
END $$;

-- Escenarios que recorren el ciclo completo de la factura
DO $$
DECLARE f INT; d INT; p INT; s DECIMAL;
BEGIN
  -- F-000001: pagada en una sola exhibición
  CALL sp_crear_factura(1, 2, f);
  CALL sp_agregar_detalle(f, 1, 1, 0, d);           -- sitio web corporativo
  CALL sp_agregar_detalle(f, 11, 12, 10, d);        -- hosting básico x12 meses, 10 %
  CALL sp_emitir_factura(f, 0);                     -- de contado
  s := fn_saldo_factura(f);
  CALL sp_registrar_pago(f, 2, s, 'SPEI-000123', 3, p);

  -- F-000002: crédito a 30 días con dos abonos (queda saldo)
  CALL sp_crear_factura(2, 2, f);
  CALL sp_agregar_detalle(f, 4, 1, 5, d);           -- sistema web a la medida, 5 %
  CALL sp_agregar_detalle(f, 53, 3, 0, d);          -- tablero de indicadores x3
  CALL sp_emitir_factura(f, 30);
  CALL sp_registrar_pago(f, 2, 50000, 'SPEI-000456', 3, p);
  CALL sp_registrar_pago(f, 3, 30000, 'TC-778812', 3, p);

  -- F-000003: emitida y cancelada
  CALL sp_crear_factura(4, 2, f);
  CALL sp_agregar_detalle(f, 23, 2, 0, d);          -- soporte por evento x2
  CALL sp_emitir_factura(f, 15);
  CALL sp_cancelar_factura(f, 1);

  -- F-000004: capacitación, emitida y pendiente de pago
  CALL sp_crear_factura(6, 2, f);
  CALL sp_agregar_detalle(f, 63, 2, 0, d);          -- curso de Python x2 grupos
  CALL sp_agregar_detalle(f, 65, 1, 15, d);         -- taller CFDI con 15 %
  CALL sp_emitir_factura(f, 30);

  -- F-000005: pagada, luego se cancela el pago (vuelve a EMITIDA)
  CALL sp_crear_factura(11, 2, f);
  CALL sp_agregar_detalle(f, 99, 2, 0, d);          -- asesoría fiscal x2 horas
  CALL sp_emitir_factura(f, 0);
  s := fn_saldo_factura(f);
  CALL sp_registrar_pago(f, 1, s, 'CAJA-0091', 3, p);
  CALL sp_cancelar_pago(p, 1);

  -- F-000006: borrador en edición
  CALL sp_crear_factura(10, 2, f);
  CALL sp_agregar_detalle(f, 41, 1, 0, d);          -- análisis de vulnerabilidades
  CALL sp_agregar_detalle(f, 45, 1, 0, d);          -- monitoreo SOC
  CALL sp_eliminar_detalle(d);                      -- se quita el SOC
END $$;
