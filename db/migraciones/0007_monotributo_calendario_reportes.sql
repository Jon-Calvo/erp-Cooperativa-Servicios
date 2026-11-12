-- =====================================================================
-- 0007 · MONOTRIBUTO, CALENDARIO Y REPORTES
-- Control del límite de facturación de cada asociado, calendario unificado
-- (eventos derivados del estado de cada entidad + recordatorios manuales) y
-- reportes: facturas por cobrar y por pagar, libros de IVA ventas y compras.
-- Requiere 0001 a 0006. Pegar TODO en SQL Editor → Run.
-- =====================================================================
begin;

do $$ begin
  if not exists (select 1 from public.migraciones where version = '0006') then
    raise exception 'Falta aplicar la migración 0006 antes de esta.';
  end if;
  if exists (select 1 from public.migraciones where version = '0007') then
    raise exception 'La migración 0007 ya fue aplicada: no se puede correr dos veces.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Monotributo: límites (versionados), ingresos externos y ajustes
-- ---------------------------------------------------------------------
create table public.monotributo_limite (
  id bigint generated always as identity primary key,
  asociado_id bigint not null references public.asociado (id),
  vigente_desde date not null,
  limite numeric(18,2) not null check (limite > 0),
  observacion text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(),
  unique (asociado_id, vigente_desde)
);

create table public.monotributo_ingreso_externo (          -- facturas propias y transferencias por fuera del circuito
  id bigint generated always as identity primary key,
  asociado_id bigint not null references public.asociado (id),
  fecha date not null,
  tipo text not null check (tipo in ('factura_propia','transferencia')),
  importe numeric(18,2) not null check (importe > 0),
  concepto text,
  anulado boolean not null default false,
  anulado_en timestamptz, anulado_motivo text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now()
);
create index on public.monotributo_ingreso_externo (asociado_id, fecha);

create table public.monotributo_ajuste (                    -- calibra el acumulado sin migrar historia
  id bigint generated always as identity primary key,
  asociado_id bigint not null references public.asociado (id),
  fecha date not null default public.hoy_ar(),
  importe numeric(18,2) not null check (importe <> 0),
  motivo text not null check (btrim(motivo) <> ''),
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now()
);
create index on public.monotributo_ajuste (asociado_id, fecha);

create or replace function public.puede_ver_monotributo(p_asociado bigint) returns boolean
language sql stable security definer set search_path = public as
$$ select public.tiene_permiso('monotributo', 1)
       or exists (select 1 from public.usuario u where u.id = auth.uid() and u.activo and u.asociado_id = p_asociado) $$;

-- Período de control de un asociado: anual o semestral, desde su propio aniversario (sin aniversario: año calendario)
create or replace function public.monotributo_periodo(p_asociado bigint, p_fecha date default public.hoy_ar())
returns table (desde date, hasta date)
language plpgsql stable security definer set search_path = public as
$$
declare a public.asociado; v_paso int; v_ini date; v_m int; v_d int;
begin
  select * into a from public.asociado where id = p_asociado;
  if not found then raise exception 'No existe el asociado.'; end if;
  v_paso := case when a.periodicidad_control = 'semestral' then 6 else 12 end;
  v_m := extract(month from coalesce(a.aniversario_periodo, make_date(2000, 1, 1)))::int;
  v_d := least(extract(day from coalesce(a.aniversario_periodo, make_date(2000, 1, 1)))::int, 28);
  select max(s) into v_ini
    from (select (make_date(extract(year from p_fecha)::int, v_m, v_d) + (n * v_paso) * interval '1 month')::date as s
            from generate_series(-6, 6) n) x
   where s <= p_fecha;
  desde := v_ini; hasta := (v_ini + v_paso * interval '1 month')::date - 1;
  return next;
end $$;

create or replace function public.monotributo_limite_en(p_asociado bigint, p_fecha date default public.hoy_ar()) returns numeric
language sql stable security definer set search_path = public as
$$ select limite from public.monotributo_limite where asociado_id = p_asociado and vigente_desde <= p_fecha order by vigente_desde desc limit 1 $$;

create or replace function public._semaforo(p_pct numeric, p_limite numeric) returns text
language sql stable security definer set search_path = public as
$$
  select case when p_limite is null then 'sin_limite'
              when p_pct >= 100 then 'excedido'
              when p_pct >= (select umbral_mono_critico from public.organizacion) then 'rojo'
              when p_pct >= (select umbral_mono_aviso from public.organizacion) then 'amarillo'
              else 'verde' end
$$;

-- Qué cuenta en el acumulado del período:
--   · facturas que emitió el asociado (vigentes: con sus ND y NC)
--   · facturas que le hizo a la Cooperativa
--   · transferencias de la Cooperativa SIN factura (nunca se cuenta dos veces un mismo pago: lo pagado contra factura ya cuenta por la factura)
--   · ingresos externos y ajustes
create or replace function public._monotributo_detalle(p_asociado bigint, p_fecha date) returns table (fecha date, tipo text, referencia text, importe numeric)
language sql stable security definer set search_path = public as
$$
  with per as (select * from public.monotributo_periodo(p_asociado, p_fecha))
  select f.fecha, 'factura'::text, f.codigo || coalesce(' · ' || f.punto_venta || '-' || f.numero, ' · interna'), r.total_vigente
    from public.factura f join public.factura_resumen r on r.id = f.id, per
   where f.clase = 'factura' and f.estado_doc = 'emitida' and f.emisor_asociado_id = p_asociado and f.fecha between per.desde and per.hasta
  union all
  select fp.fecha, 'factura_a_cooperativa', fp.codigo || ' · ' || fp.nro_comprobante, fp.total
    from public.factura_proveedor fp, per
   where fp.asociado_id = p_asociado and not fp.anulada and fp.fecha between per.desde and per.hasta
  union all
  select l.fecha, 'transferencia_sin_factura', l.codigo, l.importe
    from public.liquidacion l, per
   where l.asociado_id = p_asociado and l.sentido = 'a_asociado' and l.factura_proveedor_id is null and not l.anulada and l.fecha between per.desde and per.hasta
  union all
  select e.fecha, 'externo_' || e.tipo, coalesce(e.concepto, 'Ingreso externo'), e.importe
    from public.monotributo_ingreso_externo e, per
   where e.asociado_id = p_asociado and not e.anulado and e.fecha between per.desde and per.hasta
  union all
  select a.fecha, 'ajuste', a.motivo, a.importe
    from public.monotributo_ajuste a, per
   where a.asociado_id = p_asociado and a.fecha between per.desde and per.hasta
$$;

create or replace function public.monotributo_detalle(p_asociado bigint, p_fecha date default public.hoy_ar())
returns table (fecha date, tipo text, referencia text, importe numeric)
language plpgsql stable security definer set search_path = public as
$$
begin
  if auth.uid() is not null and not public.puede_ver_monotributo(p_asociado) then
    raise exception 'No tenés permiso para ver el monotributo de este asociado.' using errcode = '42501';
  end if;
  return query select d.fecha, d.tipo, d.referencia, d.importe from public._monotributo_detalle(p_asociado, p_fecha) d order by 1, 2;
end $$;

create or replace function public._monotributo_resumen(p_asociado bigint, p_fecha date) returns table (
  asociado_id bigint, apellido_nombre text, desde date, hasta date, facturas numeric, facturas_a_cooperativa numeric,
  transferencias numeric, externos numeric, ajustes numeric, total numeric, limite numeric, pct numeric, semaforo text)
language plpgsql stable security definer set search_path = public as
$$
declare a public.asociado; p record; v_tot numeric; v_lim numeric; v_pct numeric;
begin
  select * into a from public.asociado where id = p_asociado;
  select * into p from public.monotributo_periodo(p_asociado, p_fecha);
  select coalesce(sum(importe) filter (where tipo = 'factura'), 0), coalesce(sum(importe) filter (where tipo = 'factura_a_cooperativa'), 0),
         coalesce(sum(importe) filter (where tipo = 'transferencia_sin_factura'), 0),
         coalesce(sum(importe) filter (where tipo like 'externo_%'), 0), coalesce(sum(importe) filter (where tipo = 'ajuste'), 0)
    into facturas, facturas_a_cooperativa, transferencias, externos, ajustes
    from public._monotributo_detalle(p_asociado, p_fecha);
  v_tot := facturas + facturas_a_cooperativa + transferencias + externos + ajustes;
  v_lim := public.monotributo_limite_en(p_asociado, p_fecha);
  v_pct := case when v_lim > 0 then round(v_tot * 100 / v_lim, 2) end;
  asociado_id := p_asociado; apellido_nombre := a.apellido_nombre; desde := p.desde; hasta := p.hasta;
  total := v_tot; limite := v_lim; pct := v_pct;
  semaforo := case when a.condicion_iva <> 'Monotributo' then 'no_aplica' else public._semaforo(v_pct, v_lim) end;
  return next;
end $$;

create or replace function public.monotributo_resumen(p_asociado bigint, p_fecha date default public.hoy_ar())
returns table (asociado_id bigint, apellido_nombre text, desde date, hasta date, facturas numeric, facturas_a_cooperativa numeric,
               transferencias numeric, externos numeric, ajustes numeric, total numeric, limite numeric, pct numeric, semaforo text)
language plpgsql stable security definer set search_path = public as
$$
begin
  if auth.uid() is not null and not public.puede_ver_monotributo(p_asociado) then
    raise exception 'No tenés permiso para ver el monotributo de este asociado.' using errcode = '42501';
  end if;
  return query select * from public._monotributo_resumen(p_asociado, p_fecha);
end $$;

-- Estado de todos los asociados monotributistas que no están de baja
create or replace function public.monotributo_estado(p_fecha date default public.hoy_ar())
returns table (asociado_id bigint, apellido_nombre text, desde date, hasta date, facturas numeric, facturas_a_cooperativa numeric,
               transferencias numeric, externos numeric, ajustes numeric, total numeric, limite numeric, pct numeric, semaforo text)
language plpgsql stable security definer set search_path = public as
$$
declare a record;
begin
  for a in select x.id from public.asociado x where x.condicion_iva = 'Monotributo' and x.estado <> 'baja' and public.puede_ver_monotributo(x.id) order by x.apellido_nombre loop
    return query select * from public._monotributo_resumen(a.id, p_fecha);
  end loop;
end $$;

-- Al elegir el emisor de una factura: cómo quedaría cada asociado si se le suma este monto, y cuánto margen tiene
create or replace function public.monotributo_proyeccion(p_monto numeric, p_fecha date default public.hoy_ar())
returns table (asociado_id bigint, apellido_nombre text, total numeric, limite numeric, pct_actual numeric, pct_con_monto numeric,
               semaforo_actual text, semaforo_con_monto text, disponible numeric)
language plpgsql stable security definer set search_path = public as
$$
declare r record;
begin
  if auth.uid() is not null and not (public.tiene_permiso('facturacion', 2) or public.tiene_permiso('monotributo', 1)) then
    raise exception 'No tenés permiso para consultar el monotributo.' using errcode = '42501';
  end if;
  for r in select m.* from public.asociado a, lateral public._monotributo_resumen(a.id, p_fecha) m
            where a.condicion_iva = 'Monotributo' and a.estado = 'activo' order by m.apellido_nombre loop
    asociado_id := r.asociado_id; apellido_nombre := r.apellido_nombre; total := r.total; limite := r.limite;
    pct_actual := r.pct;
    pct_con_monto := case when r.limite > 0 then round((r.total + coalesce(p_monto, 0)) * 100 / r.limite, 2) end;
    semaforo_actual := r.semaforo;
    semaforo_con_monto := public._semaforo(pct_con_monto, r.limite);
    disponible := case when r.limite is not null then r.limite - r.total end;
    return next;
  end loop;
end $$;

create or replace function public.anular_ingreso_externo(p_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as
$$
declare v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  perform public.exige_permiso('monotributo', 3);
  if v_mot is null then raise exception 'El motivo es obligatorio.'; end if;
  update public.monotributo_ingreso_externo set anulado = true, anulado_en = now(), anulado_motivo = v_mot where id = p_id and not anulado;
  if not found then raise exception 'El ingreso no existe o ya está anulado.'; end if;
end $$;

-- ---------------------------------------------------------------------
-- Recordatorios manuales (lo único del calendario que se guarda)
-- ---------------------------------------------------------------------
create table public.recordatorio (
  id bigint generated always as identity primary key,
  fecha date not null,
  titulo text not null check (btrim(titulo) <> ''),
  detalle text,
  usuario_id uuid not null default auth.uid(),
  compartido boolean not null default false,
  cumplido boolean not null default false,
  cumplido_en timestamptz,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now()
);
create index on public.recordatorio (fecha);

-- ---------------------------------------------------------------------
-- Calendario unificado: eventos derivados del estado de cada entidad
-- ---------------------------------------------------------------------
create view public.calendario_eventos with (security_invoker = true) as
  -- Comercial
  select r.proximo_seguimiento as fecha, 'presupuesto_seguimiento'::text as tipo, 'comercial'::text as modulo,
         ('Seguimiento del presupuesto ' || r.codigo)::text as titulo, null::text as detalle, 'presupuesto'::text as entidad, r.id as entidad_id,
         false as cumplido, 'media'::text as prioridad
    from public.presupuesto_resumen r where r.estado = 'enviado' and r.proximo_seguimiento is not null
  union all
  select r.vence_el, 'presupuesto_vence', 'comercial', 'Vence el presupuesto ' || r.codigo, null, 'presupuesto', r.id, false, 'media'
    from public.presupuesto_resumen r where r.estado = 'enviado' and r.vence_el is not null
  -- Operaciones
  union all
  select o.inicio_previsto, 'ot_inicio', 'operaciones', 'Inicio de ' || o.codigo, null, 'ot', o.id, o.estado <> 'pendiente', 'media'
    from public.ot o where o.estado <> 'cancelada'
  union all
  select coalesce(o.finalizada_en, public.hoy_ar()), 'ot_facturar', 'operaciones', 'Facturar ' || o.codigo || ' (finalizada sin facturar completo)', null, 'ot', o.id, false, 'alta'
    from public.ot o join public.ot_facturacion f on f.ot_id = o.id
   where o.estado = 'finalizada' and f.estado_facturacion in ('sin_facturar','parcial')
  union all
  select s.fecha_fin, 'sm_fin', 'operaciones', 'Fin previsto del servicio mensual ' || s.codigo, null, 'sm', s.id, false, 'media'
    from public.sm s where s.estado = 'activo' and s.fecha_fin is not null
  union all
  select make_date(extract(year from public.hoy_ar())::int, extract(month from public.hoy_ar())::int, s.dia_generacion::int),
         'sm_generar', 'operaciones', 'Generar la OT del mes de ' || s.codigo, null, 'sm', s.id, false, 'media'
    from public.sm s
   where s.estado = 'activo' and s.fecha_inicio <= (date_trunc('month', public.hoy_ar()) + interval '1 month - 1 day')::date
     and not exists (select 1 from public.ot o where o.sm_id = s.id and o.periodo = date_trunc('month', public.hoy_ar())::date)
  -- Facturación y cobranza
  union all
  select f.fecha, 'factura_borrador', 'facturacion', 'Emitir el borrador ' || f.codigo || case f.origen_borrador when 'anticipo' then ' (anticipo)' when 'sm' then ' (servicio mensual)' else '' end,
         null, 'factura', f.id, false, case when f.origen_borrador = 'manual' then 'media' else 'alta' end
    from public.factura f where f.estado_doc = 'borrador' and f.clase = 'factura'
  union all
  select r.vencimiento, 'factura_vence', 'facturacion', 'Vence la factura ' || r.codigo, null, 'factura', r.id, r.estado in ('cobrada','acreditada'), 'alta'
    from public.factura_resumen r where r.clase = 'factura' and r.estado_doc = 'emitida' and r.vencimiento is not null
  union all
  select public.hoy_ar(), 'factura_credito', 'cobranza', 'Resolver el crédito de la factura ' || r.codigo, null, 'factura', r.id, false, 'alta'
    from public.factura_resumen r where r.estado = 'credito_a_resolver'
  union all
  select c.fecha_disponibilidad, 'cobranza_disponible', 'cobranza', 'Se acreditan los fondos de ' || c.codigo, null, 'cobranza', c.id, c.fecha_disponibilidad <= public.hoy_ar(), 'baja'
    from public.cobranza c where c.tipo = 'cobro' and not c.anulada
  union all
  select p.fecha_cobro, 'cobranza_distribuir', 'distribucion', 'Distribuir la cobranza ' || p.codigo, null, 'cobranza', p.cobranza_id, false, 'alta'
    from public.cobranza_pendiente_distribuir p
  -- Costos
  union all
  select r.vencimiento, 'factura_proveedor_vence', 'costos', 'Vence la factura de proveedor ' || r.codigo, null, 'factura_proveedor', r.id, r.estado = 'pagada', 'alta'
    from public.factura_proveedor_resumen r where r.vencimiento is not null and r.estado <> 'anulada'
  union all
  select g.fecha, 'gasto_aprobar', 'costos', 'Aprobar el gasto ' || g.codigo, null, 'gasto', g.id, false, 'media'
    from public.gasto g where g.aprobacion = 'registrado' and not g.anulado
  -- Maestros y monotributo
  union all
  select a.venc_matricula, 'matricula_vence', 'maestros', 'Vence la matrícula de ' || a.apellido_nombre, null, 'asociado', a.id, false, 'media'
    from public.asociado a where a.venc_matricula is not null and a.estado <> 'baja'
  union all
  select public.hoy_ar(), 'monotributo_alerta', 'monotributo', 'Monotributo de ' || e.apellido_nombre || ': ' || e.pct || '% del límite (' || e.semaforo || ')', null, 'asociado', e.asociado_id, false,
         case e.semaforo when 'amarillo' then 'media' else 'alta' end
    from public.monotributo_estado() e where e.semaforo in ('amarillo','rojo','excedido')
  union all
  select e.hasta, 'monotributo_cierre', 'monotributo', 'Cierra el período de monotributo de ' || e.apellido_nombre, null, 'asociado', e.asociado_id, false, 'media'
    from public.monotributo_estado() e
  -- Manuales
  union all
  select r.fecha, 'manual', 'calendario', r.titulo, r.detalle, 'recordatorio', r.id, r.cumplido, 'media'
    from public.recordatorio r;

-- ---------------------------------------------------------------------
-- Reportes
-- ---------------------------------------------------------------------
create view public.facturas_por_cobrar with (security_invoker = true) as
select r.id as factura_id, r.codigo, r.cliente_id, c.razon_social as cliente, r.emisor_tipo, r.emisor_asociado_id, r.fecha, r.vencimiento,
       r.total_vigente, r.cobrado, r.saldo,
       case when r.vencimiento is null then 0 else greatest(public.hoy_ar() - r.vencimiento, 0) end as dias_vencida,
       case when r.vencimiento is null or r.vencimiento >= public.hoy_ar() then 'a_vencer'
            when public.hoy_ar() - r.vencimiento <= 30 then '1_30'
            when public.hoy_ar() - r.vencimiento <= 60 then '31_60'
            else 'mas_60' end as tramo
  from public.factura_resumen r join public.cliente c on c.id = r.cliente_id
 where r.clase = 'factura' and r.estado_doc = 'emitida' and r.saldo > 0.005;

create view public.facturas_proveedor_por_pagar with (security_invoker = true) as
select r.id as factura_id, r.codigo, r.emisor_tipo, coalesce(p.nombre_fantasia, a.apellido_nombre) as emisor, r.nro_comprobante, r.fecha, r.vencimiento,
       r.total, r.pagado, r.saldo,
       case when r.vencimiento is null then 0 else greatest(public.hoy_ar() - r.vencimiento, 0) end as dias_vencida,
       case when r.vencimiento is null then 'sin_vencimiento'
            when r.vencimiento >= public.hoy_ar() then 'a_vencer'
            when public.hoy_ar() - r.vencimiento <= 30 then '1_30'
            when public.hoy_ar() - r.vencimiento <= 60 then '31_60'
            else 'mas_60' end as tramo
  from public.factura_proveedor_resumen r
  left join public.proveedor p on p.id = r.proveedor_id left join public.asociado a on a.id = r.asociado_id
 where r.estado in ('pendiente','parcial');

-- Libro IVA Ventas de la Cooperativa: comprobantes fiscales emitidos por ella, por alícuota (las NC restan)
create view public.libro_iva_ventas with (security_invoker = true) as
select f.fecha, f.id as comprobante_id, f.codigo, f.clase, lv.nombre as tipo, f.punto_venta, f.numero, c.razon_social as cliente, c.nro_doc, c.condicion_iva,
       l.iva_pct as alicuota,
       case when f.clase = 'nc' then -sum(l.neto) else sum(l.neto) end as neto_gravado,
       case when f.clase = 'nc' then -sum(l.iva)  else sum(l.iva)  end as iva
  from public.factura f
  join public.factura_linea l on l.factura_id = f.id
  join public.cliente c on c.id = f.cliente_id
  left join public.lista_valor lv on lv.id = f.tipo_comprobante_id
 where f.estado_doc = 'emitida' and f.modo = 'fiscal' and f.emisor_tipo = 'cooperativa'
 group by f.id, f.fecha, f.codigo, f.clase, lv.nombre, f.punto_venta, f.numero, c.razon_social, c.nro_doc, c.condicion_iva, l.iva_pct;

-- Libro IVA Compras: facturas de proveedores (y de asociados) no anuladas
create view public.libro_iva_compras with (security_invoker = true) as
select r.fecha, r.id as comprobante_id, r.codigo, lv.nombre as tipo, r.nro_comprobante,
       coalesce(p.nombre_fantasia, a.apellido_nombre) as emisor, coalesce(p.nro_doc, a.nro_doc) as nro_doc,
       r.neto, r.iva, r.otros_tributos, r.total
  from public.factura_proveedor_resumen r
  left join public.lista_valor lv on lv.id = r.tipo_comprobante_id
  left join public.proveedor p on p.id = r.proveedor_id left join public.asociado a on a.id = r.asociado_id
 where r.estado <> 'anulada';

-- ---------------------------------------------------------------------
-- Auditoría y permisos
-- ---------------------------------------------------------------------
select public.preparar_tabla('monotributo_limite',          'monotributo', 'id', false, 3, false);
select public.preparar_tabla('monotributo_ingreso_externo', 'monotributo', 'id', false, 2, false);
select public.preparar_tabla('monotributo_ajuste',          'monotributo', 'id', false, 3, false);
select public.preparar_tabla('recordatorio',                'calendario',  'id', false, 2, true);
drop policy p_upd on public.monotributo_limite;          -- los límites se versionan: solo se agregan
drop policy p_upd on public.monotributo_ingreso_externo; -- un ingreso externo se anula con motivo
drop policy p_upd on public.monotributo_ajuste;          -- los ajustes no se modifican

-- Cada asociado vinculado a un usuario ve lo suyo
do $$ declare t text; begin
  foreach t in array array['monotributo_limite','monotributo_ingreso_externo','monotributo_ajuste'] loop
    execute format('drop policy p_sel on public.%I', t);
    execute format('create policy p_sel on public.%I for select to authenticated using (public.puede_ver_monotributo(asociado_id))', t);
  end loop;
end $$;

-- Recordatorios: cada uno ve los suyos y los compartidos; administra los suyos (o todos con Administrar)
drop policy p_sel on public.recordatorio; drop policy p_ins on public.recordatorio; drop policy p_upd on public.recordatorio; drop policy p_del on public.recordatorio;
create policy p_sel on public.recordatorio for select to authenticated
  using (public.tiene_permiso('calendario', 1) and (compartido or usuario_id = auth.uid() or public.tiene_permiso('calendario', 3)));
create policy p_ins on public.recordatorio for insert to authenticated
  with check (public.tiene_permiso('calendario', 2) and usuario_id = auth.uid());
create policy p_upd on public.recordatorio for update to authenticated
  using (public.tiene_permiso('calendario', 2) and (usuario_id = auth.uid() or public.tiene_permiso('calendario', 3)))
  with check (public.tiene_permiso('calendario', 2) and (usuario_id = auth.uid() or public.tiene_permiso('calendario', 3)));
create policy p_del on public.recordatorio for delete to authenticated
  using (usuario_id = auth.uid() or public.tiene_permiso('calendario', 3));

create or replace function public.trg_recordatorio_cumplido() returns trigger
language plpgsql as
$$
begin
  if new.cumplido and not old.cumplido then new.cumplido_en := now(); end if;
  if not new.cumplido then new.cumplido_en := null; end if;
  return new;
end $$;
create trigger trg_cumplido before update on public.recordatorio for each row execute function public.trg_recordatorio_cumplido();

revoke execute on function public.puede_ver_monotributo(bigint) from public, anon;
revoke execute on function public.monotributo_periodo(bigint, date) from public, anon;
revoke execute on function public.monotributo_limite_en(bigint, date) from public, anon;
revoke execute on function public.monotributo_detalle(bigint, date) from public, anon;
revoke execute on function public.monotributo_resumen(bigint, date) from public, anon;
revoke execute on function public.monotributo_estado(date) from public, anon;
revoke execute on function public.monotributo_proyeccion(numeric, date) from public, anon;
revoke execute on function public.anular_ingreso_externo(bigint, text) from public, anon;
revoke execute on function public._semaforo(numeric, numeric) from public, anon;
revoke execute on function public._monotributo_detalle(bigint, date) from public, anon, authenticated;
revoke execute on function public._monotributo_resumen(bigint, date) from public, anon, authenticated;
grant execute on function public.puede_ver_monotributo(bigint) to authenticated, service_role;
grant execute on function public.monotributo_periodo(bigint, date) to authenticated, service_role;
grant execute on function public.monotributo_limite_en(bigint, date) to authenticated, service_role;
grant execute on function public.monotributo_detalle(bigint, date) to authenticated, service_role;
grant execute on function public.monotributo_resumen(bigint, date) to authenticated, service_role;
grant execute on function public.monotributo_estado(date) to authenticated, service_role;
grant execute on function public.monotributo_proyeccion(numeric, date) to authenticated, service_role;
grant execute on function public.anular_ingreso_externo(bigint, text) to authenticated, service_role;
grant execute on function public._semaforo(numeric, numeric) to authenticated, service_role;

insert into public.migraciones (version, descripcion) values ('0007', 'Monotributo, calendario unificado y reportes (por cobrar, por pagar, libros de IVA)');
commit;
