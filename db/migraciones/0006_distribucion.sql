-- =====================================================================
-- 0006 · DISTRIBUCIÓN
-- Reglas de reparto por OT (versionadas), distribución de cada cobranza
-- (cada cobro parcial genera su propia instancia), modos proporcional y
-- "costos primero", retenciones y efectivo retenido, ajuste automático
-- cuando cambian los costos, reversión proporcional por notas de crédito,
-- reversión de cobranzas y regalías.
-- Requiere 0001 a 0005. Pegar TODO en SQL Editor → Run.
--
-- Cuenta corriente de asociados: + la Cooperativa le debe · − el asociado debe.
-- =====================================================================
begin;

do $$ begin
  if not exists (select 1 from public.migraciones where version = '0005') then
    raise exception 'Falta aplicar la migración 0005 antes de esta.';
  end if;
  if exists (select 1 from public.migraciones where version = '0006') then
    raise exception 'La migración 0006 ya fue aplicada: no se puede correr dos veces.';
  end if;
end $$;

-- Configuración: distribuir sola, con la regla vigente, al registrar cada cobranza
alter table public.organizacion add column distribuir_al_cobrar boolean not null default false;

-- Anticipo: el monto se indica al aprobar la línea o al crear la OT; es neto (sin IVA) y no supera el neto de la OT
alter table public.ot add constraint ot_anticipo_coherente
  check (anticipo_monto is null or (requiere_anticipo and anticipo_monto <= neto));

-- ---------------------------------------------------------------------
-- Reglas de distribución (versionadas: nunca se modifican)
-- ---------------------------------------------------------------------
create table public.regla_distribucion (
  id bigint generated always as identity primary key,
  ot_id bigint not null references public.ot (id),
  version int not null check (version >= 1),
  motivo text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(),
  unique (ot_id, version)
);

create table public.regla_distribucion_parte (
  id bigint generated always as identity primary key,
  regla_id bigint not null references public.regla_distribucion (id),
  orden int not null,
  asociado_id bigint references public.asociado (id),                         -- vacío = la Cooperativa
  tipo text not null check (tipo in ('porcentaje','fijo','residual')),
  valor numeric(18,4),
  como text check (como in ('socio','profesional')),                          -- retorno (socio) u honorarios (profesional)
  unique (regla_id, orden),
  check ((tipo = 'residual' and valor is null) or (tipo <> 'residual' and valor > 0)),
  check ((asociado_id is null) = (como is null))
);
create unique index regla_parte_un_asociado on public.regla_distribucion_parte (regla_id, asociado_id) where asociado_id is not null;
create unique index regla_parte_una_coop on public.regla_distribucion_parte (regla_id) where asociado_id is null;
create unique index regla_parte_un_residual on public.regla_distribucion_parte (regla_id) where tipo = 'residual';

-- ---------------------------------------------------------------------
-- Distribuciones: una instancia por cobranza y OT, más los ajustes
-- ---------------------------------------------------------------------
create table public.distribucion (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  ot_id bigint not null references public.ot (id),
  tipo text not null check (tipo in ('cobro','ajuste_costos','ajuste_nc','ajuste_cierre')),
  cobranza_id bigint references public.cobranza (id),
  credito_resuelto_id bigint references public.factura_credito_resuelto (id),
  fecha date not null default public.hoy_ar(),
  regla_id bigint references public.regla_distribucion (id),
  variante boolean not null default false,                                    -- se usó una regla distinta solo para este cobro
  base numeric(18,2) not null,                                                -- neto cobrado sin IVA
  costo_descontado numeric(18,2) not null default 0,
  resultado numeric(18,2) not null,                                           -- lo que se reparte
  motivo text,
  anulada boolean not null default false,
  anulada_en timestamptz, anulada_motivo text,
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now()
);
create unique index dist_un_cobro on public.distribucion (cobranza_id, ot_id) where tipo = 'cobro' and not anulada;
create index on public.distribucion (ot_id);
create index on public.distribucion (cobranza_id);

create table public.distribucion_parte (
  id bigint generated always as identity primary key,
  distribucion_id bigint not null references public.distribucion (id),
  orden int not null,
  asociado_id bigint references public.asociado (id),
  tipo text not null check (tipo in ('porcentaje','fijo','residual')),
  valor numeric(18,4),
  como text check (como in ('socio','profesional')),
  monto numeric(18,2) not null,
  unique (distribucion_id, orden)
);

-- ---------------------------------------------------------------------
-- Vistas
-- ---------------------------------------------------------------------
create view public.regla_distribucion_vigente with (security_invoker = true) as
select distinct on (r.ot_id) r.ot_id, r.id as regla_id, r.version, r.creado_en
  from public.regla_distribucion r order by r.ot_id, r.version desc;

create view public.cobranza_pendiente_distribuir with (security_invoker = true) as
select c.id as cobranza_id, c.codigo, c.cliente_id, c.fecha_cobro, c.tipo,
       array_agg(distinct co.ot_id) as ots
  from public.cobranza c
  join public.cobranza_ot co on co.cobranza_id = c.id
 where not c.anulada
   and exists (select 1 from public.cobranza_ot x where x.cobranza_id = c.id
                and not exists (select 1 from public.distribucion d where d.cobranza_id = c.id and d.ot_id = x.ot_id and d.tipo = 'cobro' and not d.anulada))
 group by c.id;

create view public.ot_resumen_financiero with (security_invoker = true) as
select o.id as ot_id, o.codigo, o.cliente_id, o.estado, o.neto,
       f.facturado_neto, f.estado_facturacion, c.cobrado_neto,
       k.gastos_total, k.costo_margen,
       o.neto - k.costo_margen as margen_estimado,
       coalesce(d.distribuido, 0) as distribuido
  from public.ot o
  join public.ot_facturacion f on f.ot_id = o.id
  join public.ot_cobranza c on c.ot_id = o.id
  join public.ot_costos k on k.ot_id = o.id
  left join lateral (select sum(resultado) as distribuido from public.distribucion where ot_id = o.id and not anulada) d on true;

-- ---------------------------------------------------------------------
-- Cálculo
-- ---------------------------------------------------------------------
-- Valida y normaliza los participantes: [{asociado_id|null, tipo, valor, como}]
create or replace function public._validar_partes(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as
$$
declare it jsonb; v_tipo text; v_val numeric; v_aid bigint; v_como text; a public.asociado; v_out jsonb := '[]'::jsonb;
        v_pct numeric := 0; v_res int := 0; v_fijo int := 0; v_coop int := 0; v_vistos bigint[] := '{}';
begin
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) = 0 then
    raise exception 'La regla necesita al menos un participante.';
  end if;
  for it in select * from jsonb_array_elements(p) loop
    v_tipo := it ->> 'tipo';
    v_aid := nullif(it ->> 'asociado_id', '')::bigint;
    if coalesce(v_tipo, '') not in ('porcentaje','fijo','residual') then raise exception 'El tipo de participación debe ser porcentaje, fijo o residual.'; end if;
    v_val := nullif(it ->> 'valor', '')::numeric;
    if v_tipo = 'residual' then
      v_val := null; v_res := v_res + 1;
    else
      if v_val is null or v_val <= 0 then raise exception 'Cada participación necesita un valor mayor a cero.'; end if;
      if v_tipo = 'porcentaje' then
        if v_val > 100 then raise exception 'Un porcentaje no puede superar 100.'; end if;
        v_pct := v_pct + v_val;
      else
        v_fijo := v_fijo + 1;
      end if;
    end if;
    if v_aid is null then
      v_coop := v_coop + 1; v_como := null;
    else
      select * into a from public.asociado where id = v_aid;
      if not found then raise exception 'No existe el asociado %.', v_aid; end if;
      if a.estado = 'baja' then raise exception 'El asociado % está dado de baja: no admite nuevas asignaciones.', a.apellido_nombre; end if;
      if v_aid = any (v_vistos) then raise exception 'Un participante aparece más de una vez.'; end if;
      v_vistos := v_vistos || v_aid;
      v_como := nullif(it ->> 'como', '');
      if v_como is null then
        v_como := case a.vinculo when 'socio_cooperativo' then 'socio' when 'monotributista_autonomo' then 'profesional' else null end;
      end if;
      if v_como is null then raise exception 'Elegí cómo participa % (socio o profesional).', a.apellido_nombre; end if;
      if v_como not in ('socio','profesional') then raise exception 'La participación debe ser socio o profesional.'; end if;
    end if;
    v_out := v_out || jsonb_build_object('asociado_id', v_aid, 'tipo', v_tipo, 'valor', v_val, 'como', v_como);
  end loop;
  if v_coop > 1 then raise exception 'La Cooperativa aparece más de una vez.'; end if;
  if v_res > 1 then raise exception 'Solo puede haber un participante con el resto (residual).'; end if;
  if v_fijo > 0 and v_res = 0 then raise exception 'Con importes fijos hace falta un participante residual que reciba el resto.'; end if;
  if v_pct > 100.0001 then raise exception 'Los porcentajes superan 100.'; end if;
  if v_res = 0 and abs(v_pct - 100) > 0.0001 then
    raise exception 'Los porcentajes deben sumar 100 (suman %) o debe haber un participante residual.', v_pct;
  end if;
  return v_out;
end $$;

-- Monto de cada participante. Porcentaje: % del resultado. Fijo: prorrateado por lo cobrado de la OT.
-- Residual: lo que queda. Sin residual, el redondeo lo absorbe el mayor.
create or replace function public._repartir(p_res numeric, p_partes jsonb, p_base numeric, p_neto_ot numeric) returns numeric[]
language plpgsql immutable as
$$
declare n int := jsonb_array_length(p_partes); i int; p jsonb; m numeric[] := array_fill(0::numeric, array[n]);
        v numeric; suma numeric := 0; i_res int := null; i_max int := 1; v_max numeric := -1;
begin
  for i in 0 .. n - 1 loop
    p := p_partes -> i;
    if p ->> 'tipo' = 'porcentaje' then v := round(p_res * (p ->> 'valor')::numeric / 100, 2);
    elsif p ->> 'tipo' = 'fijo' then v := case when p_neto_ot > 0 then round((p ->> 'valor')::numeric * p_base / p_neto_ot, 2) else 0 end;
    else v := 0; i_res := i + 1;
    end if;
    m[i + 1] := v; suma := suma + v;
    if abs(v) > v_max then v_max := abs(v); i_max := i + 1; end if;
  end loop;
  if i_res is not null then m[i_res] := p_res - suma;
  else m[i_max] := m[i_max] + (p_res - suma);
  end if;
  return m;
end $$;

create or replace function public._regla_actual(p_ot bigint) returns bigint
language sql stable security definer set search_path = public as
$$ select id from public.regla_distribucion where ot_id = p_ot order by version desc limit 1 $$;

create or replace function public._partes_regla(p_regla bigint) returns jsonb
language sql stable security definer set search_path = public as
$$ select jsonb_agg(jsonb_build_object('asociado_id', asociado_id, 'tipo', tipo, 'valor', valor, 'como', como) order by orden)
     from public.regla_distribucion_parte where regla_id = p_regla $$;

create or replace function public._nueva_version_regla(p_ot bigint, p_partes jsonb, p_motivo text) returns bigint
language plpgsql security definer set search_path = public as
$$
declare v_id bigint; v_ver int; it jsonb; n int := 0;
begin
  select coalesce(max(version), 0) + 1 into v_ver from public.regla_distribucion where ot_id = p_ot;
  insert into public.regla_distribucion (ot_id, version, motivo) values (p_ot, v_ver, p_motivo) returning id into v_id;
  for it in select * from jsonb_array_elements(p_partes) loop
    n := n + 1;
    insert into public.regla_distribucion_parte (regla_id, orden, asociado_id, tipo, valor, como)
    values (v_id, n, nullif(it ->> 'asociado_id', '')::bigint, it ->> 'tipo', nullif(it ->> 'valor', '')::numeric, it ->> 'como');
  end loop;
  return v_id;
end $$;

-- Crea una instancia de distribución y acredita a cada asociado su parte
create or replace function public._crear_distribucion(p_ot bigint, p_tipo text, p_cobranza bigint, p_resuelto bigint, p_regla bigint,
    p_variante boolean, p_partes jsonb, p_base numeric, p_desc numeric, p_res numeric, p_motivo text) returns bigint
language plpgsql security definer set search_path = public as
$$
declare v_id bigint; v_cod text; v_neto numeric; m numeric[]; it jsonb; i int := 0; v_mov text; v_ot text;
begin
  select neto, codigo into v_neto, v_ot from public.ot where id = p_ot;
  insert into public.distribucion (ot_id, tipo, cobranza_id, credito_resuelto_id, regla_id, variante, base, costo_descontado, resultado, motivo)
  values (p_ot, p_tipo, p_cobranza, p_resuelto, p_regla, p_variante, p_base, p_desc, p_res, p_motivo) returning id, codigo into v_id, v_cod;
  m := public._repartir(p_res, p_partes, p_base, v_neto);
  v_mov := case when p_tipo = 'cobro' then 'distribucion' else 'ajuste' end;
  for it in select * from jsonb_array_elements(p_partes) loop
    i := i + 1;
    insert into public.distribucion_parte (distribucion_id, orden, asociado_id, tipo, valor, como, monto)
    values (v_id, i, nullif(it ->> 'asociado_id', '')::bigint, it ->> 'tipo', nullif(it ->> 'valor', '')::numeric, it ->> 'como', m[i]);
    if nullif(it ->> 'asociado_id', '') is not null and m[i] <> 0 then
      perform public.mov_cc((it ->> 'asociado_id')::bigint, m[i],
        v_cod || ' · ' || case p_tipo when 'cobro' then 'participación en ' when 'ajuste_costos' then 'ajuste por costos de ' when 'ajuste_nc' then 'ajuste por nota de crédito de ' else 'ajuste de ' end || v_ot,
        v_mov, v_id);
    end if;
  end loop;
  return v_id;
end $$;

-- Reajusta la distribución de una OT para que lo repartido coincida con lo que corresponde hoy.
-- p_base_delta: variación del neto cobrado (negativa en una nota de crédito resuelta)
create or replace function public._reajustar_ot(p_ot bigint, p_base_delta numeric, p_tipo text, p_cobranza bigint, p_resuelto bigint,
    p_motivo text, p_umbral numeric default 0.5) returns bigint
language plpgsql security definer set search_path = public as
$$
declare o public.ot; v_reg bigint; v_base numeric; v_new numeric; v_cm numeric; v_real numeric; v_cur numeric; v_dif numeric;
begin
  select * into o from public.ot where id = p_ot for update;
  if not exists (select 1 from public.distribucion where ot_id = p_ot and not anulada) then return null; end if;
  v_reg := public._regla_actual(p_ot);
  if v_reg is null then return null; end if;
  select coalesce(sum(base), 0), coalesce(sum(resultado), 0) into v_base, v_cur
    from public.distribucion where ot_id = p_ot and not anulada;
  select coalesce(sum(base) filter (where tipo in ('cobro','ajuste_nc')), 0) into v_base
    from public.distribucion where ot_id = p_ot and not anulada;
  v_new := v_base + p_base_delta;
  select costo_margen into v_cm from public.ot_costos where ot_id = p_ot;
  if o.modo_dist_parcial = 'costos_primero' then v_real := greatest(0, v_new - v_cm);
  else v_real := case when o.neto > 0 then v_new * greatest(0, (o.neto - v_cm) / o.neto) else v_new end;
  end if;
  v_dif := round(v_real - v_cur, 2);
  if p_base_delta = 0 and abs(v_dif) < p_umbral then return null; end if;
  return public._crear_distribucion(p_ot, p_tipo, p_cobranza, p_resuelto, v_reg, false, public._partes_regla(v_reg),
                                    p_base_delta, p_base_delta - v_dif, v_dif, p_motivo);
end $$;

-- Movimientos de cuenta corriente propios de la cobranza (no de la distribución):
--   · el asociado que recibió el efectivo debe rendir lo cobrado neto de retenciones (y el sobrante)
--   · el emisor asociado absorbe las retenciones de Ganancias/IIBB/otras
--   · el IVA y otros tributos cobrados en efectivo son del emisor: quien los recibe y no los emitió se los debe
create or replace function public._movs_cobranza(p_cobranza bigint) returns void
language plpgsql security definer set search_path = public as
$$
declare c public.cobranza; f record; v_sn numeric; v_sv numeric; v_roi numeric; v_rii numeric; v_tax numeric;
        v_deb numeric := 0; v_totn numeric; v_totv numeric;
begin
  select * into c from public.cobranza where id = p_cobranza;
  if c.tipo <> 'cobro' then return; end if;
  select coalesce(sum(neto), 0), coalesce(sum(iva), 0) into v_totn, v_totv from public.cobranza_ot where cobranza_id = p_cobranza;
  for f in select ap.factura_id, fa.emisor_asociado_id as emisor,
                  coalesce(sum(co.neto), 0) as n, coalesce(sum(co.iva), 0) as v, coalesce(sum(co.otros), 0) as o
             from public.cobranza_aplicacion ap
             join public.factura fa on fa.id = ap.factura_id
             left join public.cobranza_ot co on co.cobranza_id = ap.cobranza_id and co.factura_id = ap.factura_id
            where ap.cobranza_id = p_cobranza
            group by ap.factura_id, fa.emisor_asociado_id
  loop
    v_roi := case when v_totn > 0 then round(c.ret_otras * f.n / v_totn, 2) else 0 end;
    v_rii := case when v_totv > 0 then round(c.ret_iva * f.v / v_totv, 2) else 0 end;
    if f.emisor is not null and v_roi > 0 then
      perform public.mov_cc(f.emisor, -v_roi, c.codigo || ' · retenciones absorbidas por el emisor', 'cobranza', p_cobranza, c.fecha_cobro);
    end if;
    if c.receptor_asociado_id is not null then
      v_deb := v_deb + f.n - v_roi;
      v_tax := greatest(f.v + f.o - v_rii, 0);
      if f.emisor is distinct from c.receptor_asociado_id and v_tax > 0 then
        v_deb := v_deb + v_tax;
        if f.emisor is not null then
          perform public.mov_cc(f.emisor, v_tax, c.codigo || ' · IVA y tributos cobrados por otro asociado', 'cobranza', p_cobranza, c.fecha_cobro);
        end if;
      end if;
    end if;
  end loop;
  if c.receptor_asociado_id is not null then
    v_deb := v_deb + c.sobrante;
    if v_deb <> 0 then
      perform public.mov_cc(c.receptor_asociado_id, -v_deb, c.codigo || ' · efectivo cobrado por el asociado', 'cobranza', p_cobranza, c.fecha_cobro);
    end if;
  end if;
end $$;

-- Distribuye una cobranza entre las OT que cancela. p_reglas: [{ot_id, partes, alcance, motivo, modo}]
create or replace function public._distribuir_cobranza(p_cobranza bigint, p_reglas jsonb) returns int
language plpgsql security definer set search_path = public as
$$
declare c public.cobranza; r record; o public.ot; spec jsonb; v_reg bigint; v_partes jsonb; v_var boolean; v_norm jsonb;
        v_cm numeric; v_desc_tot numeric; v_desc numeric; v_res numeric; v_rem numeric; v_n int := 0; v_alc text; v_mot text; v_modo text;
begin
  select * into c from public.cobranza where id = p_cobranza for update;
  if not found then raise exception 'No existe la cobranza %.', p_cobranza; end if;
  if c.anulada then raise exception 'La cobranza está anulada.'; end if;
  if exists (select 1 from public.distribucion where cobranza_id = p_cobranza and tipo = 'cobro' and not anulada) then
    raise exception 'La cobranza % ya fue distribuida.', c.codigo;
  end if;
  for r in select ot_id, sum(neto) as b from public.cobranza_ot where cobranza_id = p_cobranza group by ot_id order by ot_id loop
    select * into o from public.ot where id = r.ot_id for update;
    spec := null;
    if p_reglas is not null and jsonb_typeof(p_reglas) = 'array' then
      select e into spec from jsonb_array_elements(p_reglas) e where (e ->> 'ot_id')::bigint = r.ot_id limit 1;
    end if;
    v_reg := public._regla_actual(o.id); v_var := false;
    v_modo := nullif(spec ->> 'modo', '');
    if v_modo is not null and v_modo <> o.modo_dist_parcial then
      if v_modo not in ('proporcional','costos_primero') then raise exception 'El modo debe ser proporcional o costos_primero.'; end if;
      if exists (select 1 from public.distribucion where ot_id = o.id and not anulada) then
        raise exception 'La OT % ya tiene distribuciones: no se cambia el modo de reparto parcial.', o.codigo;
      end if;
      update public.ot set modo_dist_parcial = v_modo where id = o.id;
      o.modo_dist_parcial := v_modo;
    end if;
    if spec is not null and jsonb_typeof(spec -> 'partes') = 'array' then
      if o.estado in ('cerrada','cancelada') then raise exception 'La OT % está %: no se cambia su regla.', o.codigo, o.estado; end if;
      v_norm := public._validar_partes(spec -> 'partes');
      v_mot := nullif(btrim(coalesce(spec ->> 'motivo', '')), '');
      if v_reg is null then
        v_reg := public._nueva_version_regla(o.id, v_norm, coalesce(v_mot, 'Regla inicial')); v_partes := v_norm;
      else
        v_alc := spec ->> 'alcance';
        if v_mot is null then raise exception 'Cambiar la regla de % exige un motivo.', o.codigo; end if;
        if coalesce(v_alc, '') not in ('solo_este_cobro','nueva_version') then raise exception 'Indicá si el cambio vale solo para este cobro o como nueva versión.'; end if;
        v_partes := v_norm;
        if v_alc = 'nueva_version' then v_reg := public._nueva_version_regla(o.id, v_norm, v_mot); else v_var := true; end if;
      end if;
    else
      if v_reg is null then raise exception 'La OT % no tiene regla de distribución: definila antes de distribuir.', o.codigo; end if;
      v_partes := public._partes_regla(v_reg);
    end if;

    select costo_margen into v_cm from public.ot_costos where ot_id = o.id;
    select coalesce(sum(costo_descontado), 0) into v_desc_tot from public.distribucion where ot_id = o.id and not anulada;
    if o.modo_dist_parcial = 'costos_primero' then
      v_rem := greatest(0, v_cm - v_desc_tot);
      v_desc := least(greatest(r.b, 0), v_rem);
    else
      v_desc := case when o.neto > 0 then round(r.b * (1 - greatest(0, (o.neto - v_cm) / o.neto)), 2) else 0 end;
    end if;
    v_res := r.b - v_desc;
    perform public._crear_distribucion(o.id, 'cobro', p_cobranza, null, v_reg, v_var, v_partes, r.b, v_desc, v_res,
                                       case when v_var then v_mot end);
    v_n := v_n + 1;
  end loop;
  perform public._movs_cobranza(p_cobranza);
  return v_n;
end $$;

-- ---------------------------------------------------------------------
-- Funciones públicas
-- ---------------------------------------------------------------------
-- Define una nueva versión de la regla de una OT
create or replace function public.definir_regla_ot(p_ot bigint, p_partes jsonb, p_motivo text default null, p_modo text default null) returns bigint
language plpgsql security definer set search_path = public as
$$
declare o public.ot; v_mot text := nullif(btrim(coalesce(p_motivo, '')), ''); v_norm jsonb;
begin
  perform public.exige_permiso('distribucion', 3);
  select * into o from public.ot where id = p_ot for update;
  if not found then raise exception 'No existe la OT %.', p_ot; end if;
  if o.estado in ('cerrada','cancelada') then raise exception 'La OT está %: no se cambia su regla.', o.estado; end if;
  v_norm := public._validar_partes(p_partes);
  if public._regla_actual(p_ot) is not null and v_mot is null then raise exception 'Cambiar la regla exige un motivo.'; end if;
  if p_modo is not null and p_modo <> o.modo_dist_parcial then
    if p_modo not in ('proporcional','costos_primero') then raise exception 'El modo debe ser proporcional o costos_primero.'; end if;
    if exists (select 1 from public.distribucion where ot_id = p_ot and not anulada) then
      raise exception 'La OT ya tiene distribuciones: no se cambia el modo de reparto parcial.';
    end if;
    update public.ot set modo_dist_parcial = p_modo where id = p_ot;
  end if;
  return public._nueva_version_regla(p_ot, v_norm, coalesce(v_mot, 'Regla inicial'));
end $$;

create or replace function public.distribuir_cobranza(p_cobranza bigint, p_reglas jsonb default '[]'::jsonb) returns int
language plpgsql security definer set search_path = public as
$$
declare e jsonb;
begin
  perform public.exige_permiso('distribucion', 2);
  if p_reglas is not null and jsonb_typeof(p_reglas) = 'array' then
    for e in select * from jsonb_array_elements(p_reglas) loop
      if jsonb_typeof(e -> 'partes') = 'array' then perform public.exige_permiso('distribucion', 3); end if;
    end loop;
  end if;
  return public._distribuir_cobranza(p_cobranza, coalesce(p_reglas, '[]'::jsonb));
end $$;

-- Facturar y cobrar una regalía en un solo paso (factura interna + cobranza + distribución); requiere regla previa
create or replace function public.facturar_cobrar_regalia(p_ot bigint, p_fecha date default public.hoy_ar(), p_medio_id bigint default null) returns bigint
language plpgsql security definer set search_path = public as
$$
declare o public.ot; v_f bigint; v_c bigint; v_tipo bigint; v_fact numeric;
begin
  perform public.exige_permiso('distribucion', 2);
  select * into o from public.ot where id = p_ot for update;
  if not found then raise exception 'No existe la OT %.', p_ot; end if;
  if o.modalidad <> 'regalia' then raise exception 'La OT % no es una regalía.', o.codigo; end if;
  if o.estado = 'cancelada' then raise exception 'La OT está cancelada.'; end if;
  if o.neto <= 0 then raise exception 'La regalía no tiene importe.'; end if;
  select facturado_neto into v_fact from public.ot_facturacion where ot_id = p_ot;
  if v_fact > 0 then raise exception 'La OT ya tiene facturación: la regalía no se factura de nuevo.'; end if;
  if public._regla_actual(p_ot) is null then raise exception 'Definí primero la regla de distribución de la OT.'; end if;
  select id into v_tipo from public.lista_valor where lista = 'tipo_comprobante' and nombre = 'Ticket / otro';
  insert into public.factura (clase, modo, cliente_id, emisor_tipo, fecha, tipo_comprobante_id, observacion)
  values ('factura', 'interna', o.cliente_id, 'cooperativa', p_fecha, v_tipo, 'Regalía') returning id into v_f;
  insert into public.factura_linea (factura_id, ot_id, descripcion, neto, iva_pct) values (v_f, p_ot, 'Regalía', o.neto, 0);
  perform public.emitir_factura(v_f, null, null, null, p_fecha, v_tipo);
  v_c := public.registrar_cobranza(p_cliente := o.cliente_id, p_importe := o.neto,
           p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', v_f, 'importe', o.neto)),
           p_medio_id := p_medio_id, p_fecha_cobro := p_fecha, p_observacion := 'Regalía');
  if not exists (select 1 from public.distribucion where cobranza_id = v_c and tipo = 'cobro' and not anulada) then
    perform public._distribuir_cobranza(v_c, '[]'::jsonb);
  end if;
  return v_c;
end $$;

-- ---------------------------------------------------------------------
-- Ganchos: reemplazan a los de 0004 y 0005
-- ---------------------------------------------------------------------
create or replace function public.costos_cambiaron(p_ot_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as
$$ begin perform public._reajustar_ot(p_ot_id, 0, 'ajuste_costos', null, null, p_motivo); end $$;

create or replace function public.hook_cobranza_registrada(p_cobranza bigint) returns void
language plpgsql security definer set search_path = public as
$$
begin
  if not (select distribuir_al_cobrar from public.organizacion) then return; end if;
  if exists (select 1 from public.cobranza_ot co where co.cobranza_id = p_cobranza and public._regla_actual(co.ot_id) is null) then return; end if;
  perform public._distribuir_cobranza(p_cobranza, '[]'::jsonb);
end $$;

create or replace function public.hook_cobranza_revertida(p_cobranza bigint) returns void
language plpgsql security definer set search_path = public as
$$
declare d record; v_cod text; v_ot bigint;
begin
  select codigo into v_cod from public.cobranza where id = p_cobranza;
  for d in select * from public.distribucion where cobranza_id = p_cobranza and not anulada loop
    update public.distribucion set anulada = true, anulada_en = now(), anulada_motivo = 'Cobranza revertida' where id = d.id;
    perform public.revertir_movs_cc(case when d.tipo = 'cobro' then 'distribucion' else 'ajuste' end, d.id, d.codigo || ' · reversión (cobranza revertida)');
  end loop;
  perform public.revertir_movs_cc('cobranza', p_cobranza, v_cod || ' · reversión de movimientos de la cobranza');
  for v_ot in select distinct ot_id from public.distribucion where cobranza_id = p_cobranza loop
    perform public._reajustar_ot(v_ot, 0, 'ajuste_costos', null, null, 'Cobranza ' || v_cod || ' revertida');
  end loop;
end $$;

create or replace function public.hook_credito_resuelto(p_resuelto bigint) returns void
language plpgsql security definer set search_path = public as
$$
declare r record;
begin
  for r in select ot_id, neto from public.factura_credito_resuelto_ot where resuelto_id = p_resuelto and neto > 0 loop
    perform public._reajustar_ot(r.ot_id, -r.neto, 'ajuste_nc', null, p_resuelto, 'Nota de crédito resuelta');
  end loop;
end $$;

revoke execute on function public.hook_cobranza_registrada(bigint) from public, anon, authenticated;
revoke execute on function public.hook_cobranza_revertida(bigint) from public, anon, authenticated;
revoke execute on function public.hook_credito_resuelto(bigint) from public, anon, authenticated;
revoke execute on function public.costos_cambiaron(bigint, text) from public, anon, authenticated;
revoke execute on function public._validar_partes(jsonb) from public, anon, authenticated;
revoke execute on function public._regla_actual(bigint) from public, anon, authenticated;
revoke execute on function public._partes_regla(bigint) from public, anon, authenticated;
revoke execute on function public._nueva_version_regla(bigint, jsonb, text) from public, anon, authenticated;
revoke execute on function public._crear_distribucion(bigint, text, bigint, bigint, bigint, boolean, jsonb, numeric, numeric, numeric, text) from public, anon, authenticated;
revoke execute on function public._reajustar_ot(bigint, numeric, text, bigint, bigint, text, numeric) from public, anon, authenticated;
revoke execute on function public._movs_cobranza(bigint) from public, anon, authenticated;
revoke execute on function public._distribuir_cobranza(bigint, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Auditoría y permisos
-- ---------------------------------------------------------------------
select public.preparar_tabla('regla_distribucion',       'distribucion', 'id', false, 2, false);
select public.preparar_tabla('regla_distribucion_parte', 'distribucion', 'id', false, 2, false);
select public.preparar_tabla('distribucion',             'distribucion', 'id', false, 2, false);
select public.preparar_tabla('distribucion_parte',       'distribucion', 'id', false, 2, false);
drop policy p_ins on public.regla_distribucion;       drop policy p_upd on public.regla_distribucion;
drop policy p_ins on public.regla_distribucion_parte; drop policy p_upd on public.regla_distribucion_parte;
drop policy p_ins on public.distribucion;             drop policy p_upd on public.distribucion;
drop policy p_ins on public.distribucion_parte;       drop policy p_upd on public.distribucion_parte;

create trigger trg_codigo before insert on public.distribucion for each row execute function public.trg_codigo('DIS','t');

revoke execute on function public.definir_regla_ot(bigint, jsonb, text, text) from public, anon;
revoke execute on function public.distribuir_cobranza(bigint, jsonb) from public, anon;
revoke execute on function public.facturar_cobrar_regalia(bigint, date, bigint) from public, anon;
grant execute on function public.definir_regla_ot(bigint, jsonb, text, text) to authenticated, service_role;
grant execute on function public.distribuir_cobranza(bigint, jsonb) to authenticated, service_role;
grant execute on function public.facturar_cobrar_regalia(bigint, date, bigint) to authenticated, service_role;

insert into public.migraciones (version, descripcion) values ('0006', 'Distribución: reglas versionadas, reparto por cobranza, ajustes por costos y notas de crédito, regalías');
commit;
