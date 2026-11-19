-- =====================================================================
--  03_datos.sql — DML: DATOS INICIALES (catálogos + escenarios de prueba)
--  Requiere 01_esquema.sql y 02_procedimientos.sql.
--  Los servicios y sus características se cargan con los SP para que
--  pasen por las mismas validaciones que usará la aplicación.
-- =====================================================================
SET search_path TO facturacion;

INSERT INTO empleados(nombre, puesto, correo) VALUES
  ('Laura Méndez Ríos',    'Gerente',    'laura.mendez@facturacion.mx'),
  ('Ana Torres Vega',      'Facturista', 'ana.torres@facturacion.mx'),
  ('Carlos Ruiz Pineda',   'Cajero',     'carlos.ruiz@facturacion.mx'),
  ('Diego Salas Ortega',   'Auxiliar',   'diego.salas@facturacion.mx');

INSERT INTO roles(nombre_rol, descripcion) VALUES
  ('Gerente',    'Todo: cancelaciones, precios con variación mayor a ±30 %, impuestos, cierres y usuarios'),
  ('Facturista', 'Crea, edita y emite facturas; cambia tarifas hasta ±30 %'),
  ('Cajero',     'Registra pagos'),
  ('Auxiliar',   'Sólo consulta');

-- Cuentas de demostración, una por empleado, con el rol igual a su puesto.
-- Contraseña de las 4 cuentas: Demo2026!  (SÓLO PARA LA DEMO; cámbiese en
-- producción). La base guarda únicamente el hash bcrypt, cada uno con su sal.
INSERT INTO usuarios(id_empleado, id_rol, nombre_usuario, contrasena_hash)
SELECT e.id_empleado, r.id_rol, u.usuario, u.hash
  FROM (VALUES
    ('laura.mendez@facturacion.mx', 'laura.mendez', '$2b$12$yCN2m8PGhvCmRi6G0UX4PuYCVv4VOd2e1uGiy0Zsx15eQ9uKjbDbi'),
    ('ana.torres@facturacion.mx',   'ana.torres',   '$2b$12$A6nYvxMcoKhb8ypLfQF6YuK4r0pUqhUDdkGl3cDf6zVQ7ElFXUClu'),
    ('carlos.ruiz@facturacion.mx',  'carlos.ruiz',  '$2b$12$lkB.VyOKe8INeEhoKprWQuDm3B7NrZTov.2xuB2a982DiK53mmb3K'),
    ('diego.salas@facturacion.mx',  'diego.salas',  '$2b$12$29xLZUY9ry7YVIhioA30MOjc032zHJi6k7/4NgCn8fA9h0zCsf7ki')
       ) AS u(correo, usuario, hash)
  JOIN empleados e ON e.correo = u.correo
  JOIN roles r     ON r.nombre_rol = e.puesto;

-- Impuestos con su vigencia (el 15 % se conserva como historial)
INSERT INTO impuestos_historico(clave, tipo, tasa, vigente_desde, vigente_hasta, descripcion) VALUES
  ('IVA', 'TRASLADO',  0.150000, '1995-04-01', '2009-12-31', 'IVA general 15 % (1995 a 2009)'),
  ('IVA', 'TRASLADO',  0.160000, '2010-01-01', NULL,         'IVA general 16 %'),
  ('IVA', 'RETENCION', 0.106667, '2014-01-01', NULL,         'Retención de dos terceras partes del IVA'),
  ('ISR', 'RETENCION', 0.100000, '2014-01-01', NULL,         'Retención de ISR del 10 %');

-- Descuento automático por cantidad en un mismo renglón
INSERT INTO descuentos_volumen(cantidad_minima, descuento_pct) VALUES
  (10, 3.00), (24, 5.00), (50, 8.00);

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

-- Condiciones comerciales y fiscales pactadas (clientes fuera de los
-- escenarios de abajo, para no alterar sus montos)
INSERT INTO condiciones_cliente(id_cliente, descuento_pct, retiene_isr, retiene_iva, notas)
SELECT c.id_cliente, v.descuento, v.isr, v.iva, v.notas
  FROM (VALUES
    ('CON170918XY4', 0, TRUE,  TRUE,  'Persona moral obligada a retener ISR e IVA'),
    ('ALI190601GH9', 8, FALSE, FALSE, 'Convenio anual: 8 % en todos los servicios'),
    ('SER180912UV1', 5, FALSE, TRUE,  'Convenio 5 %; retiene dos terceras partes del IVA')
       ) AS v(rfc, descuento, isr, iva, notas)
  JOIN clientes c ON c.identificacion_fiscal = v.rfc;

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

-- Estructura de comprobante (CFDI 4.0) de las dos primeras facturas
DO $$
DECLARE j JSONB;
BEGIN
  CALL sp_generar_comprobante(1, j);                -- F-000001, de contado (PUE)
  CALL sp_generar_comprobante(2, j);                -- F-000002, a crédito (PPD)
END $$;
