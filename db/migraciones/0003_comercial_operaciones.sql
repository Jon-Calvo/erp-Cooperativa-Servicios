-- =====================================================================
-- 0003 · COMERCIAL Y OPERACIONES
-- Presupuestos (versiones, líneas, seguimiento, decisión por línea),
-- órdenes de trabajo (OT), equipo de la OT y servicios mensuales (SM).
-- Requiere 0001 y 0002. Pegar TODO en SQL Editor → Run.
--
-- Las acciones con reglas (enviar, aprobar, rechazar, reabrir, nueva versión,
-- cambiar estado de OT, generar OT de SM) son FUNCIONES: el frontend las
-- llama con rpc(); los estados no se pueden cambiar con un update directo.
-- =====================================================================
begin;

do $$ begin
  if not exists (select 1 from public.migraciones where version = '0002') then
    raise exception 'Falta aplicar la migración 0002 antes de esta.';
  end if;
  if exists (select 1 from public.migraciones where version = '0003') then
    raise exception 'La migración 0003 ya fue aplicada: no se puede correr dos veces.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Ayudas generales
-- ---------------------------------------------------------------------
-- Exige permiso. Sin sesión de usuario (SQL Editor o tareas programadas) no se exige.
create or replace function public.exige_permiso(p_modulo text, p_nivel int) returns void
language plpgsql stable security definer set search_path = public as
$$
begin
  if auth.uid() is not null and not public.tiene_permiso(p_modulo, p_nivel) then
    raise exception 'No tenés permiso para esta operación (módulo %).', p_modulo using errcode = '42501';
  end if;
end $$;

-- Marca "esto lo hace una función del sistema": habilita cambios de estado.
create or replace function public.via_funcion(p boolean) returns void
language plpgsql as
$$ begin perform set_config('app.via_funcion', case when p then '1' else '0' end, true); end $$;

create or replace function public.en_funcion() returns boolean
language sql stable as
$$ select coalesce(current_setting('app.via_funcion', true), '0') = '1' $$;

-- IVA sugerido según quién emite: Exento y Monotributo → 0; el resto → IVA por defecto de la Organización
create or replace function public.iva_sugerido_emisor(p_tipo text, p_asociado_id bigint default null, p_fecha date default public.hoy_ar())
returns numeric language plpgsql stable as
$$
declare v_cond text;
begin
  if p_tipo = 'cooperativa' then
    v_cond := public.condicion_iva_coop(p_fecha);
  else
    select condicion_iva into v_cond from public.asociado where id = p_asociado_id;
  end if;
  return case when v_cond in ('Exento','Monotributo') then 0 else (select iva_defecto from public.organizacion) end;
end $$;

-- ---------------------------------------------------------------------
-- Presupuestos
--   Cada versión es una fila: mismo código, distinta versión.
--   Estados: borrador → enviado → procesado (todas las líneas con decisión);
--   la versión anterior queda "reemplazado".
-- ---------------------------------------------------------------------
create table public.presupuesto (
  id bigint generated always as identity primary key,
  codigo text not null,
  version int not null default 1 check (version >= 1),
  estado text not null default 'borrador' check (estado in ('borrador','enviado','procesado','reemplazado')),
  emisor_tipo text not null default 'cooperativa' check (emisor_tipo in ('cooperativa','asociado')),
  emisor_asociado_id bigint references public.asociado (id),
  plantilla_id bigint references public.plantilla_presupuesto (id),
  cliente_id bigint not null references public.cliente (id),
  establecimiento_id bigint not null references public.establecimiento (id),     -- establecimiento de cabecera
  contacto_id bigint references public.contacto (id),
  contacto_nombre text, contacto_telefono text, contacto_email text,              -- copia editable del contacto elegido
  fecha_realizacion date not null default public.hoy_ar(),
  fecha_envio date,
  validez_dias int not null,                                                      -- se copian de la Organización al crear
  dias_seguimiento int not null,
  iva_modo text not null check (iva_modo in ('por_linea','en_subtotal')),
  iva_general numeric(5,2) not null check (iva_general between 0 and 100),        -- IVA del subtotal (o sugerido por línea)
  texto_condiciones text,                                                         -- copia editable del texto de la plantilla
  comentarios text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (codigo, version),
  check ((emisor_tipo = 'asociado') = (emisor_asociado_id is not null)),
  check (estado = 'borrador' or fecha_envio is not null)
);
create index on public.presupuesto (cliente_id);
create index on public.presupuesto (estado);

create table public.presupuesto_linea (
  id bigint generated always as identity primary key,
  presupuesto_id bigint not null references public.presupuesto (id) on delete cascade,
  orden int not null,
  servicio_id bigint not null references public.servicio (id),
  establecimiento_id bigint not null references public.establecimiento (id),     -- hereda el de cabecera; editable por línea
  cantidad numeric(14,3) not null check (cantidad > 0),
  unidad_id bigint, unidad_lista text generated always as ('unidad_medida') stored,
  descripcion text,
  precio_unitario numeric(18,2) not null check (precio_unitario >= 0),            -- sin IVA; editable en la línea
  precio_catalogo numeric(18,2),                                                  -- precio del servicio al momento de armar la línea
  precio_modificado boolean generated always as (precio_catalogo is not null and precio_unitario <> precio_catalogo) stored,
  descuento_pct numeric(5,2) not null default 0 check (descuento_pct between 0 and 100),
  iva_pct numeric(5,2) not null check (iva_pct between 0 and 100),
  neto numeric(18,2) generated always as (round(cantidad * precio_unitario * (1 - descuento_pct / 100), 2)) stored,
  estado text not null default 'pendiente' check (estado in ('pendiente','aprobada','rechazada')),
  motivo_rechazo_id bigint, motivo_rechazo_lista text generated always as ('motivo_rechazo') stored,
  comentario_decision text,
  fecha_decision date,
  unique (presupuesto_id, orden),
  check ((estado = 'rechazada') = (motivo_rechazo_id is not null)),
  foreign key (unidad_id, unidad_lista) references public.lista_valor (id, lista),
  foreign key (motivo_rechazo_id, motivo_rechazo_lista) references public.lista_valor (id, lista)
);
create index on public.presupuesto_linea (presupuesto_id);

create table public.presupuesto_seguimiento (
  id bigint generated always as identity primary key,
  presupuesto_id bigint not null references public.presupuesto (id) on delete cascade,
  fecha date not null default public.hoy_ar(),
  nota text,
  usuario_id uuid default auth.uid(),
  creado_en timestamptz not null default now()
);
create index on public.presupuesto_seguimiento (presupuesto_id, fecha);

-- Totales, vencimiento y próximo seguimiento (derivados: no se guardan)
create view public.presupuesto_resumen with (security_invoker = true) as
select p.id, p.codigo, p.version, p.estado, p.cliente_id, p.fecha_envio,
       coalesce(t.neto, 0) as neto,
       case when p.iva_modo = 'por_linea' then coalesce(t.iva_lineas, 0)
            else round(coalesce(t.neto, 0) * p.iva_general / 100, 2) end as iva,
       coalesce(t.neto, 0) + case when p.iva_modo = 'por_linea' then coalesce(t.iva_lineas, 0)
            else round(coalesce(t.neto, 0) * p.iva_general / 100, 2) end as total,
       coalesce(t.lineas, 0) as lineas, coalesce(t.pendientes, 0) as lineas_pendientes,
       coalesce(t.aprobadas, 0) as lineas_aprobadas, coalesce(t.rechazadas, 0) as lineas_rechazadas,
       case when p.estado = 'enviado' then p.fecha_envio + p.validez_dias end as vence_el,
       case when p.estado = 'enviado' then coalesce(s.ultimo, p.fecha_envio) + p.dias_seguimiento end as proximo_seguimiento
  from public.presupuesto p
  left join lateral (
    select sum(l.neto) as neto, sum(round(l.neto * l.iva_pct / 100, 2)) as iva_lineas, count(*) as lineas,
           count(*) filter (where l.estado = 'pendiente') as pendientes,
           count(*) filter (where l.estado = 'aprobada') as aprobadas,
           count(*) filter (where l.estado = 'rechazada') as rechazadas
      from public.presupuesto_linea l where l.presupuesto_id = p.id) t on true
  left join lateral (
    select max(fecha) as ultimo from public.presupuesto_seguimiento where presupuesto_id = p.id) s on true;

-- ---------------------------------------------------------------------
-- Servicios mensuales (SM): contrato marco con precio mensual versionado
-- ---------------------------------------------------------------------
create table public.sm (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  cliente_id bigint not null references public.cliente (id),
  establecimiento_id bigint not null references public.establecimiento (id),
  servicio_id bigint not null references public.servicio (id),
  dia_generacion smallint not null check (dia_generacion between 1 and 28),
  dia_inicio smallint not null check (dia_inicio between 1 and 28),
  fecha_inicio date not null,
  fecha_fin date,                                    -- genera una alerta; no corta nada solo
  responsable_id bigint not null references public.asociado (id),
  estado text not null default 'activo' check (estado in ('activo','suspendido','finalizado')),
  observacion text,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  check (fecha_fin is null or fecha_fin >= fecha_inicio)
);
create index on public.sm (cliente_id);

create table public.sm_precio (                       -- se versiona: solo hacia adelante
  id bigint generated always as identity primary key,
  sm_id bigint not null references public.sm (id),
  vigente_desde date not null check (vigente_desde = date_trunc('month', vigente_desde)::date),
  precio numeric(18,2) not null check (precio >= 0),  -- neto mensual, sin IVA
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(),
  unique (sm_id, vigente_desde)
);

-- ---------------------------------------------------------------------
-- Órdenes de trabajo (OT): una OT = un servicio en un establecimiento
-- ---------------------------------------------------------------------
create table public.ot (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  origen text not null check (origen in ('presupuesto','sm','directa')),
  presupuesto_linea_id bigint unique references public.presupuesto_linea (id),
  sm_id bigint references public.sm (id),
  periodo date check (periodo = date_trunc('month', periodo)::date),
  cliente_id bigint not null references public.cliente (id),
  establecimiento_id bigint not null references public.establecimiento (id),
  servicio_id bigint not null references public.servicio (id),
  responsable_id bigint not null references public.asociado (id),
  inicio_previsto date not null,
  inicio_real date,
  finalizada_en date,
  cerrada_en timestamptz,
  neto numeric(18,2) not null check (neto >= 0),
  modalidad text not null default 'servicio' check (modalidad in ('servicio','regalia')),
  modo_dist_parcial text not null default 'proporcional' check (modo_dist_parcial in ('proporcional','costos_primero')),
  requiere_anticipo boolean not null default false,
  anticipo_monto numeric(18,2) check (anticipo_monto >= 0),
  estado text not null default 'pendiente' check (estado in ('pendiente','en_ejecucion','finalizada','cerrada','cancelada')),
  motivo_directa text,                               -- obligatorio si la OT se creó sin presupuesto
  autorizado_por uuid,
  motivo_cancelacion text,
  observacion text,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  check (origen <> 'directa' or nullif(btrim(coalesce(motivo_directa, '')), '') is not null),
  check ((origen = 'presupuesto') = (presupuesto_linea_id is not null)),
  check ((origen = 'sm') = (sm_id is not null)),
  check (estado not in ('en_ejecucion','finalizada','cerrada') or inicio_real is not null)
);
create unique index ot_sm_periodo on public.ot (sm_id, periodo) where origen = 'sm' and estado <> 'cancelada';
create index on public.ot (cliente_id);
create index on public.ot (estado);
create index on public.ot (responsable_id);

create table public.ot_equipo (                        -- asociados que acompañan al responsable
  ot_id bigint not null references public.ot (id) on delete cascade,
  asociado_id bigint not null references public.asociado (id),
  primary key (ot_id, asociado_id)
);

-- Vista de SM: precio vigente, último período generado y alerta de fin
create view public.sm_resumen with (security_invoker = true) as
select s.id, s.codigo, s.cliente_id, s.estado, s.fecha_fin,
       (select p.precio from public.sm_precio p where p.sm_id = s.id and p.vigente_desde <= public.hoy_ar()
         order by p.vigente_desde desc limit 1) as precio_vigente,
       (select max(o.periodo) from public.ot o where o.sm_id = s.id and o.estado <> 'cancelada') as ultimo_periodo_generado,
       case when s.fecha_fin is not null and s.estado = 'activo' then s.fecha_fin - public.hoy_ar() end as dias_para_fin
  from public.sm s;

-- ---------------------------------------------------------------------
-- Reglas de integridad (triggers)
-- ---------------------------------------------------------------------
-- Presupuesto: alta
create or replace function public.trg_pres_antes() returns trigger
language plpgsql as
$$
declare o public.organizacion; v_ok boolean; v_texto text;
begin
  select * into o from public.organizacion;
  new.validez_dias     := coalesce(new.validez_dias, o.validez_presupuesto_dias);
  new.dias_seguimiento := coalesce(new.dias_seguimiento, o.dias_seguimiento);
  new.iva_modo         := coalesce(new.iva_modo, o.modo_iva);
  new.iva_general      := coalesce(new.iva_general, o.iva_defecto);
  if not public.en_funcion() then            -- un alta directa siempre es la versión 1 en borrador
    new.codigo := null; new.version := 1; new.estado := 'borrador'; new.fecha_envio := null;
  end if;
  if not exists (select 1 from public.establecimiento e where e.id = new.establecimiento_id and e.cliente_id = new.cliente_id) then
    raise exception 'El establecimiento no pertenece al cliente del presupuesto.' using errcode = '23514';
  end if;
  if new.contacto_id is not null then
    select exists (select 1 from public.contacto c where c.id = new.contacto_id and c.cliente_id = new.cliente_id) into v_ok;
    if not v_ok then raise exception 'El contacto no pertenece al cliente del presupuesto.' using errcode = '23514'; end if;
  end if;
  if new.contacto_id is not null and new.contacto_nombre is null then
    select c.nombre, c.telefono, c.email into new.contacto_nombre, new.contacto_telefono, new.contacto_email
      from public.contacto c where c.id = new.contacto_id;
  end if;
  if new.emisor_asociado_id is not null
     and exists (select 1 from public.asociado a where a.id = new.emisor_asociado_id and a.estado = 'baja') then
    raise exception 'El asociado emisor está dado de baja.' using errcode = '23514';
  end if;
  if new.texto_condiciones is null and new.plantilla_id is not null then
    select texto_condiciones into v_texto from public.plantilla_presupuesto where id = new.plantilla_id;
    new.texto_condiciones := v_texto;
  end if;
  return new;
end $$;
create trigger trg_a_pres_antes before insert on public.presupuesto
  for each row execute function public.trg_pres_antes();
create trigger trg_codigo before insert on public.presupuesto
  for each row execute function public.trg_codigo('PRE','t');

-- Presupuesto: un enviado no se edita (salvo comentarios); el estado solo cambia por funciones
create or replace function public.trg_pres_guard() returns trigger
language plpgsql as
$$
begin
  if tg_op = 'DELETE' then
    if old.estado <> 'borrador' and not public.en_funcion() then
      raise exception 'Solo se pueden borrar presupuestos en borrador.' using errcode = '23514';
    end if;
    return old;
  end if;
  if not public.en_funcion() then
    if new.estado is distinct from old.estado then
      raise exception 'El estado del presupuesto cambia con las funciones del sistema (enviar, aprobar, etc.).' using errcode = '23514';
    end if;
    if old.estado <> 'borrador'
       and (to_jsonb(new) - 'comentarios' - 'actualizado_en') is distinct from (to_jsonb(old) - 'comentarios' - 'actualizado_en') then
      raise exception 'Un presupuesto enviado no se edita: creá una nueva versión.' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger trg_b_pres_guard before update or delete on public.presupuesto
  for each row execute function public.trg_pres_guard();

-- Línea de presupuesto
create or replace function public.trg_linea_guard() returns trigger
language plpgsql as
$$
declare h record; s record; v_pv numeric;
begin
  select estado, cliente_id, establecimiento_id, iva_general into h
    from public.presupuesto where id = coalesce(new.presupuesto_id, old.presupuesto_id);

  if tg_op = 'DELETE' then
    if h.estado <> 'borrador' and not public.en_funcion() then
      raise exception 'Las líneas de un presupuesto enviado no se borran.' using errcode = '23514';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and not public.en_funcion() then
    if (new.estado, new.motivo_rechazo_id, new.comentario_decision, new.fecha_decision)
       is distinct from (old.estado, old.motivo_rechazo_id, old.comentario_decision, old.fecha_decision) then
      raise exception 'La decisión de una línea se registra con aprobar_linea / rechazar_linea / reabrir_linea.' using errcode = '23514';
    end if;
    if h.estado <> 'borrador'
       and (to_jsonb(new) - 'estado' - 'motivo_rechazo_id' - 'comentario_decision' - 'fecha_decision')
           is distinct from (to_jsonb(old) - 'estado' - 'motivo_rechazo_id' - 'comentario_decision' - 'fecha_decision') then
      raise exception 'Un presupuesto enviado no se edita: creá una nueva versión.' using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT' then
    if h.estado <> 'borrador' and not public.en_funcion() then
      raise exception 'Solo se agregan líneas a un presupuesto en borrador.' using errcode = '23514';
    end if;
    if not public.en_funcion() then
      new.estado := 'pendiente'; new.motivo_rechazo_id := null; new.comentario_decision := null; new.fecha_decision := null;
    end if;
    select * into s from public.servicio where id = new.servicio_id;
    if new.unidad_id is null then new.unidad_id := s.unidad_id; end if;          -- la unidad viene del servicio
    if new.descripcion is null then new.descripcion := coalesce(s.descripcion, s.nombre); end if;
    if new.establecimiento_id is null then new.establecimiento_id := h.establecimiento_id; end if;
    if new.precio_catalogo is null then
      select precio_ars into v_pv from public.servicio_vigente where servicio_id = new.servicio_id;
      new.precio_catalogo := v_pv;
    end if;
    if new.precio_unitario is null then new.precio_unitario := coalesce(new.precio_catalogo, 0); end if;
    if new.iva_pct is null then new.iva_pct := h.iva_general; end if;
    if new.orden is null then
      select coalesce(max(orden), 0) + 1 into new.orden from public.presupuesto_linea where presupuesto_id = new.presupuesto_id;
    end if;
  end if;

  if not exists (select 1 from public.establecimiento e where e.id = new.establecimiento_id and e.cliente_id = h.cliente_id) then
    raise exception 'El establecimiento de la línea no pertenece al cliente del presupuesto.' using errcode = '23514';
  end if;
  if new.descuento_pct > 0 and not (select usa_descuentos from public.organizacion) then
    raise exception 'Los descuentos no están habilitados en la configuración.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger trg_linea_guard before insert or update or delete on public.presupuesto_linea
  for each row execute function public.trg_linea_guard();

-- Seguimiento: solo mientras el presupuesto está "enviado"
create or replace function public.trg_seguimiento_estado() returns trigger
language plpgsql as
$$
declare h record;
begin
  select estado, fecha_envio into h from public.presupuesto where id = new.presupuesto_id;
  if h.estado <> 'enviado' then
    raise exception 'Solo se registra seguimiento en presupuestos enviados.' using errcode = '23514';
  end if;
  if new.fecha < h.fecha_envio then
    raise exception 'El seguimiento no puede ser anterior a la fecha de envío.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger trg_seguimiento before insert on public.presupuesto_seguimiento
  for each row execute function public.trg_seguimiento_estado();

-- SM: el precio solo se versiona hacia adelante
create or replace function public.trg_sm_precio() returns trigger
language plpgsql as
$$
declare v_ult date;
begin
  select max(periodo) into v_ult from public.ot where sm_id = new.sm_id and estado <> 'cancelada';
  if v_ult is not null and new.vigente_desde <= v_ult then
    raise exception 'El precio solo se ajusta hacia adelante: ya hay una OT generada hasta %.', to_char(v_ult, 'MM/YYYY') using errcode = '23514';
  end if;
  return new;
end $$;
create trigger trg_sm_precio before insert on public.sm_precio
  for each row execute function public.trg_sm_precio();

create or replace function public.trg_sm_antes() returns trigger
language plpgsql as
$$
begin
  if not exists (select 1 from public.establecimiento e where e.id = new.establecimiento_id and e.cliente_id = new.cliente_id) then
    raise exception 'El establecimiento no pertenece al cliente.' using errcode = '23514';
  end if;
  if exists (select 1 from public.asociado a where a.id = new.responsable_id and a.estado = 'baja')
     and (tg_op = 'INSERT' or new.responsable_id is distinct from old.responsable_id) then
    raise exception 'El asociado está dado de baja: no admite nuevas asignaciones.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger trg_antes before insert or update on public.sm
  for each row execute function public.trg_sm_antes();
create trigger trg_codigo before insert on public.sm
  for each row execute function public.trg_codigo('SM','f');

-- OT
create or replace function public.trg_ot_antes() returns trigger
language plpgsql as
$$
begin
  if tg_op = 'INSERT' then
    if not public.en_funcion() then
      if new.origen <> 'directa' then
        raise exception 'Las OT de presupuesto y de SM se generan desde su función (aprobar_linea / generar_ot_sm).' using errcode = '23514';
      end if;
      new.estado := 'pendiente'; new.inicio_real := null; new.finalizada_en := null; new.cerrada_en := null;
    end if;
    if new.origen = 'directa' then new.autorizado_por := coalesce(new.autorizado_por, auth.uid()); end if;
    new.periodo := coalesce(new.periodo, date_trunc('month', new.inicio_previsto)::date);
  else
    if not public.en_funcion() then
      if new.estado is distinct from old.estado or new.inicio_real is distinct from old.inicio_real
         or new.cerrada_en is distinct from old.cerrada_en or new.finalizada_en is distinct from old.finalizada_en then
        raise exception 'El estado de la OT cambia con cambiar_estado_ot.' using errcode = '23514';
      end if;
      if old.estado in ('cerrada','cancelada')
         and (to_jsonb(new) - 'observacion' - 'actualizado_en') is distinct from (to_jsonb(old) - 'observacion' - 'actualizado_en') then
        raise exception 'Una OT % no se modifica.', old.estado using errcode = '23514';
      end if;
    end if;
  end if;
  if not exists (select 1 from public.establecimiento e where e.id = new.establecimiento_id and e.cliente_id = new.cliente_id) then
    raise exception 'El establecimiento no pertenece al cliente de la OT.' using errcode = '23514';
  end if;
  if (tg_op = 'INSERT' or new.responsable_id is distinct from old.responsable_id)
     and exists (select 1 from public.asociado a where a.id = new.responsable_id and a.estado = 'baja') then
    raise exception 'El asociado está dado de baja: no admite nuevas asignaciones.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger trg_a_ot_antes before insert or update on public.ot
  for each row execute function public.trg_ot_antes();
create trigger trg_codigo before insert on public.ot
  for each row execute function public.trg_codigo('OT','t');

create or replace function public.trg_ot_equipo() returns trigger
language plpgsql as
$$
declare v_estado text;
begin
  select estado into v_estado from public.ot where id = coalesce(new.ot_id, old.ot_id);
  if v_estado in ('cerrada','cancelada') then
    raise exception 'La OT está % : no se modifica su equipo.', v_estado using errcode = '23514';
  end if;
  if tg_op <> 'DELETE' and exists (select 1 from public.asociado a where a.id = new.asociado_id and a.estado = 'baja') then
    raise exception 'El asociado está dado de baja: no admite nuevas asignaciones.' using errcode = '23514';
  end if;
  return coalesce(new, old);
end $$;
create trigger trg_equipo before insert or update or delete on public.ot_equipo
  for each row execute function public.trg_ot_equipo();

-- ---------------------------------------------------------------------
-- Funciones de Comercial
-- ---------------------------------------------------------------------
create or replace function public.recalcular_estado_presupuesto(p_id bigint) returns void
language plpgsql security definer set search_path = public as
$$
declare v_estado text; v_pend int;
begin
  select estado into v_estado from public.presupuesto where id = p_id;
  select count(*) into v_pend from public.presupuesto_linea where presupuesto_id = p_id and estado = 'pendiente';
  if v_estado = 'enviado' and v_pend = 0 then
    update public.presupuesto set estado = 'procesado' where id = p_id;
  elsif v_estado = 'procesado' and v_pend > 0 then
    update public.presupuesto set estado = 'enviado' where id = p_id;
  end if;
end $$;
revoke execute on function public.recalcular_estado_presupuesto(bigint) from public, anon, authenticated;

create or replace function public.enviar_presupuesto(p_id bigint, p_fecha date default public.hoy_ar()) returns void
language plpgsql security definer set search_path = public as
$$
declare v public.presupuesto;
begin
  perform public.exige_permiso('comercial', 2);
  select * into v from public.presupuesto where id = p_id for update;
  if not found then raise exception 'No existe el presupuesto %.', p_id; end if;
  if v.estado <> 'borrador' then raise exception 'Solo se envía un presupuesto en borrador (está %).', v.estado; end if;
  if not exists (select 1 from public.presupuesto_linea where presupuesto_id = p_id) then
    raise exception 'El presupuesto no tiene líneas.';
  end if;
  perform public.via_funcion(true);
  update public.presupuesto set estado = 'enviado', fecha_envio = p_fecha where id = p_id;
  perform public.via_funcion(false);
end $$;

create or replace function public.nueva_version_presupuesto(p_id bigint) returns bigint
language plpgsql security definer set search_path = public as
$$
declare v public.presupuesto; v_new bigint;
begin
  perform public.exige_permiso('comercial', 2);
  select * into v from public.presupuesto where id = p_id for update;
  if not found then raise exception 'No existe el presupuesto %.', p_id; end if;
  if v.estado <> 'enviado' then raise exception 'Solo se versiona un presupuesto enviado (está %).', v.estado; end if;
  if exists (select 1 from public.presupuesto_linea where presupuesto_id = p_id and estado = 'aprobada') then
    raise exception 'Hay líneas aprobadas con OT generada: no se puede crear una nueva versión.';
  end if;
  perform public.via_funcion(true);
  insert into public.presupuesto (codigo, version, estado, emisor_tipo, emisor_asociado_id, plantilla_id, cliente_id, establecimiento_id,
                                  contacto_id, contacto_nombre, contacto_telefono, contacto_email, fecha_realizacion,
                                  iva_modo, iva_general, texto_condiciones, comentarios)
  values (v.codigo, v.version + 1, 'borrador', v.emisor_tipo, v.emisor_asociado_id, v.plantilla_id, v.cliente_id, v.establecimiento_id,
          v.contacto_id, v.contacto_nombre, v.contacto_telefono, v.contacto_email, public.hoy_ar(),
          v.iva_modo, v.iva_general, v.texto_condiciones, v.comentarios)
  returning id into v_new;
  insert into public.presupuesto_linea (presupuesto_id, orden, servicio_id, establecimiento_id, cantidad, unidad_id, descripcion,
                                        precio_unitario, precio_catalogo, descuento_pct, iva_pct)
  select v_new, orden, servicio_id, establecimiento_id, cantidad, unidad_id, descripcion,
         precio_unitario, precio_catalogo, descuento_pct, iva_pct
    from public.presupuesto_linea where presupuesto_id = p_id order by orden;
  update public.presupuesto set estado = 'reemplazado' where id = p_id;
  perform public.via_funcion(false);
  return v_new;
end $$;

create or replace function public.aprobar_linea(p_linea_id bigint, p_inicio_previsto date, p_responsable_id bigint default null,
                                                p_requiere_anticipo boolean default false, p_anticipo_monto numeric default null)
returns bigint language plpgsql security definer set search_path = public as
$$
declare l public.presupuesto_linea; p public.presupuesto; v_resp bigint; v_ot bigint; v_cli_estado text;
begin
  perform public.exige_permiso('comercial', 2);
  select * into l from public.presupuesto_linea where id = p_linea_id for update;
  if not found then raise exception 'No existe la línea %.', p_linea_id; end if;
  select * into p from public.presupuesto where id = l.presupuesto_id for update;
  if p.estado <> 'enviado' then raise exception 'Solo se deciden líneas de un presupuesto enviado (está %).', p.estado; end if;
  if l.estado <> 'pendiente' then raise exception 'La línea ya tiene una decisión (%).', l.estado; end if;
  if p_inicio_previsto is null then raise exception 'Indicá la fecha de inicio previsto de la OT.'; end if;
  select estado into v_cli_estado from public.cliente where id = p.cliente_id;
  if v_cli_estado = 'inactivo' then raise exception 'El cliente está inactivo.'; end if;
  v_resp := coalesce(p_responsable_id, p.emisor_asociado_id);
  if v_resp is null then raise exception 'Indicá el responsable de la OT.'; end if;

  perform public.via_funcion(true);
  insert into public.ot (origen, presupuesto_linea_id, cliente_id, establecimiento_id, servicio_id, responsable_id,
                         inicio_previsto, neto, requiere_anticipo, anticipo_monto, observacion)
  values ('presupuesto', l.id, p.cliente_id, l.establecimiento_id, l.servicio_id, v_resp,
          p_inicio_previsto, l.neto, coalesce(p_requiere_anticipo, false), p_anticipo_monto, l.descripcion)
  returning id into v_ot;
  update public.presupuesto_linea set estado = 'aprobada', fecha_decision = public.hoy_ar() where id = l.id;
  update public.cliente set estado = 'activo' where id = p.cliente_id and estado = 'prospecto';   -- el prospecto pasa a activo
  perform public.recalcular_estado_presupuesto(p.id);
  perform public.via_funcion(false);
  return v_ot;
end $$;

create or replace function public.rechazar_linea(p_linea_id bigint, p_motivo_id bigint, p_comentario text default null) returns void
language plpgsql security definer set search_path = public as
$$
declare l public.presupuesto_linea; p public.presupuesto;
begin
  perform public.exige_permiso('comercial', 2);
  if p_motivo_id is null then raise exception 'El motivo del rechazo es obligatorio.'; end if;
  select * into l from public.presupuesto_linea where id = p_linea_id for update;
  if not found then raise exception 'No existe la línea %.', p_linea_id; end if;
  select * into p from public.presupuesto where id = l.presupuesto_id for update;
  if p.estado <> 'enviado' then raise exception 'Solo se deciden líneas de un presupuesto enviado (está %).', p.estado; end if;
  if l.estado <> 'pendiente' then raise exception 'La línea ya tiene una decisión (%).', l.estado; end if;
  perform public.via_funcion(true);
  update public.presupuesto_linea
     set estado = 'rechazada', motivo_rechazo_id = p_motivo_id, comentario_decision = p_comentario, fecha_decision = public.hoy_ar()
   where id = l.id;
  perform public.recalcular_estado_presupuesto(p.id);
  perform public.via_funcion(false);
end $$;

create or replace function public.reabrir_linea(p_linea_id bigint) returns void
language plpgsql security definer set search_path = public as
$$
declare l public.presupuesto_linea; p public.presupuesto;
begin
  perform public.exige_permiso('comercial', 2);
  if not (select reabrir_linea_rechazada from public.organizacion) then
    raise exception 'La reapertura de líneas rechazadas está desactivada en la configuración.';
  end if;
  select * into l from public.presupuesto_linea where id = p_linea_id for update;
  if not found then raise exception 'No existe la línea %.', p_linea_id; end if;
  if l.estado <> 'rechazada' then raise exception 'Solo se reabre una línea rechazada (está %).', l.estado; end if;
  select * into p from public.presupuesto where id = l.presupuesto_id for update;
  if p.estado not in ('enviado','procesado') then raise exception 'El presupuesto está %: no se reabren sus líneas.', p.estado; end if;
  perform public.via_funcion(true);
  update public.presupuesto_linea
     set estado = 'pendiente', motivo_rechazo_id = null, comentario_decision = null, fecha_decision = null
   where id = l.id;
  perform public.recalcular_estado_presupuesto(p.id);    -- un procesado vuelve a enviado
  perform public.via_funcion(false);
end $$;

-- ---------------------------------------------------------------------
-- Funciones de Operaciones
-- ---------------------------------------------------------------------
create or replace function public.cambiar_estado_ot(p_ot bigint, p_estado text, p_motivo text default null) returns void
language plpgsql security definer set search_path = public as
$$
declare v public.ot; v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  perform public.exige_permiso('operaciones', 2);
  select * into v from public.ot where id = p_ot for update;
  if not found then raise exception 'No existe la OT %.', p_ot; end if;
  if (v.estado, p_estado) not in (('pendiente','en_ejecucion'),('pendiente','cancelada'),('en_ejecucion','finalizada'),
        ('en_ejecucion','cancelada'),('finalizada','cerrada'),('finalizada','en_ejecucion'),('cerrada','finalizada')) then
    raise exception 'Transición no permitida: % → %.', v.estado, p_estado;
  end if;
  if p_estado = 'cancelada' and v_mot is null then raise exception 'Cancelar una OT exige un motivo.'; end if;
  if v.estado = 'cerrada' then                                  -- reapertura: auditada y solo con permiso de administración
    perform public.exige_permiso('operaciones', 3);
    if v_mot is null then raise exception 'Reabrir una OT cerrada exige un motivo.'; end if;
  end if;
  if v.estado = 'finalizada' and p_estado = 'en_ejecucion' and v_mot is null then
    raise exception 'Reanudar una OT finalizada exige un motivo.';
  end if;
  perform public.via_funcion(true);
  perform public.set_motivo(v_mot);
  update public.ot set
      estado = p_estado,
      inicio_real = case when p_estado = 'en_ejecucion' and inicio_real is null then public.hoy_ar() else inicio_real end,
      finalizada_en = case when p_estado = 'finalizada' then public.hoy_ar() when p_estado = 'en_ejecucion' then null else finalizada_en end,
      cerrada_en = case when p_estado = 'cerrada' then now() when v.estado = 'cerrada' then null else cerrada_en end,
      motivo_cancelacion = case when p_estado = 'cancelada' then v_mot else motivo_cancelacion end
    where id = p_ot;
  perform public.set_motivo(null);
  perform public.via_funcion(false);
end $$;

-- Pasa a "en ejecución" las OT pendientes cuya fecha de inicio llegó (si la Organización lo tiene activado)
create or replace function public.iniciar_ots_vencidas(p_fecha date default public.hoy_ar()) returns int
language plpgsql security definer set search_path = public as
$$
declare n int;
begin
  perform public.exige_permiso('operaciones', 2);
  if not (select inicio_auto_ot from public.organizacion) then return 0; end if;
  perform public.via_funcion(true);
  update public.ot set estado = 'en_ejecucion', inicio_real = p_fecha
   where estado = 'pendiente' and inicio_previsto <= p_fecha;
  get diagnostics n = row_count;
  perform public.via_funcion(false);
  return n;
end $$;

create or replace function public.sm_precio_en(p_sm bigint, p_periodo date) returns numeric
language sql stable as
$$ select precio from public.sm_precio where sm_id = p_sm and vigente_desde <= date_trunc('month', p_periodo)::date
    order by vigente_desde desc limit 1 $$;

-- Genera la OT de un período del SM (manual; también se puede regenerar si la anterior se canceló)
create or replace function public.generar_ot_sm(p_sm bigint, p_periodo date default public.hoy_ar()) returns bigint
language plpgsql security definer set search_path = public as
$$
declare s public.sm; v_per date := date_trunc('month', p_periodo)::date; v_precio numeric; v_ot bigint;
begin
  perform public.exige_permiso('operaciones', 2);
  select * into s from public.sm where id = p_sm for update;
  if not found then raise exception 'No existe el SM %.', p_sm; end if;
  if s.estado <> 'activo' then raise exception 'El SM está % : no genera OT.', s.estado; end if;
  if v_per < date_trunc('month', s.fecha_inicio)::date then raise exception 'El período es anterior al inicio del contrato.'; end if;
  v_precio := public.sm_precio_en(p_sm, v_per);
  if v_precio is null then raise exception 'El SM no tiene precio para ese período.'; end if;
  if exists (select 1 from public.ot where sm_id = p_sm and periodo = v_per and estado <> 'cancelada') then
    raise exception 'Ya existe una OT activa de ese período.';
  end if;
  perform public.via_funcion(true);
  insert into public.ot (origen, sm_id, periodo, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
  values ('sm', s.id, v_per, s.cliente_id, s.establecimiento_id, s.servicio_id, s.responsable_id, v_per + (s.dia_inicio - 1), v_precio)
  returning id into v_ot;
  perform public.via_funcion(false);
  return v_ot;
end $$;

-- Generación automática (si la Organización la tiene activada): una OT por SM activo y por mes,
-- a partir del día de generación. Nunca regenera un período ya generado, aunque se haya cancelado.
create or replace function public.generar_ots_sm_pendientes(p_fecha date default public.hoy_ar()) returns int
language plpgsql security definer set search_path = public as
$$
declare s record; n int := 0; v_per date := date_trunc('month', p_fecha)::date;
begin
  perform public.exige_permiso('operaciones', 2);
  if not (select generar_sm_auto from public.organizacion) then return 0; end if;
  for s in select * from public.sm
            where estado = 'activo' and fecha_inicio <= p_fecha
              and extract(day from p_fecha) >= dia_generacion
              and public.sm_precio_en(id, v_per) is not null
              and not exists (select 1 from public.ot o where o.sm_id = sm.id and o.periodo = v_per)
  loop
    perform public.generar_ot_sm(s.id, v_per);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- Auditoría y permisos
-- ---------------------------------------------------------------------
select public.preparar_tabla('presupuesto',             'comercial',   'id', false, 2, true);
select public.preparar_tabla('presupuesto_linea',       'comercial',   'id', false, 2, true);
select public.preparar_tabla('presupuesto_seguimiento', 'comercial',   'id', false, 2, false);
select public.preparar_tabla('sm',                      'operaciones', 'id', false, 2, false);
select public.preparar_tabla('sm_precio',               'operaciones', 'id', false, 2, false);
select public.preparar_tabla('ot',                      'operaciones', 'id', false, 2, false);
select public.preparar_tabla('ot_equipo',               'operaciones', 'ot_id', false, 2, true);

drop policy p_upd on public.presupuesto_seguimiento;   -- el seguimiento no se edita
drop policy p_upd on public.sm_precio;                 -- los precios solo se agregan

-- Funciones expuestas solo a usuarios con sesión (nunca a visitantes anónimos)
revoke execute on function public.enviar_presupuesto(bigint, date) from public, anon;
revoke execute on function public.nueva_version_presupuesto(bigint) from public, anon;
revoke execute on function public.aprobar_linea(bigint, date, bigint, boolean, numeric) from public, anon;
revoke execute on function public.rechazar_linea(bigint, bigint, text) from public, anon;
revoke execute on function public.reabrir_linea(bigint) from public, anon;
revoke execute on function public.cambiar_estado_ot(bigint, text, text) from public, anon;
revoke execute on function public.iniciar_ots_vencidas(date) from public, anon;
revoke execute on function public.generar_ot_sm(bigint, date) from public, anon;
revoke execute on function public.generar_ots_sm_pendientes(date) from public, anon;
revoke execute on function public.exige_permiso(text, int) from public, anon;
grant execute on function public.enviar_presupuesto(bigint, date) to authenticated, service_role;
grant execute on function public.nueva_version_presupuesto(bigint) to authenticated, service_role;
grant execute on function public.aprobar_linea(bigint, date, bigint, boolean, numeric) to authenticated, service_role;
grant execute on function public.rechazar_linea(bigint, bigint, text) to authenticated, service_role;
grant execute on function public.reabrir_linea(bigint) to authenticated, service_role;
grant execute on function public.cambiar_estado_ot(bigint, text, text) to authenticated, service_role;
grant execute on function public.iniciar_ots_vencidas(date) to authenticated, service_role;
grant execute on function public.generar_ot_sm(bigint, date) to authenticated, service_role;
grant execute on function public.generar_ots_sm_pendientes(date) to authenticated, service_role;
grant execute on function public.exige_permiso(text, int) to authenticated, service_role;

insert into public.migraciones (version, descripcion) values ('0003', 'Comercial y Operaciones: presupuestos, líneas, seguimiento, OT, equipo, SM');
commit;
