-- =====================================================================
-- 0004 · COSTOS Y GASTOS
-- Gastos (cabecera + conceptos), facturas de proveedor y sus pagos,
-- subcontratos, cuenta corriente de asociados (libro de movimientos),
-- liquidaciones y las reversiones de todo eso.
-- Requiere 0001, 0002 y 0003. Pegar TODO en SQL Editor → Run.
--
-- Todo lo que mueve plata se hace con FUNCIONES (rpc): crear_gasto,
-- aprobar_gasto, anular_gasto, pagar_gasto_sf, registrar_pago_factura,
-- registrar_liquidacion, registrar_pago_subcontrato y sus reversiones.
-- Los movimientos de cuenta corriente son un libro: solo se agregan filas.
-- =====================================================================
begin;

do $$ begin
  if not exists (select 1 from public.migraciones where version = '0003') then
    raise exception 'Falta aplicar la migración 0003 antes de esta.';
  end if;
  if exists (select 1 from public.migraciones where version = '0004') then
    raise exception 'La migración 0004 ya fue aplicada: no se puede correr dos veces.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Cuenta corriente de asociados: libro de movimientos
--   importe > 0: la Cooperativa le debe al asociado · importe < 0: el asociado le debe a la Cooperativa
-- ---------------------------------------------------------------------
create table public.movimiento_cc_asociado (
  id bigint generated always as identity primary key,
  asociado_id bigint not null references public.asociado (id),
  fecha date not null default public.hoy_ar(),
  importe numeric(18,2) not null check (importe <> 0),
  concepto text not null,
  origen_tipo text not null check (origen_tipo in ('gasto','liquidacion','distribucion','ajuste','manual')),
  origen_id bigint,
  revierte_id bigint references public.movimiento_cc_asociado (id),
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now()
);
create unique index mov_cc_una_reversion on public.movimiento_cc_asociado (revierte_id) where revierte_id is not null;
create index on public.movimiento_cc_asociado (asociado_id, fecha);
create index on public.movimiento_cc_asociado (origen_tipo, origen_id);

create view public.saldo_cc_asociado with (security_invoker = true) as
select asociado_id, sum(importe) as saldo, count(*) as movimientos, max(fecha) as ultimo_movimiento
  from public.movimiento_cc_asociado group by asociado_id;

create or replace function public.mov_cc(p_asociado bigint, p_importe numeric, p_concepto text, p_tipo text, p_origen_id bigint, p_fecha date default public.hoy_ar())
returns bigint language plpgsql security definer set search_path = public as
$$
declare v bigint;
begin
  insert into public.movimiento_cc_asociado (asociado_id, fecha, importe, concepto, origen_tipo, origen_id)
  values (p_asociado, p_fecha, p_importe, p_concepto, p_tipo, p_origen_id) returning id into v;
  return v;
end $$;

-- Contrarresta (sin borrar) todos los movimientos de un origen que no se hayan revertido
create or replace function public.revertir_movs_cc(p_tipo text, p_origen_id bigint, p_concepto text)
returns int language plpgsql security definer set search_path = public as
$$
declare m record; n int := 0;
begin
  for m in select * from public.movimiento_cc_asociado x
            where x.origen_tipo = p_tipo and x.origen_id = p_origen_id and x.revierte_id is null
              and not exists (select 1 from public.movimiento_cc_asociado r where r.revierte_id = x.id)
  loop
    insert into public.movimiento_cc_asociado (asociado_id, fecha, importe, concepto, origen_tipo, origen_id, revierte_id)
    values (m.asociado_id, public.hoy_ar(), -m.importe, p_concepto, m.origen_tipo, m.origen_id, m.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- Gancho: se llama cuando cambian los costos de una OT (la 0005 lo reemplaza para recalcular la distribución)
create or replace function public.costos_cambiaron(p_ot_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as
$$ begin null; end $$;

-- Verifica que una cuenta bancaria pertenezca a quien corresponde
create or replace function public.exige_cuenta(p_cuenta bigint, p_tipo text, p_id bigint) returns void
language plpgsql stable security definer set search_path = public as
$$
begin
  if p_cuenta is null then return; end if;
  if not exists (select 1 from public.cuenta_bancaria c
                  where c.id = p_cuenta and c.titular_tipo = p_tipo and c.titular_id is not distinct from p_id and c.estado = 'activa') then
    raise exception 'La cuenta bancaria elegida no corresponde (%).', p_tipo using errcode = '23514';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Facturas de proveedor (también las que un asociado le factura a la Cooperativa)
-- ---------------------------------------------------------------------
create table public.factura_proveedor (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  emisor_tipo text not null default 'proveedor' check (emisor_tipo in ('proveedor','asociado')),
  proveedor_id bigint references public.proveedor (id),
  asociado_id bigint references public.asociado (id),
  tipo_comprobante_id bigint, tipo_comprobante_lista text generated always as ('tipo_comprobante') stored,
  nro_comprobante text not null check (btrim(nro_comprobante) <> ''),
  fecha date not null,
  neto numeric(18,2) not null check (neto >= 0),
  iva numeric(18,2) not null default 0 check (iva >= 0),
  otros_tributos numeric(18,2) not null default 0 check (otros_tributos >= 0),    -- percepciones y otros
  total numeric(18,2) not null,
  vencimiento date,
  observacion text,
  anulada boolean not null default false,
  anulada_en timestamptz, anulada_motivo text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  check ((emisor_tipo = 'proveedor') = (proveedor_id is not null)),
  check ((emisor_tipo = 'asociado') = (asociado_id is not null)),
  check (total = neto + iva + otros_tributos),
  foreign key (tipo_comprobante_id, tipo_comprobante_lista) references public.lista_valor (id, lista)
);
create unique index fp_unica_proveedor on public.factura_proveedor (proveedor_id, nro_comprobante) where proveedor_id is not null and not anulada;
create unique index fp_unica_asociado  on public.factura_proveedor (asociado_id, nro_comprobante)  where asociado_id  is not null and not anulada;
create index on public.factura_proveedor (vencimiento) where not anulada;

create table public.liquidacion (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  asociado_id bigint not null references public.asociado (id),
  sentido text not null check (sentido in ('a_asociado','de_asociado')),     -- a_asociado: la Cooperativa le paga · de_asociado: el asociado le paga a la Cooperativa
  importe numeric(18,2) not null check (importe > 0),
  fecha date not null default public.hoy_ar(),
  factura_proveedor_id bigint references public.factura_proveedor (id),
  medio_pago_id bigint references public.medio_pago (id),
  cuenta_origen_id bigint references public.cuenta_bancaria (id),
  cuenta_destino_id bigint references public.cuenta_bancaria (id),
  observacion text,
  anulada boolean not null default false,
  anulada_en timestamptz, anulada_motivo text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(),
  check (factura_proveedor_id is null or sentido = 'a_asociado')
);
create index on public.liquidacion (asociado_id);

create table public.factura_proveedor_pago (
  id bigint generated always as identity primary key,
  factura_id bigint not null references public.factura_proveedor (id),
  fecha date not null default public.hoy_ar(),
  importe numeric(18,2) not null check (importe > 0),
  origen text not null check (origen in ('cooperativa','asociado','liquidacion')),
  asociado_id bigint references public.asociado (id),                   -- si lo pagó un asociado
  liquidacion_id bigint references public.liquidacion (id),
  medio_pago_id bigint references public.medio_pago (id),
  cuenta_origen_id bigint references public.cuenta_bancaria (id),
  cuenta_destino_id bigint references public.cuenta_bancaria (id),
  anulado boolean not null default false,
  anulado_en timestamptz, anulado_motivo text, anulado_por uuid,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(),
  check (origen <> 'asociado' or asociado_id is not null),
  check (origen <> 'liquidacion' or liquidacion_id is not null)
);
create index on public.factura_proveedor_pago (factura_id);

-- ---------------------------------------------------------------------
-- Subcontratos
-- ---------------------------------------------------------------------
create table public.subcontrato (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  ot_id bigint not null references public.ot (id),
  proveedor_id bigint not null references public.proveedor (id),
  descripcion text,
  costo_presupuestado numeric(18,2) not null default 0 check (costo_presupuestado >= 0),
  costo_contratado numeric(18,2) not null default 0 check (costo_contratado >= 0),
  estado text not null default 'activo' check (estado in ('activo','cerrado','cancelado')),
  observacion text,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now()
);
create index on public.subcontrato (ot_id);

-- ---------------------------------------------------------------------
-- Gastos: cabecera y conceptos
--   Una carga = un pagador y una fecha (si pagó otra persona, es otra carga).
-- ---------------------------------------------------------------------
create table public.gasto (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  clase text not null check (clase in ('operativo','general')),            -- operativo: con OT · general: sin OT
  ot_id bigint references public.ot (id),
  fecha date not null default public.hoy_ar(),
  pagador_tipo text not null default 'cooperativa' check (pagador_tipo in ('cooperativa','asociado')),
  pagador_asociado_id bigint references public.asociado (id),
  imputacion text not null check (imputacion in ('ot','recuperable','cooperativa','asociado')),
  asume_asociado_id bigint references public.asociado (id),
  aprobacion text not null default 'registrado' check (aprobacion in ('registrado','aprobado')),
  aprobado_por uuid, aprobado_en timestamptz,
  pagado_sf boolean not null default false,                                 -- pago de los conceptos sin factura
  pagado_sf_fecha date,
  pagado_sf_medio_id bigint references public.medio_pago (id),
  pagado_sf_cuenta_origen_id bigint references public.cuenta_bancaria (id),
  pagado_sf_cuenta_destino_id bigint references public.cuenta_bancaria (id),
  anulado boolean not null default false,
  anulado_en timestamptz, anulado_motivo text, anulado_por uuid,
  observacion text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  check ((clase = 'operativo') = (ot_id is not null)),
  check ((pagador_tipo = 'asociado') = (pagador_asociado_id is not null)),
  check ((imputacion = 'asociado') = (asume_asociado_id is not null)),
  check ((clase = 'operativo' and imputacion in ('ot','recuperable','asociado'))
      or (clase = 'general' and imputacion in ('cooperativa','asociado')))
);
create index on public.gasto (ot_id);
create index on public.gasto (fecha);

create table public.gasto_item (
  id bigint generated always as identity primary key,
  gasto_id bigint not null references public.gasto (id),
  orden int not null,
  categoria_id bigint not null references public.categoria_gasto (id),
  descripcion text,
  discriminado boolean not null default false,                              -- IVA discriminado (genera crédito fiscal) o importe total
  neto numeric(18,2),
  iva numeric(18,2) not null default 0,
  total numeric(18,2) not null check (total > 0),
  costo_neto numeric(18,2) generated always as (coalesce(neto, total)) stored,   -- lo que cuenta como costo (sin IVA recuperable)
  afecta_margen boolean not null,
  proveedor_id bigint references public.proveedor (id),
  nro_factura text,                                                          -- número de la factura del proveedor
  tipo_comprobante_id bigint, tipo_comprobante_lista text generated always as ('tipo_comprobante') stored,
  factura_proveedor_id bigint references public.factura_proveedor (id),
  comprobante_path text,
  unique (gasto_id, orden),
  check ((discriminado and neto is not null and iva >= 0 and total = neto + iva) or (not discriminado and neto is null and iva = 0)),
  foreign key (tipo_comprobante_id, tipo_comprobante_lista) references public.lista_valor (id, lista)
);
create index on public.gasto_item (gasto_id);
create index on public.gasto_item (factura_proveedor_id);

create table public.subcontrato_pago (
  id bigint generated always as identity primary key,
  subcontrato_id bigint not null references public.subcontrato (id),
  gasto_id bigint not null unique references public.gasto (id),
  creado_en timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Vistas derivadas (nada de esto se guarda)
-- ---------------------------------------------------------------------
create view public.factura_proveedor_resumen with (security_invoker = true) as
select f.*,
       coalesce(p.pagado, 0) as pagado,
       f.total - coalesce(p.pagado, 0) as saldo,
       coalesce(i.imputado, 0) as imputado,
       coalesce(i.imputado, 0) > f.total as imputado_excede,
       case when f.anulada then 'anulada'
            when f.total > 0 and coalesce(p.pagado, 0) >= f.total then 'pagada'
            when coalesce(p.pagado, 0) > 0 then 'parcial'
            else 'pendiente' end as estado
  from public.factura_proveedor f
  left join lateral (select sum(importe) as pagado from public.factura_proveedor_pago where factura_id = f.id and not anulado) p on true
  left join lateral (select sum(i.total) as imputado from public.gasto_item i join public.gasto g on g.id = i.gasto_id
                      where i.factura_proveedor_id = f.id and not g.anulado) i on true;

create view public.gasto_resumen with (security_invoker = true) as
select g.id, g.codigo, g.clase, g.ot_id, g.fecha, g.imputacion, g.aprobacion, g.anulado, g.pagador_tipo, g.pagador_asociado_id,
       t.total, t.total_sin_factura, t.costo_margen,
       case when g.anulado then 'anulado'
            when g.pagador_tipo = 'asociado' then 'pagado'
            when f.partes = 0 and coalesce(t.total_sin_factura, 0) = 0 then 'pagado'
            else case
              when f.pagadas + (case when coalesce(t.total_sin_factura, 0) > 0 and g.pagado_sf then 1 else 0 end)
                   = f.partes + (case when coalesce(t.total_sin_factura, 0) > 0 then 1 else 0 end) then 'pagado'
              when f.pagadas + f.parciales + (case when coalesce(t.total_sin_factura, 0) > 0 and g.pagado_sf then 1 else 0 end) > 0 then 'parcial'
              else 'pendiente' end
       end as pago_estado
  from public.gasto g
  left join lateral (select sum(i.total) as total,
                            sum(i.total) filter (where i.factura_proveedor_id is null) as total_sin_factura,
                            sum(i.costo_neto) filter (where i.afecta_margen) as costo_margen
                       from public.gasto_item i where i.gasto_id = g.id) t on true
  left join lateral (select count(*) as partes,
                            count(*) filter (where r.estado = 'pagada') as pagadas,
                            count(*) filter (where r.estado = 'parcial') as parciales
                       from (select distinct i.factura_proveedor_id from public.gasto_item i
                              where i.gasto_id = g.id and i.factura_proveedor_id is not null) d
                       join public.factura_proveedor_resumen r on r.id = d.factura_proveedor_id) f on true;

-- Costos por OT: "gastos_total" incluye todo lo cargado; "costo_margen" es lo que descuenta de la base distribuible
-- (solo gastos aprobados, no anulados, con "afecta margen", sin IVA discriminado)
create view public.ot_costos with (security_invoker = true) as
select o.id as ot_id,
       coalesce(sum(i.total) filter (where not g.anulado), 0) as gastos_total,
       coalesce(sum(i.total) filter (where not g.anulado and g.aprobacion = 'aprobado'), 0) as gastos_aprobados,
       coalesce(sum(i.costo_neto) filter (where not g.anulado and g.aprobacion = 'aprobado' and i.afecta_margen), 0) as costo_margen
  from public.ot o
  left join public.gasto g on g.ot_id = o.id
  left join public.gasto_item i on i.gasto_id = g.id
 group by o.id;

create view public.subcontrato_resumen with (security_invoker = true) as
select s.id, s.codigo, s.ot_id, s.proveedor_id, s.estado, s.costo_presupuestado, s.costo_contratado,
       coalesce(r.real, 0) as costo_real,
       s.costo_contratado - coalesce(r.real, 0) as saldo
  from public.subcontrato s
  left join lateral (select sum(i.total) as real
                       from public.subcontrato_pago sp
                       join public.gasto g on g.id = sp.gasto_id and not g.anulado
                       join public.gasto_item i on i.gasto_id = g.id
                      where sp.subcontrato_id = s.id) r on true;

-- ---------------------------------------------------------------------
-- Reglas de integridad
-- ---------------------------------------------------------------------
-- Gasto: no se cargan gastos en una OT cerrada o cancelada; solo la observación se edita a mano
create or replace function public.trg_gasto_guard() returns trigger
language plpgsql as
$$
declare v_estado text;
begin
  if tg_op = 'INSERT' then
    if new.ot_id is not null then
      select estado into v_estado from public.ot where id = new.ot_id;
      if v_estado in ('cerrada','cancelada') then
        raise exception 'La OT está %: no admite nuevos gastos.', v_estado using errcode = '23514';
      end if;
    end if;
    if new.pagador_asociado_id is not null and exists (select 1 from public.asociado where id = new.pagador_asociado_id and estado = 'baja')
       or new.asume_asociado_id is not null and exists (select 1 from public.asociado where id = new.asume_asociado_id and estado = 'baja') then
      raise exception 'El asociado está dado de baja: no admite nuevas asignaciones.' using errcode = '23514';
    end if;
  elsif not public.en_funcion() then
    if (to_jsonb(new) - 'observacion' - 'actualizado_en') is distinct from (to_jsonb(old) - 'observacion' - 'actualizado_en') then
      raise exception 'Un gasto no se edita: se revierte (anular_gasto) y se vuelve a cargar.' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger trg_gasto_guard before insert or update on public.gasto
  for each row execute function public.trg_gasto_guard();
create trigger trg_codigo before insert on public.gasto for each row execute function public.trg_codigo('GAS','t');
create trigger trg_codigo before insert on public.factura_proveedor for each row execute function public.trg_codigo('FPR','t');
create trigger trg_codigo before insert on public.liquidacion for each row execute function public.trg_codigo('LIQ','t');
create trigger trg_codigo before insert on public.subcontrato for each row execute function public.trg_codigo('SUB','t');

-- Factura de proveedor: con pagos o gastos imputados no se tocan sus importes ni su emisor
create or replace function public.trg_fp_guard() returns trigger
language plpgsql as
$$
begin
  if tg_op = 'UPDATE' and not public.en_funcion() then
    if new.anulada is distinct from old.anulada then
      raise exception 'La factura se anula con anular_factura_proveedor.' using errcode = '23514';
    end if;
    if (new.emisor_tipo, new.proveedor_id, new.asociado_id, new.nro_comprobante, new.neto, new.iva, new.otros_tributos, new.total)
       is distinct from (old.emisor_tipo, old.proveedor_id, old.asociado_id, old.nro_comprobante, old.neto, old.iva, old.otros_tributos, old.total)
       and (exists (select 1 from public.factura_proveedor_pago where factura_id = old.id and not anulado)
            or exists (select 1 from public.gasto_item where factura_proveedor_id = old.id)) then
      raise exception 'La factura tiene pagos o gastos imputados: no se modifican sus importes ni su emisor.' using errcode = '23514';
    end if;
  end if;
  if new.asociado_id is not null and tg_op = 'INSERT'
     and exists (select 1 from public.asociado where id = new.asociado_id and estado = 'baja') then
    raise exception 'El asociado está dado de baja: no admite nuevas asignaciones.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger trg_fp_guard before insert or update on public.factura_proveedor
  for each row execute function public.trg_fp_guard();

-- Subcontrato: el proveedor debe ser subcontratista; la OT debe estar abierta
create or replace function public.trg_subcontrato_antes() returns trigger
language plpgsql as
$$
declare v_tipo text; v_estado text;
begin
  select tipo into v_tipo from public.proveedor where id = new.proveedor_id;
  if v_tipo = 'proveedor' then
    raise exception 'Ese proveedor no está marcado como subcontratista.' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' then
    select estado into v_estado from public.ot where id = new.ot_id;
    if v_estado in ('cerrada','cancelada') then
      raise exception 'La OT está %: no admite nuevos subcontratos.', v_estado using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger trg_antes before insert or update on public.subcontrato
  for each row execute function public.trg_subcontrato_antes();

-- Una OT con gastos vigentes no se cancela
create or replace function public.trg_ot_cancela_gastos() returns trigger
language plpgsql as
$$
begin
  if new.estado = 'cancelada' and old.estado <> 'cancelada'
     and exists (select 1 from public.gasto where ot_id = new.id and not anulado) then
    raise exception 'La OT tiene gastos cargados: revertilos antes de cancelarla.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger trg_c_ot_cancela_gastos before update on public.ot
  for each row execute function public.trg_ot_cancela_gastos();

-- ---------------------------------------------------------------------
-- Funciones: carga de gastos
-- ---------------------------------------------------------------------
-- Interna. p_items: [{categoria_id, descripcion, discriminado, neto, iva, total, afecta_margen,
--                     proveedor_id, nro_factura, tipo_comprobante_id, comprobante_path}]
create or replace function public._crear_gasto(p_clase text, p_ot_id bigint, p_fecha date, p_pagador_asociado_id bigint,
    p_imputacion text, p_asume_asociado_id bigint, p_observacion text, p_items jsonb,
    p_pagado_sf boolean default false, p_medio_id bigint default null)
returns bigint language plpgsql security definer set search_path = public as
$$
declare
  v_id bigint; v_cod text; it jsonb; v_n int := 0; v_cat public.categoria_gasto;
  v_disc boolean; v_neto numeric; v_iva numeric; v_total numeric; v_afecta boolean;
  v_prov bigint; v_nro text; r record; v_fp bigint; v_T numeric; v_A bigint; v_B bigint;
  v_aprob text;
begin
  if p_clase not in ('operativo','general') then raise exception 'La clase del gasto debe ser operativo o general.'; end if;
  if p_clase = 'operativo' and p_ot_id is null then raise exception 'Un gasto operativo necesita una OT.'; end if;
  if p_clase = 'general' and p_ot_id is not null then raise exception 'Un gasto general no lleva OT.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El gasto necesita al menos un concepto.';
  end if;
  v_aprob := case when (select aprobar_gastos from public.organizacion) then 'registrado' else 'aprobado' end;

  insert into public.gasto (clase, ot_id, fecha, pagador_tipo, pagador_asociado_id, imputacion, asume_asociado_id, aprobacion, observacion,
                            pagado_sf, pagado_sf_fecha, pagado_sf_medio_id)
  values (p_clase, p_ot_id, coalesce(p_fecha, public.hoy_ar()),
          case when p_pagador_asociado_id is null then 'cooperativa' else 'asociado' end, p_pagador_asociado_id,
          p_imputacion, p_asume_asociado_id, v_aprob, p_observacion,
          p_pagado_sf, case when p_pagado_sf then coalesce(p_fecha, public.hoy_ar()) end, case when p_pagado_sf then p_medio_id end)
  returning id, codigo into v_id, v_cod;

  for it in select * from jsonb_array_elements(p_items) loop
    v_n := v_n + 1;
    select * into v_cat from public.categoria_gasto where id = (it ->> 'categoria_id')::bigint;
    if not found then raise exception 'La categoría del concepto % no existe.', v_n; end if;
    v_disc := coalesce((it ->> 'discriminado')::boolean, false);
    if v_disc then
      v_neto := (it ->> 'neto')::numeric; v_iva := coalesce((it ->> 'iva')::numeric, 0); v_total := v_neto + v_iva;
    else
      v_neto := null; v_iva := 0; v_total := (it ->> 'total')::numeric;
    end if;
    if v_total is null or v_total <= 0 then raise exception 'El concepto % necesita un importe mayor a cero.', v_n; end if;
    v_afecta := coalesce((it ->> 'afecta_margen')::boolean,
                         case when p_imputacion = 'asociado' then false else v_cat.afecta_margen_distribuible end);
    v_nro := nullif(btrim(coalesce(it ->> 'nro_factura', '')), '');
    v_prov := nullif(it ->> 'proveedor_id', '')::bigint;
    insert into public.gasto_item (gasto_id, orden, categoria_id, descripcion, discriminado, neto, iva, total, afecta_margen,
                                   proveedor_id, nro_factura, tipo_comprobante_id, comprobante_path)
    values (v_id, v_n, v_cat.id, it ->> 'descripcion', v_disc, v_neto, v_iva, v_total, v_afecta,
            v_prov, v_nro, nullif(it ->> 'tipo_comprobante_id', '')::bigint, it ->> 'comprobante_path');
  end loop;

  -- Conceptos con proveedor y número de factura: generan o vinculan la Factura de proveedor
  for r in select proveedor_id, nro_factura, min(tipo_comprobante_id) as tc, sum(coalesce(neto, total)) as neto,
                  sum(iva) as iva, sum(total) as total
             from public.gasto_item where gasto_id = v_id and proveedor_id is not null and nro_factura is not null
            group by proveedor_id, nro_factura
  loop
    select id into v_fp from public.factura_proveedor
     where proveedor_id = r.proveedor_id and nro_comprobante = r.nro_factura and not anulada;
    if found then
      if p_pagador_asociado_id is not null then
        raise exception 'La factura % ya está registrada: cargá el gasto con la Cooperativa como pagadora o revisá el número.', r.nro_factura;
      end if;
    else
      insert into public.factura_proveedor (emisor_tipo, proveedor_id, tipo_comprobante_id, nro_comprobante, fecha, neto, iva, total)
      values ('proveedor', r.proveedor_id, r.tc, r.nro_factura, coalesce(p_fecha, public.hoy_ar()), r.neto, r.iva, r.neto + r.iva)
      returning id into v_fp;
      if p_pagador_asociado_id is not null then      -- pagó un asociado: la factura queda pagada y la deuda va a su cuenta corriente
        insert into public.factura_proveedor_pago (factura_id, fecha, importe, origen, asociado_id)
        values (v_fp, coalesce(p_fecha, public.hoy_ar()), r.neto + r.iva, 'asociado', p_pagador_asociado_id);
      end if;
    end if;
    update public.gasto_item set factura_proveedor_id = v_fp
     where gasto_id = v_id and proveedor_id = r.proveedor_id and nro_factura = r.nro_factura;
  end loop;

  -- Cuenta corriente de asociados
  select sum(total) into v_T from public.gasto_item where gasto_id = v_id;
  v_A := p_pagador_asociado_id;
  v_B := case when p_imputacion = 'asociado' then p_asume_asociado_id end;
  if v_A is distinct from v_B then
    if v_A is not null then perform public.mov_cc(v_A, v_T, v_cod || ' · gasto pagado por el asociado', 'gasto', v_id, coalesce(p_fecha, public.hoy_ar())); end if;
    if v_B is not null then perform public.mov_cc(v_B, -v_T, v_cod || ' · gasto a cargo del asociado', 'gasto', v_id, coalesce(p_fecha, public.hoy_ar())); end if;
  end if;

  if p_ot_id is not null and v_aprob = 'aprobado' then
    perform public.costos_cambiaron(p_ot_id, v_cod || ' cargado');
  end if;
  return v_id;
end $$;
revoke execute on function public._crear_gasto(text, bigint, date, bigint, text, bigint, text, jsonb, boolean, bigint) from public, anon, authenticated;
revoke execute on function public.mov_cc(bigint, numeric, text, text, bigint, date) from public, anon, authenticated;
revoke execute on function public.revertir_movs_cc(text, bigint, text) from public, anon, authenticated;
revoke execute on function public.costos_cambiaron(bigint, text) from public, anon, authenticated;

create or replace function public.crear_gasto(p_clase text, p_ot_id bigint, p_fecha date, p_pagador_asociado_id bigint,
    p_imputacion text, p_asume_asociado_id bigint, p_observacion text, p_items jsonb) returns bigint
language plpgsql security definer set search_path = public as
$$
declare v bigint;
begin
  perform public.exige_permiso('costos', 2);
  perform public.via_funcion(true);
  v := public._crear_gasto(p_clase, p_ot_id, p_fecha, p_pagador_asociado_id, p_imputacion, p_asume_asociado_id, p_observacion, p_items);
  perform public.via_funcion(false);
  return v;
end $$;

create or replace function public.aprobar_gasto(p_id bigint) returns void
language plpgsql security definer set search_path = public as
$$
declare g public.gasto;
begin
  perform public.exige_permiso('costos', 3);
  select * into g from public.gasto where id = p_id for update;
  if not found then raise exception 'No existe el gasto %.', p_id; end if;
  if g.anulado then raise exception 'El gasto está anulado.'; end if;
  if g.aprobacion = 'aprobado' then raise exception 'El gasto ya está aprobado.'; end if;
  perform public.via_funcion(true);
  update public.gasto set aprobacion = 'aprobado', aprobado_por = auth.uid(), aprobado_en = now() where id = p_id;
  perform public.via_funcion(false);
  if g.ot_id is not null then perform public.costos_cambiaron(g.ot_id, g.codigo || ' aprobado'); end if;
end $$;

-- Revertir un gasto mal cargado: queda anulado, se contrarresta la cuenta corriente y se recalculan costos
create or replace function public.anular_gasto(p_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as
$$
declare g public.gasto; v_mot text := nullif(btrim(coalesce(p_motivo, '')), ''); v_estado text; fp record;
begin
  perform public.exige_permiso('costos', 2);
  if v_mot is null then raise exception 'El motivo es obligatorio.'; end if;
  select * into g from public.gasto where id = p_id for update;
  if not found then raise exception 'No existe el gasto %.', p_id; end if;
  if g.anulado then raise exception 'El gasto ya está anulado.'; end if;
  if g.ot_id is not null then
    select estado into v_estado from public.ot where id = g.ot_id;
    if v_estado in ('cerrada','cancelada') then
      raise exception 'La OT está %: reabrila para revertir sus gastos.', v_estado;
    end if;
  end if;
  if g.pagado_sf and not exists (select 1 from public.subcontrato_pago where gasto_id = g.id) then
    raise exception 'El gasto ya tiene un pago de la Cooperativa: primero revertí el pago.';
  end if;
  if exists (select 1 from public.gasto_item i join public.factura_proveedor_pago p on p.factura_id = i.factura_proveedor_id
              where i.gasto_id = g.id and not p.anulado and p.origen <> 'asociado') then
    raise exception 'Una factura vinculada tiene pagos de la Cooperativa: primero revertí esos pagos.';
  end if;
  perform public.via_funcion(true);
  perform public.set_motivo(v_mot);
  update public.gasto set anulado = true, anulado_en = now(), anulado_motivo = v_mot, anulado_por = auth.uid() where id = p_id;
  perform public.revertir_movs_cc('gasto', p_id, g.codigo || ' · reversión del gasto');
  for fp in select distinct i.factura_proveedor_id as id from public.gasto_item i where i.gasto_id = p_id and i.factura_proveedor_id is not null loop
    if not exists (select 1 from public.gasto_item i2 join public.gasto g2 on g2.id = i2.gasto_id
                    where i2.factura_proveedor_id = fp.id and not g2.anulado) then
      update public.factura_proveedor_pago set anulado = true, anulado_en = now(), anulado_motivo = 'Gasto revertido', anulado_por = auth.uid()
       where factura_id = fp.id and not anulado and origen = 'asociado';
      update public.factura_proveedor set anulada = true, anulada_en = now(), anulada_motivo = 'Gasto revertido: ' || v_mot where id = fp.id;
    end if;
  end loop;
  perform public.set_motivo(null);
  perform public.via_funcion(false);
  if g.ot_id is not null and g.aprobacion = 'aprobado' then perform public.costos_cambiaron(g.ot_id, g.codigo || ' revertido'); end if;
end $$;

-- Pago de los conceptos sin factura de un gasto pagado por la Cooperativa
create or replace function public.pagar_gasto_sf(p_gasto bigint, p_fecha date default public.hoy_ar(), p_medio_id bigint default null,
    p_cuenta_origen_id bigint default null, p_cuenta_destino_id bigint default null) returns void
language plpgsql security definer set search_path = public as
$$
declare g public.gasto; v_sf numeric;
begin
  perform public.exige_permiso('costos', 2);
  select * into g from public.gasto where id = p_gasto for update;
  if not found then raise exception 'No existe el gasto %.', p_gasto; end if;
  if g.anulado then raise exception 'El gasto está anulado.'; end if;
  if g.aprobacion <> 'aprobado' then raise exception 'El gasto debe aprobarse antes de pagarse.'; end if;
  if g.pagador_tipo <> 'cooperativa' then raise exception 'Este gasto lo pagó un asociado: se le devuelve con una liquidación.'; end if;
  if g.pagado_sf then raise exception 'Los conceptos sin factura ya están pagados.'; end if;
  select coalesce(sum(total), 0) into v_sf from public.gasto_item where gasto_id = p_gasto and factura_proveedor_id is null;
  if v_sf <= 0 then raise exception 'Todos los conceptos tienen factura: se pagan desde la factura del proveedor.'; end if;
  perform public.exige_cuenta(p_cuenta_origen_id, 'cooperativa', null);
  perform public.via_funcion(true);
  update public.gasto set pagado_sf = true, pagado_sf_fecha = p_fecha, pagado_sf_medio_id = p_medio_id,
         pagado_sf_cuenta_origen_id = p_cuenta_origen_id, pagado_sf_cuenta_destino_id = p_cuenta_destino_id where id = p_gasto;
  perform public.via_funcion(false);
end $$;

create or replace function public.revertir_pago_gasto_sf(p_gasto bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as
$$
declare g public.gasto; v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  perform public.exige_permiso('costos', 3);
  if v_mot is null then raise exception 'El motivo es obligatorio.'; end if;
  select * into g from public.gasto where id = p_gasto for update;
  if not found then raise exception 'No existe el gasto %.', p_gasto; end if;
  if not g.pagado_sf then raise exception 'El gasto no tiene un pago registrado.'; end if;
  if exists (select 1 from public.subcontrato_pago where gasto_id = g.id) then
    raise exception 'Es el pago de un subcontrato: se revierte revirtiendo el gasto.';
  end if;
  perform public.via_funcion(true);
  perform public.set_motivo(v_mot);
  update public.gasto set pagado_sf = false, pagado_sf_fecha = null, pagado_sf_medio_id = null,
         pagado_sf_cuenta_origen_id = null, pagado_sf_cuenta_destino_id = null where id = p_gasto;
  perform public.set_motivo(null);
  perform public.via_funcion(false);
end $$;

-- ---------------------------------------------------------------------
-- Funciones: facturas de proveedor
-- ---------------------------------------------------------------------
create or replace function public.registrar_pago_factura(p_factura bigint, p_importe numeric, p_fecha date default public.hoy_ar(),
    p_medio_id bigint default null, p_cuenta_origen_id bigint default null, p_cuenta_destino_id bigint default null) returns bigint
language plpgsql security definer set search_path = public as
$$
declare f public.factura_proveedor; v_saldo numeric; v bigint;
begin
  perform public.exige_permiso('costos', 2);
  select * into f from public.factura_proveedor where id = p_factura for update;
  if not found then raise exception 'No existe la factura %.', p_factura; end if;
  if f.anulada then raise exception 'La factura está anulada.'; end if;
  if f.emisor_tipo = 'asociado' then raise exception 'La factura de un asociado se paga con una liquidación (registrar_liquidacion).'; end if;
  if p_importe is null or p_importe <= 0 then raise exception 'El importe debe ser mayor a cero.'; end if;
  select saldo into v_saldo from public.factura_proveedor_resumen where id = p_factura;
  if p_importe > v_saldo then raise exception 'El importe supera el saldo de la factura (%).', v_saldo; end if;
  perform public.exige_cuenta(p_cuenta_origen_id, 'cooperativa', null);
  perform public.exige_cuenta(p_cuenta_destino_id, 'proveedor', f.proveedor_id);
  insert into public.factura_proveedor_pago (factura_id, fecha, importe, origen, medio_pago_id, cuenta_origen_id, cuenta_destino_id)
  values (p_factura, p_fecha, p_importe, 'cooperativa', p_medio_id, p_cuenta_origen_id, p_cuenta_destino_id) returning id into v;
  return v;
end $$;

create or replace function public.revertir_pago_factura(p_pago bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as
$$
declare p public.factura_proveedor_pago; v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  perform public.exige_permiso('costos', 3);
  if v_mot is null then raise exception 'El motivo es obligatorio.'; end if;
  select * into p from public.factura_proveedor_pago where id = p_pago for update;
  if not found then raise exception 'No existe el pago %.', p_pago; end if;
  if p.anulado then raise exception 'El pago ya está anulado.'; end if;
  if p.origen = 'asociado' then raise exception 'Ese pago lo hizo un asociado: se revierte revirtiendo el gasto.'; end if;
  if p.origen = 'liquidacion' then raise exception 'Ese pago viene de una liquidación: se revierte revirtiendo la liquidación.'; end if;
  update public.factura_proveedor_pago set anulado = true, anulado_en = now(), anulado_motivo = v_mot, anulado_por = auth.uid() where id = p_pago;
end $$;

create or replace function public.anular_factura_proveedor(p_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as
$$
declare v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  perform public.exige_permiso('costos', 2);
  if v_mot is null then raise exception 'El motivo es obligatorio.'; end if;
  if not exists (select 1 from public.factura_proveedor where id = p_id and not anulada) then
    raise exception 'La factura no existe o ya está anulada.';
  end if;
  if exists (select 1 from public.factura_proveedor_pago where factura_id = p_id and not anulado) then
    raise exception 'La factura tiene pagos: primero revertilos.';
  end if;
  if exists (select 1 from public.gasto_item i join public.gasto g on g.id = i.gasto_id where i.factura_proveedor_id = p_id and not g.anulado) then
    raise exception 'La factura tiene gastos imputados: primero revertí esos gastos.';
  end if;
  perform public.via_funcion(true);
  perform public.set_motivo(v_mot);
  update public.factura_proveedor set anulada = true, anulada_en = now(), anulada_motivo = v_mot where id = p_id;
  perform public.set_motivo(null);
  perform public.via_funcion(false);
end $$;

-- ---------------------------------------------------------------------
-- Funciones: liquidaciones a asociados
-- ---------------------------------------------------------------------
create or replace function public.registrar_liquidacion(p_asociado bigint, p_sentido text, p_importe numeric,
    p_fecha date default public.hoy_ar(), p_factura_id bigint default null, p_medio_id bigint default null,
    p_cuenta_origen_id bigint default null, p_cuenta_destino_id bigint default null, p_observacion text default null) returns bigint
language plpgsql security definer set search_path = public as
$$
declare v bigint; v_cod text; f record; v_signo int;
begin
  perform public.exige_permiso('costos', 2);
  if not exists (select 1 from public.asociado where id = p_asociado) then raise exception 'No existe el asociado.'; end if;
  if p_sentido not in ('a_asociado','de_asociado') then raise exception 'El sentido debe ser a_asociado o de_asociado.'; end if;
  if p_importe is null or p_importe <= 0 then raise exception 'El importe debe ser mayor a cero.'; end if;
  if p_factura_id is not null then
    if p_sentido <> 'a_asociado' then raise exception 'Solo se aplica una factura cuando la Cooperativa le paga al asociado.'; end if;
    select * into f from public.factura_proveedor_resumen where id = p_factura_id;
    if not found or f.emisor_tipo <> 'asociado' or f.asociado_id <> p_asociado then raise exception 'La factura no es de ese asociado.'; end if;
    if f.anulada then raise exception 'La factura está anulada.'; end if;
    if p_importe > f.saldo then raise exception 'El importe supera el saldo de la factura (%).', f.saldo; end if;
  end if;
  if p_sentido = 'a_asociado' then
    perform public.exige_cuenta(p_cuenta_origen_id, 'cooperativa', null);
    perform public.exige_cuenta(p_cuenta_destino_id, 'asociado', p_asociado);
    v_signo := -1;
  else
    perform public.exige_cuenta(p_cuenta_origen_id, 'asociado', p_asociado);
    perform public.exige_cuenta(p_cuenta_destino_id, 'cooperativa', null);
    v_signo := 1;
  end if;
  insert into public.liquidacion (asociado_id, sentido, importe, fecha, factura_proveedor_id, medio_pago_id, cuenta_origen_id, cuenta_destino_id, observacion)
  values (p_asociado, p_sentido, p_importe, p_fecha, p_factura_id, p_medio_id, p_cuenta_origen_id, p_cuenta_destino_id, p_observacion)
  returning id, codigo into v, v_cod;
  perform public.mov_cc(p_asociado, v_signo * p_importe,
         v_cod || case when p_sentido = 'a_asociado' then ' · liquidación al asociado' else ' · pago del asociado a la Cooperativa' end,
         'liquidacion', v, p_fecha);
  if p_factura_id is not null then
    insert into public.factura_proveedor_pago (factura_id, fecha, importe, origen, liquidacion_id, medio_pago_id, cuenta_origen_id, cuenta_destino_id)
    values (p_factura_id, p_fecha, p_importe, 'liquidacion', v, p_medio_id, p_cuenta_origen_id, p_cuenta_destino_id);
  end if;
  return v;
end $$;

create or replace function public.revertir_liquidacion(p_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as
$$
declare l public.liquidacion; v_mot text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  perform public.exige_permiso('costos', 3);
  if v_mot is null then raise exception 'El motivo es obligatorio.'; end if;
  select * into l from public.liquidacion where id = p_id for update;
  if not found then raise exception 'No existe la liquidación %.', p_id; end if;
  if l.anulada then raise exception 'La liquidación ya está anulada.'; end if;
  update public.liquidacion set anulada = true, anulada_en = now(), anulada_motivo = v_mot where id = p_id;
  perform public.revertir_movs_cc('liquidacion', p_id, l.codigo || ' · reversión de liquidación');
  update public.factura_proveedor_pago set anulado = true, anulado_en = now(), anulado_motivo = 'Liquidación revertida: ' || v_mot, anulado_por = auth.uid()
   where liquidacion_id = p_id and not anulado;
end $$;

-- ---------------------------------------------------------------------
-- Funciones: pago de subcontrato (genera el gasto en la OT)
-- ---------------------------------------------------------------------
create or replace function public.registrar_pago_subcontrato(p_subcontrato bigint, p_importe numeric, p_fecha date default public.hoy_ar(),
    p_pagador_asociado_id bigint default null, p_medio_id bigint default null, p_observacion text default null) returns bigint
language plpgsql security definer set search_path = public as
$$
declare s public.subcontrato; v_cat bigint; v_gasto bigint;
begin
  perform public.exige_permiso('costos', 2);
  select * into s from public.subcontrato where id = p_subcontrato for update;
  if not found then raise exception 'No existe el subcontrato %.', p_subcontrato; end if;
  if s.estado <> 'activo' then raise exception 'El subcontrato está %.', s.estado; end if;
  if p_importe is null or p_importe <= 0 then raise exception 'El importe debe ser mayor a cero.'; end if;
  select id into v_cat from public.categoria_gasto where nombre = 'Subcontrataciones';
  if v_cat is null then raise exception 'Falta la categoría de gasto "Subcontrataciones".'; end if;
  perform public.via_funcion(true);
  v_gasto := public._crear_gasto('operativo', s.ot_id, p_fecha, p_pagador_asociado_id, 'ot', null, p_observacion,
      jsonb_build_array(jsonb_build_object('categoria_id', v_cat, 'descripcion', 'Pago de subcontrato ' || s.codigo,
                                           'discriminado', false, 'total', p_importe, 'proveedor_id', s.proveedor_id)),
      p_pagador_asociado_id is null, p_medio_id);
  insert into public.subcontrato_pago (subcontrato_id, gasto_id) values (s.id, v_gasto);
  perform public.via_funcion(false);
  return v_gasto;
end $$;

-- ---------------------------------------------------------------------
-- Auditoría y permisos
-- ---------------------------------------------------------------------
select public.preparar_tabla('movimiento_cc_asociado', 'costos', 'id', false, 2, false);
select public.preparar_tabla('gasto',                  'costos', 'id', false, 2, false);
select public.preparar_tabla('gasto_item',             'costos', 'id', false, 2, false);
select public.preparar_tabla('factura_proveedor',      'costos', 'id', false, 2, false);
select public.preparar_tabla('factura_proveedor_pago', 'costos', 'id', false, 2, false);
select public.preparar_tabla('liquidacion',            'costos', 'id', false, 2, false);
select public.preparar_tabla('subcontrato',            'costos', 'id', false, 2, false);
select public.preparar_tabla('subcontrato_pago',       'costos', 'id', false, 2, false);

-- Lo que mueve plata o cuentas solo se toca por funciones: sin altas, cambios ni bajas directas
drop policy p_ins on public.movimiento_cc_asociado; drop policy p_upd on public.movimiento_cc_asociado;
drop policy p_ins on public.gasto;                  -- (la observación del gasto sí se puede editar)
drop policy p_ins on public.gasto_item;             drop policy p_upd on public.gasto_item;
drop policy p_ins on public.factura_proveedor_pago; drop policy p_upd on public.factura_proveedor_pago;
drop policy p_ins on public.liquidacion;            drop policy p_upd on public.liquidacion;
drop policy p_ins on public.subcontrato_pago;       drop policy p_upd on public.subcontrato_pago;

-- Cada asociado vinculado a un usuario puede ver su propia cuenta corriente
drop policy p_sel on public.movimiento_cc_asociado;
create policy p_sel on public.movimiento_cc_asociado for select to authenticated
  using (public.tiene_permiso('costos', 1)
         or exists (select 1 from public.usuario u where u.id = auth.uid() and u.activo and u.asociado_id = movimiento_cc_asociado.asociado_id));

-- Funciones expuestas solo a usuarios con sesión
revoke execute on function public.crear_gasto(text, bigint, date, bigint, text, bigint, text, jsonb) from public, anon;
revoke execute on function public.aprobar_gasto(bigint) from public, anon;
revoke execute on function public.anular_gasto(bigint, text) from public, anon;
revoke execute on function public.pagar_gasto_sf(bigint, date, bigint, bigint, bigint) from public, anon;
revoke execute on function public.revertir_pago_gasto_sf(bigint, text) from public, anon;
revoke execute on function public.registrar_pago_factura(bigint, numeric, date, bigint, bigint, bigint) from public, anon;
revoke execute on function public.revertir_pago_factura(bigint, text) from public, anon;
revoke execute on function public.anular_factura_proveedor(bigint, text) from public, anon;
revoke execute on function public.registrar_liquidacion(bigint, text, numeric, date, bigint, bigint, bigint, bigint, text) from public, anon;
revoke execute on function public.revertir_liquidacion(bigint, text) from public, anon;
revoke execute on function public.registrar_pago_subcontrato(bigint, numeric, date, bigint, bigint, text) from public, anon;
revoke execute on function public.exige_cuenta(bigint, text, bigint) from public, anon;
grant execute on function public.crear_gasto(text, bigint, date, bigint, text, bigint, text, jsonb) to authenticated, service_role;
grant execute on function public.aprobar_gasto(bigint) to authenticated, service_role;
grant execute on function public.anular_gasto(bigint, text) to authenticated, service_role;
grant execute on function public.pagar_gasto_sf(bigint, date, bigint, bigint, bigint) to authenticated, service_role;
grant execute on function public.revertir_pago_gasto_sf(bigint, text) to authenticated, service_role;
grant execute on function public.registrar_pago_factura(bigint, numeric, date, bigint, bigint, bigint) to authenticated, service_role;
grant execute on function public.revertir_pago_factura(bigint, text) to authenticated, service_role;
grant execute on function public.anular_factura_proveedor(bigint, text) to authenticated, service_role;
grant execute on function public.registrar_liquidacion(bigint, text, numeric, date, bigint, bigint, bigint, bigint, text) to authenticated, service_role;
grant execute on function public.revertir_liquidacion(bigint, text) to authenticated, service_role;
grant execute on function public.registrar_pago_subcontrato(bigint, numeric, date, bigint, bigint, text) to authenticated, service_role;
grant execute on function public.exige_cuenta(bigint, text, bigint) to authenticated, service_role;

insert into public.migraciones (version, descripcion) values ('0004', 'Costos y gastos: gastos, facturas de proveedor, subcontratos, cuenta corriente de asociados, liquidaciones');
commit;
