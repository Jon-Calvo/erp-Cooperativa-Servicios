-- =====================================================================
-- 0001 · FUNDACIONES
-- ERP Cooperativa de Seguridad e Higiene · Supabase / PostgreSQL
-- Contenido: registro de migraciones, numeración de códigos, listas
-- editables, Organización, seguridad (usuarios, puestos, permisos),
-- auditoría y ayudas para preparar tablas (RLS, auditoría, fecha de
-- modificación).
-- Cómo aplicar: pegar TODO este archivo en Supabase → SQL Editor → Run.
-- Corre en una sola transacción: si algo falla, no queda nada a medias.
-- =====================================================================
begin;

create table if not exists public.migraciones (
  version     text primary key,
  descripcion text not null,
  aplicada_en timestamptz not null default now()
);

do $$ begin
  if exists (select 1 from public.migraciones where version = '0001') then
    raise exception 'La migración 0001 ya fue aplicada: no se puede correr dos veces.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Utilidades generales
-- ---------------------------------------------------------------------
create or replace function public.hoy_ar() returns date
language sql stable as
$$ select (now() at time zone 'America/Argentina/Buenos_Aires')::date $$;

create or replace function public.set_actualizado() returns trigger
language plpgsql as
$$ begin new.actualizado_en := now(); return new; end $$;

-- ---------------------------------------------------------------------
-- Numeración de códigos
--   Documentos: PREFIJO-AAAA-NNNNN (reinicia cada año)
--   Maestros:   PREFIJO-NNNNN      (continuo)
-- ---------------------------------------------------------------------
create table public.contador (
  clave  text   not null,
  anio   int    not null default 0,
  ultimo bigint not null default 0,
  primary key (clave, anio)
);
alter table public.contador enable row level security;   -- sin políticas: solo las funciones de abajo lo tocan

create or replace function public.siguiente_codigo(p_prefijo text, p_con_anio boolean default false)
returns text language plpgsql security definer set search_path = public as
$$
declare
  v_anio int := case when p_con_anio then extract(year from public.hoy_ar())::int else 0 end;
  v_n    bigint;
begin
  insert into public.contador (clave, anio, ultimo) values (p_prefijo, v_anio, 1)
  on conflict (clave, anio) do update set ultimo = public.contador.ultimo + 1
  returning ultimo into v_n;
  return p_prefijo || '-' || case when p_con_anio then v_anio::text || '-' else '' end || lpad(v_n::text, 5, '0');
end $$;

-- Trigger: completa "codigo" al insertar. Uso: execute function public.trg_codigo('CLI','f')
create or replace function public.trg_codigo() returns trigger
language plpgsql as
$$
begin
  if new.codigo is null or new.codigo = '' then
    new.codigo := public.siguiente_codigo(tg_argv[0], coalesce(tg_argv[1], 'f') = 't');
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Listas editables (tipo de cliente, rubro, especialidad, banco, etc.)
-- Una sola tabla de valores; cada columna que la usa se ata a su lista
-- con una clave compuesta (no se puede cargar un valor de otra lista).
-- ---------------------------------------------------------------------
create table public.lista (
  clave       text primary key,
  nombre      text not null,
  descripcion text
);

create table public.lista_valor (
  id             bigint generated always as identity primary key,
  lista          text not null references public.lista (clave) on update cascade,
  nombre         text not null check (btrim(nombre) <> ''),
  orden          int  not null default 0,
  activo         boolean not null default true,
  datos          jsonb not null default '{}'::jsonb,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (lista, nombre),
  unique (id, lista)
);

-- ---------------------------------------------------------------------
-- Organización (una sola fila) y su historial de condición ante IVA
-- ---------------------------------------------------------------------
create table public.organizacion (
  id                      boolean primary key default true check (id),
  razon_social            text not null default '',
  nombre_fantasia         text,
  cuit                    text,
  domicilio               text,
  telefono                text,
  email                   text,
  web                     text,
  logo_path               text,
  firma_path              text,
  texto_firma             text,
  condiciones_comerciales text,
  -- parámetros de configuración
  aprobar_gastos          boolean not null default false,
  inicio_auto_ot          boolean not null default true,
  generar_sm_auto         boolean not null default false,
  umbral_mono_aviso       numeric(5,2) not null default 80  check (umbral_mono_aviso between 0 and 100),
  umbral_mono_critico     numeric(5,2) not null default 95  check (umbral_mono_critico between 0 and 100),
  validez_presupuesto_dias int not null default 30 check (validez_presupuesto_dias > 0),
  dias_seguimiento        int not null default 7  check (dias_seguimiento > 0),
  modo_iva                text not null default 'por_linea' check (modo_iva in ('por_linea','en_subtotal')),
  iva_defecto             numeric(5,2) not null default 21,
  usa_descuentos          boolean not null default false,
  limite_contactos        int not null default 5 check (limite_contactos > 0),
  reabrir_linea_rechazada boolean not null default true,
  cierre_ejercicio_dia    smallint not null default 31 check (cierre_ejercicio_dia between 1 and 31),
  cierre_ejercicio_mes    smallint not null default 12 check (cierre_ejercicio_mes between 1 and 12),
  actualizado_en          timestamptz not null default now()
);
insert into public.organizacion (id) values (true);

create table public.organizacion_condicion_iva (
  desde     date primary key,
  condicion text not null check (condicion in ('Resp. Inscripto','Monotributo','Exento'))
);
-- La Cooperativa es hoy Responsable Inscripta. Si cambia, se agrega una fila nueva con "desde".
insert into public.organizacion_condicion_iva (desde, condicion) values (date '2000-01-01', 'Resp. Inscripto');

create or replace function public.condicion_iva_coop(p_fecha date default public.hoy_ar())
returns text language sql stable as
$$ select condicion from public.organizacion_condicion_iva where desde <= p_fecha order by desde desc limit 1 $$;

-- ---------------------------------------------------------------------
-- Seguridad: usuarios, puestos y permisos
-- ---------------------------------------------------------------------
create table public.modulo (
  clave  text primary key,
  nombre text not null,
  orden  int  not null default 0
);

create table public.puesto (
  id             bigint generated always as identity primary key,
  nombre         text not null unique,
  descripcion    text,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

-- Usuario = cuenta de acceso (Authentication). El vínculo con un Asociado se agrega en 0002.
create table public.usuario (
  id             uuid primary key references auth.users (id) on delete cascade,
  nombre         text not null,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table public.usuario_puesto (            -- muchos a muchos
  usuario_id uuid   not null references public.usuario (id) on delete cascade,
  puesto_id  bigint not null references public.puesto (id) on delete cascade,
  primary key (usuario_id, puesto_id)
);

-- Nivel: 0 sin acceso · 1 solo lectura · 2 operar · 3 administrar
create table public.permiso_puesto (
  puesto_id bigint   not null references public.puesto (id) on delete cascade,
  modulo    text     not null references public.modulo (clave) on update cascade on delete cascade,
  nivel     smallint not null check (nivel between 0 and 3),
  primary key (puesto_id, modulo)
);

-- Excepciones puntuales por usuario (pisan a los puestos)
create table public.permiso_usuario (
  usuario_id uuid     not null references public.usuario (id) on delete cascade,
  modulo     text     not null references public.modulo (clave) on update cascade on delete cascade,
  nivel      smallint not null check (nivel between 0 and 3),
  primary key (usuario_id, modulo)
);

-- Alta de módulos: el puesto Director queda siempre con nivel 3.
create or replace function public.registrar_modulo(p_clave text, p_nombre text, p_orden int default 0)
returns void language plpgsql as
$$
declare v_dir bigint;
begin
  insert into public.modulo (clave, nombre, orden) values (p_clave, p_nombre, p_orden)
  on conflict (clave) do update set nombre = excluded.nombre, orden = excluded.orden;
  select id into v_dir from public.puesto where nombre = 'Director';
  if v_dir is not null then
    insert into public.permiso_puesto (puesto_id, modulo, nivel) values (v_dir, p_clave, 3)
    on conflict (puesto_id, modulo) do nothing;
  end if;
end $$;

insert into public.puesto (nombre, descripcion) values ('Director', 'Acceso total. Se crea con la base y no debe borrarse.');

select public.registrar_modulo('organizacion', 'Organización',   10);
select public.registrar_modulo('seguridad',    'Seguridad',      20);
select public.registrar_modulo('maestros',     'Maestros',       30);
select public.registrar_modulo('comercial',    'Comercial',      40);
select public.registrar_modulo('operaciones',  'Operaciones',    50);
select public.registrar_modulo('costos',       'Costos y gastos',60);
select public.registrar_modulo('distribucion', 'Distribución',   70);
select public.registrar_modulo('facturacion',  'Facturación',    80);
select public.registrar_modulo('cobranza',     'Cobranza',       90);
select public.registrar_modulo('monotributo',  'Monotributo',   100);
select public.registrar_modulo('calendario',   'Calendario',    110);
select public.registrar_modulo('bancos',       'Bancos',        120);
select public.registrar_modulo('contabilidad', 'Contabilidad',  130);
select public.registrar_modulo('auditoria',    'Auditoría',     140);

-- ¿El usuario de la sesión está activo?
create or replace function public.es_usuario_activo() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.usuario where id = auth.uid() and activo) $$;

-- ¿Tiene al menos el nivel pedido en el módulo? La excepción por usuario manda; si no hay, vale el mayor nivel de sus puestos.
create or replace function public.tiene_permiso(p_modulo text, p_nivel int) returns boolean
language sql stable security definer set search_path = public as
$$
  select case
    when not exists (select 1 from public.usuario where id = auth.uid() and activo) then false
    else coalesce(
      (select pu.nivel >= p_nivel from public.permiso_usuario pu
        where pu.usuario_id = auth.uid() and pu.modulo = p_modulo),
      (select coalesce(max(pp.nivel), 0) >= p_nivel
         from public.usuario_puesto up
         join public.permiso_puesto pp on pp.puesto_id = up.puesto_id
        where up.usuario_id = auth.uid() and pp.modulo = p_modulo),
      false)
  end
$$;

-- ---------------------------------------------------------------------
-- Auditoría
-- ---------------------------------------------------------------------
create table public.log_auditoria (
  id             bigint generated always as identity primary key,
  tabla          text not null,
  registro_id    text,
  operacion      text not null check (operacion in ('alta','cambio','baja')),
  campo          text,
  valor_anterior text,
  valor_nuevo    text,
  usuario_id     uuid,
  fecha          timestamptz not null default now(),
  motivo         text
);
create index on public.log_auditoria (tabla, registro_id);
create index on public.log_auditoria (fecha);

create table public.log_acceso (
  id         bigint generated always as identity primary key,
  usuario_id uuid not null,
  evento     text not null,
  fecha      timestamptz not null default now()
);

-- Motivo del cambio: se fija dentro de la misma transacción antes de modificar.
create or replace function public.set_motivo(p_motivo text) returns void
language plpgsql as
$$ begin perform set_config('app.motivo', coalesce(p_motivo, ''), true); end $$;

create or replace function public.trg_auditoria() returns trigger
language plpgsql security definer set search_path = public as
$$
declare
  v_pk  text := coalesce(tg_argv[0], 'id');
  v_old jsonb; v_new jsonb; k text;
  v_mot text := nullif(current_setting('app.motivo', true), '');
begin
  if tg_op = 'INSERT' then
    v_new := to_jsonb(new);
    insert into public.log_auditoria (tabla, registro_id, operacion, usuario_id, motivo)
    values (tg_table_name, v_new ->> v_pk, 'alta', auth.uid(), v_mot);
    return new;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new);
    for k in select jsonb_object_keys(v_new) loop
      if k <> 'actualizado_en' and (v_old -> k) is distinct from (v_new -> k) then
        insert into public.log_auditoria (tabla, registro_id, operacion, campo, valor_anterior, valor_nuevo, usuario_id, motivo)
        values (tg_table_name, v_new ->> v_pk, 'cambio', k, v_old ->> k, v_new ->> k, auth.uid(), v_mot);
      end if;
    end loop;
    return new;
  else
    v_old := to_jsonb(old);
    insert into public.log_auditoria (tabla, registro_id, operacion, usuario_id, motivo)
    values (tg_table_name, v_old ->> v_pk, 'baja', auth.uid(), v_mot);
    return old;
  end if;
end $$;

-- Campos críticos: cambiarlos exige permiso Administrar en Maestros y un motivo.
-- (Sin sesión de usuario, como desde el SQL Editor, solo se exige el motivo.)
-- Uso: execute function public.trg_campos_criticos('nro_doc','razon_social')
create or replace function public.trg_campos_criticos() returns trigger
language plpgsql security definer set search_path = public as
$$
declare k text; v_old jsonb := to_jsonb(old); v_new jsonb := to_jsonb(new);
begin
  foreach k in array tg_argv loop
    if (v_old -> k) is distinct from (v_new -> k) then
      if auth.uid() is not null and not public.tiene_permiso('maestros', 3) then
        raise exception 'Cambiar "%" requiere permiso de administración en Maestros.', k using errcode = '42501';
      end if;
      if nullif(current_setting('app.motivo', true), '') is null then
        raise exception 'Cambiar "%" requiere indicar un motivo.', k using errcode = '23514';
      end if;
    end if;
  end loop;
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Ayuda para preparar cada tabla: fecha de modificación + auditoría + RLS
--   p_lectura_libre: cualquier usuario activo puede leer (catálogos)
--   p_nivel_escritura: nivel mínimo para insertar y modificar (2 operar, 3 administrar)
--   p_borrado: si se permite borrar (siempre exige nivel 3)
-- ---------------------------------------------------------------------
create or replace function public.preparar_tabla(
  p_tabla text, p_modulo text, p_pk text default 'id',
  p_lectura_libre boolean default false, p_nivel_escritura int default 2, p_borrado boolean default true)
returns void language plpgsql as
$$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = p_tabla and column_name = 'actualizado_en') then
    execute format('drop trigger if exists trg_actualizado on public.%I', p_tabla);
    execute format('create trigger trg_actualizado before update on public.%I for each row execute function public.set_actualizado()', p_tabla);
  end if;

  execute format('drop trigger if exists trg_auditoria on public.%I', p_tabla);
  execute format('create trigger trg_auditoria after insert or update or delete on public.%I for each row execute function public.trg_auditoria(%L)', p_tabla, p_pk);

  execute format('alter table public.%I enable row level security', p_tabla);
  execute format('drop policy if exists p_sel on public.%I', p_tabla);
  execute format('drop policy if exists p_ins on public.%I', p_tabla);
  execute format('drop policy if exists p_upd on public.%I', p_tabla);
  execute format('drop policy if exists p_del on public.%I', p_tabla);

  if p_lectura_libre then
    execute format('create policy p_sel on public.%I for select to authenticated using (public.es_usuario_activo())', p_tabla);
  else
    execute format('create policy p_sel on public.%I for select to authenticated using (public.tiene_permiso(%L, 1))', p_tabla, p_modulo);
  end if;
  execute format('create policy p_ins on public.%I for insert to authenticated with check (public.tiene_permiso(%L, %s))', p_tabla, p_modulo, p_nivel_escritura);
  execute format('create policy p_upd on public.%I for update to authenticated using (public.tiene_permiso(%L, %s)) with check (public.tiene_permiso(%L, %s))', p_tabla, p_modulo, p_nivel_escritura, p_modulo, p_nivel_escritura);
  if p_borrado then
    execute format('create policy p_del on public.%I for delete to authenticated using (public.tiene_permiso(%L, 3))', p_tabla, p_modulo);
  end if;
end $$;

-- Tablas de esta migración
select public.preparar_tabla('lista',        'maestros',     'clave', true,  3, false);
select public.preparar_tabla('lista_valor',  'maestros',     'id',    true,  3, true);
select public.preparar_tabla('organizacion', 'organizacion', 'id',    true,  3, false);
select public.preparar_tabla('organizacion_condicion_iva', 'organizacion', 'desde', true, 3, false);
select public.preparar_tabla('modulo',       'seguridad',    'clave', true,  3, false);
select public.preparar_tabla('puesto',       'seguridad',    'id',    true,  3, true);
select public.preparar_tabla('usuario',      'seguridad',    'id',    false, 3, false);
select public.preparar_tabla('permiso_puesto', 'seguridad',  'puesto_id', true, 3, true);

-- usuario_puesto y permiso_usuario: cada uno ve lo suyo; la administración ve todo
select public.preparar_tabla('usuario_puesto',  'seguridad', 'usuario_id', false, 3, true);
select public.preparar_tabla('permiso_usuario', 'seguridad', 'usuario_id', false, 3, true);
drop policy p_sel on public.usuario;
create policy p_sel on public.usuario for select to authenticated
  using (id = auth.uid() or public.tiene_permiso('seguridad', 1));
drop policy p_sel on public.usuario_puesto;
create policy p_sel on public.usuario_puesto for select to authenticated
  using (usuario_id = auth.uid() or public.tiene_permiso('seguridad', 1));
drop policy p_sel on public.permiso_usuario;
create policy p_sel on public.permiso_usuario for select to authenticated
  using (usuario_id = auth.uid() or public.tiene_permiso('seguridad', 1));

-- Logs: se leen con permiso de Auditoría; las filas de auditoría solo las escriben los triggers
alter table public.log_auditoria enable row level security;
create policy p_sel on public.log_auditoria for select to authenticated using (public.tiene_permiso('auditoria', 1));
alter table public.log_acceso enable row level security;
create policy p_sel on public.log_acceso for select to authenticated using (public.tiene_permiso('auditoria', 1));
create policy p_ins on public.log_acceso for insert to authenticated with check (usuario_id = auth.uid());

-- ---------------------------------------------------------------------
-- Administrador inicial: se crea una sola vez, desde el SQL Editor.
--   1) Crear el usuario en Authentication → Users.
--   2) select public.inicializar_admin('su@mail.com');
-- ---------------------------------------------------------------------
create or replace function public.inicializar_admin(p_email text) returns text
language plpgsql security definer set search_path = public as
$$
declare v_uid uuid; v_dir bigint;
begin
  if exists (select 1 from public.usuario) then
    raise exception 'Ya hay usuarios cargados: el administrador inicial se crea una sola vez.';
  end if;
  select id into v_uid from auth.users where lower(email) = lower(p_email);
  if v_uid is null then
    raise exception 'No existe un usuario con el e-mail % en Authentication. Crealo primero en Authentication → Users.', p_email;
  end if;
  select id into v_dir from public.puesto where nombre = 'Director';
  insert into public.usuario (id, nombre) values (v_uid, p_email);
  insert into public.usuario_puesto (usuario_id, puesto_id) values (v_uid, v_dir);
  return 'Administrador inicial creado: ' || p_email;
end $$;
revoke all on function public.inicializar_admin(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Seguridad de las funciones: en Supabase todas las funciones de "public" quedan
-- invocables por la API; se cierra lo que no debe usar un visitante anónimo.
-- ---------------------------------------------------------------------
revoke execute on function public.siguiente_codigo(text, boolean) from public, anon;
grant  execute on function public.siguiente_codigo(text, boolean) to authenticated, service_role;
revoke execute on function public.preparar_tabla(text, text, text, boolean, int, boolean) from public, anon, authenticated;
revoke execute on function public.registrar_modulo(text, text, int) from public, anon, authenticated;

insert into public.migraciones (version, descripcion) values ('0001', 'Fundaciones: numeración, listas, organización, seguridad, auditoría');
commit;
