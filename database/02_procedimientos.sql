-- =====================================================================
--  02_procedimientos.sql — PROCEDIMIENTOS ALMACENADOS, FUNCIONES Y VISTAS
--  Requiere 01_esquema.sql. Se puede volver a ejecutar sin perder datos
--  (CREATE OR REPLACE).
--  Las reglas de negocio (RN-xx) viven aquí. La aplicación sólo llama
--  CALL facturacion.sp_xxx(...). Si una regla falla se lanza EXCEPTION
--  con su código y toda la operación se revierte.
-- =====================================================================
SET search_path TO facturacion;

-- Fechas: los TIMESTAMP se guardan en la zona de la sesión (UTC en RDS).
-- Los cortes fiscales se hacen por día calendario del centro de México.
CREATE OR REPLACE FUNCTION fn_fecha_local(p_ts TIMESTAMP) RETURNS DATE
LANGUAGE sql STABLE AS $$
    SELECT ((p_ts AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'America/Mexico_City')::DATE
$$;

CREATE OR REPLACE FUNCTION fn_hoy() RETURNS DATE
LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'America/Mexico_City')::DATE $$;

-- RN-27  Tasa vigente de un impuesto a una fecha (tabla impuestos_historico)
CREATE OR REPLACE FUNCTION fn_tasa_impuesto(p_clave TEXT, p_tipo TEXT, p_fecha DATE DEFAULT NULL)
RETURNS DECIMAL
LANGUAGE sql STABLE
SET search_path = facturacion, pg_catalog AS $$
    SELECT tasa FROM impuestos_historico
     WHERE clave = p_clave AND tipo = p_tipo
       AND vigente_desde <= coalesce(p_fecha, fn_hoy())
       AND (vigente_hasta IS NULL OR vigente_hasta >= coalesce(p_fecha, fn_hoy()))
     ORDER BY vigente_desde DESC
     LIMIT 1
$$;

-- IVA trasladado vigente hoy (se conserva el nombre original para las vistas)
CREATE OR REPLACE FUNCTION fn_tasa_iva() RETURNS DECIMAL
LANGUAGE sql STABLE
SET search_path = facturacion, pg_catalog AS $$ SELECT fn_tasa_impuesto('IVA', 'TRASLADO') $$;

-- Saldo de una factura = total − pagos APLICADOS (no se guarda: se calcula)
CREATE OR REPLACE FUNCTION fn_saldo_factura(p_id_factura INT) RETURNS DECIMAL
LANGUAGE sql STABLE
SET search_path = facturacion, pg_catalog AS $$
    SELECT f.total - coalesce((SELECT sum(p.monto) FROM pagos p
                                WHERE p.id_factura = f.id_factura AND p.estado = 'APLICADO'), 0)
      FROM facturas f WHERE f.id_factura = p_id_factura
$$;

-- RN-32  Valida que el empleado esté activo, tenga una cuenta de usuario
--        activa y que el rol de esa cuenta sea uno de los indicados
CREATE OR REPLACE FUNCTION fn_empleado_puede(p_id_empleado INT, p_roles TEXT[]) RETURNS BOOLEAN
LANGUAGE sql STABLE
SET search_path = facturacion, pg_catalog AS $$
    SELECT EXISTS (SELECT 1 FROM empleados e
                     JOIN usuarios u USING (id_empleado)
                     JOIN roles r    USING (id_rol)
                    WHERE e.id_empleado = p_id_empleado AND e.estado AND u.estado
                      AND r.nombre_rol = ANY (p_roles))
$$;

-- RN-26  Descuento automático: el mayor entre el pactado con el cliente y
--        el de volumen que corresponde a la cantidad del renglón
CREATE OR REPLACE FUNCTION fn_descuento_automatico(p_id_cliente INT, p_cantidad INT) RETURNS DECIMAL
LANGUAGE sql STABLE
SET search_path = facturacion, pg_catalog AS $$
    SELECT greatest(
        coalesce((SELECT descuento_pct FROM condiciones_cliente WHERE id_cliente = p_id_cliente), 0),
        coalesce((SELECT descuento_pct FROM descuentos_volumen
                   WHERE estado AND cantidad_minima <= p_cantidad
                   ORDER BY cantidad_minima DESC LIMIT 1), 0))
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
--   RN-25 Sólo Gerente o Facturista cambian tarifas; cada cambio queda en
--         auditoria_tarifas (trigger tg_auditar_tarifa) con el empleado
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
    IF NOT fn_empleado_puede(p_id_empleado, ARRAY['Gerente','Facturista']) THEN
        RAISE EXCEPTION 'RN-25: El empleado % no puede cambiar tarifas', p_id_empleado;
    END IF;
    IF abs(p_precio - v_actual) / v_actual > 0.30
       AND NOT fn_empleado_puede(p_id_empleado, ARRAY['Gerente']) THEN
        RAISE EXCEPTION 'RN-08: Variación de % %% requiere autorización de un Gerente',
              round(abs(p_precio - v_actual) / v_actual * 100, 1);
    END IF;
    -- El trigger de auditoría lee quién hizo el cambio de esta variable de la transacción
    PERFORM set_config('facturacion.id_empleado', p_id_empleado::TEXT, TRUE);
    UPDATE servicios SET precio_base = round(p_precio,2) WHERE id_servicio = p_id_servicio;
    PERFORM set_config('facturacion.id_empleado', '', TRUE);
END $$;

-- RN-25  Trigger: registra TODO cambio de precio_base, incluso un UPDATE
--        hecho fuera del SP (en ese caso id_empleado queda NULL)
CREATE OR REPLACE FUNCTION fn_tg_auditar_tarifa() RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
BEGIN
    INSERT INTO auditoria_tarifas(id_servicio, precio_anterior, precio_nuevo, id_empleado)
    VALUES (NEW.id_servicio, OLD.precio_base, NEW.precio_base,
            nullif(current_setting('facturacion.id_empleado', TRUE), '')::INT);
    RETURN NEW;
END $$;

CREATE OR REPLACE TRIGGER tg_auditar_tarifa
AFTER UPDATE OF precio_base ON servicios
FOR EACH ROW WHEN (OLD.precio_base IS DISTINCT FROM NEW.precio_base)
EXECUTE FUNCTION fn_tg_auditar_tarifa();

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
-- SP07  Recalcular totales, IVA y retenciones
--   RN-15 subtotal = Σ detalle.subtotal; impuestos = IVA trasladado;
--         total = subtotal + traslados − retenciones
--   RN-27 Las tasas son las vigentes a la fecha de emisión (o a hoy si es
--         borrador) en impuestos_historico. Las retenciones de ISR e IVA
--         se aplican si condiciones_cliente lo indica. El desglose queda
--         en factura_impuestos.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_recalcular_totales(p_id_factura INT)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    v_cli   INT;
    v_fecha DATE;
    v_sub   DECIMAL;
    v_tras  DECIMAL;
    v_ret   DECIMAL;
    v_risr  BOOLEAN;
    v_riva  BOOLEAN;
BEGIN
    SELECT id_cliente, coalesce(fn_fecha_local(fecha_emision), fn_hoy())
      INTO v_cli, v_fecha FROM facturas WHERE id_factura = p_id_factura;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La factura % no existe', p_id_factura;
    END IF;
    SELECT coalesce(sum(subtotal),0) INTO v_sub FROM detalle_factura WHERE id_factura = p_id_factura;
    SELECT retiene_isr, retiene_iva INTO v_risr, v_riva FROM condiciones_cliente WHERE id_cliente = v_cli;

    DELETE FROM factura_impuestos WHERE id_factura = p_id_factura;
    IF v_sub > 0 THEN
        INSERT INTO factura_impuestos(id_factura, id_impuesto, base, importe)
        SELECT p_id_factura, i.id_impuesto, v_sub, round(v_sub * i.tasa, 2)
          FROM impuestos_historico i
         WHERE i.vigente_desde <= v_fecha AND (i.vigente_hasta IS NULL OR i.vigente_hasta >= v_fecha)
           AND (   (i.clave = 'IVA' AND i.tipo = 'TRASLADO')
                OR (i.clave = 'IVA' AND i.tipo = 'RETENCION' AND coalesce(v_riva, FALSE))
                OR (i.clave = 'ISR' AND i.tipo = 'RETENCION' AND coalesce(v_risr, FALSE)));
        IF fn_tasa_impuesto('IVA', 'TRASLADO', v_fecha) IS NULL THEN
            RAISE EXCEPTION 'RN-27: No hay tasa de IVA vigente al %', v_fecha;
        END IF;
    END IF;

    SELECT coalesce(sum(fi.importe) FILTER (WHERE i.tipo = 'TRASLADO'), 0),
           coalesce(sum(fi.importe) FILTER (WHERE i.tipo = 'RETENCION'), 0)
      INTO v_tras, v_ret
      FROM factura_impuestos fi JOIN impuestos_historico i USING (id_impuesto)
     WHERE fi.id_factura = p_id_factura;

    UPDATE facturas
       SET subtotal  = v_sub,
           impuestos = v_tras,
           total     = v_sub + v_tras - v_ret
     WHERE id_factura = p_id_factura;
END $$;

-- ---------------------------------------------------------------------
-- SP08  Agregar concepto a la factura
--   RN-12 Sólo facturas en BORRADOR se modifican
--   RN-13 Servicio activo, cantidad > 0, precio tomado del catálogo
--   RN-14 Descuento capturado entre 0 y 50 % del importe del renglón
--   RN-26 Se aplica el mayor entre el capturado, el pactado con el
--         cliente y el de volumen (fn_descuento_automatico)
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
    v_cliente INT;
    v_precio  DECIMAL;
    v_pct     DECIMAL;
    v_desc    DECIMAL;
BEGIN
    SELECT estado, id_cliente INTO v_estado, v_cliente FROM facturas WHERE id_factura = p_id_factura FOR UPDATE;
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

    v_pct  := greatest(coalesce(p_descuento_pct,0), fn_descuento_automatico(v_cliente, p_cantidad));
    v_desc := round(p_cantidad * v_precio * v_pct / 100, 2);
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

    CALL sp_contabilizar('EMISION', p_id_factura, NULL, v_f.id_empleado);   -- RN-28
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

    CALL sp_contabilizar('COBRO', p_id_factura, p_id_pago, p_id_empleado);   -- RN-28

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
    CALL sp_contabilizar('CANCELACION_COBRO', v_id_factura, p_id_pago, p_id_empleado);   -- RN-28
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
    CALL sp_contabilizar('CANCELACION_FACTURA', p_id_factura, NULL, p_id_empleado);   -- RN-28
    UPDATE comprobantes SET estado = 'CANCELADO' WHERE id_factura = p_id_factura;
END $$;

-- =====================================================================
--  VISTAS DE REPORTE
-- =====================================================================

-- V1 Catálogo: servicio, categoría y número de características
CREATE OR REPLACE VIEW vw_catalogo_servicios AS
SELECT s.codigo_servicio, s.nombre_servicio, c.nombre_categoria, s.precio_base,
       s.unidad_medida, s.estado, count(sc.id_caracteristica) AS num_caracteristicas,
       s.id_servicio, s.id_categoria, s.descripcion
  FROM servicios s
  JOIN categorias_servicio c USING (id_categoria)
  LEFT JOIN servicio_caracteristicas sc USING (id_servicio)
 GROUP BY s.id_servicio, c.nombre_categoria
 ORDER BY s.codigo_servicio;

-- V2 Ficha técnica de cada servicio
CREATE OR REPLACE VIEW vw_ficha_servicio AS
SELECT s.codigo_servicio, s.nombre_servicio, k.nombre_caracteristica, sc.valor, k.unidad,
       s.id_servicio, k.id_caracteristica, k.tipo_dato
  FROM servicio_caracteristicas sc
  JOIN servicios s       USING (id_servicio)
  JOIN caracteristicas k USING (id_caracteristica)
 ORDER BY s.codigo_servicio, k.id_caracteristica;

-- V3 Facturas con cliente, empleado, saldo y días de atraso
CREATE OR REPLACE VIEW vw_facturas AS
SELECT f.id_factura, f.folio,
       trim(c.nombre || ' ' || coalesce(c.apellido,'')) AS cliente,
       c.identificacion_fiscal AS rfc, e.nombre AS empleado,
       f.fecha_emision, f.fecha_vencimiento, f.subtotal, f.impuestos,
       f.subtotal + f.impuestos - f.total AS retenciones, f.total,
       CASE WHEN f.estado = 'CANCELADA' THEN 0 ELSE fn_saldo_factura(f.id_factura) END AS saldo,
       CASE WHEN f.estado = 'EMITIDA' AND f.fecha_vencimiento < now()
            THEN extract(day FROM now() - f.fecha_vencimiento)::INT ELSE 0 END AS dias_atraso,
       f.estado, f.id_cliente, f.id_empleado
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
--  EXTENSIÓN PARA LA RÚBRICA DEL PROYECTO C
--  SP14 a SP21, funciones y vistas para los propósitos que faltaban:
--  retenciones (2), descuentos por cliente o volumen (3), reversión
--  contable (4), cierre fiscal (5), antigüedad de saldos (7),
--  comprobante (8), asignación masiva (9), auditoría de tarifas (10)
--  y usuarios con roles.
-- =====================================================================

-- ---------------------------------------------------------------------
-- SP14  Registrar una nueva tasa de impuesto (Impuestos_Histórico)
--   RN-27 Sólo un Gerente; tasa entre 0 y 1; la nueva vigencia empieza
--         después de la tasa abierta, que se cierra un día antes
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_tasa_impuesto(
    p_clave          VARCHAR,
    p_tipo           VARCHAR,
    p_tasa           DECIMAL,
    p_vigente_desde  DATE,
    p_id_empleado    INT,
    INOUT p_id_impuesto INT DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE v_abierta impuestos_historico%ROWTYPE;
BEGIN
    IF NOT fn_empleado_puede(p_id_empleado, ARRAY['Gerente']) THEN
        RAISE EXCEPTION 'RN-27: Sólo un Gerente registra tasas de impuestos';
    END IF;
    IF upper(p_clave) NOT IN ('IVA','ISR') OR upper(p_tipo) NOT IN ('TRASLADO','RETENCION') THEN
        RAISE EXCEPTION 'RN-27: Impuesto %/% no válido', p_clave, p_tipo;
    END IF;
    IF p_tasa IS NULL OR p_tasa < 0 OR p_tasa >= 1 THEN
        RAISE EXCEPTION 'RN-27: La tasa debe expresarse como fracción entre 0 y 1 (16 %% = 0.16)';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('impuestos_historico'));
    SELECT * INTO v_abierta FROM impuestos_historico
     WHERE clave = upper(p_clave) AND tipo = upper(p_tipo) AND vigente_hasta IS NULL FOR UPDATE;
    IF FOUND THEN
        IF p_vigente_desde IS NULL OR p_vigente_desde <= v_abierta.vigente_desde THEN
            RAISE EXCEPTION 'RN-27: La nueva vigencia debe empezar después del % (no se reescribe el historial)',
                  v_abierta.vigente_desde;
        END IF;
        UPDATE impuestos_historico SET vigente_hasta = p_vigente_desde - 1
         WHERE id_impuesto = v_abierta.id_impuesto;
    END IF;

    INSERT INTO impuestos_historico(clave, tipo, tasa, vigente_desde, descripcion, id_empleado)
    VALUES (upper(p_clave), upper(p_tipo), p_tasa, p_vigente_desde,
            upper(p_tipo) || ' de ' || upper(p_clave) || ' al ' || round(p_tasa * 100, 4) || ' %', p_id_empleado)
    RETURNING id_impuesto INTO p_id_impuesto;
END $$;

-- ---------------------------------------------------------------------
-- SP15  Aplicar reglas de descuento a una factura en borrador
--   RN-12 Sólo en BORRADOR
--   RN-26 Cada renglón queda con el mayor entre su descuento actual y el
--         automático (cliente o volumen). Útil cuando cambian las reglas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_aplicar_descuentos(
    p_id_factura INT,
    INOUT p_renglones INT DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    v_estado  VARCHAR;
    v_cliente INT;
BEGIN
    SELECT estado, id_cliente INTO v_estado, v_cliente FROM facturas WHERE id_factura = p_id_factura FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La factura % no existe', p_id_factura;
    ELSIF v_estado <> 'BORRADOR' THEN
        RAISE EXCEPTION 'RN-12: La factura está %; sólo se modifica en BORRADOR', v_estado;
    END IF;

    WITH nuevo AS (
        SELECT d.id_detalle,
               round(d.cantidad * d.precio_unitario * fn_descuento_automatico(v_cliente, d.cantidad) / 100, 2) AS desc_auto
          FROM detalle_factura d
         WHERE d.id_factura = p_id_factura)
    UPDATE detalle_factura d
       SET descuento = n.desc_auto,
           subtotal  = round(d.cantidad * d.precio_unitario, 2) - n.desc_auto
      FROM nuevo n
     WHERE d.id_detalle = n.id_detalle AND n.desc_auto > d.descuento;
    GET DIAGNOSTICS p_renglones = ROW_COUNT;

    CALL sp_recalcular_totales(p_id_factura);
END $$;

-- ---------------------------------------------------------------------
-- SP16  Póliza contable de un evento (la llaman SP10, SP11, SP12 y SP13)
--   RN-28 Cada evento genera cargos y abonos que suman lo mismo.
--         Emisión:  Clientes (+ impuestos retenidos) = Ingresos + IVA
--         Cobro:    Caja o Bancos = Clientes
--         Cancelación de factura o de cobro: póliza inversa de la original
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_contabilizar(
    p_evento      VARCHAR,
    p_id_factura  INT,
    p_id_pago     INT,
    p_id_empleado INT)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    v_f      facturas%ROWTYPE;
    v_ret    DECIMAL;
    v_monto  DECIMAL;
    v_cuenta VARCHAR;
    v_dif    DECIMAL;
BEGIN
    SELECT * INTO v_f FROM facturas WHERE id_factura = p_id_factura;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La factura % no existe', p_id_factura;
    END IF;

    IF p_evento = 'EMISION' THEN
        v_ret := v_f.subtotal + v_f.impuestos - v_f.total;
        INSERT INTO movimientos_contables(id_factura, evento, cuenta, cargo, abono, id_empleado)
        SELECT p_id_factura, 'EMISION', m.cuenta, m.cargo, m.abono, p_id_empleado
          FROM (VALUES ('105 Clientes',                          v_f.total, 0::DECIMAL),
                       ('113 Impuestos retenidos por acreditar', v_ret,     0),
                       ('401 Ingresos por servicios',            0,         v_f.subtotal),
                       ('209 IVA trasladado no cobrado',         0,         v_f.impuestos)
               ) AS m(cuenta, cargo, abono)
         WHERE m.cargo > 0 OR m.abono > 0;

    ELSIF p_evento = 'COBRO' THEN
        SELECT p.monto, CASE WHEN m.nombre_metodo = 'Efectivo' THEN '101 Caja' ELSE '102 Bancos' END
          INTO v_monto, v_cuenta
          FROM pagos p JOIN metodos_pago m USING (id_metodo_pago)
         WHERE p.id_pago = p_id_pago AND p.id_factura = p_id_factura;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El pago % no corresponde a la factura %', p_id_pago, p_id_factura;
        END IF;
        INSERT INTO movimientos_contables(id_factura, id_pago, evento, cuenta, cargo, abono, id_empleado)
        VALUES (p_id_factura, p_id_pago, 'COBRO', v_cuenta,       v_monto, 0,       p_id_empleado),
               (p_id_factura, p_id_pago, 'COBRO', '105 Clientes', 0,       v_monto, p_id_empleado);

    ELSIF p_evento IN ('CANCELACION_FACTURA', 'CANCELACION_COBRO') THEN
        INSERT INTO movimientos_contables(id_factura, id_pago, evento, cuenta, cargo, abono, id_empleado)
        SELECT id_factura, id_pago, p_evento, cuenta, abono, cargo, p_id_empleado   -- cargo ↔ abono
          FROM movimientos_contables
         WHERE id_factura = p_id_factura
           AND ((p_evento = 'CANCELACION_FACTURA' AND evento = 'EMISION')
             OR (p_evento = 'CANCELACION_COBRO'   AND evento = 'COBRO' AND id_pago = p_id_pago));
        IF NOT FOUND THEN
            RAISE EXCEPTION 'RN-28: No hay póliza original que revertir para %', p_evento;
        END IF;
    ELSE
        RAISE EXCEPTION 'RN-28: Evento contable % no válido', p_evento;
    END IF;

    SELECT sum(cargo) - sum(abono) INTO v_dif
      FROM movimientos_contables
     WHERE id_factura = p_id_factura AND evento = p_evento
       AND id_pago IS NOT DISTINCT FROM p_id_pago;
    IF v_dif <> 0 THEN
        RAISE EXCEPTION 'RN-28: Póliza % de la factura % desbalanceada por %', p_evento, p_id_factura, v_dif;
    END IF;
END $$;

-- ---------------------------------------------------------------------
-- SP17  Cierre y consolidado fiscal diario o mensual
--   RN-29 Sólo un Gerente; el periodo no puede ser futuro ni cerrarse
--         dos veces. Guarda una fotografía de las cifras del periodo
--         (día calendario del centro de México).
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cierre_fiscal(
    p_tipo        VARCHAR,
    p_fecha       DATE,
    p_id_empleado INT,
    INOUT p_id_cierre INT DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    v_tipo VARCHAR := upper(p_tipo);
    v_ini  DATE;
    v_fin  DATE;
BEGIN
    IF NOT fn_empleado_puede(p_id_empleado, ARRAY['Gerente']) THEN
        RAISE EXCEPTION 'RN-29: Sólo un Gerente puede hacer el cierre fiscal';
    END IF;
    IF v_tipo = 'DIARIO' THEN
        v_ini := p_fecha;  v_fin := p_fecha;
    ELSIF v_tipo = 'MENSUAL' THEN
        v_ini := date_trunc('month', p_fecha)::DATE;
        v_fin := (v_ini + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
    ELSE
        RAISE EXCEPTION 'RN-29: Tipo de cierre % no válido (DIARIO o MENSUAL)', p_tipo;
    END IF;
    IF p_fecha IS NULL OR v_ini > fn_hoy() THEN
        RAISE EXCEPTION 'RN-29: No se puede cerrar un periodo futuro';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('cierre_fiscal'));
    IF EXISTS (SELECT 1 FROM cierres_fiscales WHERE tipo = v_tipo AND periodo_inicio = v_ini) THEN
        RAISE EXCEPTION 'RN-29: El periodo % % ya está cerrado', v_tipo, v_ini;
    END IF;

    INSERT INTO cierres_fiscales(tipo, periodo_inicio, periodo_fin, facturas_emitidas, facturas_canceladas,
                                 subtotal, iva_trasladado, retenciones, total_facturado, total_cobrado, id_empleado)
    SELECT v_tipo, v_ini, v_fin,
           count(*),
           count(*) FILTER (WHERE f.estado = 'CANCELADA'),
           coalesce(sum(f.subtotal)  FILTER (WHERE f.estado <> 'CANCELADA'), 0),
           coalesce(sum(f.impuestos) FILTER (WHERE f.estado <> 'CANCELADA'), 0),
           coalesce(sum(f.subtotal + f.impuestos - f.total) FILTER (WHERE f.estado <> 'CANCELADA'), 0),
           coalesce(sum(f.total)     FILTER (WHERE f.estado <> 'CANCELADA'), 0),
           (SELECT coalesce(sum(p.monto), 0) FROM pagos p
             WHERE p.estado = 'APLICADO' AND fn_fecha_local(p.fecha_pago) BETWEEN v_ini AND v_fin),
           p_id_empleado
      FROM facturas f
     WHERE f.fecha_emision IS NOT NULL
       AND fn_fecha_local(f.fecha_emision) BETWEEN v_ini AND v_fin
    RETURNING id_cierre INTO p_id_cierre;
END $$;

-- ---------------------------------------------------------------------
-- Datos fiscales del emisor (ficticios, para el proyecto escolar).
-- Se cambian aquí cuando se tenga un RFC real y certificado de sello.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_datos_emisor() RETURNS JSONB
LANGUAGE sql IMMUTABLE AS $$
    SELECT jsonb_build_object('Rfc', 'SFE260101AB1',
                              'Nombre', 'SERVICIOS DE FACTURACION EQUIPO TRES',
                              'RegimenFiscal', '601',
                              'CodigoPostal', '62760')
$$;

-- ---------------------------------------------------------------------
-- SP18  Generar la estructura del comprobante (CFDI 4.0) para timbrado
--   RN-30 Sólo de facturas EMITIDA o PAGADA; el cliente debe tener código
--         postal en su domicilio; un comprobante ya TIMBRADO no se regenera.
--   El timbrado con un PAC queda fuera del alcance del proyecto.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_generar_comprobante(
    p_id_factura INT,
    INOUT p_comprobante JSONB DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    v_f        facturas%ROWTYPE;
    v_c        clientes%ROWTYPE;
    v_cp       TEXT;
    v_metodo   TEXT;
    v_forma    TEXT;
    v_emisor   JSONB := fn_datos_emisor();
    v_estado   VARCHAR;
BEGIN
    SELECT * INTO v_f FROM facturas WHERE id_factura = p_id_factura;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La factura % no existe', p_id_factura;
    ELSIF v_f.estado NOT IN ('EMITIDA','PAGADA') THEN
        RAISE EXCEPTION 'RN-30: Sólo se genera el comprobante de una factura EMITIDA o PAGADA (está %)', v_f.estado;
    END IF;
    SELECT estado INTO v_estado FROM comprobantes WHERE id_factura = p_id_factura;
    IF v_estado = 'TIMBRADO' THEN
        RAISE EXCEPTION 'RN-30: El comprobante de la factura % ya está timbrado', v_f.folio;
    END IF;
    SELECT * INTO v_c FROM clientes WHERE id_cliente = v_f.id_cliente;
    v_cp := substring(v_c.direccion FROM 'CP ([0-9]{5})');
    IF v_cp IS NULL THEN
        RAISE EXCEPTION 'RN-30: El domicilio del cliente % no tiene código postal (CP #####)', v_c.identificacion_fiscal;
    END IF;

    -- PUE: de contado (vence el mismo día). PPD: a crédito, forma "99 Por definir".
    v_metodo := CASE WHEN v_f.fecha_vencimiento = v_f.fecha_emision THEN 'PUE' ELSE 'PPD' END;
    SELECT CASE m.nombre_metodo WHEN 'Efectivo' THEN '01' WHEN 'Cheque nominativo' THEN '02'
                                WHEN 'Transferencia SPEI' THEN '03' WHEN 'Tarjeta de crédito' THEN '04'
                                WHEN 'Tarjeta de débito' THEN '28' ELSE '99' END
      INTO v_forma
      FROM pagos p JOIN metodos_pago m USING (id_metodo_pago)
     WHERE p.id_factura = p_id_factura AND p.estado = 'APLICADO'
     ORDER BY p.fecha_pago LIMIT 1;
    IF v_metodo = 'PPD' OR v_forma IS NULL THEN
        v_forma := '99';
    END IF;

    p_comprobante := jsonb_build_object(
        'Version', '4.0',
        'Serie', 'F',
        'Folio', substring(v_f.folio FROM 3),
        'Fecha', to_char((v_f.fecha_emision AT TIME ZONE current_setting('TimeZone')) AT TIME ZONE 'America/Mexico_City',
                         'YYYY-MM-DD"T"HH24:MI:SS'),
        'FormaPago', v_forma,
        'MetodoPago', v_metodo,
        'Moneda', 'MXN',
        'TipoDeComprobante', 'I',
        'Exportacion', '01',
        'LugarExpedicion', v_emisor->>'CodigoPostal',
        'SubTotal', (SELECT sum(round(cantidad * precio_unitario, 2)) FROM detalle_factura WHERE id_factura = p_id_factura),
        'Descuento', (SELECT sum(descuento) FROM detalle_factura WHERE id_factura = p_id_factura),
        'Total', v_f.total,
        'Emisor', v_emisor - 'CodigoPostal',
        'Receptor', jsonb_build_object(
            'Rfc', v_c.identificacion_fiscal,
            'Nombre', upper(trim(v_c.nombre || ' ' || coalesce(v_c.apellido, ''))),
            'DomicilioFiscalReceptor', v_cp,
            'RegimenFiscalReceptor', CASE WHEN length(v_c.identificacion_fiscal) = 12 THEN '601' ELSE '612' END,
            'UsoCFDI', 'G03'),
        'Conceptos', (
            SELECT jsonb_agg(jsonb_build_object(
                       'ClaveProdServ', '01010101',
                       'NoIdentificacion', s.codigo_servicio,
                       'Cantidad', d.cantidad,
                       'ClaveUnidad', CASE s.unidad_medida WHEN 'Hora' THEN 'HUR' WHEN 'Mes' THEN 'MON'
                                                           WHEN 'Año' THEN 'ANN' ELSE 'E48' END,
                       'Unidad', s.unidad_medida,
                       'Descripcion', s.nombre_servicio,
                       'ValorUnitario', d.precio_unitario,
                       'Importe', round(d.cantidad * d.precio_unitario, 2),
                       'Descuento', d.descuento,
                       'ObjetoImp', '02',
                       'Impuestos', (
                           SELECT jsonb_object_agg(grupo, lista) FROM (
                               SELECT CASE i.tipo WHEN 'TRASLADO' THEN 'Traslados' ELSE 'Retenciones' END AS grupo,
                                      jsonb_agg(jsonb_build_object(
                                          'Base', d.subtotal,
                                          'Impuesto', CASE i.clave WHEN 'ISR' THEN '001' ELSE '002' END,
                                          'TipoFactor', 'Tasa',
                                          'TasaOCuota', to_char(i.tasa, 'FM0.000000'),
                                          'Importe', round(d.subtotal * i.tasa, 2))) AS lista
                                 FROM factura_impuestos fi JOIN impuestos_historico i USING (id_impuesto)
                                WHERE fi.id_factura = p_id_factura
                                GROUP BY i.tipo) g))
                   ORDER BY d.id_detalle)
              FROM detalle_factura d JOIN servicios s USING (id_servicio)
             WHERE d.id_factura = p_id_factura),
        'Impuestos', (
            SELECT jsonb_build_object(
                       'TotalImpuestosTrasladados', coalesce(sum(fi.importe) FILTER (WHERE i.tipo = 'TRASLADO'), 0),
                       'TotalImpuestosRetenidos',   coalesce(sum(fi.importe) FILTER (WHERE i.tipo = 'RETENCION'), 0),
                       'Detalle', jsonb_agg(jsonb_build_object(
                           'Tipo', i.tipo,
                           'Impuesto', CASE i.clave WHEN 'ISR' THEN '001' ELSE '002' END,
                           'Base', fi.base,
                           'TasaOCuota', to_char(i.tasa, 'FM0.000000'),
                           'Importe', fi.importe) ORDER BY i.tipo DESC, i.clave))
              FROM factura_impuestos fi JOIN impuestos_historico i USING (id_impuesto)
             WHERE fi.id_factura = p_id_factura));

    INSERT INTO comprobantes(id_factura, contenido)
    VALUES (p_id_factura, p_comprobante)
    ON CONFLICT (id_factura) DO UPDATE
        SET contenido = EXCLUDED.contenido, estado = 'PENDIENTE_TIMBRADO', fecha_generacion = now();
END $$;

-- ---------------------------------------------------------------------
-- SP19  Asignación masiva de características
--   RN-31 Recibe un arreglo JSON; cada elemento trae id_caracteristica,
--         valor y uno de: id_servicio, codigo_servicio o id_categoria
--         (todos los servicios activos de la categoría). Todo o nada:
--         si un valor viola RN-06 no se asigna ninguno.
--   Ejemplo: '[{"id_categoria": 2, "id_caracteristica": 18, "valor": "99.95"},
--             {"codigo_servicio": "SRV-001", "id_caracteristica": 3, "valor": "25"}]'
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_asignar_caracteristicas_masivo(
    p_asignaciones JSONB,
    INOUT p_total INT DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    e JSONB;
    v_servicio INT;
    v_n INT;
BEGIN
    IF jsonb_typeof(p_asignaciones) IS DISTINCT FROM 'array' OR jsonb_array_length(p_asignaciones) = 0 THEN
        RAISE EXCEPTION 'RN-31: Se espera un arreglo JSON con al menos una asignación';
    END IF;
    p_total := 0;
    FOR e IN SELECT value FROM jsonb_array_elements(p_asignaciones) LOOP
        IF NOT (e ? 'id_caracteristica' AND e ? 'valor')
           OR (e ? 'id_servicio')::INT + (e ? 'codigo_servicio')::INT + (e ? 'id_categoria')::INT <> 1 THEN
            RAISE EXCEPTION 'RN-31: Asignación incompleta o ambigua: %', e;
        END IF;
        v_n := 0;
        FOR v_servicio IN
            SELECT id_servicio FROM servicios
             WHERE (e ? 'id_servicio'     AND id_servicio     = (e->>'id_servicio')::INT)
                OR (e ? 'codigo_servicio' AND codigo_servicio = upper(e->>'codigo_servicio'))
                OR (e ? 'id_categoria'    AND id_categoria    = (e->>'id_categoria')::INT AND estado)
             ORDER BY id_servicio
        LOOP
            CALL sp_asignar_caracteristica(v_servicio, (e->>'id_caracteristica')::INT, e->>'valor');
            v_n := v_n + 1;
        END LOOP;
        IF v_n = 0 THEN
            RAISE EXCEPTION 'RN-31: La asignación % no corresponde a ningún servicio', e;
        END IF;
        p_total := p_total + v_n;
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- SP20  Alta de usuario del sistema
--   RN-32 Sólo un Gerente da de alta usuarios; un usuario por empleado
--         activo; nombre de usuario único; la contraseña llega YA en hash
--         bcrypt o Argon2id (la API la cifra; la base nunca ve el texto).
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_usuario(
    p_id_empleado       INT,
    p_nombre_usuario    VARCHAR,
    p_contrasena_hash   VARCHAR,
    p_rol               VARCHAR,
    p_id_empleado_admin INT,
    INOUT p_id_usuario  INT DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
DECLARE
    v_usuario VARCHAR := lower(trim(p_nombre_usuario));
    v_id_rol  INT;
BEGIN
    IF NOT fn_empleado_puede(p_id_empleado_admin, ARRAY['Gerente']) THEN
        RAISE EXCEPTION 'RN-32: Sólo un Gerente da de alta usuarios';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM empleados WHERE id_empleado = p_id_empleado AND estado) THEN
        RAISE EXCEPTION 'RN-32: El empleado % no existe o está inactivo', p_id_empleado;
    END IF;
    IF EXISTS (SELECT 1 FROM usuarios WHERE id_empleado = p_id_empleado) THEN
        RAISE EXCEPTION 'RN-32: El empleado % ya tiene usuario', p_id_empleado;
    END IF;
    IF coalesce(v_usuario, '') !~ '^[a-z0-9._-]{3,50}$' THEN
        RAISE EXCEPTION 'RN-32: Nombre de usuario inválido (3 a 50 caracteres: letras, números, punto, guion)';
    END IF;
    IF EXISTS (SELECT 1 FROM usuarios WHERE nombre_usuario = v_usuario) THEN
        RAISE EXCEPTION 'RN-32: El usuario % ya existe', v_usuario;
    END IF;
    IF coalesce(p_contrasena_hash, '') !~ '^\$(2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}|argon2id\$.+)$' THEN
        RAISE EXCEPTION 'RN-32: La contraseña debe llegar como hash bcrypt o Argon2id, nunca en texto plano';
    END IF;
    SELECT id_rol INTO v_id_rol FROM roles WHERE nombre_rol = p_rol;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'RN-32: Rol % no válido', p_rol;
    END IF;

    INSERT INTO usuarios(id_empleado, id_rol, nombre_usuario, contrasena_hash)
    VALUES (p_id_empleado, v_id_rol, v_usuario, p_contrasena_hash)
    RETURNING id_usuario INTO p_id_usuario;
END $$;

-- ---------------------------------------------------------------------
-- SP21  Registrar un intento de inicio de sesión (lo llama la API después
--       de verificar el hash)
--   RN-33 5 intentos fallidos seguidos bloquean la cuenta 15 minutos;
--         un acceso correcto reinicia el contador.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_intento_acceso(
    p_id_usuario INT,
    p_exito      BOOLEAN,
    INOUT p_bloqueado_hasta TIMESTAMP DEFAULT NULL)
LANGUAGE plpgsql
SET search_path = facturacion, pg_catalog
AS $$
BEGIN
    IF p_exito THEN
        UPDATE usuarios
           SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_acceso = now()
         WHERE id_usuario = p_id_usuario AND (bloqueado_hasta IS NULL OR bloqueado_hasta <= now())
        RETURNING bloqueado_hasta INTO p_bloqueado_hasta;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'RN-33: La cuenta % no existe o está bloqueada', p_id_usuario;
        END IF;
    ELSE
        UPDATE usuarios
           SET intentos_fallidos = intentos_fallidos + 1,
               bloqueado_hasta = CASE WHEN intentos_fallidos + 1 >= 5
                                      THEN now() + INTERVAL '15 minutes' ELSE bloqueado_hasta END
         WHERE id_usuario = p_id_usuario
        RETURNING bloqueado_hasta INTO p_bloqueado_hasta;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'La cuenta % no existe', p_id_usuario;
        END IF;
    END IF;
END $$;

-- Datos para el inicio de sesión (la API compara el hash; no se expone en vistas)
CREATE OR REPLACE FUNCTION fn_credenciales_usuario(p_nombre_usuario TEXT)
RETURNS TABLE (id_usuario INT, id_empleado INT, nombre VARCHAR, rol VARCHAR,
               contrasena_hash VARCHAR, activo BOOLEAN, bloqueado_hasta TIMESTAMP)
LANGUAGE sql STABLE
SET search_path = facturacion, pg_catalog AS $$
    SELECT u.id_usuario, e.id_empleado, e.nombre, r.nombre_rol, u.contrasena_hash,
           u.estado AND e.estado, u.bloqueado_hasta
      FROM usuarios u
      JOIN empleados e USING (id_empleado)
      JOIN roles r     USING (id_rol)
     WHERE u.nombre_usuario = lower(trim(p_nombre_usuario))
$$;

-- Reporte de antigüedad de saldos por rangos a una fecha de corte
-- (propósito 7 de la rúbrica; función porque devuelve un conjunto de filas)
CREATE OR REPLACE FUNCTION fn_antiguedad_saldos(p_fecha_corte DATE DEFAULT NULL)
RETURNS TABLE (id_cliente INT, cliente TEXT, rfc VARCHAR, facturas BIGINT,
               por_vencer DECIMAL, dias_1_30 DECIMAL, dias_31_60 DECIMAL,
               dias_61_90 DECIMAL, mas_de_90 DECIMAL, saldo_total DECIMAL)
LANGUAGE sql STABLE
SET search_path = facturacion, pg_catalog AS $$
    WITH s AS (
        SELECT f.id_cliente, fn_saldo_factura(f.id_factura) AS saldo,
               coalesce(p_fecha_corte, fn_hoy()) - fn_fecha_local(f.fecha_vencimiento) AS dias
          FROM facturas f
         WHERE f.estado = 'EMITIDA')
    SELECT c.id_cliente,
           trim(c.nombre || ' ' || coalesce(c.apellido, '')),
           c.identificacion_fiscal,
           count(*),
           coalesce(sum(s.saldo) FILTER (WHERE s.dias <= 0), 0),
           coalesce(sum(s.saldo) FILTER (WHERE s.dias BETWEEN 1  AND 30), 0),
           coalesce(sum(s.saldo) FILTER (WHERE s.dias BETWEEN 31 AND 60), 0),
           coalesce(sum(s.saldo) FILTER (WHERE s.dias BETWEEN 61 AND 90), 0),
           coalesce(sum(s.saldo) FILTER (WHERE s.dias > 90), 0),
           sum(s.saldo)
      FROM s JOIN clientes c ON c.id_cliente = s.id_cliente
     WHERE s.saldo > 0
     GROUP BY c.id_cliente
     ORDER BY sum(s.saldo) DESC
$$;

-- V6 Antigüedad de saldos a hoy
CREATE OR REPLACE VIEW vw_antiguedad_saldos AS
SELECT * FROM fn_antiguedad_saldos();

-- V7 Bitácora de cambios de tarifa
CREATE OR REPLACE VIEW vw_auditoria_tarifas AS
SELECT a.id_auditoria, s.codigo_servicio, s.nombre_servicio, a.precio_anterior, a.precio_nuevo,
       round((a.precio_nuevo - a.precio_anterior) / a.precio_anterior * 100, 2) AS variacion_pct,
       coalesce(e.nombre, '(fuera del SP: ' || a.usuario_bd || ')') AS empleado, a.fecha_cambio
  FROM auditoria_tarifas a
  JOIN servicios s USING (id_servicio)
  LEFT JOIN empleados e USING (id_empleado)
 ORDER BY a.fecha_cambio DESC, a.id_auditoria DESC;

-- V8 Pólizas contables por factura
CREATE OR REPLACE VIEW vw_polizas AS
SELECT f.folio, m.evento, m.id_pago, m.cuenta, m.cargo, m.abono, e.nombre AS empleado, m.fecha
  FROM movimientos_contables m
  JOIN facturas f  USING (id_factura)
  JOIN empleados e ON e.id_empleado = m.id_empleado
 ORDER BY m.id_movimiento;

-- V9 Balanza de comprobación (saldo deudor positivo)
CREATE OR REPLACE VIEW vw_balanza AS
SELECT cuenta, sum(cargo) AS cargos, sum(abono) AS abonos, sum(cargo) - sum(abono) AS saldo
  FROM movimientos_contables
 GROUP BY cuenta
 ORDER BY cuenta;

-- V10 Usuarios y roles (sin el hash de la contraseña)
CREATE OR REPLACE VIEW vw_usuarios AS
SELECT u.id_usuario, u.nombre_usuario, e.id_empleado, e.nombre AS empleado, e.puesto, r.nombre_rol AS rol,
       u.estado AND e.estado AS activo, u.intentos_fallidos, u.bloqueado_hasta, u.ultimo_acceso
  FROM usuarios u
  JOIN empleados e USING (id_empleado)
  JOIN roles r     USING (id_rol)
 ORDER BY u.id_usuario;

-- V11 Impuestos vigentes hoy e historial
CREATE OR REPLACE VIEW vw_impuestos AS
SELECT id_impuesto, clave, tipo, tasa, vigente_desde, vigente_hasta,
       (vigente_desde <= fn_hoy() AND (vigente_hasta IS NULL OR vigente_hasta >= fn_hoy())) AS vigente,
       descripcion
  FROM impuestos_historico
 ORDER BY clave, tipo, vigente_desde;

-- =====================================================================
--  VISTAS DE LECTURA PARA LA API (la aplicación sólo lee de vistas)
-- =====================================================================

-- V12 Clientes con su tipo de persona y condiciones pactadas
CREATE OR REPLACE VIEW vw_clientes AS
SELECT c.id_cliente, trim(c.nombre || ' ' || coalesce(c.apellido, '')) AS cliente,
       c.identificacion_fiscal AS rfc,
       CASE WHEN length(c.identificacion_fiscal) = 12 THEN 'MORAL' ELSE 'FISICA' END AS persona,
       c.correo, c.telefono, c.direccion, c.estado,
       coalesce(k.descuento_pct, 0) AS descuento_pct,
       coalesce(k.retiene_isr, FALSE) AS retiene_isr,
       coalesce(k.retiene_iva, FALSE) AS retiene_iva
  FROM clientes c
  LEFT JOIN condiciones_cliente k USING (id_cliente)
 ORDER BY c.id_cliente;

-- V13 Renglones de cada factura
CREATE OR REPLACE VIEW vw_detalle_factura AS
SELECT d.id_detalle, d.id_factura, f.folio, s.id_servicio, s.codigo_servicio, s.nombre_servicio,
       s.unidad_medida, d.cantidad, d.precio_unitario, d.descuento, d.subtotal
  FROM detalle_factura d
  JOIN facturas f  USING (id_factura)
  JOIN servicios s USING (id_servicio)
 ORDER BY d.id_factura, d.id_detalle;

-- V14 Pagos con su método
CREATE OR REPLACE VIEW vw_pagos AS
SELECT p.id_pago, p.id_factura, f.folio, m.nombre_metodo AS metodo, p.fecha_pago,
       p.monto, p.referencia, p.estado
  FROM pagos p
  JOIN facturas f     USING (id_factura)
  JOIN metodos_pago m USING (id_metodo_pago)
 ORDER BY p.id_pago;

-- V15 Métodos de pago
CREATE OR REPLACE VIEW vw_metodos_pago AS
SELECT id_metodo_pago, nombre_metodo, descripcion, estado
  FROM metodos_pago
 ORDER BY id_metodo_pago;

-- V16 Comprobantes generados
CREATE OR REPLACE VIEW vw_comprobantes AS
SELECT c.id_factura, f.folio, c.version_cfdi, c.estado, c.uuid_fiscal, c.fecha_generacion, c.contenido
  FROM comprobantes c
  JOIN facturas f USING (id_factura)
 ORDER BY c.id_factura;

-- V18 Diccionario de características
CREATE OR REPLACE VIEW vw_caracteristicas AS
SELECT id_caracteristica, nombre_caracteristica, tipo_dato, unidad, descripcion
  FROM caracteristicas
 ORDER BY id_caracteristica;

-- V19 Categorías
CREATE OR REPLACE VIEW vw_categorias AS
SELECT id_categoria, nombre_categoria, descripcion, estado
  FROM categorias_servicio
 ORDER BY id_categoria;

-- V20 Desglose de impuestos de cada factura
CREATE OR REPLACE VIEW vw_factura_impuestos AS
SELECT fi.id_factura, i.clave, i.tipo, i.tasa, fi.base, fi.importe
  FROM factura_impuestos fi
  JOIN impuestos_historico i USING (id_impuesto)
 ORDER BY fi.id_factura, i.tipo DESC, i.clave;

-- V21 Empleados y si ya tienen cuenta
CREATE OR REPLACE VIEW vw_empleados AS
SELECT e.id_empleado, e.nombre, e.puesto, e.correo, e.estado,
       EXISTS (SELECT 1 FROM usuarios u WHERE u.id_empleado = e.id_empleado) AS tiene_usuario
  FROM empleados e
 ORDER BY e.id_empleado;

-- V17 Cierres fiscales con quién los hizo
CREATE OR REPLACE VIEW vw_cierres_fiscales AS
SELECT c.id_cierre, c.tipo, c.periodo_inicio, c.periodo_fin, c.facturas_emitidas, c.facturas_canceladas,
       c.subtotal, c.iva_trasladado, c.retenciones, c.total_facturado, c.total_cobrado,
       e.nombre AS empleado, c.fecha_cierre
  FROM cierres_fiscales c
  JOIN empleados e USING (id_empleado)
 ORDER BY c.periodo_inicio, c.tipo;

