# ERP Cooperativa · Frontend

Aplicación web (Next.js 14, App Router, TypeScript) conectada a Supabase. Toda la seguridad vive en la base de datos (permisos por puesto y políticas RLS): el navegador solo usa la clave **publishable**, que es pública por diseño. **Nunca** pongas en el frontend la clave `service_role` ni la contraseña de la base.

## Qué incluye hoy
- Inicio de sesión con e-mail y contraseña (y "Olvidé mi contraseña").
- Menú lateral en cascada, contraíble y responsive, que muestra solo lo que el usuario puede ver (`mis_permisos`).
- Modo claro / sistema / oscuro por usuario (se guarda en la base) y color de la organización (azul por defecto).
- **Panel** con los indicadores (`kpi_panel`): importe, porcentaje, variación contra el período anterior y detalle desglosado al tocar cada tarjeta (`kpi_detalle`). Navegación por mes.
- **Configuración → Apariencia** (color de la organización) y **Configuración → Indicadores** (umbrales de los semáforos).
- Las demás pantallas muestran "en construcción": sus datos y reglas ya están en la base.

## Correr en tu computadora
```bash
cd frontend/web
cp .env.example .env.local        # ya trae la URL y la clave publishable de tu proyecto
npm install
npm run dev                       # http://localhost:3000
```

## Publicar en Vercel
1. En Vercel: **Add New → Project** y elegí el repositorio de GitHub.
2. **Root Directory:** `frontend/web` (Next.js se detecta solo).
3. **Environment Variables:** `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (los valores están en `.env.example`).
4. **Deploy**.
5. En Supabase → **Authentication → URL Configuration**: poné la URL de Vercel como *Site URL* y agregá `https://TU-DOMINIO/login` y `http://localhost:3000/login` en *Redirect URLs* (lo usa el restablecimiento de contraseña).

## Primer ingreso
1. Aplicá las migraciones `0001` a `0009` en el SQL Editor, en orden.
2. Creá tu usuario en **Authentication → Users → Add user** (e-mail y contraseña).
3. Ejecutá `select public.inicializar_admin('tu@mail.com');` (solo funciona una vez y te deja como Director).
4. Entrá a la aplicación.

## Estructura
```
app/                  páginas (login, panel, configuración) y estilos globales
components/           menú, barra superior, tarjetas de indicadores, detalle, autenticación
lib/                  cliente de Supabase, tipos, formato (es-AR), tema, definición del menú
```
