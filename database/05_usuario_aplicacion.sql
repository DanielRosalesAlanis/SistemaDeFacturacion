-- =====================================================================
-- 05 · Usuario de base de datos para la aplicación (mínimo privilegio)
--
-- La Lambda deja de conectarse como postgres (el maestro de RDS, dueño de
-- todo) y usa app_facturacion, que SÓLO puede:
--   · ejecutar los procedimientos que la API llama (db.py → SP_FIRMAS)
--   · ejecutar fn_credenciales_usuario y fn_antiguedad_saldos
--   · leer las vistas vw_* (y las funciones que esas vistas llaman)
-- No puede leer ni modificar ninguna tabla directamente, ni llamar a los
-- procedimientos internos (sp_recalcular_totales, sp_contabilizar...).
--
-- Cómo funciona: esas rutinas pasan a SECURITY DEFINER, o sea que corren con
-- los permisos de su dueño (postgres). Es seguro porque todas fijan
-- "SET search_path = facturacion, pg_catalog", y así nadie puede colarles
-- objetos falsos. Las vistas ya se ejecutan con los permisos de su dueño.
--
-- Ejecutar UNA vez, conectado como postgres:
--   psql -X -v ON_ERROR_STOP=1 -f database/05_usuario_aplicacion.sql
-- y después asignar la contraseña (psql la pide y sólo envía el hash):
--   psql -X -c "\password app_facturacion"
-- Si se vuelve a cargar 02_procedimientos.sql (CREATE OR REPLACE conserva
-- los permisos pero no SECURITY DEFINER), se vuelve a correr este archivo.
-- =====================================================================
\set ON_ERROR_STOP on

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_facturacion') THEN
        CREATE ROLE app_facturacion LOGIN NOINHERIT;   -- sin contraseña hasta \password
    END IF;
END $$;

ALTER ROLE app_facturacion SET search_path = facturacion, pg_catalog;
ALTER ROLE app_facturacion SET statement_timeout = '15s';
ALTER ROLE app_facturacion CONNECTION LIMIT 20;

DO $$ BEGIN EXECUTE format('GRANT CONNECT ON DATABASE %I TO app_facturacion', current_database()); END $$;
GRANT USAGE ON SCHEMA facturacion TO app_facturacion;

-- Nadie fuera del dueño ejecuta rutinas del esquema por omisión (PostgreSQL
-- da EXECUTE a PUBLIC al crearlas). Se concede después sólo lo necesario.
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA facturacion FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA facturacion FROM app_facturacion;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA facturacion FROM app_facturacion;

DO $$
DECLARE
    expuestas TEXT[] := ARRAY[
        'sp_registrar_cliente', 'sp_registrar_servicio', 'sp_asignar_caracteristica',
        'sp_asignar_caracteristicas_masivo', 'sp_actualizar_precio', 'sp_cambiar_estado_servicio',
        'sp_crear_factura', 'sp_agregar_detalle', 'sp_eliminar_detalle', 'sp_aplicar_descuentos',
        'sp_emitir_factura', 'sp_cancelar_factura', 'sp_registrar_pago', 'sp_cancelar_pago',
        'sp_generar_comprobante', 'sp_cierre_fiscal', 'sp_registrar_tasa_impuesto',
        'sp_registrar_usuario', 'sp_registrar_intento_acceso',
        'fn_credenciales_usuario', 'fn_antiguedad_saldos',
        -- Las vistas ejecutan sus funciones con los permisos de quien consulta,
        -- no del dueño de la vista: las que leen tablas también van aquí
        'fn_saldo_factura', 'fn_tasa_iva', 'fn_tasa_impuesto'];
    -- Funciones puras (no leen tablas) que usan las vistas: sólo EXECUTE
    puras TEXT[] := ARRAY['fn_hoy', 'fn_fecha_local'];
    r RECORD;
    n INT := 0;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS firma, p.proname, p.proconfig
          FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
         WHERE s.nspname = 'facturacion' AND p.proname = ANY (expuestas)
    LOOP
        IF NOT coalesce(array_to_string(r.proconfig, ',') LIKE '%search_path=%', FALSE) THEN
            RAISE EXCEPTION '% no fija search_path; no se puede hacer SECURITY DEFINER', r.firma;
        END IF;
        EXECUTE format('ALTER ROUTINE %s SECURITY DEFINER', r.firma);
        EXECUTE format('GRANT EXECUTE ON ROUTINE %s TO app_facturacion', r.firma);
        n := n + 1;
    END LOOP;
    IF n < array_length(expuestas, 1) THEN
        RAISE EXCEPTION 'Sólo se encontraron % de % rutinas: ¿se cargó 02_procedimientos.sql?',
                        n, array_length(expuestas, 1);
    END IF;

    FOR r IN
        SELECT p.oid::regprocedure AS firma
          FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
         WHERE s.nspname = 'facturacion' AND p.proname = ANY (puras)
    LOOP
        EXECUTE format('GRANT EXECUTE ON ROUTINE %s TO app_facturacion', r.firma);
    END LOOP;

    FOR r IN
        SELECT format('%I.%I', schemaname, viewname) AS vista
          FROM pg_views WHERE schemaname = 'facturacion' AND viewname LIKE 'vw\_%'
    LOOP
        EXECUTE format('GRANT SELECT ON %s TO app_facturacion', r.vista);
    END LOOP;
    RAISE NOTICE 'app_facturacion: % rutinas y las vistas vw_* concedidas', n;
END $$;

-- Comprobación: debe decir false en tablas y true en vistas y SP expuestos
SELECT has_table_privilege('app_facturacion', 'facturacion.usuarios', 'SELECT')        AS lee_tabla_usuarios,
       has_table_privilege('app_facturacion', 'facturacion.vw_facturas', 'SELECT')     AS lee_vw_facturas,
       has_function_privilege('app_facturacion',
           'facturacion.fn_credenciales_usuario(text)', 'EXECUTE')                     AS ejecuta_login;
