-- =====================================================================
-- 0010 · ALTA DE USUARIOS, PROTECCIÓN DEL ÚLTIMO DIRECTOR Y
--        ACTUALIZACIÓN DE MAESTROS CON MOTIVO
-- · lista_usuarios(): usuarios con su e-mail, puestos y último ingreso.
-- · alta_usuario(): da de alta en el sistema a alguien creado antes en
--   Authentication, con sus puestos.
-- · set_puestos_usuario(): reemplaza los puestos de un usuario.
-- · Siempre queda al menos un Director activo con acceso total.
-- · actualizar_con_motivo(): modifica un maestro en una sola operación,
--   con el motivo que exigen los campos críticos (documento, razón social, CBU).
-- Requiere 0001 a 0009. Pegar TODO en SQL Editor → Run.
-- =====================================================================
begin;

do $$ begin
  if not exists (select 1 from public.migraciones where version = '0009') then
    raise exception 'Falta aplicar la migración 0009 antes de esta.';
  end if;
  if exists (select 1 from public.migraciones where version = '0010') then
    raise exception 'La migración 0010 ya fue aplicada: no se puede correr dos veces.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Usuarios
-- ---------------------------------------------------------------------
create or replace function public.lista_usuarios() returns table (
  usuario_id uuid, email text, nombre text, activo boolean, modo_tema text, asociado_id bigint, asociado text,
  puestos text[], puestos_ids bigint[], ultimo_ingreso timestamptz)
language plpgsql stable security definer set search_path = public as
$$
begin
  perform public.exige_permiso('seguridad', 1);
  return query
    select u.id, a.email::text, u.nombre, u.activo, u.modo_tema, u.asociado_id, s.apellido_nombre,
           coalesce((select array_agg(p.nombre order by p.nombre) from public.usuario_puesto up join public.puesto p on p.id = up.puesto_id where up.usuario_id = u.id), '{}'::text[]),
           coalesce((select array_agg(up.puesto_id order by up.puesto_id) from public.usuario_puesto up where up.usuario_id = u.id), '{}'::bigint[]),
           a.last_sign_in_at
      from public.usuario u
      left join auth.users a on a.id = u.id
      left join public.asociado s on s.id = u.asociado_id
     order by u.nombre;
end $$;

-- Da de alta en el sistema a una persona que ya fue creada en Authentication → Users
create or replace function public.alta_usuario(p_email text, p_nombre text default null, p_puestos bigint[] default '{}', p_asociado_id bigint default null)
returns uuid language plpgsql security definer set search_path = public as
$$
declare v_id uuid; v_p bigint;
begin
  perform public.exige_permiso('seguridad', 3);
  if nullif(btrim(coalesce(p_email, '')), '') is null then raise exception 'Indicá el e-mail.'; end if;
  select id into v_id from auth.users where lower(email) = lower(btrim(p_email));
  if v_id is null then
    raise exception 'No existe un usuario con el e-mail % en Authentication. Creálo primero en Supabase → Authentication → Users → Add user.', btrim(p_email);
  end if;
  if exists (select 1 from public.usuario where id = v_id) then raise exception 'Ese usuario ya está dado de alta.'; end if;
  insert into public.usuario (id, nombre, asociado_id) values (v_id, coalesce(nullif(btrim(coalesce(p_nombre, '')), ''), btrim(p_email)), p_asociado_id);
  foreach v_p in array coalesce(p_puestos, '{}') loop
    insert into public.usuario_puesto (usuario_id, puesto_id) values (v_id, v_p) on conflict do nothing;
  end loop;
  return v_id;
end $$;

-- Reemplaza los puestos de un usuario (solo toca lo que cambia)
create or replace function public.set_puestos_usuario(p_usuario uuid, p_puestos bigint[]) returns void
language plpgsql security definer set search_path = public as
$$
declare v_p bigint;
begin
  perform public.exige_permiso('seguridad', 3);
  if not exists (select 1 from public.usuario where id = p_usuario) then raise exception 'No existe el usuario.'; end if;
  delete from public.usuario_puesto where usuario_id = p_usuario and not (puesto_id = any (coalesce(p_puestos, '{}')));
  foreach v_p in array coalesce(p_puestos, '{}') loop
    insert into public.usuario_puesto (usuario_id, puesto_id) values (p_usuario, v_p) on conflict do nothing;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Siempre debe quedar al menos un Director activo con acceso total
-- ---------------------------------------------------------------------
create or replace function public._otro_director_activo(p_excluir uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.usuario u join public.usuario_puesto up on up.usuario_id = u.id join public.puesto p on p.id = up.puesto_id
                   where p.nombre = 'Director' and u.activo and u.id <> p_excluir) $$;

create or replace function public.trg_proteger_director_asignacion() returns trigger
language plpgsql security definer set search_path = public as
$$
begin
  if exists (select 1 from public.puesto where id = old.puesto_id and nombre = 'Director')
     and exists (select 1 from public.usuario where id = old.usuario_id and activo)
     and not public._otro_director_activo(old.usuario_id) then
    raise exception 'Debe quedar al menos un Director activo.' using errcode = '23514';
  end if;
  return old;
end $$;
create trigger trg_proteger_director before delete on public.usuario_puesto
  for each row execute function public.trg_proteger_director_asignacion();

create or replace function public.trg_proteger_director_usuario() returns trigger
language plpgsql security definer set search_path = public as
$$
begin
  if old.activo and not new.activo
     and exists (select 1 from public.usuario_puesto up join public.puesto p on p.id = up.puesto_id where up.usuario_id = old.id and p.nombre = 'Director')
     and not public._otro_director_activo(old.id) then
    raise exception 'Debe quedar al menos un Director activo.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger trg_proteger_director before update of activo on public.usuario
  for each row execute function public.trg_proteger_director_usuario();

create or replace function public.trg_proteger_director_puesto() returns trigger
language plpgsql as
$$
begin
  if old.nombre = 'Director' then
    if tg_op = 'DELETE' then raise exception 'El puesto Director no se puede borrar.' using errcode = '23514'; end if;
    if new.nombre <> old.nombre or not new.activo then raise exception 'El puesto Director no se puede renombrar ni desactivar.' using errcode = '23514'; end if;
  end if;
  return coalesce(new, old);
end $$;
create trigger trg_proteger_director before update or delete on public.puesto
  for each row execute function public.trg_proteger_director_puesto();

create or replace function public.trg_proteger_director_permisos() returns trigger
language plpgsql security definer set search_path = public as
$$
begin
  if exists (select 1 from public.puesto where id = old.puesto_id and nombre = 'Director') and (tg_op = 'DELETE' or new.nivel < 3) then
    raise exception 'El Director siempre tiene acceso total: no se le quitan permisos.' using errcode = '23514';
  end if;
  return coalesce(new, old);
end $$;
create trigger trg_proteger_director before update or delete on public.permiso_puesto
  for each row execute function public.trg_proteger_director_permisos();

-- ---------------------------------------------------------------------
-- Actualizar un maestro en una sola operación, con el motivo de los campos críticos
-- ---------------------------------------------------------------------
create or replace function public.actualizar_con_motivo(p_tabla text, p_id bigint, p_cambios jsonb, p_motivo text default null) returns bigint
language plpgsql security invoker set search_path = public as
$$
declare v_set text; v_n int;
begin
  if p_tabla not in ('cliente','asociado','proveedor','cuenta_bancaria','establecimiento','contacto','servicio') then
    raise exception 'Esa tabla no admite actualización por esta vía.';
  end if;
  if p_cambios is null or jsonb_typeof(p_cambios) <> 'object' then raise exception 'Los cambios deben ser un objeto.'; end if;
  select string_agg(format('%I = r.%I', c.column_name, c.column_name), ', ') into v_set
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = p_tabla and c.is_generated = 'NEVER' and c.is_identity = 'NO'
     and c.column_name not in ('id', 'codigo', 'creado_en', 'actualizado_en') and p_cambios ? c.column_name;
  if v_set is null then raise exception 'No hay cambios para guardar.'; end if;
  perform public.set_motivo(p_motivo);
  execute format('update public.%I t set %s from jsonb_populate_record(null::public.%I, $1) r where t.id = $2', p_tabla, v_set, p_tabla) using p_cambios, p_id;
  get diagnostics v_n = row_count;
  perform public.set_motivo(null);
  if v_n = 0 then raise exception 'No se pudo actualizar: el registro no existe o no tenés permiso.' using errcode = '42501'; end if;
  return p_id;
end $$;

revoke execute on function public.lista_usuarios() from public, anon;
revoke execute on function public.alta_usuario(text, text, bigint[], bigint) from public, anon;
revoke execute on function public.set_puestos_usuario(uuid, bigint[]) from public, anon;
revoke execute on function public.actualizar_con_motivo(text, bigint, jsonb, text) from public, anon;
revoke execute on function public._otro_director_activo(uuid) from public, anon, authenticated;
grant execute on function public.lista_usuarios() to authenticated, service_role;
grant execute on function public.alta_usuario(text, text, bigint[], bigint) to authenticated, service_role;
grant execute on function public.set_puestos_usuario(uuid, bigint[]) to authenticated, service_role;
grant execute on function public.actualizar_con_motivo(text, bigint, jsonb, text) to authenticated, service_role;

insert into public.migraciones (version, descripcion) values ('0010', 'Alta de usuarios, protección del último Director y actualización de maestros con motivo');
commit;
