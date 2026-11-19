-- =====================================================================
--  Parte 4: PRUEBAS DE VERIFICACIÓN
--  1) Requisitos mínimos  2) Reglas que deben RECHAZAR datos  3) Reportes
--  Ejecutar después de facturacion_completo.sql
-- =====================================================================
SET search_path TO facturacion;

-- 1) Requisitos mínimos ------------------------------------------------
SELECT 'Tablas' AS requisito, count(*) AS obtenido, 8 AS minimo
  FROM information_schema.tables WHERE table_schema = 'facturacion' AND table_type = 'BASE TABLE'
UNION ALL
SELECT 'Procedimientos almacenados', count(*), 10
  FROM information_schema.routines WHERE routine_schema = 'facturacion' AND routine_type = 'PROCEDURE'
UNION ALL SELECT 'Servicios',       count(*), 100 FROM servicios
UNION ALL SELECT 'Características', count(*), 50  FROM caracteristicas
UNION ALL SELECT 'Valores servicio-característica', count(*), 100 FROM servicio_caracteristicas;

-- 2) Cada instrucción debe fallar con la regla indicada ------------------
--    (cada prueba corre en su propia subtransacción: no deja datos)
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

-- 3) Reportes ------------------------------------------------------------
SELECT * FROM vw_facturas;
SELECT * FROM vw_ventas_categoria;
SELECT * FROM vw_cobranza_metodo;
SELECT * FROM vw_catalogo_servicios LIMIT 5;
SELECT * FROM vw_ficha_servicio WHERE codigo_servicio = 'SRV-013';
