-- ================================================================
--  CONTROL PRESUPUESTAL MUNICIPAL — Datos de demostración
-- ================================================================
--  TODOS los datos de este archivo son FICTICIOS y existen solo
--  para poder levantar el sistema localmente. No corresponden a
--  ninguna dependencia, proyecto, monto ni persona reales.
--
--  Las partidas usan nombres genéricos del Clasificador por Objeto
--  del Gasto (CONAC), que es un catálogo público nacional.
--
--  Usuarios demo (cambiar en cualquier entorno no local):
--    admin / demo1234   → rol GOD (acceso total)
--    area  / demo1234   → sin rol especial (usuario de área)
--  Las contraseñas se hashean con bcrypt (pgcrypto) al sembrar.
-- ================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── Catálogo de tipo de impuesto ─────────────────────────────
INSERT INTO public.cat_impuesto_tipo (clave, descripcion) VALUES
  ('NONE', 'Sin retención'),
  ('IVA',  'Impuesto al Valor Agregado'),
  ('ISR',  'Retención de ISR'),
  ('IEPS', 'Impuesto Especial sobre Producción y Servicios')
ON CONFLICT (clave) DO NOTHING;

-- ── Roles ────────────────────────────────────────────────────
INSERT INTO public.roles (id, clave, descripcion) VALUES
  (1, 'GOD',   'Superusuario del sistema'),
  (2, 'ADMIN', 'Administrador de presupuesto'),
  (3, 'AREA',  'Usuario de área solicitante')
ON CONFLICT DO NOTHING;

-- ── Estructura administrativa ficticia ───────────────────────
INSERT INTO public.dgeneral (id, clave, dependencia) VALUES
  (1, 'A00', 'DIRECCIÓN GENERAL DE ADMINISTRACIÓN (DEMO)'),
  (2, 'B00', 'DIRECCIÓN GENERAL DE SERVICIOS PÚBLICOS (DEMO)')
ON CONFLICT DO NOTHING;

INSERT INTO public.dauxiliar (id, clave, dependencia) VALUES
  (1, '101', 'COORDINACIÓN ADMINISTRATIVA (DEMO)'),
  (2, '102', 'DEPARTAMENTO DE TECNOLOGÍAS (DEMO)'),
  (3, '201', 'DEPARTAMENTO DE ALUMBRADO (DEMO)')
ON CONFLICT DO NOTHING;

INSERT INTO public.fuentes (id, clave, fuente) VALUES
  (1, '110101', 'RECURSOS PROPIOS (DEMO)'),
  (2, '150101', 'PARTICIPACIONES (DEMO)')
ON CONFLICT DO NOTHING;

INSERT INTO public.programas (id, clave, descripcion) VALUES
  (1, '01050206', 'Programa de consolidación administrativa (demo)'),
  (2, '02020401', 'Programa de servicios urbanos (demo)')
ON CONFLICT DO NOTHING;

INSERT INTO public.proyectos (id, clave, descripcion, conac) VALUES
  (1, '0105020601', 'Proyecto demo de gestión administrativa', 'E'),
  (2, '0202040101', 'Proyecto demo de mantenimiento de alumbrado', 'K')
ON CONFLICT DO NOTHING;

-- ── Partidas (muestra reducida del clasificador CONAC) ───────
INSERT INTO public.partidas (id, clave, descripcion) VALUES
  (1, '2111', 'MATERIALES, ÚTILES Y EQUIPOS MENORES DE OFICINA'),
  (2, '2141', 'MATERIALES, ÚTILES Y EQUIPOS MENORES DE TECNOLOGÍAS DE LA INFORMACIÓN Y COMUNICACIONES'),
  (3, '2461', 'MATERIAL ELÉCTRICO Y ELECTRÓNICO'),
  (4, '2611', 'COMBUSTIBLES, LUBRICANTES Y ADITIVOS'),
  (5, '3361', 'SERVICIOS DE APOYO ADMINISTRATIVO, TRADUCCIÓN, FOTOCOPIADO E IMPRESIÓN'),
  (6, '3571', 'REPARACIÓN Y MANTENIMIENTO DE MAQUINARIA, OTROS EQUIPOS Y HERRAMIENTA')
ON CONFLICT DO NOTHING;

-- ── Combinaciones permitidas DG/DA/proyecto/fuente/partida ───
INSERT INTO public.proyectos_fuentes_permitidas
  (dgeneral_clave, dauxiliar_clave, proyecto_clave, fuente_clave, dgeneral_id) VALUES
  ('A00', '101', '0105020601', '110101', 1),
  ('A00', '102', '0105020601', '110101', 1),
  ('B00', '201', '0202040101', '150101', 2);

INSERT INTO public.partidas_permitidas
  (dgeneral_clave, dauxiliar_clave, proyecto_clave, fuente_clave, partida_clave) VALUES
  ('A00', '101', '0105020601', '110101', '2111'),
  ('A00', '101', '0105020601', '110101', '3361'),
  ('A00', '102', '0105020601', '110101', '2141'),
  ('B00', '201', '0202040101', '150101', '2461'),
  ('B00', '201', '0202040101', '150101', '2611'),
  ('B00', '201', '0202040101', '150101', '3571');

-- ── Metas ficticias ──────────────────────────────────────────
INSERT INTO public.metas (dg_clave, da_clave, proy_clave, conac, meta) VALUES
  ('A00', '101', '0105020601', 'E', 'Atender solicitudes administrativas (demo)'),
  ('A00', '102', '0105020601', 'E', 'Mantener la infraestructura de cómputo (demo)'),
  ('B00', '201', '0202040101', 'K', 'Rehabilitar luminarias (demo)');

-- ── Presupuesto base mensual (montos inventados) ─────────────
INSERT INTO public.presupuesto_base_partidas
  (id_dgeneral, id_dauxiliar, id_fuente, id_partida, id_proyecto, ejercicio,
   ene, feb, mar, abr, may, jun, jul, ago, sep, oct, nov, dic)
SELECT v.dg, v.da, v.fu, v.pa, v.pr, EXTRACT(year FROM CURRENT_DATE)::int,
       v.m, v.m, v.m, v.m, v.m, v.m, v.m, v.m, v.m, v.m, v.m, v.m
FROM (VALUES
  (1, 1, 1, 1, 1, 10000.00),
  (1, 1, 1, 5, 1,  5000.00),
  (1, 2, 1, 2, 1, 15000.00),
  (2, 3, 2, 3, 2, 20000.00),
  (2, 3, 2, 4, 2,  8000.00),
  (2, 3, 2, 6, 2, 12000.00)
) AS v(dg, da, fu, pa, pr, m);

-- ── Usuarios demo ────────────────────────────────────────────
INSERT INTO public.usuarios (id, nombre_completo, usuario, correo, password, id_dgeneral, id_dauxiliar) VALUES
  (1, 'Usuario Administrador Demo', 'admin', 'admin@ejemplo.com', crypt('demo1234', gen_salt('bf', 10)), 1, 1),
  (2, 'Usuario de Área Demo',       'area',  'area@ejemplo.com',  crypt('demo1234', gen_salt('bf', 10)), 2, 3)
ON CONFLICT DO NOTHING;

INSERT INTO public.usuario_rol (id_usuario, id_rol) VALUES (1, 1), (2, 3)
ON CONFLICT DO NOTHING;

-- ── Ajustar secuencias tras inserts con id explícito ─────────
SELECT setval('public.roles_id_seq',     (SELECT MAX(id) FROM public.roles));
SELECT setval('public.dgeneral_id_seq',  (SELECT MAX(id) FROM public.dgeneral));
SELECT setval('public.dauxiliar_id_seq', (SELECT MAX(id) FROM public.dauxiliar));
SELECT setval('public.fuentes_id_seq',   (SELECT MAX(id) FROM public.fuentes));
SELECT setval('public.programas_id_seq', (SELECT MAX(id) FROM public.programas));
SELECT setval('public.proyectos_id_seq', (SELECT MAX(id) FROM public.proyectos));
SELECT setval('public.partidas_id_seq',  (SELECT MAX(id) FROM public.partidas));
SELECT setval('public.usuarios_id_seq',  (SELECT MAX(id) FROM public.usuarios));

COMMIT;
