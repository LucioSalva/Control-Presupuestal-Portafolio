# Control Presupuestal Web

Sistema web para la gestión, control y seguimiento del presupuesto de egresos de un municipio: suficiencias presupuestales, comprometido, devengado, reconducciones, folios y firmas, con saldos calculados en la base de datos y auditoría de cada movimiento.

Proyecto desarrollado por **Humberto Salvador Ruiz Lucio** ([@LucioSalva](https://github.com/LucioSalva)) en su trabajo como desarrollador en el H. Ayuntamiento de Ecatepec de Morelos, México.

> **Versión de portafolio:** se removieron datos, configuraciones y recursos institucionales. El sistema original fue desarrollado para una dependencia municipal.

---

## Problema que resuelve

El ejercicio del presupuesto municipal se llevaba en hojas de cálculo y formatos llenados a mano. Eso generaba saldos inconsistentes entre áreas, folios duplicados, documentos sin firma o con montos que excedían lo disponible, y poca trazabilidad de quién movió qué.

El sistema concentra el flujo completo del gasto en una sola aplicación:

```
Presupuesto base ─► Suficiencia ─► Comprometido ─► Devengado
                         ▲
                  Reconducciones (traspasos entre partidas)
```

Cada paso valida el saldo disponible de la partida en el mes, asigna un folio único y genera el formato PDF listo para firma.

## Módulos

| Módulo | Qué hace |
|---|---|
| **Inicio de sesión** | Login con JWT de expiración corta; inicios y cierres de sesión quedan en la auditoría. |
| **Suficiencia presupuestal** | Captura de solicitudes por DG/DA/fuente/proyecto/partida/mes, cálculo de IVA/ISR/IEPS, selector de metas filtrado por jerarquía y generación del PDF. Incluye historial y cancelación. |
| **Carga masiva de suficiencias** | Importación desde una plantilla `.xlsx` (la plantilla se genera con `server/scripts/generar_plantilla_suficiencias.mjs`). |
| **Comprometido** | Compromete el gasto a partir de una suficiencia vigente. |
| **Devengado** | Registra el gasto ejercido; el monto puede ser menor al comprometido y la diferencia se libera. |
| **Reconducciones** | Traspasos entre partidas (lados origen/destino, metas, movimientos), dictamen en PDF, carga de oficios PDF e historial. |
| **Presupuesto base de partidas** | Carga del presupuesto mensual original (enero–diciembre) por partida. |
| **Partidas permitidas** | Catálogo de combinaciones DG/DA/proyecto/fuente/partida que cada área puede usar. |
| **Dashboard de partidas** | Tablero y gráfica (Chart.js) de presupuesto, reservado, comprometido, devengado y saldo. |
| **Expedientes de entrega** | Control mensual de la entrega física de expedientes por folio. |
| **Administración de usuarios** | Alta/edición de usuarios y roles. |
| **Consola de monitoreo** | Bitácora de eventos de auditoría en tiempo casi real para el rol de superusuario. |

## Arquitectura

```
┌──────────────────────────┐      HTTPS / JSON       ┌──────────────────────────┐
│  Frontend (server/public)│  ─────────────────────► │  API Node.js + Express   │
│  HTML + Bootstrap 5      │   Authorization: Bearer │  (server/server.js)      │
│  JavaScript vanilla      │ ◄─────────────────────  │  routes/ middleware/     │
│  Chart.js, pdf-lib,      │                         │  utils/                  │
│  SweetAlert2, SheetJS    │                         └────────────┬─────────────┘
└──────────────────────────┘                                      │ pg (pool)
                                                                  ▼
                                                     ┌──────────────────────────┐
                                                     │  PostgreSQL              │
                                                     │  funciones PL/pgSQL,     │
                                                     │  triggers de auditoría,  │
                                                     │  contadores de folios    │
                                                     └──────────────────────────┘
```

- **API:** Express con un router por módulo (`server/routes/*.routes.js`), consultas parametrizadas con `pg` y transacciones con bloqueo de fila en operaciones de saldo.
- **Frontend:** páginas HTML servidas por Express; JavaScript sin framework. En producción, `build.js` ofusca el JS a `public/dist` con `javascript-obfuscator`.
- **Base de datos:** la lógica crítica vive en PostgreSQL:
  - `fn_saldo_disponible_partida(...)`: calcula el saldo disponible de una partida por mes en tres fases (suficiencias sin comprometido, comprometidos vigentes, devengados de comprometidos cerrados) para evitar el doble conteo.
  - `fn_next_folio(tipo, anio, mes)`: folios consecutivos por tipo y mes (`MUN-AAAA-MM-SP-0001`) con `INSERT … ON CONFLICT DO UPDATE`, seguro ante concurrencia y con reinicio mensual.
  - Triggers de auditoría (`suficiencias_audit`, `suficiencia_detalle_audit`, `usuarios_audit`), vencimiento automático de suficiencias y normalización del mes de pago.

## Seguridad

- **Autenticación JWT** (HS256) con `issuer`/`audience`, expiración de 10 minutos y rechazo de `alg: none` y de tokens con formato heredado.
- **Contraseñas con bcrypt**; las contraseñas heredadas en texto plano se migran a bcrypt en el primer login correcto.
- **Roles:** `GOD` (superusuario), `ADMIN` y usuarios de área. Las rutas de administración exigen `GOD`/`ADMIN`; los usuarios de área solo ven y capturan lo de su DG/DA.
- **Visibilidad de campos financieros:** IEPS, pensiones y partidas del capítulo 1000 se ocultan y enmascaran en el backend para áreas no autorizadas, y cada intento queda en la auditoría de accesos.
- **Defensa en profundidad:** Helmet, rate limiting (general, login y escritura), validación de `Origin` contra CSRF, CORS con lista blanca, validación del entorno al arrancar (fail-fast si falta `JWT_SECRET` o es corto en producción), protección contra prototype pollution y uploads de PDF validados por *magic bytes* con guardia contra path traversal.

## Pruebas automatizadas

- **159 pruebas con Jest + Supertest** en 15 suites (`server/tests/`): autenticación y JWT, CSRF/Origin, validación de entorno, permisos por rol, validación del panel de administración, suficiencias y cancelación, bloqueo de saldo, reconducciones, partidas del capítulo 1000 y uploads de PDF.
  - Sin base de datos corren **154**; las **4** de folios (`fn_next_folio`, incluida una prueba de concurrencia) requieren PostgreSQL vía `DATABASE_URL_TEST` y se omiten si no está definida (más 1 marcador de omisión).
- **2 pruebas con `node:test`** en `server/utils/*.test.js` (permisos de campos financieros y filtro de metas).

## Stack

| Capa | Tecnología |
|---|---|
| Backend | Node.js, Express 4, `pg`, `jsonwebtoken`, `bcryptjs`, Helmet, `express-rate-limit`, Multer |
| Frontend | HTML, CSS, JavaScript, Bootstrap 5, Bootstrap Icons, Chart.js, pdf-lib, SweetAlert2, SheetJS (xlsx), QRCode |
| Base de datos | PostgreSQL 17, PL/pgSQL |
| Pruebas | Jest, Supertest, `node:test` |
| Infraestructura | Docker (multi-stage), Docker Compose, PowerShell (smoke test post-despliegue) |

## Estructura

```
.
├── docker-compose.yml          # db (PostgreSQL) + app (Node), red interna
├── Dockerfile                  # build multi-stage, usuario sin privilegios
├── .env.docker.example         # variables para Docker Compose
├── sql/
│   ├── 01_schema.sql           # esquema completo (tablas, funciones, triggers), sin datos
│   ├── 02_migraciones.sh       # aplica migraciones posteriores al esquema base
│   └── 03_demo_seed.sql        # datos ficticios para probar localmente
└── server/
    ├── server.js               # arranque de Express, middlewares y montaje de rutas
    ├── db.js                   # pool de PostgreSQL
    ├── build.js                # ofuscación del frontend para producción
    ├── middleware/             # auth (JWT), csrf (Origin), permisos
    ├── routes/                 # un router por módulo
    ├── utils/                  # helpers, validación de env, uploads PDF
    ├── sql/                    # migraciones y scripts de validación de saldos
    ├── public/                 # frontend (HTML, CSS, JS)
    ├── scripts/                # generador de la plantilla de carga masiva
    ├── ops/                    # smoke test post-despliegue (PowerShell)
    ├── docs/                   # notas técnicas de reglas de negocio
    └── tests/                  # pruebas Jest
```

## Cómo levantarlo localmente

### Opción A: Docker Compose

```bash
cp .env.docker.example .env      # y cambia los valores CHANGE_ME
docker compose up -d --build
```

Al iniciar con un volumen vacío, PostgreSQL ejecuta `sql/01_schema.sql`, `sql/02_migraciones.sh` y `sql/03_demo_seed.sql`. La app queda en `http://localhost:3000`.

### Opción B: Node + PostgreSQL locales

Requisitos: Node.js 20+ y PostgreSQL 15+ (con la extensión `pgcrypto`, incluida en la distribución estándar).

```bash
createdb presupuesto_db
psql -d presupuesto_db -f sql/01_schema.sql
psql -d presupuesto_db -f server/sql/migrations/2026_05_21_folios_mensuales.sql
psql -d presupuesto_db -f sql/03_demo_seed.sql

cd server
cp .env.example .env             # ajusta DATABASE_URL y JWT_SECRET
npm install
npm run dev                      # o: npm start (ofusca el JS y arranca)
```

**Usuarios de demostración** (creados por `03_demo_seed.sql`, solo para uso local):

| Usuario | Contraseña | Rol |
|---|---|---|
| `admin` | `demo1234` | GOD |
| `area` | `demo1234` | Usuario de área |

### Plantillas PDF

Los formatos oficiales que el frontend rellena con pdf-lib (`/PDF/SUFICIENCIA_PRESUPUESTAL_2025.pdf`, `/PDF/comprometido.pdf`, `/PDF/devengado.pdf`) **no se incluyen** en esta versión por ser documentos institucionales. Para generar PDFs, coloca en `server/public/PDF/` plantillas propias con campos de formulario de los mismos nombres. La plantilla de carga masiva se genera con:

```bash
cd server && node scripts/generar_plantilla_suficiencias.mjs
```

## Cómo correr las pruebas

```bash
cd server
npm install
npm test                         # Jest (las pruebas de folios se omiten sin BD)
node --test utils/*.test.js      # pruebas con node:test

# Para incluir las pruebas de folios contra PostgreSQL:
DATABASE_URL_TEST=postgres://USUARIO:PASSWORD@localhost:5432/presupuesto_test npm test
```

---

## English summary

**Control Presupuestal Web** is a municipal budget control system built by Humberto Salvador Ruiz Lucio while working as a developer at a Mexican municipal government. It covers the full spending workflow (budget allocation → availability certificate → commitment → accrual, plus transfers between budget lines), with per-month balance calculation and concurrency-safe folio numbering implemented in PL/pgSQL, audit triggers, and PDF generation for signed forms.

Stack: Node.js/Express REST API, vanilla JavaScript + Bootstrap frontend, PostgreSQL, Docker. Security: JWT (HS256, issuer/audience, 10-minute expiry), bcrypt, role-based access, Helmet, rate limiting, Origin-based CSRF protection, fail-fast env validation and hardened PDF uploads. Tests: 159 Jest/Supertest tests (154 run without a database) plus 2 `node:test` tests.

*Portfolio version: institutional data, configuration and assets were removed. The original system was built for a municipal agency.*
