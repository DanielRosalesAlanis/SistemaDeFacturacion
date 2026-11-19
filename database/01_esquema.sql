-- =====================================================================
--  SISTEMA DE FACTURACIÓN DE SERVICIOS  ·  Modelo del Equipo 3
--  01_esquema.sql — DDL: esquema, tablas, restricciones e índices
--  SGBD: PostgreSQL 16+ (probado en 16.15 y en Amazon RDS 18.3) · UTF-8
--
--  Orden de carga:  01_esquema.sql → 02_procedimientos.sql → 03_datos.sql
--  Pruebas:         04_pruebas.sql
--  Automatizado:    scripts/cargar_bd.ps1  (o scripts/cargar_bd.sh)
--
--  Tablas 1 a 10:  modelo ER del Equipo 3 (nombres y campos sin cambios)
--  Tablas 11 a 20: extensión para la rúbrica del Proyecto C
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
CREATE INDEX ix_detalle_servicio     ON detalle_factura(id_servicio);
CREATE INDEX ix_pagos_metodo         ON pagos(id_metodo_pago);
CREATE INDEX ix_facturas_empleado    ON facturas(id_empleado);
CREATE INDEX ix_facturas_emision     ON facturas(fecha_emision);      -- cierre fiscal
CREATE INDEX ix_facturas_vencimiento ON facturas(fecha_vencimiento) WHERE estado = 'EMITIDA';  -- antigüedad
CREATE INDEX ix_pagos_fecha          ON pagos(fecha_pago);

-- =====================================================================
--  EXTENSIÓN PARA LA RÚBRICA DEL PROYECTO C (tablas 11 a 20)
--  Las 10 tablas anteriores son las del diagrama del equipo y no cambian.
--  Estas cubren: Usuarios_Roles, Impuestos_Histórico, retenciones,
--  descuentos por cliente y volumen, auditoría de tarifas, reversión
--  contable, cierre fiscal y estructura del comprobante (CFDI).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 11. roles  (permisos del sistema; fn_empleado_puede consulta esta tabla)
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    id_rol       SERIAL        PRIMARY KEY,
    nombre_rol   VARCHAR(30)   NOT NULL UNIQUE
                 CHECK (nombre_rol IN ('Gerente','Facturista','Cajero','Auxiliar')),
    descripcion  VARCHAR(255)  NOT NULL
);

-- ---------------------------------------------------------------------
-- 12. usuarios  (una cuenta por empleado; la contraseña sólo como hash)
--     empleados.puesto es el cargo del diagrama; usuarios.id_rol es el
--     permiso en el sistema (normalmente coinciden).
-- ---------------------------------------------------------------------
CREATE TABLE usuarios (
    id_usuario         SERIAL        PRIMARY KEY,
    id_empleado        INT           NOT NULL UNIQUE REFERENCES empleados(id_empleado),
    id_rol             INT           NOT NULL REFERENCES roles(id_rol),
    nombre_usuario     VARCHAR(50)   NOT NULL UNIQUE,
    contrasena_hash    VARCHAR(255)  NOT NULL,
    estado             BOOLEAN       NOT NULL DEFAULT TRUE,
    intentos_fallidos  INT           NOT NULL DEFAULT 0 CHECK (intentos_fallidos >= 0),
    bloqueado_hasta    TIMESTAMP,
    ultimo_acceso      TIMESTAMP,
    fecha_creacion     TIMESTAMP     NOT NULL DEFAULT now(),
    CONSTRAINT ck_usuarios_hash   CHECK (contrasena_hash ~ '^\$(2[aby]|argon2id)\$'),
    CONSTRAINT ck_usuarios_nombre CHECK (nombre_usuario ~ '^[a-z0-9._-]{3,50}$')
);

-- ---------------------------------------------------------------------
-- 13. impuestos_historico  (tasas de IVA e ISR con vigencia)
-- ---------------------------------------------------------------------
CREATE TABLE impuestos_historico (
    id_impuesto     SERIAL        PRIMARY KEY,
    clave           VARCHAR(3)    NOT NULL CHECK (clave IN ('ISR','IVA')),
    tipo            VARCHAR(10)   NOT NULL CHECK (tipo IN ('TRASLADO','RETENCION')),
    tasa            DECIMAL(7,6)  NOT NULL CHECK (tasa >= 0 AND tasa < 1),
    vigente_desde   DATE          NOT NULL,
    vigente_hasta   DATE,                                           -- NULL = vigente
    descripcion     VARCHAR(255),
    id_empleado     INT           REFERENCES empleados(id_empleado), -- quién la registró
    fecha_registro  TIMESTAMP     NOT NULL DEFAULT now(),
    CONSTRAINT ck_impuestos_vigencia CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde),
    CONSTRAINT uq_impuestos_inicio   UNIQUE (clave, tipo, vigente_desde)
);
-- Sólo una tasa abierta por impuesto y tipo
CREATE UNIQUE INDEX uq_impuesto_abierto ON impuestos_historico(clave, tipo) WHERE vigente_hasta IS NULL;

-- ---------------------------------------------------------------------
-- 14. factura_impuestos  (desglose de traslados y retenciones por factura;
--     la tasa se lee del registro de impuestos_historico)
-- ---------------------------------------------------------------------
CREATE TABLE factura_impuestos (
    id_factura   INT            NOT NULL REFERENCES facturas(id_factura) ON DELETE CASCADE,
    id_impuesto  INT            NOT NULL REFERENCES impuestos_historico(id_impuesto),
    base         DECIMAL(10,2)  NOT NULL CHECK (base >= 0),
    importe      DECIMAL(10,2)  NOT NULL CHECK (importe >= 0),
    PRIMARY KEY (id_factura, id_impuesto)
);
CREATE INDEX ix_factura_impuestos_impuesto ON factura_impuestos(id_impuesto);

-- ---------------------------------------------------------------------
-- 15. condiciones_cliente  (descuento pactado y retenciones de cada cliente)
-- ---------------------------------------------------------------------
CREATE TABLE condiciones_cliente (
    id_cliente     INT           PRIMARY KEY REFERENCES clientes(id_cliente),
    descuento_pct  DECIMAL(5,2)  NOT NULL DEFAULT 0 CHECK (descuento_pct BETWEEN 0 AND 50),
    retiene_isr    BOOLEAN       NOT NULL DEFAULT FALSE,
    retiene_iva    BOOLEAN       NOT NULL DEFAULT FALSE,
    notas          VARCHAR(255)
);

-- ---------------------------------------------------------------------
-- 16. descuentos_volumen  (descuento automático por cantidad del renglón)
-- ---------------------------------------------------------------------
CREATE TABLE descuentos_volumen (
    id_descuento     SERIAL        PRIMARY KEY,
    cantidad_minima  INT           NOT NULL UNIQUE CHECK (cantidad_minima > 1),
    descuento_pct    DECIMAL(5,2)  NOT NULL CHECK (descuento_pct > 0 AND descuento_pct <= 50),
    estado           BOOLEAN       NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 17. auditoria_tarifas  (la llena un trigger en cada cambio de precio_base)
-- ---------------------------------------------------------------------
CREATE TABLE auditoria_tarifas (
    id_auditoria     SERIAL         PRIMARY KEY,
    id_servicio      INT            NOT NULL REFERENCES servicios(id_servicio),
    precio_anterior  DECIMAL(10,2)  NOT NULL,
    precio_nuevo     DECIMAL(10,2)  NOT NULL,
    id_empleado      INT            REFERENCES empleados(id_empleado),  -- NULL = cambio hecho fuera de sp_actualizar_precio
    usuario_bd       VARCHAR(63)    NOT NULL DEFAULT current_user,
    fecha_cambio     TIMESTAMP      NOT NULL DEFAULT now()
);
CREATE INDEX ix_auditoria_servicio ON auditoria_tarifas(id_servicio, fecha_cambio);

-- ---------------------------------------------------------------------
-- 18. movimientos_contables  (pólizas: cada evento genera cargos y abonos
--     balanceados; las cancelaciones generan la póliza inversa)
-- ---------------------------------------------------------------------
CREATE TABLE movimientos_contables (
    id_movimiento  SERIAL         PRIMARY KEY,
    id_factura     INT            NOT NULL REFERENCES facturas(id_factura),
    id_pago        INT            REFERENCES pagos(id_pago),
    evento         VARCHAR(25)    NOT NULL
                   CHECK (evento IN ('EMISION','COBRO','CANCELACION_COBRO','CANCELACION_FACTURA')),
    cuenta         VARCHAR(60)    NOT NULL
                   CHECK (cuenta IN ('101 Caja','102 Bancos','105 Clientes',
                                     '113 Impuestos retenidos por acreditar',
                                     '209 IVA trasladado no cobrado','401 Ingresos por servicios')),
    cargo          DECIMAL(12,2)  NOT NULL DEFAULT 0 CHECK (cargo >= 0),
    abono          DECIMAL(12,2)  NOT NULL DEFAULT 0 CHECK (abono >= 0),
    id_empleado    INT            NOT NULL REFERENCES empleados(id_empleado),
    fecha          TIMESTAMP      NOT NULL DEFAULT now(),
    CONSTRAINT ck_mov_un_lado CHECK ((cargo > 0) <> (abono > 0)),
    CONSTRAINT ck_mov_pago    CHECK ((evento IN ('COBRO','CANCELACION_COBRO')) = (id_pago IS NOT NULL))
);
CREATE INDEX ix_mov_factura ON movimientos_contables(id_factura, evento);
CREATE INDEX ix_mov_pago    ON movimientos_contables(id_pago) WHERE id_pago IS NOT NULL;

-- ---------------------------------------------------------------------
-- 19. cierres_fiscales  (fotografía de cifras al cerrar un día o un mes;
--     desnormalizada a propósito: no debe cambiar aunque cambien los datos)
-- ---------------------------------------------------------------------
CREATE TABLE cierres_fiscales (
    id_cierre            SERIAL         PRIMARY KEY,
    tipo                 VARCHAR(10)    NOT NULL CHECK (tipo IN ('DIARIO','MENSUAL')),
    periodo_inicio       DATE           NOT NULL,
    periodo_fin          DATE           NOT NULL,
    facturas_emitidas    INT            NOT NULL,
    facturas_canceladas  INT            NOT NULL,
    subtotal             DECIMAL(14,2)  NOT NULL,
    iva_trasladado       DECIMAL(14,2)  NOT NULL,
    retenciones          DECIMAL(14,2)  NOT NULL,
    total_facturado      DECIMAL(14,2)  NOT NULL,
    total_cobrado        DECIMAL(14,2)  NOT NULL,
    id_empleado          INT            NOT NULL REFERENCES empleados(id_empleado),
    fecha_cierre         TIMESTAMP      NOT NULL DEFAULT now(),
    CONSTRAINT uq_cierre_periodo UNIQUE (tipo, periodo_inicio),
    CONSTRAINT ck_cierre_periodo CHECK (periodo_fin >= periodo_inicio)
);

-- ---------------------------------------------------------------------
-- 20. comprobantes  (estructura del CFDI 4.0 lista para timbrar)
-- ---------------------------------------------------------------------
CREATE TABLE comprobantes (
    id_factura        INT          PRIMARY KEY REFERENCES facturas(id_factura),
    version_cfdi      VARCHAR(5)   NOT NULL DEFAULT '4.0',
    contenido         JSONB        NOT NULL,
    estado            VARCHAR(20)  NOT NULL DEFAULT 'PENDIENTE_TIMBRADO'
                      CHECK (estado IN ('PENDIENTE_TIMBRADO','TIMBRADO','CANCELADO')),
    uuid_fiscal       UUID         UNIQUE,      -- lo asigna el PAC al timbrar (fuera de alcance)
    fecha_generacion  TIMESTAMP    NOT NULL DEFAULT now()
);

