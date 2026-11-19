-- =====================================================================
--  04_pruebas.sql — PRUEBAS DE VERIFICACIÓN
--  1) Requisitos mínimos  2) Reglas que deben RECHAZAR datos
--  3) Cálculos y procesos que deben DAR un resultado exacto  4) Reportes
--  Ejecutar después de 01, 02 y 03. Se puede repetir: cada prueba corre
--  en su propia subtransacción y no deja datos.
--  Cada línea "NOTICE:  OK" es una prueba aprobada; no debe aparecer
--  ninguna línea con "FALLA" ni con "ERROR".
-- =====================================================================
SET search_path TO facturacion;

-- 1) Requisitos mínimos ------------------------------------------------
SELECT 'Tablas' AS requisito, count(*) AS obtenido, 8 AS minimo
  FROM information_schema.tables WHERE table_schema = 'facturacion' AND table_type = 'BASE TABLE'
UNION ALL
SELECT 'Procedimientos almacenados', count(*), 10
  FROM information_schema.routines WHERE routine_schema = 'facturacion' AND routine_type = 'PROCEDURE'
UNION ALL
SELECT 'Funciones', count(*), NULL
  FROM information_schema.routines WHERE routine_schema = 'facturacion' AND routine_type = 'FUNCTION'
UNION ALL
SELECT 'Vistas', count(*), NULL
  FROM information_schema.views WHERE table_schema = 'facturacion'
UNION ALL SELECT 'Servicios',       count(*), 100 FROM servicios
UNION ALL SELECT 'Características', count(*), 50  FROM caracteristicas
UNION ALL SELECT 'Valores servicio-característica', count(*), 100 FROM servicio_caracteristicas;

-- Una instrucción que debe fallar con la regla indicada
CREATE OR REPLACE PROCEDURE pg_temp.debe_fallar(p_sql TEXT, p_regla TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RAISE NOTICE 'FALLA LA PRUEBA  % : la instrucción NO fue rechazada', p_regla;
EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE p_regla || '%' THEN
        RAISE NOTICE 'OK  %', SQLERRM;
    ELSE
        RAISE NOTICE 'FALLA LA PRUEBA  % : se obtuvo "%"', p_regla, SQLERRM;
    END IF;
END $$;

-- Un bloque DO que comprueba un resultado y termina con
-- RAISE EXCEPTION 'VERIFICADO' (así se deshace todo lo que hizo)
CREATE OR REPLACE PROCEDURE pg_temp.verificar(p_sql TEXT, p_descripcion TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RAISE NOTICE 'FALLA LA PRUEBA  % : el bloque no llegó a la verificación', p_descripcion;
EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'VERIFICADO' THEN
        RAISE NOTICE 'OK  %', p_descripcion;
    ELSE
        RAISE NOTICE 'FALLA LA PRUEBA  % : %', p_descripcion, SQLERRM;
    END IF;
END $$;

-- 2) Cada instrucción debe fallar con la regla indicada ------------------
-- Clientes
CALL pg_temp.debe_fallar($q$CALL sp_registrar_cliente('X', NULL, 'XX12', 'a@b.mx', NULL, NULL)$q$, 'RN-01');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_cliente('X', NULL, 'CMA180315KJ2', 'a@b.mx', NULL, NULL)$q$, 'RN-02');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_cliente('X', NULL, 'ZZZ180315KJ2', 'sin-arroba', NULL, NULL)$q$, 'RN-03');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_cliente('Pedro', NULL, 'PEPP900101AB1', 'p@b.mx', NULL, NULL)$q$, 'RN-03');
-- Catálogo
CALL pg_temp.debe_fallar($q$CALL sp_registrar_servicio(1, 'SRV-001', 'Dup', NULL, 10, 'Servicio')$q$, 'RN-04');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_servicio(99, 'SRV-999', 'X', NULL, 10, 'Servicio')$q$, 'RN-04');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_servicio(1, 'SRV-999', 'X', NULL, 0, 'Servicio')$q$, 'RN-05');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_servicio(1, 'SRV-999', 'X', NULL, 10, 'Litro')$q$, 'RN-05');
CALL pg_temp.debe_fallar($q$CALL sp_asignar_caracteristica(1, 3, 'diez')$q$, 'RN-06');
CALL pg_temp.debe_fallar($q$CALL sp_asignar_caracteristica(1, 5, 'Tal vez')$q$, 'RN-06');
CALL pg_temp.debe_fallar($q$CALL sp_asignar_caracteristica(1, 8, '30/06/2027')$q$, 'RN-06');
CALL pg_temp.debe_fallar($q$CALL sp_actualizar_precio(1, 35000, 1)$q$, 'RN-07');
CALL pg_temp.debe_fallar($q$CALL sp_actualizar_precio(1, 70000, 2)$q$, 'RN-08');
CALL pg_temp.debe_fallar($q$CALL sp_cambiar_estado_servicio(41, FALSE)$q$, 'RN-09');
-- Facturación
CALL pg_temp.debe_fallar($q$CALL sp_crear_factura(1, 3)$q$, 'RN-10');
CALL pg_temp.debe_fallar($q$CALL sp_crear_factura(999, 2)$q$, 'RN-10');
CALL pg_temp.debe_fallar($q$CALL sp_agregar_detalle(1, 2, 1, 0)$q$, 'RN-12');
CALL pg_temp.debe_fallar($q$CALL sp_agregar_detalle(6, 2, 0, 0)$q$, 'RN-13');
CALL pg_temp.debe_fallar($q$DO $d$ DECLARE x INT; BEGIN CALL sp_cambiar_estado_servicio(100, FALSE); CALL sp_agregar_detalle(6, 100, 1, 0, x); END $d$$q$, 'RN-13');
CALL pg_temp.debe_fallar($q$CALL sp_agregar_detalle(6, 2, 1, 60)$q$, 'RN-14');
CALL pg_temp.debe_fallar($q$DO $d$ DECLARE f INT; BEGIN CALL sp_crear_factura(3, 2, f); CALL sp_emitir_factura(f, 30); END $d$$q$, 'RN-16');
CALL pg_temp.debe_fallar($q$DO $d$ DECLARE f INT; d INT; BEGIN CALL sp_crear_factura(3, 2, f); CALL sp_agregar_detalle(f, 3, 1, 0, d); CALL sp_emitir_factura(f, 120); END $d$$q$, 'RN-17');
-- RN-18: se simula que la F-000004 ya venció y se intenta facturar al mismo cliente
CALL pg_temp.debe_fallar($q$DO $d$ DECLARE f INT; d INT; BEGIN
      UPDATE facturas SET fecha_emision = now() - interval '45 days', fecha_vencimiento = now() - interval '15 days' WHERE folio = 'F-000004';
      CALL sp_crear_factura(6, 2, f); CALL sp_agregar_detalle(f, 61, 1, 0, d); CALL sp_emitir_factura(f, 30); END $d$$q$, 'RN-18');
-- Cobranza
CALL pg_temp.debe_fallar($q$CALL sp_registrar_pago(3, 2, 100, 'x', 3)$q$, 'RN-19');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_pago(2, 2, 100, 'x', 2)$q$, 'RN-19');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_pago(2, 5, 100, 'x', 3)$q$, 'RN-20');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_pago(2, 2, 999999, 'x', 3)$q$, 'RN-21');
CALL pg_temp.debe_fallar($q$CALL sp_cancelar_pago(1, 3)$q$, 'RN-23');
CALL pg_temp.debe_fallar($q$CALL sp_cancelar_pago(4, 1)$q$, 'RN-23');
CALL pg_temp.debe_fallar($q$CALL sp_cancelar_factura(2, 1)$q$, 'RN-24');
CALL pg_temp.debe_fallar($q$CALL sp_cancelar_factura(4, 2)$q$, 'RN-24');
-- Tarifas
CALL pg_temp.debe_fallar($q$CALL sp_actualizar_precio(1, 36000, 4)$q$, 'RN-25');
-- Impuestos
CALL pg_temp.debe_fallar($q$CALL sp_registrar_tasa_impuesto('IVA', 'TRASLADO', 0.17, '2030-01-01', 2)$q$, 'RN-27');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_tasa_impuesto('IVA', 'TRASLADO', 0.17, '2009-01-01', 1)$q$, 'RN-27');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_tasa_impuesto('IVA', 'TRASLADO', 16, '2030-01-01', 1)$q$, 'RN-27');
-- Descuentos
CALL pg_temp.debe_fallar($q$CALL sp_aplicar_descuentos(1)$q$, 'RN-12');
-- Contabilidad
CALL pg_temp.debe_fallar($q$CALL sp_contabilizar('AJUSTE', 1, NULL, 1)$q$, 'RN-28');
-- Cierre fiscal
CALL pg_temp.debe_fallar($q$CALL sp_cierre_fiscal('DIARIO', current_date + 30, 1)$q$, 'RN-29');
CALL pg_temp.debe_fallar($q$CALL sp_cierre_fiscal('DIARIO', current_date, 3)$q$, 'RN-29');
CALL pg_temp.debe_fallar($q$CALL sp_cierre_fiscal('SEMANAL', current_date, 1)$q$, 'RN-29');
CALL pg_temp.debe_fallar($q$DO $d$ DECLARE c INT; BEGIN CALL sp_cierre_fiscal('MENSUAL', current_date, 1, c); CALL sp_cierre_fiscal('MENSUAL', current_date, 1, c); END $d$$q$, 'RN-29');
-- Comprobante
CALL pg_temp.debe_fallar($q$CALL sp_generar_comprobante(6)$q$, 'RN-30');
CALL pg_temp.debe_fallar($q$CALL sp_generar_comprobante(3)$q$, 'RN-30');
-- Asignación masiva
CALL pg_temp.debe_fallar($q$CALL sp_asignar_caracteristicas_masivo('[]')$q$, 'RN-31');
CALL pg_temp.debe_fallar($q$CALL sp_asignar_caracteristicas_masivo('[{"codigo_servicio": "SRV-999", "id_caracteristica": 3, "valor": "5"}]')$q$, 'RN-31');
CALL pg_temp.debe_fallar($q$CALL sp_asignar_caracteristicas_masivo('[{"id_servicio": 1, "codigo_servicio": "SRV-001", "id_caracteristica": 3, "valor": "5"}]')$q$, 'RN-31');
CALL pg_temp.debe_fallar($q$CALL sp_asignar_caracteristicas_masivo('[{"id_categoria": 1, "id_caracteristica": 3, "valor": "15"}, {"codigo_servicio": "SRV-002", "id_caracteristica": 3, "valor": "quince"}]')$q$, 'RN-06');
-- Usuarios y roles
CALL pg_temp.debe_fallar($q$CALL sp_registrar_usuario(4, 'diego2', '$2b$12$A6nYvxMcoKhb8ypLfQF6YuK4r0pUqhUDdkGl3cDf6zVQ7ElFXUClu', 'Auxiliar', 2)$q$, 'RN-32');
CALL pg_temp.debe_fallar($q$CALL sp_registrar_usuario(4, 'diego2', '$2b$12$A6nYvxMcoKhb8ypLfQF6YuK4r0pUqhUDdkGl3cDf6zVQ7ElFXUClu', 'Auxiliar', 1)$q$, 'RN-32');
CALL pg_temp.debe_fallar($q$DO $d$ DECLARE e INT; u INT; BEGIN
      INSERT INTO empleados(nombre, puesto, correo) VALUES ('Prueba', 'Cajero', 'prueba@facturacion.mx') RETURNING id_empleado INTO e;
      CALL sp_registrar_usuario(e, 'prueba', 'Demo2026!', 'Cajero', 1, u); END $d$$q$, 'RN-32');
-- Una cuenta desactivada pierde sus permisos aunque el empleado siga activo
CALL pg_temp.debe_fallar($q$DO $d$ DECLARE f INT; BEGIN
      UPDATE usuarios SET estado = FALSE WHERE id_empleado = 2; CALL sp_crear_factura(1, 2, f); END $d$$q$, 'RN-10');
CALL pg_temp.debe_fallar($q$DO $d$ DECLARE b TIMESTAMP; BEGIN
      FOR i IN 1..5 LOOP CALL sp_registrar_intento_acceso(4, FALSE, b); END LOOP;
      CALL sp_registrar_intento_acceso(4, TRUE, b); END $d$$q$, 'RN-33');

-- 3) Cálculos y procesos que deben dar un resultado exacto ---------------
CALL pg_temp.verificar($q$DO $d$ BEGIN
      CALL sp_actualizar_precio(1, 36000, 1);
      IF NOT EXISTS (SELECT 1 FROM auditoria_tarifas WHERE id_servicio = 1 AND precio_anterior = 35000
                        AND precio_nuevo = 36000 AND id_empleado = 1) THEN
          RAISE EXCEPTION 'no se auditó el cambio hecho con el SP'; END IF;
      UPDATE servicios SET precio_base = 70000 WHERE id_servicio = 2;
      IF NOT EXISTS (SELECT 1 FROM auditoria_tarifas WHERE id_servicio = 2 AND precio_nuevo = 70000 AND id_empleado IS NULL) THEN
          RAISE EXCEPTION 'no se auditó el UPDATE directo'; END IF;
      RAISE EXCEPTION 'VERIFICADO'; END $d$$q$,
  'RN-25: todo cambio de tarifa queda auditado (con el SP y con un UPDATE directo)');

CALL pg_temp.verificar($q$DO $d$ DECLARE f INT; d1 INT; d2 INT; d3 INT; BEGIN
      CALL sp_crear_factura(3, 2, f);                    -- cliente sin convenio
      CALL sp_agregar_detalle(f, 11, 24, 0, d1);         -- 24 unidades → 5 % por volumen
      CALL sp_agregar_detalle(f, 11, 12, 1, d2);         -- 12 unidades → 3 % (mayor que el 1 % capturado)
      CALL sp_agregar_detalle(f, 11, 12, 20, d3);        -- capturado 20 % > 3 % por volumen
      IF (SELECT descuento FROM detalle_factura WHERE id_detalle = d1) <> round(24 * (SELECT precio_base FROM servicios WHERE id_servicio = 11) * 0.05, 2)
      OR (SELECT descuento FROM detalle_factura WHERE id_detalle = d2) <> round(12 * (SELECT precio_base FROM servicios WHERE id_servicio = 11) * 0.03, 2)
      OR (SELECT descuento FROM detalle_factura WHERE id_detalle = d3) <> round(12 * (SELECT precio_base FROM servicios WHERE id_servicio = 11) * 0.20, 2) THEN
          RAISE EXCEPTION 'descuento por volumen incorrecto'; END IF;
      CALL sp_crear_factura(8, 2, f);                    -- cliente con convenio del 8 %
      CALL sp_agregar_detalle(f, 1, 1, 0, d1);           -- 35,000 × 8 % = 2,800
      IF (SELECT descuento FROM detalle_factura WHERE id_detalle = d1) <> 2800 THEN
          RAISE EXCEPTION 'descuento por cliente incorrecto'; END IF;
      RAISE EXCEPTION 'VERIFICADO'; END $d$$q$,
  'RN-26: descuento automático = mayor entre capturado, cliente y volumen');

CALL pg_temp.verificar($q$DO $d$ DECLARE f INT; d INT; n INT; BEGIN
      CALL sp_crear_factura(9, 2, f);
      CALL sp_agregar_detalle(f, 1, 1, 0, d);
      INSERT INTO condiciones_cliente(id_cliente, descuento_pct) VALUES (9, 10);
      CALL sp_aplicar_descuentos(f, n);
      IF n <> 1 OR (SELECT subtotal FROM facturas WHERE id_factura = f) <> 31500 THEN
          RAISE EXCEPTION 'sp_aplicar_descuentos no aplicó el nuevo convenio (renglones %)', n; END IF;
      RAISE EXCEPTION 'VERIFICADO'; END $d$$q$,
  'RN-26: sp_aplicar_descuentos aplica un convenio nuevo a un borrador');

CALL pg_temp.verificar($q$DO $d$ DECLARE f INT; d INT; j JSONB; BEGIN
      CALL sp_crear_factura(7, 2, f);                    -- cliente que retiene ISR e IVA
      CALL sp_agregar_detalle(f, 1, 1, 0, d);            -- 35,000
      -- IVA 5,600 · ret. ISR 3,500 · ret. IVA 3,733.35 → total 33,366.65
      IF (SELECT (subtotal, impuestos, total) FROM facturas WHERE id_factura = f)
         IS DISTINCT FROM (35000.00, 5600.00, 33366.65) THEN
          RAISE EXCEPTION 'totales con retenciones incorrectos'; END IF;
      IF (SELECT count(*) FROM factura_impuestos WHERE id_factura = f) <> 3 THEN
          RAISE EXCEPTION 'desglose de impuestos incompleto'; END IF;
      CALL sp_emitir_factura(f, 30);
      IF NOT EXISTS (SELECT 1 FROM movimientos_contables WHERE id_factura = f
                        AND cuenta = '113 Impuestos retenidos por acreditar' AND cargo = 7233.35) THEN
          RAISE EXCEPTION 'la póliza no registra las retenciones'; END IF;
      CALL sp_generar_comprobante(f, j);
      IF (j->'Impuestos'->>'TotalImpuestosRetenidos')::DECIMAL <> 7233.35 OR (j->>'Total')::DECIMAL <> 33366.65 THEN
          RAISE EXCEPTION 'el comprobante no cuadra con la factura'; END IF;
      RAISE EXCEPTION 'VERIFICADO'; END $d$$q$,
  'RN-27: subtotal, IVA y retenciones de ISR e IVA (factura, póliza y comprobante)');

CALL pg_temp.verificar($q$DO $d$ DECLARE x INT; BEGIN
      CALL sp_registrar_tasa_impuesto('IVA', 'TRASLADO', 0.17, '2030-01-01', 1, x);
      IF (SELECT vigente_hasta FROM impuestos_historico WHERE clave = 'IVA' AND tipo = 'TRASLADO' AND tasa = 0.16) <> '2029-12-31'
      OR fn_tasa_impuesto('IVA', 'TRASLADO', '2030-06-01') <> 0.17
      OR fn_tasa_impuesto('IVA', 'TRASLADO', '2008-06-01') <> 0.15
      OR fn_tasa_iva() <> 0.16 THEN
          RAISE EXCEPTION 'la vigencia de tasas no se respetó'; END IF;
      RAISE EXCEPTION 'VERIFICADO'; END $d$$q$,
  'RN-27: una tasa nueva cierra la anterior y se respeta el historial');

CALL pg_temp.verificar($q$DO $d$ BEGIN
      IF EXISTS (SELECT 1 FROM movimientos_contables GROUP BY id_factura, evento, id_pago HAVING sum(cargo) <> sum(abono)) THEN
          RAISE EXCEPTION 'hay pólizas desbalanceadas'; END IF;
      IF EXISTS (SELECT 1 FROM movimientos_contables WHERE id_factura = 3 GROUP BY cuenta HAVING sum(cargo) <> sum(abono)) THEN
          RAISE EXCEPTION 'la cancelación de F-000003 no revirtió su emisión'; END IF;
      IF EXISTS (SELECT 1 FROM movimientos_contables WHERE id_pago = 4 GROUP BY cuenta HAVING sum(cargo) <> sum(abono)) THEN
          RAISE EXCEPTION 'la cancelación del pago 4 no revirtió su cobro'; END IF;
      IF (SELECT saldo FROM vw_balanza WHERE cuenta = '105 Clientes')
         <> (SELECT sum(saldo) FROM vw_facturas WHERE estado IN ('EMITIDA', 'PAGADA')) THEN
          RAISE EXCEPTION 'el saldo de Clientes no coincide con las facturas por cobrar'; END IF;
      RAISE EXCEPTION 'VERIFICADO'; END $d$$q$,
  'RN-28: pólizas balanceadas, reversiones completas y Clientes = cuentas por cobrar');

CALL pg_temp.verificar($q$DO $d$ DECLARE c INT; r cierres_fiscales%ROWTYPE; dia DATE; BEGIN
      SELECT fn_fecha_local(fecha_emision) INTO dia FROM facturas WHERE id_factura = 1;
      CALL sp_cierre_fiscal('DIARIO', dia, 1, c);
      SELECT * INTO r FROM cierres_fiscales WHERE id_cierre = c;
      -- Escenarios de 03_datos: 5 emitidas (1 cancelada), 4 vigentes, 3 pagos aplicados
      IF (r.facturas_emitidas, r.facturas_canceladas, r.subtotal, r.iva_trasladado, r.total_facturado, r.total_cobrado)
         IS DISTINCT FROM (5, 1, 196479.20::DECIMAL, 31436.67::DECIMAL, 227915.87::DECIMAL, 122466.67::DECIMAL) THEN
          RAISE EXCEPTION 'cifras del cierre incorrectas: %', r; END IF;
      RAISE EXCEPTION 'VERIFICADO'; END $d$$q$,
  'RN-29: cierre fiscal diario con las cifras exactas de los escenarios');

CALL pg_temp.verificar($q$DO $d$ DECLARE j JSONB; BEGIN
      SELECT contenido INTO j FROM comprobantes WHERE id_factura = 1;
      IF j->>'MetodoPago' <> 'PUE' OR j->>'FormaPago' <> '03' OR (j->>'Total')::DECIMAL <> 42466.67
         OR jsonb_array_length(j->'Conceptos') <> 2
         OR (j->>'SubTotal')::DECIMAL - (j->>'Descuento')::DECIMAL
            + (j->'Impuestos'->>'TotalImpuestosTrasladados')::DECIMAL <> (j->>'Total')::DECIMAL THEN
          RAISE EXCEPTION 'comprobante de F-000001 incorrecto'; END IF;
      SELECT contenido INTO j FROM comprobantes WHERE id_factura = 2;
      IF j->>'MetodoPago' <> 'PPD' OR j->>'FormaPago' <> '99' OR j->'Receptor'->>'Rfc' <> 'TEC200110AB5' THEN
          RAISE EXCEPTION 'comprobante de F-000002 incorrecto'; END IF;
      RAISE EXCEPTION 'VERIFICADO'; END $d$$q$,
  'RN-30: estructura CFDI 4.0 (PUE/PPD, forma de pago y totales que cuadran)');

CALL pg_temp.verificar($q$DO $d$ DECLARE n INT; BEGIN
      BEGIN
          CALL sp_asignar_caracteristicas_masivo('[{"id_categoria": 1, "id_caracteristica": 3, "valor": "15"},
                                                   {"codigo_servicio": "SRV-002", "id_caracteristica": 3, "valor": "quince"}]', n);
      EXCEPTION WHEN raise_exception THEN NULL;
      END;
      IF (SELECT valor FROM servicio_caracteristicas WHERE id_servicio = 1 AND id_caracteristica = 3) <> '30' THEN
          RAISE EXCEPTION 'la asignación fallida dejó cambios a medias'; END IF;
      CALL sp_asignar_caracteristicas_masivo('[{"id_categoria": 2, "id_caracteristica": 18, "valor": "99.95"},
                                               {"codigo_servicio": "srv-001", "id_caracteristica": 3, "valor": "25"}]', n);
      IF n <> 11 OR (SELECT count(*) FROM servicio_caracteristicas sc JOIN servicios s USING (id_servicio)
                      WHERE s.id_categoria = 2 AND sc.id_caracteristica = 18 AND sc.valor = '99.95') <> 10 THEN
          RAISE EXCEPTION 'la asignación masiva afectó % servicios', n; END IF;
      RAISE EXCEPTION 'VERIFICADO'; END $d$$q$,
  'RN-31: asignación masiva todo o nada (10 servicios de una categoría + 1 por código)');

CALL pg_temp.verificar($q$DO $d$ DECLARE e INT; u INT; f INT; BEGIN
      INSERT INTO empleados(nombre, puesto, correo) VALUES ('Prueba', 'Facturista', 'prueba@facturacion.mx') RETURNING id_empleado INTO e;
      IF fn_empleado_puede(e, ARRAY['Facturista']) THEN
          RAISE EXCEPTION 'un empleado sin cuenta tiene permisos'; END IF;
      CALL sp_registrar_usuario(e, 'Prueba.Factura', '$2b$12$A6nYvxMcoKhb8ypLfQF6YuK4r0pUqhUDdkGl3cDf6zVQ7ElFXUClu', 'Facturista', 1, u);
      CALL sp_crear_factura(1, e, f);
      IF (SELECT nombre_usuario FROM usuarios WHERE id_usuario = u) <> 'prueba.factura' THEN
          RAISE EXCEPTION 'el usuario no se normalizó'; END IF;
      RAISE EXCEPTION 'VERIFICADO'; END $d$$q$,
  'RN-32: el permiso viene del rol de la cuenta; alta de usuario con hash bcrypt');

CALL pg_temp.verificar($q$DO $d$ DECLARE b TIMESTAMP; BEGIN
      CALL sp_registrar_intento_acceso(3, FALSE, b);
      CALL sp_registrar_intento_acceso(3, FALSE, b);
      CALL sp_registrar_intento_acceso(3, TRUE, b);
      IF (SELECT intentos_fallidos FROM usuarios WHERE id_usuario = 3) <> 0 THEN
          RAISE EXCEPTION 'un acceso correcto no reinició el contador'; END IF;
      FOR i IN 1..4 LOOP CALL sp_registrar_intento_acceso(3, FALSE, b); END LOOP;
      IF b IS NOT NULL THEN RAISE EXCEPTION 'se bloqueó antes del quinto intento'; END IF;
      CALL sp_registrar_intento_acceso(3, FALSE, b);
      IF b IS NULL OR b <= now() + interval '14 minutes' THEN
          RAISE EXCEPTION 'no se bloqueó al quinto intento'; END IF;
      IF (SELECT bloqueado_hasta FROM fn_credenciales_usuario('CARLOS.RUIZ')) IS DISTINCT FROM b THEN
          RAISE EXCEPTION 'fn_credenciales_usuario no refleja el bloqueo'; END IF;
      RAISE EXCEPTION 'VERIFICADO'; END $d$$q$,
  'RN-33: bloqueo de 15 minutos al quinto intento fallido y reinicio con acceso correcto');

-- 4) Reportes ------------------------------------------------------------
SELECT * FROM vw_facturas;
SELECT * FROM vw_ventas_categoria;
SELECT * FROM vw_cobranza_metodo;
SELECT * FROM vw_catalogo_servicios LIMIT 5;
SELECT * FROM vw_ficha_servicio WHERE codigo_servicio = 'SRV-013';
SELECT * FROM vw_antiguedad_saldos;
SELECT * FROM vw_balanza;
SELECT * FROM vw_impuestos;
SELECT * FROM vw_usuarios;
