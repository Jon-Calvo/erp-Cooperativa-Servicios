-- =====================================================================
-- 0005 · FACTURACIÓN Y COBRANZA
-- Facturas emitidas (el sistema solo REGISTRA lo que emite ARCA), notas de
-- crédito y de débito, cobranzas con retenciones y aplicaciones, cuenta
-- corriente del cliente (saldo a favor), resolución del crédito de una nota
-- de crédito (devolución o saldo a favor) y reversión de cobranzas.
-- Requiere 0001 a 0004. Pegar TODO en SQL Editor → Run.
--
-- El reparto entre asociados (Distribución) se activa en la migración 0006:
-- esta deja "ganchos" (hook_*) que 0006 reemplaza.
-- =====================================================================
begin;

do $$ begin
  if not exists (select 1 from public.migraciones where version = '0004') then
    raise exception 'Falta aplicar la migración 0004 antes de esta.';
  end if;
  if exists (select 1 from public.migraciones where version = '0005') then
    raise exception 'La migración 0005 ya fue aplicada: no se puede correr dos veces.';
  end if;
end $$;

-- Los movimientos de cuenta corriente de asociados ahora también nacen de cobranzas y devoluciones
alter table public.movimiento_cc_asociado drop constraint movimiento_cc_asociado_origen_tipo_check;
alter table public.movimiento_cc_asociado add constraint movimiento_cc_asociado_origen_tipo_check
  check (origen_tipo in ('gasto','liquidacion','distribucion','ajuste','manual','cobranza','devolucion'));

-- ---------------------------------------------------------------------
-- Facturas, notas de crédito y notas de débito
-- ---------------------------------------------------------------------
create table public.factura (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  clase text not null default 'factura' check (clase in ('factura','nc','nd')),
  modo text not null default 'fiscal' check (modo in ('fiscal','interna')),         -- interna: sin CAE (p. ej. regalías)
  estado_doc text not null default 'borrador' check (estado_doc in ('borrador','emitida')),
  tipo_comprobante_id bigint, tipo_comprobante_lista text generated always as ('tipo_comprobante') stored,
  emisor_tipo text not null default 'cooperativa' check (emisor_tipo in ('cooperativa','asociado')),
  emisor_asociado_id bigint references public.asociado (id),
  cliente_id bigint not null references public.cliente (id),
  factura_origen_id bigint references public.factura (id),                           -- las NC y ND apuntan a su factura
  punto_venta text check (punto_venta ~ '^[0-9]{1,5}$'),
  numero text check (numero ~ '^[0-9]{1,8}$'),
  cae text,
  cae_vencimiento date,
  fecha date not null default public.hoy_ar(),
  vencimiento date,
  otros_tributos numeric(18,2) not null default 0 check (otros_tributos >= 0),       -- percepciones y otros
  motivo text,
  origen_borrador text not null default 'manual' check (origen_borrador in ('manual','anticipo','sm')),
  observacion text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  check ((emisor_tipo = 'asociado') = (emisor_asociado_id is not null)),
  check ((clase = 'factura') = (factura_origen_id is null)),
  check (estado_doc = 'borrador' or tipo_comprobante_id is not null),
  check (estado_doc = 'borrador' or modo = 'interna' or (punto_venta is not null and numero is not null and cae is not null)),
  foreign key (tipo_comprobante_id, tipo_comprobante_lista) references public.lista_valor (id, lista)
);
create unique index factura_unica_fiscal on public.factura
  (emisor_tipo, coalesce(emisor_asociado_id, 0), tipo_comprobante_id, punto_venta, numero)
  where estado_doc = 'emitida' and modo = 'fiscal';
create index on public.factura (cliente_id);
create index on public.factura (factura_origen_id);

create table public.factura_linea (
  id bigint generated always as identity primary key,
  factura_id bigint not null references public.factura (id) on delete cascade,
  orden int not null,
  ot_id bigint not null references public.ot (id),
  descripcion text,
  neto numeric(18,2) not null check (neto > 0),
  iva_pct numeric(5,2) not null check (iva_pct between 0 and 100),
  iva numeric(18,2) generated always as (round(neto * iva_pct / 100, 2)) stored,
  total numeric(18,2) generated always as (neto + round(neto * iva_pct / 100, 2)) stored,
  unique (factura_id, orden)
);
create index on public.factura_linea (factura_id);
create index on public.factura_linea (ot_id);

-- ---------------------------------------------------------------------
-- Cobranzas
-- ---------------------------------------------------------------------
create table public.cobranza (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  tipo text not null default 'cobro' check (tipo in ('cobro','saldo_favor')),       -- saldo_favor: se aplicó crédito del cliente (no entra plata)
  cliente_id bigint not null references public.cliente (id),
  receptor_tipo text not null default 'cooperativa' check (receptor_tipo in ('cooperativa','asociado')),
  receptor_asociado_id bigint references public.asociado (id),
  cuenta_destino_id bigint references public.cuenta_bancaria (id),
  medio_pago_id bigint references public.medio_pago (id),
  fecha_cobro date not null default public.hoy_ar(),
  fecha_disponibilidad date not null default public.hoy_ar(),
  importe numeric(18,2) not null default 0 check (importe >= 0),                    -- efectivo recibido
  ret_iva numeric(18,2) not null default 0 check (ret_iva >= 0),                    -- no la absorbe el emisor
  ret_otras numeric(18,2) not null default 0 check (ret_otras >= 0),                -- Ganancias / IIBB / otras: las absorbe el emisor
  sobrante numeric(18,2) not null default 0 check (sobrante >= 0),                  -- va a la cuenta corriente del cliente
  observacion text,
  anulada boolean not null default false,
  anulada_en timestamptz, anulada_motivo text, anulada_por uuid,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(),
  check ((receptor_tipo = 'asociado') = (receptor_asociado_id is not null)),
  check (tipo = 'cobro' or (importe = 0 and ret_iva = 0 and ret_otras = 0))
);
create index on public.cobranza (cliente_id);

create table public.cobranza_aplicacion (
  id bigint generated always as identity primary key,
  cobranza_id bigint not null references public.cobranza (id),
  factura_id bigint not null references public.factura (id),
  importe numeric(18,2) not null check (importe > 0),                              -- incluye lo cancelado con retenciones
  unique (cobranza_id, factura_id)
);
create index on public.cobranza_aplicacion (factura_id);

-- Cómo se reparte cada aplicación entre las OT de la factura (queda fijo al momento del cobro)
create table public.cobranza_ot (
  id bigint generated always as identity primary key,
  cobranza_id bigint not null references public.cobranza (id),
  factura_id bigint not null references public.factura (id),
  ot_id bigint not null references public.ot (id),
  neto numeric(18,2) not null default 0,
  iva numeric(18,2) not null default 0,
  otros numeric(18,2) not null default 0,
  unique (cobranza_id, factura_id, ot_id)
);
create index on public.cobranza_ot (ot_id);

-- ---------------------------------------------------------------------
-- Cuenta corriente del cliente (libro): + saldo a favor del cliente · − se usó
-- ---------------------------------------------------------------------
create table public.movimiento_cc_cliente (
  id bigint generated always as identity primary key,
  cliente_id bigint not null references public.cliente (id),
  fecha date not null default public.hoy_ar(),
  importe numeric(18,2) not null check (importe <> 0),
  concepto text not null,
  origen_tipo text not null check (origen_tipo in ('cobranza','aplicacion','resolucion','devolucion','manual')),
  origen_id bigint,
  revierte_id bigint references public.movimiento_cc_cliente (id),
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now()
);
create unique index mov_cli_una_reversion on public.movimiento_cc_cliente (revierte_id) where revierte_id is not null;
create index on public.movimiento_cc_cliente (cliente_id, fecha);
create index on public.movimiento_cc_cliente (origen_tipo, origen_id);

create view public.saldo_cc_cliente with (security_invoker = true) as
select cliente_id, sum(importe) as saldo, count(*) as movimientos
  from public.movimiento_cc_cliente group by cliente_id;

create or replace function public.saldo_cliente(p_cliente bigint) returns numeric
language sql stable security definer set search_path = public as
$$ select coalesce(sum(importe), 0) from public.movimiento_cc_cliente where cliente_id = p_cliente $$;

create or replace function public.mov_cli(p_cliente bigint, p_importe numeric, p_concepto text, p_tipo text, p_origen_id bigint, p_fecha date default public.hoy_ar())
returns bigint language plpgsql security definer set search_path = public as
$$
declare v bigint;
begin
  insert into public.movimiento_cc_cliente (cliente_id, fecha, importe, concepto, origen_tipo, origen_id)
  values (p_cliente, p_fecha, p_importe, p_concepto, p_tipo, p_origen_id) returning id into v;
  return v;
end $$;

create or replace function public.revertir_movs_cli(p_tipo text, p_origen_id bigint, p_concepto text) returns int
language plpgsql security definer set search_path = public as
$$
declare m record; n int := 0;
begin
  for m in select * from public.movimiento_cc_cliente x
            where x.origen_tipo = p_tipo and x.origen_id = p_origen_id and x.revierte_id is null
              and not exists (select 1 from public.movimiento_cc_cliente r where r.revierte_id = x.id)
  loop
    insert into public.movimiento_cc_cliente (cliente_id, fecha, importe, concepto, origen_tipo, origen_id, revierte_id)
    values (m.cliente_id, public.hoy_ar(), -m.importe, p_concepto, m.origen_tipo, m.origen_id, m.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- Resolución del crédito de una nota de crédito (cobrado de más)
-- ---------------------------------------------------------------------
create table public.devolucion_cliente (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  cliente_id bigint not null references public.cliente (id),
  importe numeric(18,2) not null check (importe > 0),
  fecha date not null default public.hoy_ar(),
  medio_pago_id bigint references public.medio_pago (id),
  pagador_tipo text not null default 'cooperativa' check (pagador_tipo in ('cooperativa','asociado')),
  pagador_asociado_id bigint references public.asociado (id),
  cuenta_origen_id bigint references public.cuenta_bancaria (id),
  cuenta_destino_id bigint references public.cuenta_bancaria (id),
  observacion text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(),
  check ((pagador_tipo = 'asociado') = (pagador_asociado_id is not null))
);

create table public.factura_credito_resuelto (
  id bigint generated always as identity primary key,
  factura_id bigint not null references public.factura (id),
  importe numeric(18,2) not null check (importe > 0),
  destino text not null check (destino in ('saldo_favor','devolucion')),
  devolucion_id bigint references public.devolucion_cliente (id),
  fecha date not null default public.hoy_ar(),
  observacion text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(),
  check ((destino = 'devolucion') = (devolucion_id is not null))
);
create index on public.factura_credito_resuelto (factura_id);

create table public.factura_credito_resuelto_ot (
  resuelto_id bigint not null references public.factura_credito_resuelto (id),
  ot_id bigint not null references public.ot (id),
  neto numeric(18,2) not null default 0,
  iva numeric(18,2) not null default 0,
  primary key (resuelto_id, ot_id)
);

-- ---------------------------------------------------------------------
-- Vistas derivadas
-- ---------------------------------------------------------------------
create view public.factura_total with (security_invoker = true) as
select f.id, coalesce(sum(l.neto), 0) as neto, coalesce(sum(l.iva), 0) as iva, f.otros_tributos,
       coalesce(sum(l.neto), 0) + coalesce(sum(l.iva), 0) + f.otros_tributos as total
  from public.factura f left join public.factura_linea l on l.factura_id = f.id
 group by f.id;

-- Estado de cada comprobante: Borrador / Emitida / Parcial / Cobrada / Acreditada / Crédito a resolver
create view public.factura_resumen with (security_invoker = true) as
select f.id, f.codigo, f.clase, f.modo, f.estado_doc, f.cliente_id, f.emisor_tipo, f.emisor_asociado_id, f.factura_origen_id,
       f.fecha, f.vencimiento, f.punto_venta, f.numero, f.origen_borrador,
       t.neto, t.iva, t.otros_tributos, t.total,
       case when f.clase = 'factura' then t.total + coalesce(nd.total, 0) - coalesce(nc.total, 0) end as total_vigente,
       coalesce(nd.total, 0) as nd_total, coalesce(nc.total, 0) as nc_total,
       coalesce(a.cobrado, 0) - coalesce(r.resuelto, 0) as cobrado,
       case when f.clase = 'factura' and f.estado_doc = 'emitida'
            then greatest(t.total + coalesce(nd.total, 0) - coalesce(nc.total, 0) - (coalesce(a.cobrado, 0) - coalesce(r.resuelto, 0)), 0) end as saldo,
       case when f.clase = 'factura' and f.estado_doc = 'emitida'
            then greatest((coalesce(a.cobrado, 0) - coalesce(r.resuelto, 0)) - (t.total + coalesce(nd.total, 0) - coalesce(nc.total, 0)), 0) end as credito_a_resolver,
       case
         when f.estado_doc = 'borrador' then 'borrador'
         when f.clase <> 'factura' then 'emitida'
         when (coalesce(a.cobrado, 0) - coalesce(r.resuelto, 0)) > (t.total + coalesce(nd.total, 0) - coalesce(nc.total, 0)) + 0.005 then 'credito_a_resolver'
         when coalesce(nc.total, 0) > 0 and t.total + coalesce(nd.total, 0) - coalesce(nc.total, 0) <= 0.005 then 'acreditada'
         when (coalesce(a.cobrado, 0) - coalesce(r.resuelto, 0)) >= (t.total + coalesce(nd.total, 0) - coalesce(nc.total, 0)) - 0.005 then 'cobrada'
         when (coalesce(a.cobrado, 0) - coalesce(r.resuelto, 0)) > 0.005 then 'parcial'
         else 'emitida'
       end as estado
  from public.factura f
  join public.factura_total t on t.id = f.id
  left join lateral (select sum(x.total) as total from public.factura h join public.factura_total x on x.id = h.id
                      where h.factura_origen_id = f.id and h.clase = 'nd' and h.estado_doc = 'emitida') nd on true
  left join lateral (select sum(x.total) as total from public.factura h join public.factura_total x on x.id = h.id
                      where h.factura_origen_id = f.id and h.clase = 'nc' and h.estado_doc = 'emitida') nc on true
  left join lateral (select sum(ap.importe) as cobrado from public.cobranza_aplicacion ap join public.cobranza c on c.id = ap.cobranza_id
                      where ap.factura_id = f.id and not c.anulada) a on true
  left join lateral (select sum(importe) as resuelto from public.factura_credito_resuelto where factura_id = f.id) r on true;

-- Facturación y cobranza por OT
create view public.ot_facturacion with (security_invoker = true) as
select o.id as ot_id, o.neto,
       x.facturado_neto,
       coalesce(x.borrador_neto, 0) as borrador_neto,
       case when x.facturado_neto <= 0.005 then 'sin_facturar'
            when x.facturado_neto > o.neto + 0.005 then 'excedida'
            when x.facturado_neto >= o.neto - 0.005 then 'completa'
            else 'parcial' end as estado_facturacion,
       case when o.neto > 0 then round(x.facturado_neto * 100 / o.neto, 2) end as pct_facturado
  from public.ot o
  left join lateral (
    select coalesce(sum(l.neto) filter (where f.estado_doc = 'emitida' and f.clase in ('factura','nd')), 0)
         - coalesce(sum(l.neto) filter (where f.estado_doc = 'emitida' and f.clase = 'nc'), 0) as facturado_neto,
           sum(l.neto) filter (where f.estado_doc = 'borrador') as borrador_neto
      from public.factura_linea l join public.factura f on f.id = l.factura_id where l.ot_id = o.id) x on true;

create view public.ot_cobranza with (security_invoker = true) as
select o.id as ot_id,
       coalesce((select sum(co.neto) from public.cobranza_ot co join public.cobranza c on c.id = co.cobranza_id
                  where co.ot_id = o.id and not c.anulada), 0)
     - coalesce((select sum(ro.neto) from public.factura_credito_resuelto_ot ro where ro.ot_id = o.id), 0) as cobrado_neto
  from public.ot o;

-- ---------------------------------------------------------------------
-- Ganchos para la Distribución (0006 los reemplaza)
-- ---------------------------------------------------------------------
create or replace function public.hook_cobranza_registrada(p_cobranza bigint) returns void
language plpgsql security definer set search_path = public as $$ begin null; end $$;
create or replace function public.hook_cobranza_revertida(p_cobranza bigint) returns void
language plpgsql security definer set search_path = public as $$ begin null; end $$;
create or replace function public.hook_credito_resuelto(p_resuelto bigint) returns void
language plpgsql security definer set search_path = public as $$ begin null; end $$;
revoke execute on function public.hook_cobranza_registrada(bigint) from public, anon, authenticated;
revoke execute on function public.hook_cobranza_revertida(bigint) from public, anon, authenticated;
revoke execute on function public.hook_credito_resuelto(bigint) from public, anon, authenticated;
revoke execute on function public.mov_cli(bigint, numeric, text, text, bigint, date) from public, anon, authenticated;
revoke execute on function public.revertir_movs_cli(text, bigint, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Reglas de integridad
-- ---------------------------------------------------------------------
create or replace function public.trg_factura_antes() returns trigger
language plpgsql as
$$
declare o public.factura; v_clase text; v_dias int;
begin
  if tg_op = 'DELETE' then
    if old.estado_doc <> 'borrador' and not public.en_funcion() then
      raise exception 'Una factura emitida no se borra: se acredita con una nota de crédito.' using errcode = '23514';
    end if;
    return old;
  end if;

  if tg_op = 'INSERT' and not public.en_funcion() then
    new.estado_doc := 'borrador';
  end if;
  if tg_op = 'UPDATE' and not public.en_funcion() then
    if new.estado_doc is distinct from old.estado_doc then
      raise exception 'La factura se emite con emitir_factura.' using errcode = '23514';
    end if;
    if old.estado_doc = 'emitida'
       and (to_jsonb(new) - 'observacion' - 'actualizado_en' - 'tipo_comprobante_lista')
           is distinct from (to_jsonb(old) - 'observacion' - 'actualizado_en' - 'tipo_comprobante_lista') then
      raise exception 'Un comprobante emitido no se modifica (solo su observación).' using errcode = '23514';
    end if;
  end if;

  if new.punto_venta is not null then new.punto_venta := lpad(new.punto_venta, 5, '0'); end if;
  if new.numero is not null then new.numero := lpad(new.numero, 8, '0'); end if;

  if new.tipo_comprobante_id is not null and new.modo = 'fiscal' then
    select datos ->> 'clase' into v_clase from public.lista_valor where id = new.tipo_comprobante_id;
    if v_clase is distinct from new.clase then
      raise exception 'El tipo de comprobante elegido no corresponde a una % (es: %).', new.clase, v_clase using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT' and new.emisor_asociado_id is not null
     and exists (select 1 from public.asociado where id = new.emisor_asociado_id and estado = 'baja') then
    raise exception 'El asociado está dado de baja: no admite nuevas asignaciones.' using errcode = '23514';
  end if;

  if new.factura_origen_id is not null then
    select * into o from public.factura where id = new.factura_origen_id;
    if o.clase <> 'factura' then raise exception 'La nota debe apuntar a una factura.' using errcode = '23514'; end if;
    if o.cliente_id <> new.cliente_id or o.emisor_tipo <> new.emisor_tipo or o.emisor_asociado_id is distinct from new.emisor_asociado_id then
      raise exception 'La nota debe tener el mismo cliente y emisor que la factura.' using errcode = '23514';
    end if;
  end if;

  if new.vencimiento is null and new.clase = 'factura' then
    select cp.dias into v_dias from public.cliente c left join public.condicion_pago cp on cp.id = c.condicion_pago_id where c.id = new.cliente_id;
    if v_dias is not null then new.vencimiento := new.fecha + v_dias; end if;
  end if;
  return new;
end $$;
create trigger trg_factura_antes before insert or update or delete on public.factura
  for each row execute function public.trg_factura_antes();
create trigger trg_codigo before insert on public.factura for each row execute function public.trg_codigo('FAC','t');
create trigger trg_codigo before insert on public.cobranza for each row execute function public.trg_codigo('COB','t');
create trigger trg_codigo before insert on public.devolucion_cliente for each row execute function public.trg_codigo('DEV','t');

create or replace function public.trg_factura_linea_guard() returns trigger
language plpgsql as
$$
declare h record; v_cli bigint; v_estado text;
begin
  select estado_doc, cliente_id into h from public.factura where id = coalesce(new.factura_id, old.factura_id);
  if h.estado_doc <> 'borrador' and not public.en_funcion() then
    raise exception 'Las líneas de un comprobante emitido no se modifican.' using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  select cliente_id, estado into v_cli, v_estado from public.ot where id = new.ot_id;
  if v_cli <> h.cliente_id then
    raise exception 'La OT no pertenece al cliente de la factura.' using errcode = '23514';
  end if;
  if v_estado = 'cancelada' then
    raise exception 'La OT está cancelada: no se factura.' using errcode = '23514';
  end if;
  if new.orden is null then
    select coalesce(max(orden), 0) + 1 into new.orden from public.factura_linea where factura_id = new.factura_id;
  end if;
  return new;
end $$;
create trigger trg_linea_guard before insert or update or delete on public.factura_linea
  for each row execute function public.trg_factura_linea_guard();

-- Una OT con comprobantes emitidos no se cancela; al cancelarla se descartan sus borradores
create or replace function public.trg_ot_cancela_facturas() returns trigger
language plpgsql security definer set search_path = public as
$$
begin
  if new.estado = 'cancelada' and old.estado <> 'cancelada' then
    if exists (select 1 from public.factura_linea l join public.factura f on f.id = l.factura_id
                where l.ot_id = new.id and f.estado_doc = 'emitida') then
      raise exception 'La OT tiene comprobantes emitidos: acreditalos antes de cancelarla.' using errcode = '23514';
    end if;
    delete from public.factura_linea where ot_id = new.id and factura_id in (select id from public.factura where estado_doc = 'borrador');
    delete from public.factura f where f.estado_doc = 'borrador' and not exists (select 1 from public.factura_linea l where l.factura_id = f.id);
  end if;
  return new;
end $$;
create trigger trg_d_ot_cancela_facturas before update on public.ot
  for each row execute function public.trg_ot_cancela_facturas();

-- ---------------------------------------------------------------------
-- Borradores automáticos: anticipo de una OT y factura mensual de cada OT de SM
-- ---------------------------------------------------------------------
create or replace function public.crear_borrador_ot(p_ot bigint) returns bigint
language plpgsql security definer set search_path = public as
$$
declare o public.ot; v_emisor text := 'cooperativa'; v_asoc bigint; v_f bigint; v_neto numeric; v_origen text; v_serv text;
begin
  select * into o from public.ot where id = p_ot;
  if not found or o.estado = 'cancelada' then return null; end if;
  if o.origen = 'presupuesto' then
    select p.emisor_tipo, p.emisor_asociado_id into v_emisor, v_asoc
      from public.presupuesto_linea l join public.presupuesto p on p.id = l.presupuesto_id where l.id = o.presupuesto_linea_id;
  end if;
  if o.origen = 'sm' then v_origen := 'sm'; v_neto := o.neto;
  else v_origen := 'anticipo'; v_neto := coalesce(o.anticipo_monto, o.neto); end if;
  if v_neto <= 0 then return null; end if;
  select nombre into v_serv from public.servicio where id = o.servicio_id;
  insert into public.factura (clase, emisor_tipo, emisor_asociado_id, cliente_id, origen_borrador, observacion)
  values ('factura', v_emisor, v_asoc, o.cliente_id, v_origen,
          case when v_origen = 'sm' then 'Servicio mensual ' || to_char(o.periodo, 'MM/YYYY') else 'Anticipo de la OT' end)
  returning id into v_f;
  insert into public.factura_linea (factura_id, orden, ot_id, descripcion, neto, iva_pct)
  values (v_f, 1, o.id, coalesce(v_serv, 'Servicio'), v_neto, public.iva_sugerido_emisor(v_emisor, v_asoc));
  return v_f;
end $$;
revoke execute on function public.crear_borrador_ot(bigint) from public, anon, authenticated;

create or replace function public.trg_ot_borrador() returns trigger
language plpgsql security definer set search_path = public as
$$
begin
  if new.origen = 'sm' or new.requiere_anticipo then perform public.crear_borrador_ot(new.id); end if;
  return new;
end $$;
create trigger trg_ot_borrador after insert on public.ot
  for each row execute function public.trg_ot_borrador();

-- OT que ya existían con anticipo o de SM y todavía no tienen factura
select public.crear_borrador_ot(o.id) from public.ot o
 where (o.origen = 'sm' or o.requiere_anticipo) and o.estado <> 'cancelada'
   and not exists (select 1 from public.factura_linea l where l.ot_id = o.id);

-- ---------------------------------------------------------------------
-- Funciones: facturación
-- ---------------------------------------------------------------------
create or replace function public.emitir_factura(p_id bigint, p_punto_venta text default null, p_numero text default null, p_cae text default null,
    p_fecha date default null, p_tipo_comprobante_id bigint default null, p_cae_vencimiento date default null) returns void
language plpgsql security definer set search_path = public as
$$
declare f public.factura; r record; v_origen_neto numeric; v_otros_nc numeric;
begin
  perform public.exige_permiso('facturacion', 2);
  select * into f from public.factura where id = p_id for update;
  if not found then raise exception 'No existe el comprobante %.', p_id; end if;
  if f.estado_doc <> 'borrador' then raise exception 'El comprobante ya está emitido.'; end if;
  if not exists (select 1 from public.factura_linea where factura_id = p_id) then raise exception 'El comprobante no tiene líneas.'; end if;
  if coalesce(p_tipo_comprobante_id, f.tipo_comprobante_id) is null then raise exception 'Elegí el tipo de comprobante.'; end if;
  if f.modo = 'fiscal' and (nullif(btrim(coalesce(p_punto_venta, f.punto_venta, '')), '') is null
        or nullif(btrim(coalesce(p_numero, f.numero, '')), '') is null or nullif(btrim(coalesce(p_cae, f.cae, '')), '') is null) then
    raise exception 'Faltan el punto de venta, el número o el CAE del comprobante emitido en ARCA.';
  end if;
  if f.factura_origen_id is not null then
    if (select estado_doc from public.factura where id = f.factura_origen_id) <> 'emitida' then
      raise exception 'La factura de origen todavía no está emitida.';
    end if;
    if f.clase = 'nc' then
      for r in select l.ot_id, sum(l.neto) as neto from public.factura_linea l where l.factura_id = p_id group by l.ot_id loop
        select coalesce(sum(l2.neto) filter (where h.clase in ('factura','nd')), 0)
             - coalesce(sum(l2.neto) filter (where h.clase = 'nc' and h.id <> p_id), 0)
          into v_origen_neto
          from public.factura h join public.factura_linea l2 on l2.factura_id = h.id
         where l2.ot_id = r.ot_id and (h.id = f.factura_origen_id or h.factura_origen_id = f.factura_origen_id) and h.estado_doc = 'emitida';
        if r.neto > v_origen_neto + 0.005 then
          raise exception 'La nota de crédito supera lo facturado de la OT % (disponible: %).', (select codigo from public.ot where id = r.ot_id), v_origen_neto;
        end if;
      end loop;
    end if;
  end if;
  perform public.via_funcion(true);
  update public.factura set estado_doc = 'emitida',
         tipo_comprobante_id = coalesce(p_tipo_comprobante_id, tipo_comprobante_id),
         punto_venta = coalesce(p_punto_venta, punto_venta), numero = coalesce(p_numero, numero),
         cae = coalesce(p_cae, cae), cae_vencimiento = coalesce(p_cae_vencimiento, cae_vencimiento),
         fecha = coalesce(p_fecha, fecha)
   where id = p_id;
  perform public.via_funcion(false);
end $$;

-- ---------------------------------------------------------------------
-- Funciones: cobranza
-- ---------------------------------------------------------------------
-- Composición vigente de una factura por OT (líneas + ND − NC)
create or replace function public._composicion_factura(p_factura bigint) returns table (ot_id bigint, neto numeric, iva numeric)
language sql stable security definer set search_path = public as
$$
  select l.ot_id,
         sum(case when h.clase = 'nc' then -l.neto else l.neto end),
         sum(case when h.clase = 'nc' then -l.iva  else l.iva  end)
    from public.factura h join public.factura_linea l on l.factura_id = h.id
   where (h.id = p_factura or h.factura_origen_id = p_factura) and h.estado_doc = 'emitida'
   group by l.ot_id
$$;

-- Reparte un importe aplicado a una factura entre sus OT (neto, IVA, otros tributos); suma exacta
create or replace function public._asignar_cobro_ot(p_factura bigint, p_importe numeric) returns table (ot_id bigint, neto numeric, iva numeric, otros numeric)
language sql stable security definer set search_path = public as
$$
  with comp as (select c.ot_id, c.neto, c.iva from public._composicion_factura(p_factura) c where c.neto + c.iva > 0),
       tot as (select sum(neto + iva) as s from comp),
       f as (select otros_tributos as o from public.factura where id = p_factura),
       raw as (select c.ot_id,
                      round(p_importe * c.neto / (t.s + f.o), 2) as rn,
                      round(p_importe * c.iva  / (t.s + f.o), 2) as ri,
                      round(p_importe * f.o * ((c.neto + c.iva) / t.s) / (t.s + f.o), 2) as ro
                 from comp c, tot t, f),
       aj as (select *, row_number() over (order by rn desc, ot_id) as rk, p_importe - sum(rn + ri + ro) over () as resid from raw)
  select ot_id, rn + case when rk = 1 then resid else 0 end, ri, ro from aj
$$;

create or replace function public.registrar_cobranza(p_cliente bigint, p_importe numeric, p_aplicaciones jsonb,
    p_receptor_asociado bigint default null, p_cuenta_destino bigint default null, p_medio_id bigint default null,
    p_fecha_cobro date default public.hoy_ar(), p_fecha_disponibilidad date default null,
    p_ret_iva numeric default 0, p_ret_otras numeric default 0, p_observacion text default null) returns bigint
language plpgsql security definer set search_path = public as
$$
declare
  v_id bigint; ap jsonb; f record; v_imp numeric; a record; v_dias int := 0;
  v_suma numeric := 0; v_iva numeric := 0; v_neto numeric := 0; v_sobrante numeric; v_cod text;
begin
  perform public.exige_permiso('cobranza', 2);
  if not exists (select 1 from public.cliente where id = p_cliente) then raise exception 'No existe el cliente.'; end if;
  if coalesce(p_importe, 0) < 0 or coalesce(p_ret_iva, 0) < 0 or coalesce(p_ret_otras, 0) < 0 then raise exception 'Los importes no pueden ser negativos.'; end if;
  if coalesce(p_importe, 0) + coalesce(p_ret_iva, 0) + coalesce(p_ret_otras, 0) <= 0 then raise exception 'La cobranza no tiene importe.'; end if;
  if p_aplicaciones is null or jsonb_typeof(p_aplicaciones) <> 'array' or jsonb_array_length(p_aplicaciones) = 0 then
    raise exception 'Indicá a qué facturas se aplica la cobranza.';
  end if;
  if p_receptor_asociado is not null and exists (select 1 from public.asociado where id = p_receptor_asociado and estado = 'baja') then
    raise exception 'El asociado está dado de baja: no admite nuevas asignaciones.';
  end if;
  perform public.exige_cuenta(p_cuenta_destino, case when p_receptor_asociado is null then 'cooperativa' else 'asociado' end, p_receptor_asociado);
  if p_medio_id is not null then select dias_acreditacion into v_dias from public.medio_pago where id = p_medio_id; end if;

  insert into public.cobranza (cliente_id, receptor_tipo, receptor_asociado_id, cuenta_destino_id, medio_pago_id, fecha_cobro, fecha_disponibilidad,
                               importe, ret_iva, ret_otras, observacion)
  values (p_cliente, case when p_receptor_asociado is null then 'cooperativa' else 'asociado' end, p_receptor_asociado, p_cuenta_destino, p_medio_id,
          p_fecha_cobro, coalesce(p_fecha_disponibilidad, p_fecha_cobro + coalesce(v_dias, 0)), coalesce(p_importe, 0), coalesce(p_ret_iva, 0), coalesce(p_ret_otras, 0), p_observacion)
  returning id, codigo into v_id, v_cod;

  for ap in select * from jsonb_array_elements(p_aplicaciones) loop
    select * into f from public.factura_resumen where id = (ap ->> 'factura_id')::bigint;
    if not found then raise exception 'No existe la factura %.', ap ->> 'factura_id'; end if;
    if f.clase <> 'factura' or f.estado_doc <> 'emitida' then raise exception 'Solo se cobran facturas emitidas (%).', f.codigo; end if;
    if f.cliente_id <> p_cliente then raise exception 'La factura % no es de ese cliente.', f.codigo; end if;
    v_imp := (ap ->> 'importe')::numeric;
    if v_imp is null or v_imp <= 0 then raise exception 'El importe aplicado a % debe ser mayor a cero.', f.codigo; end if;
    if v_imp > f.saldo + 0.005 then raise exception 'El importe aplicado a % supera su saldo (%).', f.codigo, f.saldo; end if;
    insert into public.cobranza_aplicacion (cobranza_id, factura_id, importe) values (v_id, f.id, v_imp);
    for a in select * from public._asignar_cobro_ot(f.id, v_imp) loop
      insert into public.cobranza_ot (cobranza_id, factura_id, ot_id, neto, iva, otros) values (v_id, f.id, a.ot_id, a.neto, a.iva, a.otros);
      v_iva := v_iva + a.iva; v_neto := v_neto + a.neto;
    end loop;
    v_suma := v_suma + v_imp;
  end loop;

  v_sobrante := coalesce(p_importe, 0) + coalesce(p_ret_iva, 0) + coalesce(p_ret_otras, 0) - v_suma;
  if v_sobrante < -0.005 then raise exception 'Lo aplicado (%) supera lo cobrado más las retenciones.', v_suma; end if;
  if coalesce(p_ret_iva, 0) > v_iva + 0.005 then raise exception 'La retención de IVA (%) supera el IVA de lo aplicado (%).', p_ret_iva, v_iva; end if;
  if coalesce(p_ret_otras, 0) > v_neto + 0.005 then raise exception 'Las retenciones de Ganancias/IIBB/otras (%) superan el neto de lo aplicado (%).', p_ret_otras, v_neto; end if;
  v_sobrante := greatest(v_sobrante, 0);
  if v_sobrante > 0 then
    update public.cobranza set sobrante = v_sobrante where id = v_id;
    perform public.mov_cli(p_cliente, v_sobrante, v_cod || ' · sobrante de cobranza', 'cobranza', v_id, p_fecha_cobro);
  end if;
  perform public.hook_cobranza_registrada(v_id);
  return v_id;
end $$;

-- Aplica el saldo a favor del cliente a facturas nuevas
create or replace function public.aplicar_saldo_favor(p_cliente bigint, p_aplicaciones jsonb, p_fecha date default public.hoy_ar(), p_observacion text default null) returns bigint
language plpgsql security definer set search_path = public as
$$
declare v_id bigint; v_cod text; ap jsonb; f record; v_imp numeric; a record; v_suma numeric := 0;
begin
  perform public.exige_permiso('cobranza', 2);
  if p_aplicaciones is null or jsonb_typeof(p_aplicaciones) <> 'array' or jsonb_array_length(p_aplicaciones) = 0 then
    raise exception 'Indicá a qué facturas se aplica el saldo.';
  end if;
  insert into public.cobranza (tipo, cliente_id, fecha_cobro, fecha_disponibilidad, observacion)
  values ('saldo_favor', p_cliente, p_fecha, p_fecha, p_observacion) returning id, codigo into v_id, v_cod;
  for ap in select * from jsonb_array_elements(p_aplicaciones) loop
    select * into f from public.factura_resumen where id = (ap ->> 'factura_id')::bigint;
    if not found or f.clase <> 'factura' or f.estado_doc <> 'emitida' then raise exception 'Solo se aplica saldo a facturas emitidas.'; end if;
    if f.cliente_id <> p_cliente then raise exception 'La factura % no es de ese cliente.', f.codigo; end if;
    v_imp := (ap ->> 'importe')::numeric;
    if v_imp is null or v_imp <= 0 then raise exception 'El importe aplicado a % debe ser mayor a cero.', f.codigo; end if;
    if v_imp > f.saldo + 0.005 then raise exception 'El importe aplicado a % supera su saldo (%).', f.codigo, f.saldo; end if;
    insert into public.cobranza_aplicacion (cobranza_id, factura_id, importe) values (v_id, f.id, v_imp);
    for a in select * from public._asignar_cobro_ot(f.id, v_imp) loop
      insert into public.cobranza_ot (cobranza_id, factura_id, ot_id, neto, iva, otros) values (v_id, f.id, a.ot_id, a.neto, a.iva, a.otros);
    end loop;
    v_suma := v_suma + v_imp;
  end loop;
  if v_suma > public.saldo_cliente(p_cliente) + 0.005 then
    raise exception 'El saldo a favor del cliente (%) no alcanza para aplicar %.', public.saldo_cliente(p_cliente), v_suma;
  end if;
  perform public.mov_cli(p_cliente, -v_suma, v_cod || ' · saldo a favor aplicado a facturas', 'aplicacion', v_id, p_fecha);
  perform public.hook_cobranza_registrada(v_id);
  return v_id;
end $$;

create or replace function public.revertir_cobranza(p_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as
$$
declare c public.cobranza; v_mot text := nullif(btrim(coalesce(p_motivo, '')), ''); nc record; v_sob numeric;
begin
  perform public.exige_permiso('cobranza', 3);
  if v_mot is null then raise exception 'El motivo es obligatorio.'; end if;
  select * into c from public.cobranza where id = p_id for update;
  if not found then raise exception 'No existe la cobranza %.', p_id; end if;
  if c.anulada then raise exception 'La cobranza ya está anulada.'; end if;
  select f.codigo into nc from public.cobranza_aplicacion ap join public.factura f on f.id = ap.factura_id
   where ap.cobranza_id = p_id
     and (exists (select 1 from public.factura h where h.factura_origen_id = f.id and h.estado_doc = 'emitida' and h.clase = 'nc')
          or exists (select 1 from public.factura_credito_resuelto r where r.factura_id = f.id))
   limit 1;
  if found then raise exception 'La factura % tiene notas de crédito: por ahora no se puede revertir esta cobranza.', nc.codigo; end if;
  select coalesce(sum(importe), 0) into v_sob from public.movimiento_cc_cliente
   where origen_tipo = 'cobranza' and origen_id = p_id and revierte_id is null and importe > 0;
  if v_sob > 0 and public.saldo_cliente(c.cliente_id) < v_sob - 0.005 then
    raise exception 'El sobrante de esta cobranza ya se aplicó a otras facturas o se devolvió: revertí primero esa aplicación.';
  end if;
  perform public.set_motivo(v_mot);
  update public.cobranza set anulada = true, anulada_en = now(), anulada_motivo = v_mot, anulada_por = auth.uid() where id = p_id;
  perform public.revertir_movs_cli('cobranza', p_id, c.codigo || ' · reversión de cobranza');
  perform public.revertir_movs_cli('aplicacion', p_id, c.codigo || ' · reversión de aplicación de saldo');
  perform public.hook_cobranza_revertida(p_id);
  perform public.set_motivo(null);
end $$;

-- Resolver el crédito que deja una nota de crédito sobre una factura ya cobrada
create or replace function public.resolver_credito_factura(p_factura bigint, p_importe numeric, p_destino text, p_fecha date default public.hoy_ar(),
    p_medio_id bigint default null, p_pagador_asociado_id bigint default null, p_cuenta_origen_id bigint default null,
    p_cuenta_destino_id bigint default null, p_observacion text default null) returns bigint
language plpgsql security definer set search_path = public as
$$
declare f record; v_id bigint; v_dev bigint; v_cod text; r record; v_total_nc numeric;
begin
  perform public.exige_permiso('cobranza', 2);
  if p_destino not in ('saldo_favor','devolucion') then raise exception 'El destino debe ser saldo_favor o devolucion.'; end if;
  select * into f from public.factura_resumen where id = p_factura;
  if not found or f.clase <> 'factura' then raise exception 'No existe la factura.'; end if;
  if p_importe is null or p_importe <= 0 then raise exception 'El importe debe ser mayor a cero.'; end if;
  if p_importe > f.credito_a_resolver + 0.005 then raise exception 'El importe supera el crédito a resolver de la factura (%).', f.credito_a_resolver; end if;
  if p_destino = 'devolucion' then
    if p_pagador_asociado_id is not null and exists (select 1 from public.asociado where id = p_pagador_asociado_id and estado = 'baja') then
      raise exception 'El asociado está dado de baja: no admite nuevas asignaciones.';
    end if;
    perform public.exige_cuenta(p_cuenta_origen_id, case when p_pagador_asociado_id is null then 'cooperativa' else 'asociado' end, p_pagador_asociado_id);
    perform public.exige_cuenta(p_cuenta_destino_id, 'cliente', f.cliente_id);
    insert into public.devolucion_cliente (cliente_id, importe, fecha, medio_pago_id, pagador_tipo, pagador_asociado_id, cuenta_origen_id, cuenta_destino_id, observacion)
    values (f.cliente_id, p_importe, p_fecha, p_medio_id, case when p_pagador_asociado_id is null then 'cooperativa' else 'asociado' end,
            p_pagador_asociado_id, p_cuenta_origen_id, p_cuenta_destino_id, p_observacion) returning id, codigo into v_dev, v_cod;
  end if;
  insert into public.factura_credito_resuelto (factura_id, importe, destino, devolucion_id, fecha, observacion)
  values (p_factura, p_importe, p_destino, v_dev, p_fecha, p_observacion) returning id into v_id;

  -- se reparte lo resuelto entre las OT según las notas de crédito emitidas
  select sum(x.total) into v_total_nc
    from public.factura h join public.factura_total x on x.id = h.id
   where h.factura_origen_id = p_factura and h.clase = 'nc' and h.estado_doc = 'emitida';
  if v_total_nc is null or v_total_nc <= 0 then raise exception 'La factura no tiene notas de crédito emitidas.'; end if;
  for r in select l.ot_id, sum(l.neto) as neto, sum(l.iva) as iva
             from public.factura h join public.factura_linea l on l.factura_id = h.id
            where h.factura_origen_id = p_factura and h.clase = 'nc' and h.estado_doc = 'emitida' group by l.ot_id
  loop
    insert into public.factura_credito_resuelto_ot (resuelto_id, ot_id, neto, iva)
    values (v_id, r.ot_id, round(p_importe * r.neto / v_total_nc, 2), round(p_importe * r.iva / v_total_nc, 2));
  end loop;

  if p_destino = 'saldo_favor' then
    perform public.mov_cli(f.cliente_id, p_importe, 'Crédito de ' || f.codigo || ' dejado a favor del cliente', 'resolucion', v_id, p_fecha);
  elsif p_pagador_asociado_id is not null then
    perform public.mov_cc(p_pagador_asociado_id, p_importe, v_cod || ' · devolución a cliente pagada por el asociado', 'devolucion', v_dev, p_fecha);
  end if;
  perform public.hook_credito_resuelto(v_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Auditoría y permisos
-- ---------------------------------------------------------------------
select public.preparar_tabla('factura',                    'facturacion', 'id', false, 2, true);
select public.preparar_tabla('factura_linea',              'facturacion', 'id', false, 2, true);
select public.preparar_tabla('cobranza',                   'cobranza', 'id', false, 2, false);
select public.preparar_tabla('cobranza_aplicacion',        'cobranza', 'id', false, 2, false);
select public.preparar_tabla('cobranza_ot',                'cobranza', 'id', false, 2, false);
select public.preparar_tabla('movimiento_cc_cliente',      'cobranza', 'id', false, 2, false);
select public.preparar_tabla('devolucion_cliente',         'cobranza', 'id', false, 2, false);
select public.preparar_tabla('factura_credito_resuelto',   'cobranza', 'id', false, 2, false);
select public.preparar_tabla('factura_credito_resuelto_ot','cobranza', 'resuelto_id', false, 2, false);

-- Lo que mueve plata solo se toca por funciones
drop policy p_ins on public.cobranza;                    drop policy p_upd on public.cobranza;
drop policy p_ins on public.cobranza_aplicacion;         drop policy p_upd on public.cobranza_aplicacion;
drop policy p_ins on public.cobranza_ot;                 drop policy p_upd on public.cobranza_ot;
drop policy p_ins on public.movimiento_cc_cliente;       drop policy p_upd on public.movimiento_cc_cliente;
drop policy p_ins on public.devolucion_cliente;          drop policy p_upd on public.devolucion_cliente;
drop policy p_ins on public.factura_credito_resuelto;    drop policy p_upd on public.factura_credito_resuelto;
drop policy p_ins on public.factura_credito_resuelto_ot; drop policy p_upd on public.factura_credito_resuelto_ot;

revoke execute on function public.emitir_factura(bigint, text, text, text, date, bigint, date) from public, anon;
revoke execute on function public.registrar_cobranza(bigint, numeric, jsonb, bigint, bigint, bigint, date, date, numeric, numeric, text) from public, anon;
revoke execute on function public.aplicar_saldo_favor(bigint, jsonb, date, text) from public, anon;
revoke execute on function public.revertir_cobranza(bigint, text) from public, anon;
revoke execute on function public.resolver_credito_factura(bigint, numeric, text, date, bigint, bigint, bigint, bigint, text) from public, anon;
revoke execute on function public.saldo_cliente(bigint) from public, anon;
revoke execute on function public._composicion_factura(bigint) from public, anon, authenticated;
revoke execute on function public._asignar_cobro_ot(bigint, numeric) from public, anon, authenticated;
grant execute on function public.emitir_factura(bigint, text, text, text, date, bigint, date) to authenticated, service_role;
grant execute on function public.registrar_cobranza(bigint, numeric, jsonb, bigint, bigint, bigint, date, date, numeric, numeric, text) to authenticated, service_role;
grant execute on function public.aplicar_saldo_favor(bigint, jsonb, date, text) to authenticated, service_role;
grant execute on function public.revertir_cobranza(bigint, text) to authenticated, service_role;
grant execute on function public.resolver_credito_factura(bigint, numeric, text, date, bigint, bigint, bigint, bigint, text) to authenticated, service_role;
grant execute on function public.saldo_cliente(bigint) to authenticated, service_role;

insert into public.migraciones (version, descripcion) values ('0005', 'Facturación y cobranza: comprobantes, NC/ND, cobranzas, cuenta corriente del cliente, resolución de crédito');
commit;
