-- =====================================================================
--  02_procedimientos.sql — PROCEDIMIENTOS ALMACENADOS, FUNCIONES Y VISTAS
--  Requiere 01_esquema.sql. Se puede volver a ejecutar sin perder datos
--  (CREATE OR REPLACE).
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

