# ERP Cooperativa de Seguridad e Higiene

ERP interno de una cooperativa de consultoría en Seguridad e Higiene. Registra presupuestos, órdenes de trabajo (OT) y servicios mensuales (SM), costos y gastos, facturas y cobranzas, y reparte el resultado de cada OT entre los asociados. **No emite comprobantes**: los emite ARCA y el sistema solo los registra.

- Base de datos: PostgreSQL en **Supabase** (con RLS).
- Frontend previsto: Next.js en **Vercel**, con el diseño de Yacamba.

## Estructura

| Carpeta | Contenido |
|---|---|
| `docs/` | Documento de diseño consolidado (reglas de negocio y decisiones). |
| `prototipo/` | Prototipo HTML interactivo con la lógica de negocio de referencia. |
| `db/migraciones/` | Scripts SQL numerados, para aplicar **en orden** en el SQL Editor de Supabase. |
| `db/opcionales/` | Scripts que no son migraciones (por ejemplo, programar las tareas automáticas). |
| `db/tests/` | Pruebas automáticas contra un Postgres local (opcionales). |

## Cómo aplicar la base de datos en Supabase

1. Abrir **SQL Editor → New query**.
2. Pegar el contenido completo de `db/migraciones/0001_fundaciones.sql` y ejecutar (**Run**). Cada script corre en una sola transacción: si algo falla, no queda nada a medias.
3. Repetir con `0002_maestros.sql`, y así con los siguientes, **siempre en orden**.
4. Crear el primer usuario en **Authentication → Users** y luego ejecutar:
   ```sql
   select public.inicializar_admin('tu@mail.com');
   ```
   Eso lo deja como *Director* con acceso total. Solo funciona una vez.
5. Opcional: `db/opcionales/programar_tareas.sql` programa el inicio automático de OT y la generación automática de SM (requiere activar la extensión `pg_cron`).
6. Para saber qué está aplicado: `select * from public.migraciones order by version;`

## Reglas para versionar la base

- **Un cambio nuevo = un archivo nuevo** (`0003_...sql`). Nunca se edita un script que ya se aplicó.
- Cada script se anota en `public.migraciones` y rechaza correr dos veces.
- Cada cambio se guarda en un *commit* y, al aplicarlo en Supabase, se marca con una etiqueta (`db-0002`, `db-0003`, …).
- Los textos y datos iniciales (listas, categorías, etc.) se pueden editar desde la app; no hace falta tocar el SQL.

## Pruebas (opcional)

Requieren un Postgres local descartable (no Supabase):

```bash
cd db/tests
PSQL="psql -h localhost -U postgres" ./correr_pruebas.sh
```

Arma una base de prueba, aplica todas las migraciones, corre los escenarios y verifica que cada migración rechace una segunda ejecución. `00_stub_supabase.sql` imita lo mínimo de Supabase y **no se aplica en Supabase**.

## Estado

Ver `CHANGELOG.md`.
