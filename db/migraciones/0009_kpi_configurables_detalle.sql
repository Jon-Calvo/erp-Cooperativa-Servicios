-- =====================================================================
-- 0009 · KPIs CONFIGURABLES, DETALLE DESGLOSADO Y PERFIL DEL USUARIO
-- · Umbrales de los semáforos de cada indicador, editables por la organización.
-- · Detalle desglosado de cada indicador (grupos con importe y %, y debajo las
--   filas que los componen) para mostrar al tocar una tarjeta.
-- · mis_permisos() y mi_perfil(): lo que el frontend necesita para armar el
--   menú según permisos y aplicar color y modo.
-- Requiere 0001 a 0008. Pegar TODO en SQL Editor → Run.
-- =====================================================================
begin;

do $$ begin
  if not exists (select 1 from public.migraciones where version = '0008') then
    raise exception 'Falta aplicar la migración 0008 antes de esta.';
  end if;
  if exists (select 1 from public.migraciones where version = '0009') then
    raise exception 'La migración 0009 ya fue aplicada: no se puede correr dos veces.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Umbrales configurables de los indicadores
--   alto_bueno: un valor alto es bueno (verde desde "ok", amarillo desde "aviso", rojo por debajo)
--   alto_malo:  un valor alto es malo (verde hasta "ok", amarillo hasta "aviso", rojo por encima)
--   unidad: porcentaje o cantidad (las cobranzas por distribuir se miden por cantidad)
-- ---------------------------------------------------------------------
create table public.kpi_umbral (
  clave text primary key,
  nombre text not null,
  sentido text not null check (sentido in ('alto_bueno','alto_malo')),
  unidad text not null default 'porcentaje' check (unidad in ('porcentaje','cantidad')),
  ok numeric(10,2) not null check (ok >= 0),
  aviso numeric(10,2) not null check (aviso >= 0),
  actualizado_en timestamptz not null default now(),
  check ((sentido = 'alto_bueno' and ok >= aviso) or (sentido = 'alto_malo' and ok <= aviso))
);
insert into public.kpi_umbral (clave, nombre, sentido, unidad, ok, aviso) values
  ('facturacion_mes',          'Facturación del mes',          'alto_bueno', 'porcentaje', 80, 50),
  ('cobranza_mes',             'Cobranza del mes',             'alto_bueno', 'porcentaje', 80, 50),
  ('cartera_vencida',          'Cartera vencida',              'alto_malo',  'porcentaje', 10, 25),
  ('margen_ot',                'Margen de las OT',             'alto_bueno', 'porcentaje', 30, 15),
  ('distribucion_pendiente',   'Cobranzas por distribuir',     'alto_malo',  'cantidad',    0,  2),
  ('monotributo_riesgo',       'Monotributo en riesgo',        'alto_malo',  'porcentaje',  0, 20),
  ('presupuestos_aprobacion',  'Presupuestos aprobados',       'alto_bueno', 'porcentaje', 50, 30),
  ('presupuestos_seguimiento', 'Seguimientos vencidos',        'alto_malo',  'porcentaje',  0, 20),
  ('por_pagar_vencido',        'Por pagar vencido',            'alto_malo',  'porcentaje', 10, 25);
select public.preparar_tabla('kpi_umbral', 'organizacion', 'clave', true, 3, false);
drop policy p_ins on public.kpi_umbral;     -- los indicadores son fijos; solo se ajustan sus umbrales

create or replace function public._tono_kpi(p_clave text, p_valor numeric) returns text
language sql stable security definer set search_path = public as
$$
  select coalesce((select case
      when p_valor is null then 'neutral'
      when u.sentido = 'alto_bueno' then case when p_valor >= u.ok then 'ok' when p_valor >= u.aviso then 'warn' else 'bad' end
      else case when p_valor <= u.ok then 'ok' when p_valor <= u.aviso then 'warn' else 'bad' end end
    from public.kpi_umbral u where u.clave = p_clave), 'neutral')
$$;

-- Mismo panel de 0008, ahora con los umbrales de la tabla
create or replace function public.kpi_panel(p_fecha date default public.hoy_ar())
returns table (orden int, clave text, titulo text, modulo text, unidad text, valor numeric, referencia numeric, referencia_etiqueta text,
               pct numeric, pct_etiqueta text, variacion_pct numeric, comparado_con text, tono text)
language plpgsql stable set search_path = public as
$$
declare
  v_ini date := date_trunc('month', p_fecha)::date;
  v_fin date := (date_trunc('month', p_fecha) + interval '1 month - 1 day')::date;
  v_pini date := (date_trunc('month', p_fecha) - interval '1 month')::date;
  v_pfin date := date_trunc('month', p_fecha)::date - 1;
  v_hoy date := public.hoy_ar();
  a numeric; b numeric; c numeric; d numeric; n int; k int;
begin
  if public.tiene_permiso('facturacion', 1) then
    select coalesce(sum(case when f.clase = 'nc' then -t.neto else t.neto end), 0) into a
      from public.factura f join public.factura_total t on t.id = f.id where f.estado_doc = 'emitida' and f.fecha between v_ini and v_fin;
    select coalesce(sum(case when f.clase = 'nc' then -t.neto else t.neto end), 0) into b
      from public.factura f join public.factura_total t on t.id = f.id where f.estado_doc = 'emitida' and f.fecha between v_pini and v_pfin;
    select coalesce(sum(greatest(o.neto - x.facturado_neto, 0)), 0) into c
      from public.ot o join public.ot_facturacion x on x.ot_id = o.id
     where o.estado <> 'cancelada' and (o.estado in ('finalizada','cerrada') or (o.origen = 'sm' and o.periodo between v_ini and v_fin));
    d := a + c;
    return query select 1, 'facturacion_mes'::text, 'Facturación del mes'::text, 'facturacion'::text, 'importe'::text, a, d, 'a facturar (facturado + pendiente exigible)'::text,
                        public._pct(a, d), 'de lo que corresponde facturar'::text, public._variacion(a, b), 'mes anterior'::text, public._tono_kpi('facturacion_mes', public._pct(a, d));
  end if;
  if public.tiene_permiso('cobranza', 1) and public.tiene_permiso('facturacion', 1) then
    select coalesce(sum(ap.importe), 0) into a from public.cobranza_aplicacion ap join public.cobranza c2 on c2.id = ap.cobranza_id
     where not c2.anulada and c2.fecha_cobro between v_ini and v_fin;
    select coalesce(sum(ap.importe), 0) into b from public.cobranza_aplicacion ap join public.cobranza c2 on c2.id = ap.cobranza_id
     where not c2.anulada and c2.fecha_cobro between v_pini and v_pfin;
    select coalesce(sum(saldo), 0) into c from public.facturas_por_cobrar where vencimiento is null or vencimiento <= v_fin;
    d := a + c;
    return query select 2, 'cobranza_mes'::text, 'Cobranza del mes'::text, 'cobranza'::text, 'importe'::text, a, d, 'cobrable (cobrado + saldo con vencimiento hasta fin de mes)'::text,
                        public._pct(a, d), 'de lo cobrable del mes'::text, public._variacion(a, b), 'mes anterior'::text, public._tono_kpi('cobranza_mes', public._pct(a, d));
  end if;
  if public.tiene_permiso('facturacion', 1) then
    select coalesce(sum(saldo), 0), coalesce(sum(saldo) filter (where tramo <> 'a_vencer'), 0) into d, a from public.facturas_por_cobrar;
    return query select 3, 'cartera_vencida'::text, 'Cartera vencida'::text, 'facturacion'::text, 'importe'::text, a, d, 'total por cobrar'::text,
                        public._pct(a, d), 'del total por cobrar'::text, null::numeric, null::text, public._tono_kpi('cartera_vencida', public._pct(a, d));
  end if;
  if public.tiene_permiso('operaciones', 1) and public.tiene_permiso('costos', 1) then
    select coalesce(sum(o.neto), 0), coalesce(sum(k2.costo_margen), 0) into d, c
      from public.ot o join public.ot_costos k2 on k2.ot_id = o.id where o.estado in ('en_ejecucion','finalizada','cerrada');
    return query select 4, 'margen_ot'::text, 'Margen de las OT'::text, 'operaciones'::text, 'importe'::text, d - c, d, 'neto de las OT'::text,
                        public._pct(d - c, d), 'del neto de las OT'::text, null::numeric, null::text, public._tono_kpi('margen_ot', public._pct(d - c, d));
  end if;
  if public.tiene_permiso('operaciones', 1) then
    select count(*), count(*) filter (where estado in ('finalizada','cerrada')) into n, k from public.ot where estado <> 'cancelada' and periodo between v_ini and v_fin;
    select count(*) filter (where estado in ('finalizada','cerrada')) into b from public.ot where estado <> 'cancelada' and periodo between v_pini and v_pfin;
    return query select 5, 'avance_ot'::text, 'OT del mes finalizadas'::text, 'operaciones'::text, 'cantidad'::text, k::numeric, n::numeric, 'OT del mes'::text,
                        public._pct(k, n), 'de las OT del mes'::text, public._variacion(k, b), 'mes anterior'::text, 'neutral'::text;
  end if;
  if public.tiene_permiso('distribucion', 1) and public.tiene_permiso('cobranza', 1) then
    select count(*) into n from public.cobranza where not anulada and fecha_cobro between v_ini and v_fin;
    select count(*) into k from public.cobranza_pendiente_distribuir where fecha_cobro between v_ini and v_fin;
    select count(*) into c from public.cobranza_pendiente_distribuir;
    return query select 6, 'distribucion_pendiente'::text, 'Cobranzas por distribuir'::text, 'distribucion'::text, 'cantidad'::text, c, n::numeric, 'cobranzas del mes'::text,
                        public._pct(n - k, n), 'de las cobranzas del mes distribuidas'::text, null::numeric, null::text, public._tono_kpi('distribucion_pendiente', c);
  end if;
  if public.tiene_permiso('monotributo', 1) then
    select count(*), count(*) filter (where semaforo in ('rojo','excedido')) into n, k from public.monotributo_estado(p_fecha);
    return query select 7, 'monotributo_riesgo'::text, 'Monotributo en riesgo'::text, 'monotributo'::text, 'cantidad'::text, k::numeric, n::numeric, 'asociados monotributistas'::text,
                        public._pct(k, n), 'de los asociados en rojo o excedidos'::text, null::numeric, null::text,
                        case when n = 0 then 'neutral' else public._tono_kpi('monotributo_riesgo', public._pct(k, n)) end;
  end if;
  if public.tiene_permiso('comercial', 1) then
    select coalesce(sum(neto) filter (where estado = 'aprobada'), 0), coalesce(sum(neto), 0) into a, d
      from public.presupuesto_linea where estado in ('aprobada','rechazada') and fecha_decision between p_fecha - 90 and p_fecha;
    select coalesce(sum(neto) filter (where estado = 'aprobada'), 0) into b
      from public.presupuesto_linea where estado in ('aprobada','rechazada') and fecha_decision between p_fecha - 180 and p_fecha - 91;
    return query select 8, 'presupuestos_aprobacion'::text, 'Presupuestos aprobados (90 días)'::text, 'comercial'::text, 'importe'::text, a, d, 'decidido en 90 días'::text,
                        public._pct(a, d), 'del importe decidido'::text, public._variacion(a, b), '90 días anteriores'::text, public._tono_kpi('presupuestos_aprobacion', public._pct(a, d));
    select count(*), count(*) filter (where proximo_seguimiento < v_hoy) into n, k from public.presupuesto_resumen where estado = 'enviado';
    return query select 9, 'presupuestos_seguimiento'::text, 'Seguimientos vencidos'::text, 'comercial'::text, 'cantidad'::text, k::numeric, n::numeric, 'presupuestos enviados'::text,
                        public._pct(k, n), 'de los enviados'::text, null::numeric, null::text, public._tono_kpi('presupuestos_seguimiento', public._pct(k, n));
  end if;
  if public.tiene_permiso('costos', 1) then
    select coalesce(sum(saldo), 0), coalesce(sum(saldo) filter (where tramo not in ('a_vencer','sin_vencimiento')), 0) into d, a from public.facturas_proveedor_por_pagar;
    return query select 10, 'por_pagar_vencido'::text, 'Por pagar vencido'::text, 'costos'::text, 'importe'::text, a, d, 'total por pagar'::text,
                        public._pct(a, d), 'del total por pagar'::text, null::numeric, null::text, public._tono_kpi('por_pagar_vencido', public._pct(a, d));
    select coalesce(sum(saldo) filter (where saldo > 0), 0), coalesce(-sum(saldo) filter (where saldo < 0), 0) into a, d from public.saldo_cc_asociado;
    return query select 11, 'cc_asociados'::text, 'A favor de los asociados'::text, 'costos'::text, 'importe'::text, a, d, 'deuda de asociados con la Cooperativa'::text,
                        null::numeric, null::text, null::numeric, null::text, 'neutral'::text;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Detalle desglosado de cada indicador
--   nivel 1: grupos (con importe o cantidad y su %); nivel 2: las filas de cada grupo (hasta 50)
--   pct: sobre la referencia del indicador (en las OT del margen, sobre el neto de esa OT)
-- ---------------------------------------------------------------------
create or replace function public.kpi_detalle(p_clave text, p_fecha date default public.hoy_ar())
returns table (orden int, nivel int, grupo text, concepto text, cantidad numeric, importe numeric, pct numeric, entidad text, entidad_id bigint)
language plpgsql stable set search_path = public as
$$
declare
  v_ini date := date_trunc('month', p_fecha)::date;
  v_fin date := (date_trunc('month', p_fecha) + interval '1 month - 1 day')::date;
  v_hoy date := public.hoy_ar();
  g1 numeric; g2 numeric; g3 numeric; g4 numeric; n1 int; n2 int; n3 int; n4 int; d numeric; n int;
begin
  if p_clave not in ('facturacion_mes','cobranza_mes','cartera_vencida','margen_ot','avance_ot','distribucion_pendiente','monotributo_riesgo',
                     'presupuestos_aprobacion','presupuestos_seguimiento','por_pagar_vencido','cc_asociados') then
    raise exception 'No existe el indicador %.', p_clave;
  end if;

  if p_clave = 'facturacion_mes' and public.tiene_permiso('facturacion', 1) then
    select coalesce(sum(case when f.clase = 'nc' then -t.neto else t.neto end), 0), count(*) into g1, n1
      from public.factura f join public.factura_total t on t.id = f.id where f.estado_doc = 'emitida' and f.fecha between v_ini and v_fin;
    select coalesce(sum(greatest(o.neto - x.facturado_neto, 0)), 0), count(*) filter (where o.neto - x.facturado_neto > 0) into g2, n2
      from public.ot o join public.ot_facturacion x on x.ot_id = o.id where o.estado in ('finalizada','cerrada');
    select coalesce(sum(greatest(o.neto - x.facturado_neto, 0)), 0), count(*) filter (where o.neto - x.facturado_neto > 0) into g3, n3
      from public.ot o join public.ot_facturacion x on x.ot_id = o.id
     where o.estado not in ('cancelada','finalizada','cerrada') and o.origen = 'sm' and o.periodo between v_ini and v_fin;
    d := g1 + g2 + g3;
    return query select 100, 1, 'Facturado del mes'::text, 'Facturado del mes (facturas y notas de débito, menos notas de crédito)'::text, n1::numeric, g1, public._pct(g1, d), null::text, null::bigint;
    return query select 100 + row_number() over (order by abs(z.imp) desc)::int, 2, 'Facturado del mes'::text, (z.cod || ' · ' || z.cli)::text, 1::numeric, z.imp, public._pct(z.imp, d), 'factura'::text, z.id
      from (select f.id, f.codigo as cod, c.razon_social as cli, case when f.clase = 'nc' then -t.neto else t.neto end as imp
              from public.factura f join public.factura_total t on t.id = f.id join public.cliente c on c.id = f.cliente_id
             where f.estado_doc = 'emitida' and f.fecha between v_ini and v_fin order by abs(case when f.clase = 'nc' then -t.neto else t.neto end) desc limit 50) z;
    return query select 200, 1, 'OT finalizadas o cerradas pendientes de facturar'::text, 'OT finalizadas o cerradas con importe pendiente de facturar'::text, n2::numeric, g2, public._pct(g2, d), null::text, null::bigint;
    return query select 200 + row_number() over (order by z.imp desc)::int, 2, 'OT finalizadas o cerradas pendientes de facturar'::text, (z.cod || ' · ' || z.srv || ' · ' || z.cli)::text, 1::numeric, z.imp, public._pct(z.imp, d), 'ot'::text, z.id
      from (select o.id, o.codigo as cod, s.nombre as srv, c.razon_social as cli, o.neto - x.facturado_neto as imp
              from public.ot o join public.ot_facturacion x on x.ot_id = o.id join public.servicio s on s.id = o.servicio_id join public.cliente c on c.id = o.cliente_id
             where o.estado in ('finalizada','cerrada') and o.neto - x.facturado_neto > 0 order by o.neto - x.facturado_neto desc limit 50) z;
    return query select 300, 1, 'Servicios mensuales del período pendientes de facturar'::text, 'Servicios mensuales del período con importe pendiente de facturar'::text, n3::numeric, g3, public._pct(g3, d), null::text, null::bigint;
    return query select 300 + row_number() over (order by z.imp desc)::int, 2, 'Servicios mensuales del período pendientes de facturar'::text, (z.cod || ' · ' || z.srv || ' · ' || z.cli)::text, 1::numeric, z.imp, public._pct(z.imp, d), 'ot'::text, z.id
      from (select o.id, o.codigo as cod, s.nombre as srv, c.razon_social as cli, o.neto - x.facturado_neto as imp
              from public.ot o join public.ot_facturacion x on x.ot_id = o.id join public.servicio s on s.id = o.servicio_id join public.cliente c on c.id = o.cliente_id
             where o.estado not in ('cancelada','finalizada','cerrada') and o.origen = 'sm' and o.periodo between v_ini and v_fin and o.neto - x.facturado_neto > 0
             order by o.neto - x.facturado_neto desc limit 50) z;

  elsif p_clave = 'cobranza_mes' and public.tiene_permiso('cobranza', 1) and public.tiene_permiso('facturacion', 1) then
    select coalesce(sum(ap.importe), 0), count(distinct c2.id) into g1, n1 from public.cobranza_aplicacion ap join public.cobranza c2 on c2.id = ap.cobranza_id
     where not c2.anulada and c2.fecha_cobro between v_ini and v_fin;
    select coalesce(sum(saldo), 0), count(*) into g2, n2 from public.facturas_por_cobrar where vencimiento < v_hoy and vencimiento <= v_fin;
    select coalesce(sum(saldo), 0), count(*) into g3, n3 from public.facturas_por_cobrar where (vencimiento is null or (vencimiento >= v_hoy and vencimiento <= v_fin));
    d := g1 + g2 + g3;
    return query select 100, 1, 'Cobrado del mes'::text, 'Cobrado del mes (aplicado a facturas)'::text, n1::numeric, g1, public._pct(g1, d), null::text, null::bigint;
    return query select 100 + row_number() over (order by z.imp desc)::int, 2, 'Cobrado del mes'::text, (z.cod || ' · ' || z.cli)::text, 1::numeric, z.imp, public._pct(z.imp, d), 'cobranza'::text, z.id
      from (select c2.id, c2.codigo as cod, cl.razon_social as cli, sum(ap.importe) as imp from public.cobranza c2 join public.cobranza_aplicacion ap on ap.cobranza_id = c2.id join public.cliente cl on cl.id = c2.cliente_id
             where not c2.anulada and c2.fecha_cobro between v_ini and v_fin group by c2.id, c2.codigo, cl.razon_social order by sum(ap.importe) desc limit 50) z;
    return query select 200, 1, 'Facturas vencidas con saldo'::text, 'Facturas vencidas con saldo'::text, n2::numeric, g2, public._pct(g2, d), null::text, null::bigint;
    return query select 200 + row_number() over (order by z.imp desc)::int, 2, 'Facturas vencidas con saldo'::text, (z.cod || ' · ' || z.cli || ' · vence ' || to_char(z.v, 'DD/MM'))::text, 1::numeric, z.imp, public._pct(z.imp, d), 'factura'::text, z.id
      from (select fp.factura_id as id, fp.codigo as cod, fp.cliente as cli, fp.vencimiento as v, fp.saldo as imp from public.facturas_por_cobrar fp where fp.vencimiento < v_hoy and fp.vencimiento <= v_fin order by fp.saldo desc limit 50) z;
    return query select 300, 1, 'Facturas por vencer hasta fin de mes'::text, 'Facturas por vencer hasta fin de mes (o sin vencimiento)'::text, n3::numeric, g3, public._pct(g3, d), null::text, null::bigint;
    return query select 300 + row_number() over (order by z.imp desc)::int, 2, 'Facturas por vencer hasta fin de mes'::text, (z.cod || ' · ' || z.cli || coalesce(' · vence ' || to_char(z.v, 'DD/MM'), ''))::text, 1::numeric, z.imp, public._pct(z.imp, d), 'factura'::text, z.id
      from (select fp.factura_id as id, fp.codigo as cod, fp.cliente as cli, fp.vencimiento as v, fp.saldo as imp from public.facturas_por_cobrar fp where (fp.vencimiento is null or (fp.vencimiento >= v_hoy and fp.vencimiento <= v_fin)) order by fp.saldo desc limit 50) z;

  elsif p_clave = 'cartera_vencida' and public.tiene_permiso('facturacion', 1) then
    select coalesce(sum(saldo), 0) into d from public.facturas_por_cobrar;
    for n in 1 .. 4 loop
      return query select n * 100, 1, (array['Vencida hace 1 a 30 días','Vencida hace 31 a 60 días','Vencida hace más de 60 días','A vencer'])[n]::text,
                          (array['Vencida hace 1 a 30 días','Vencida hace 31 a 60 días','Vencida hace más de 60 días','Facturas a vencer (no vencidas)'])[n]::text,
                          count(*)::numeric, coalesce(sum(saldo), 0), public._pct(coalesce(sum(saldo), 0), d), null::text, null::bigint
                     from public.facturas_por_cobrar where tramo = (array['1_30','31_60','mas_60','a_vencer'])[n];
      return query select n * 100 + row_number() over (order by z.imp desc)::int, 2, (array['Vencida hace 1 a 30 días','Vencida hace 31 a 60 días','Vencida hace más de 60 días','A vencer'])[n]::text,
                          (z.cod || ' · ' || z.cli || coalesce(' · vence ' || to_char(z.v, 'DD/MM'), ''))::text, 1::numeric, z.imp, public._pct(z.imp, d), 'factura'::text, z.id
        from (select fp.factura_id as id, fp.codigo as cod, fp.cliente as cli, fp.vencimiento as v, fp.saldo as imp from public.facturas_por_cobrar fp
               where fp.tramo = (array['1_30','31_60','mas_60','a_vencer'])[n] order by fp.saldo desc limit 50) z;
    end loop;

  elsif p_clave = 'margen_ot' and public.tiene_permiso('operaciones', 1) and public.tiene_permiso('costos', 1) then
    select coalesce(sum(o.neto), 0), coalesce(sum(k2.costo_margen), 0) into g1, g2
      from public.ot o join public.ot_costos k2 on k2.ot_id = o.id where o.estado in ('en_ejecucion','finalizada','cerrada');
    return query select 100, 1, 'Neto de las OT'::text, 'Neto de las OT en ejecución, finalizadas y cerradas'::text, null::numeric, g1, public._pct(g1, g1), null::text, null::bigint;
    return query select 200, 1, 'Costos que afectan el margen'::text, 'Costos aprobados que afectan el margen'::text, null::numeric, g2, public._pct(g2, g1), null::text, null::bigint;
    return query select 300, 1, 'Margen'::text, 'Margen estimado (neto menos costos)'::text, null::numeric, g1 - g2, public._pct(g1 - g2, g1), null::text, null::bigint;
    return query select 300 + row_number() over (order by z.pc asc, z.id)::int, 2, 'Margen'::text, (z.cod || ' · ' || z.cli || ' (las de menor margen primero)')::text, 1::numeric, z.mg, z.pc, 'ot'::text, z.id
      from (select o.id, o.codigo as cod, c.razon_social as cli, o.neto - k2.costo_margen as mg, round((o.neto - k2.costo_margen) * 100 / o.neto, 1) as pc
              from public.ot o join public.ot_costos k2 on k2.ot_id = o.id join public.cliente c on c.id = o.cliente_id
             where o.estado in ('en_ejecucion','finalizada','cerrada') and o.neto > 0 order by (o.neto - k2.costo_margen) * 1.0 / o.neto asc limit 50) z;

  elsif p_clave = 'avance_ot' and public.tiene_permiso('operaciones', 1) then
    select count(*) into d from public.ot where estado <> 'cancelada' and periodo between v_ini and v_fin;
    for n in 1 .. 3 loop
      return query select n * 100, 1, (array['Finalizadas o cerradas','En ejecución','Pendientes de iniciar'])[n]::text, (array['Finalizadas o cerradas','En ejecución','Pendientes de iniciar'])[n]::text,
                          count(*)::numeric, coalesce(sum(neto), 0), public._pct(count(*), d), null::text, null::bigint
                     from public.ot where estado <> 'cancelada' and periodo between v_ini and v_fin
                      and estado = any (case n when 1 then array['finalizada','cerrada'] when 2 then array['en_ejecucion'] else array['pendiente'] end);
      return query select n * 100 + row_number() over (order by z.imp desc, z.id)::int, 2, (array['Finalizadas o cerradas','En ejecución','Pendientes de iniciar'])[n]::text,
                          (z.cod || ' · ' || z.srv || ' · ' || z.cli)::text, 1::numeric, z.imp, public._pct(1, d), 'ot'::text, z.id
        from (select o.id, o.codigo as cod, s.nombre as srv, c.razon_social as cli, o.neto as imp from public.ot o join public.servicio s on s.id = o.servicio_id join public.cliente c on c.id = o.cliente_id
               where o.estado <> 'cancelada' and o.periodo between v_ini and v_fin
                 and o.estado = any (case n when 1 then array['finalizada','cerrada'] when 2 then array['en_ejecucion'] else array['pendiente'] end) order by o.neto desc limit 50) z;
    end loop;

  elsif p_clave = 'distribucion_pendiente' and public.tiene_permiso('distribucion', 1) and public.tiene_permiso('cobranza', 1) then
    select count(*) into n1 from public.cobranza where not anulada and fecha_cobro between v_ini and v_fin;
    select count(*) into n2 from public.cobranza_pendiente_distribuir where fecha_cobro between v_ini and v_fin;
    select count(*) into n3 from public.cobranza_pendiente_distribuir where fecha_cobro < v_ini;
    return query select 100, 1, 'Cobranzas del mes ya distribuidas'::text, 'Cobranzas del mes ya distribuidas'::text, (n1 - n2)::numeric, null::numeric, public._pct(n1 - n2, n1), null::text, null::bigint;
    return query select 200, 1, 'Pendientes del mes'::text, 'Cobranzas del mes pendientes de distribuir'::text, n2::numeric, null::numeric, public._pct(n2, n1), null::text, null::bigint;
    return query select 200 + row_number() over (order by z.f desc, z.id)::int, 2, 'Pendientes del mes'::text, (z.cod || ' · ' || z.cli)::text, 1::numeric, null::numeric, public._pct(1, n1), 'cobranza'::text, z.id
      from (select p.cobranza_id as id, p.codigo as cod, c.razon_social as cli, p.fecha_cobro as f from public.cobranza_pendiente_distribuir p join public.cliente c on c.id = p.cliente_id
             where p.fecha_cobro between v_ini and v_fin order by p.fecha_cobro desc limit 50) z;
    return query select 300, 1, 'Pendientes de meses anteriores'::text, 'Cobranzas de meses anteriores pendientes de distribuir'::text, n3::numeric, null::numeric, null::numeric, null::text, null::bigint;
    return query select 300 + row_number() over (order by z.f desc, z.id)::int, 2, 'Pendientes de meses anteriores'::text, (z.cod || ' · ' || z.cli)::text, 1::numeric, null::numeric, null::numeric, 'cobranza'::text, z.id
      from (select p.cobranza_id as id, p.codigo as cod, c.razon_social as cli, p.fecha_cobro as f from public.cobranza_pendiente_distribuir p join public.cliente c on c.id = p.cliente_id
             where p.fecha_cobro < v_ini order by p.fecha_cobro desc limit 50) z;

  elsif p_clave = 'monotributo_riesgo' and public.tiene_permiso('monotributo', 1) then
    select count(*) into d from public.monotributo_estado(p_fecha);
    for n in 1 .. 5 loop
      return query select n * 100, 1, (array['Verde','Amarillo','Rojo','Excedido','Sin límite'])[n]::text, (array['Verde','Amarillo','Rojo','Excedido','Sin límite definido'])[n]::text,
                          count(*)::numeric, coalesce(sum(e.total), 0), public._pct(count(*), d), null::text, null::bigint
                     from public.monotributo_estado(p_fecha) e where e.semaforo = (array['verde','amarillo','rojo','excedido','sin_limite'])[n];
      return query select n * 100 + row_number() over (order by z.pc desc nulls last, z.id)::int, 2, (array['Verde','Amarillo','Rojo','Excedido','Sin límite'])[n]::text,
                          z.nom::text, 1::numeric, z.tot, z.pc, 'asociado'::text, z.id
        from (select e.asociado_id as id, e.apellido_nombre as nom, e.total as tot, e.pct as pc from public.monotributo_estado(p_fecha) e
               where e.semaforo = (array['verde','amarillo','rojo','excedido','sin_limite'])[n]) z;
    end loop;

  elsif p_clave = 'presupuestos_aprobacion' and public.tiene_permiso('comercial', 1) then
    select coalesce(sum(neto), 0) into d from public.presupuesto_linea where estado in ('aprobada','rechazada') and fecha_decision between p_fecha - 90 and p_fecha;
    for n in 1 .. 2 loop
      return query select n * 100, 1, (array['Aprobado','Rechazado'])[n]::text, (array['Importe aprobado','Importe rechazado'])[n]::text, count(*)::numeric, coalesce(sum(neto), 0), public._pct(coalesce(sum(neto), 0), d), null::text, null::bigint
                     from public.presupuesto_linea where estado = (array['aprobada','rechazada'])[n] and fecha_decision between p_fecha - 90 and p_fecha;
      return query select n * 100 + row_number() over (order by z.imp desc, z.id)::int, 2, (array['Aprobado','Rechazado'])[n]::text, (z.cod || ' · ' || z.srv)::text, 1::numeric, z.imp, public._pct(z.imp, d), 'presupuesto'::text, z.pid
        from (select l.id, p.id as pid, p.codigo as cod, s.nombre as srv, l.neto as imp from public.presupuesto_linea l join public.presupuesto p on p.id = l.presupuesto_id join public.servicio s on s.id = l.servicio_id
               where l.estado = (array['aprobada','rechazada'])[n] and l.fecha_decision between p_fecha - 90 and p_fecha order by l.neto desc limit 50) z;
    end loop;

  elsif p_clave = 'presupuestos_seguimiento' and public.tiene_permiso('comercial', 1) then
    select count(*), count(*) filter (where proximo_seguimiento < v_hoy) into n, n1 from public.presupuesto_resumen where estado = 'enviado';
    return query select 100, 1, 'Seguimiento vencido'::text, 'Presupuestos enviados con el seguimiento vencido'::text, n1::numeric, null::numeric, public._pct(n1, n), null::text, null::bigint;
    return query select 100 + row_number() over (order by z.sg, z.id)::int, 2, 'Seguimiento vencido'::text, (z.cod || ' · ' || z.cli || ' · seguimiento ' || to_char(z.sg, 'DD/MM'))::text, 1::numeric, z.tot, public._pct(1, n), 'presupuesto'::text, z.id
      from (select r.id, r.codigo as cod, c.razon_social as cli, r.proximo_seguimiento as sg, r.total as tot from public.presupuesto_resumen r join public.cliente c on c.id = r.cliente_id
             where r.estado = 'enviado' and r.proximo_seguimiento < v_hoy order by r.proximo_seguimiento limit 50) z;
    return query select 200, 1, 'Al día'::text, 'Presupuestos enviados con el seguimiento al día'::text, (n - n1)::numeric, null::numeric, public._pct(n - n1, n), null::text, null::bigint;
    return query select 200 + row_number() over (order by z.sg, z.id)::int, 2, 'Al día'::text, (z.cod || ' · ' || z.cli || ' · seguimiento ' || to_char(z.sg, 'DD/MM'))::text, 1::numeric, z.tot, public._pct(1, n), 'presupuesto'::text, z.id
      from (select r.id, r.codigo as cod, c.razon_social as cli, r.proximo_seguimiento as sg, r.total as tot from public.presupuesto_resumen r join public.cliente c on c.id = r.cliente_id
             where r.estado = 'enviado' and r.proximo_seguimiento >= v_hoy order by r.proximo_seguimiento limit 50) z;

  elsif p_clave = 'por_pagar_vencido' and public.tiene_permiso('costos', 1) then
    select coalesce(sum(saldo), 0) into d from public.facturas_proveedor_por_pagar;
    for n in 1 .. 5 loop
      return query select n * 100, 1, (array['Vencida hace 1 a 30 días','Vencida hace 31 a 60 días','Vencida hace más de 60 días','A vencer','Sin vencimiento'])[n]::text,
                          (array['Vencida hace 1 a 30 días','Vencida hace 31 a 60 días','Vencida hace más de 60 días','A vencer','Sin vencimiento cargado'])[n]::text,
                          count(*)::numeric, coalesce(sum(saldo), 0), public._pct(coalesce(sum(saldo), 0), d), null::text, null::bigint
                     from public.facturas_proveedor_por_pagar where tramo = (array['1_30','31_60','mas_60','a_vencer','sin_vencimiento'])[n];
      return query select n * 100 + row_number() over (order by z.imp desc, z.id)::int, 2, (array['Vencida hace 1 a 30 días','Vencida hace 31 a 60 días','Vencida hace más de 60 días','A vencer','Sin vencimiento'])[n]::text,
                          (z.emi || ' · ' || z.nro)::text, 1::numeric, z.imp, public._pct(z.imp, d), 'factura_proveedor'::text, z.id
        from (select p.factura_id as id, p.emisor as emi, p.nro_comprobante as nro, p.saldo as imp from public.facturas_proveedor_por_pagar p
               where p.tramo = (array['1_30','31_60','mas_60','a_vencer','sin_vencimiento'])[n] order by p.saldo desc limit 50) z;
    end loop;

  elsif p_clave = 'cc_asociados' and public.tiene_permiso('costos', 1) then
    select coalesce(sum(saldo) filter (where saldo > 0), 0), coalesce(-sum(saldo) filter (where saldo < 0), 0), count(*) filter (where saldo > 0), count(*) filter (where saldo < 0) into g1, g2, n1, n2 from public.saldo_cc_asociado;
    d := g1 + g2;
    return query select 100, 1, 'A favor de los asociados'::text, 'La Cooperativa les debe a los asociados'::text, n1::numeric, g1, public._pct(g1, d), null::text, null::bigint;
    return query select 100 + row_number() over (order by z.sal desc, z.id)::int, 2, 'A favor de los asociados'::text, z.nom::text, 1::numeric, z.sal, public._pct(z.sal, d), 'asociado'::text, z.id
      from (select s.asociado_id as id, a.apellido_nombre as nom, s.saldo as sal from public.saldo_cc_asociado s join public.asociado a on a.id = s.asociado_id where s.saldo > 0 order by s.saldo desc limit 50) z;
    return query select 200, 1, 'Deuda de asociados'::text, 'Los asociados le deben a la Cooperativa'::text, n2::numeric, g2, public._pct(g2, d), null::text, null::bigint;
    return query select 200 + row_number() over (order by z.sal desc, z.id)::int, 2, 'Deuda de asociados'::text, z.nom::text, 1::numeric, z.sal, public._pct(z.sal, d), 'asociado'::text, z.id
      from (select s.asociado_id as id, a.apellido_nombre as nom, -s.saldo as sal from public.saldo_cc_asociado s join public.asociado a on a.id = s.asociado_id where s.saldo < 0 order by s.saldo limit 50) z;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Perfil y permisos del usuario con sesión (para el menú y la apariencia)
-- ---------------------------------------------------------------------
create or replace function public.mis_permisos() returns table (modulo text, nivel int)
language sql stable security definer set search_path = public as
$$
  select m.clave,
         case when exists (select 1 from public.usuario where id = auth.uid() and activo)
              then coalesce((select pu.nivel from public.permiso_usuario pu where pu.usuario_id = auth.uid() and pu.modulo = m.clave),
                            (select coalesce(max(pp.nivel), 0) from public.usuario_puesto up join public.permiso_puesto pp on pp.puesto_id = up.puesto_id
                              where up.usuario_id = auth.uid() and pp.modulo = m.clave), 0)::int
              else 0 end
    from public.modulo m order by m.orden
$$;

create or replace function public.mi_perfil() returns table (usuario_id uuid, nombre text, activo boolean, modo_tema text, asociado_id bigint,
                                                           puestos text[], razon_social text, tema_color text, tema_color_personalizado text)
language sql stable security definer set search_path = public as
$$
  select u.id, u.nombre, u.activo, u.modo_tema, u.asociado_id,
         coalesce((select array_agg(p.nombre order by p.nombre) from public.usuario_puesto up join public.puesto p on p.id = up.puesto_id where up.usuario_id = u.id), '{}'::text[]),
         o.razon_social, o.tema_color, o.tema_color_personalizado
    from public.usuario u cross join public.organizacion o where u.id = auth.uid()
$$;

revoke execute on function public.kpi_panel(date) from public, anon;
revoke execute on function public.kpi_detalle(text, date) from public, anon;
revoke execute on function public.mis_permisos() from public, anon;
revoke execute on function public.mi_perfil() from public, anon;
revoke execute on function public._tono_kpi(text, numeric) from public, anon;
grant execute on function public.kpi_panel(date) to authenticated, service_role;
grant execute on function public.kpi_detalle(text, date) to authenticated, service_role;
grant execute on function public.mis_permisos() to authenticated, service_role;
grant execute on function public.mi_perfil() to authenticated, service_role;
grant execute on function public._tono_kpi(text, numeric) to authenticated, service_role;

insert into public.migraciones (version, descripcion) values ('0009', 'KPIs con umbrales configurables, detalle desglosado y perfil/permisos del usuario');
commit;
