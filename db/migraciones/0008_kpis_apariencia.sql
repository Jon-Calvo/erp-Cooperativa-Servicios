-- =====================================================================
-- 0008 · KPIs DEL PANEL Y APARIENCIA
-- Indicadores con importe, porcentaje de avance y variación contra el
-- período anterior (calculados en la base), color de la aplicación
-- configurable por la organización (azul por defecto) y preferencia de
-- modo claro / sistema / oscuro de cada usuario.
-- Requiere 0001 a 0007. Pegar TODO en SQL Editor → Run.
-- =====================================================================
begin;

do $$ begin
  if not exists (select 1 from public.migraciones where version = '0007') then
    raise exception 'Falta aplicar la migración 0007 antes de esta.';
  end if;
  if exists (select 1 from public.migraciones where version = '0008') then
    raise exception 'La migración 0008 ya fue aplicada: no se puede correr dos veces.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Apariencia: color de la organización (azul por defecto) y modo de cada usuario
-- ---------------------------------------------------------------------
alter table public.organizacion
  add column tema_color text not null default 'azul' check (tema_color in ('azul','verde','violeta','naranja','grafito','personalizado')),
  add column tema_color_personalizado text check (tema_color_personalizado ~ '^#[0-9A-Fa-f]{6}$'),
  add constraint organizacion_tema_personalizado check (tema_color <> 'personalizado' or tema_color_personalizado is not null);

alter table public.usuario
  add column modo_tema text not null default 'sistema' check (modo_tema in ('claro','sistema','oscuro'));

-- Cada usuario elige su modo sin necesitar permisos de administración
create or replace function public.set_modo_tema(p_modo text) returns void
language plpgsql security definer set search_path = public as
$$
begin
  if p_modo not in ('claro','sistema','oscuro') then raise exception 'El modo debe ser claro, sistema u oscuro.'; end if;
  update public.usuario set modo_tema = p_modo where id = auth.uid() and activo;
  if not found then raise exception 'No hay un usuario activo con sesión.'; end if;
end $$;
revoke execute on function public.set_modo_tema(text) from public, anon;
grant execute on function public.set_modo_tema(text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- KPIs del panel
--   valor        importe o cantidad principal
--   referencia   contra qué se mide (objetivo, total, base)
--   pct          porcentaje que lo pone en contexto
--   variacion_pct  cambio contra el período anterior (vacío si no hay base)
--   tono         ok / warn / bad / neutral
-- Cada indicador aparece solo si el usuario puede leer los módulos de los que sale.
-- ---------------------------------------------------------------------
create or replace function public._pct(p_num numeric, p_den numeric) returns numeric
language sql immutable as $$ select case when p_den > 0 then round(p_num * 100 / p_den, 1) end $$;

create or replace function public._variacion(p_actual numeric, p_previo numeric) returns numeric
language sql immutable as $$ select case when coalesce(p_previo, 0) > 0 then round((p_actual - p_previo) * 100 / p_previo, 1) end $$;

-- Tono cuando un porcentaje alto es bueno / cuando un porcentaje alto es malo
create or replace function public._tono_alto_bueno(p_pct numeric, p_ok numeric, p_warn numeric) returns text
language sql immutable as $$ select case when p_pct is null then 'neutral' when p_pct >= p_ok then 'ok' when p_pct >= p_warn then 'warn' else 'bad' end $$;
create or replace function public._tono_alto_malo(p_pct numeric, p_ok numeric, p_warn numeric) returns text
language sql immutable as $$ select case when p_pct is null then 'neutral' when p_pct <= p_ok then 'ok' when p_pct <= p_warn then 'warn' else 'bad' end $$;

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
  -- 1) Facturación del mes: facturado (neto de facturas y ND, menos NC) contra lo que corresponde facturar
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
                        public._pct(a, d), 'de lo que corresponde facturar'::text, public._variacion(a, b), 'mes anterior'::text, public._tono_alto_bueno(public._pct(a, d), 80, 50);
  end if;

  -- 2) Cobranza del mes: cobrado contra lo cobrable (cobrado + saldo con vencimiento hasta fin de mes)
  if public.tiene_permiso('cobranza', 1) and public.tiene_permiso('facturacion', 1) then
    select coalesce(sum(ap.importe), 0) into a from public.cobranza_aplicacion ap join public.cobranza c2 on c2.id = ap.cobranza_id
     where not c2.anulada and c2.fecha_cobro between v_ini and v_fin;
    select coalesce(sum(ap.importe), 0) into b from public.cobranza_aplicacion ap join public.cobranza c2 on c2.id = ap.cobranza_id
     where not c2.anulada and c2.fecha_cobro between v_pini and v_pfin;
    select coalesce(sum(saldo), 0) into c from public.facturas_por_cobrar where vencimiento is null or vencimiento <= v_fin;
    d := a + c;
    return query select 2, 'cobranza_mes'::text, 'Cobranza del mes'::text, 'cobranza'::text, 'importe'::text, a, d, 'cobrable (cobrado + saldo con vencimiento hasta fin de mes)'::text,
                        public._pct(a, d), 'de lo cobrable del mes'::text, public._variacion(a, b), 'mes anterior'::text, public._tono_alto_bueno(public._pct(a, d), 80, 50);
  end if;

  -- 3) Cartera vencida: saldo vencido sobre el total por cobrar
  if public.tiene_permiso('facturacion', 1) then
    select coalesce(sum(saldo), 0), coalesce(sum(saldo) filter (where tramo <> 'a_vencer'), 0) into d, a from public.facturas_por_cobrar;
    return query select 3, 'cartera_vencida'::text, 'Cartera vencida'::text, 'facturacion'::text, 'importe'::text, a, d, 'total por cobrar'::text,
                        public._pct(a, d), 'del total por cobrar'::text, null::numeric, null::text, public._tono_alto_malo(public._pct(a, d), 10, 25);
  end if;

  -- 4) Margen de las OT en marcha: neto menos costos que afectan el margen
  if public.tiene_permiso('operaciones', 1) and public.tiene_permiso('costos', 1) then
    select coalesce(sum(o.neto), 0), coalesce(sum(k2.costo_margen), 0) into d, c
      from public.ot o join public.ot_costos k2 on k2.ot_id = o.id where o.estado in ('en_ejecucion','finalizada','cerrada');
    return query select 4, 'margen_ot'::text, 'Margen de las OT'::text, 'operaciones'::text, 'importe'::text, d - c, d, 'neto de las OT'::text,
                        public._pct(d - c, d), 'del neto de las OT'::text, null::numeric, null::text, public._tono_alto_bueno(public._pct(d - c, d), 30, 15);
  end if;

  -- 5) Avance de las OT del mes
  if public.tiene_permiso('operaciones', 1) then
    select count(*), count(*) filter (where estado in ('finalizada','cerrada')) into n, k from public.ot where estado <> 'cancelada' and periodo between v_ini and v_fin;
    select count(*) filter (where estado in ('finalizada','cerrada')) into b from public.ot where estado <> 'cancelada' and periodo between v_pini and v_pfin;
    return query select 5, 'avance_ot'::text, 'OT del mes finalizadas'::text, 'operaciones'::text, 'cantidad'::text, k::numeric, n::numeric, 'OT del mes'::text,
                        public._pct(k, n), 'de las OT del mes'::text, public._variacion(k, b), 'mes anterior'::text, 'neutral'::text;
  end if;

  -- 6) Distribución: cobranzas del mes ya distribuidas; valor = pendientes de todo período
  if public.tiene_permiso('distribucion', 1) and public.tiene_permiso('cobranza', 1) then
    select count(*) into n from public.cobranza where not anulada and fecha_cobro between v_ini and v_fin;
    select count(*) into k from public.cobranza_pendiente_distribuir where fecha_cobro between v_ini and v_fin;
    select count(*) into c from public.cobranza_pendiente_distribuir;
    return query select 6, 'distribucion_pendiente'::text, 'Cobranzas por distribuir'::text, 'distribucion'::text, 'cantidad'::text, c, n::numeric, 'cobranzas del mes'::text,
                        public._pct(n - k, n), 'de las cobranzas del mes distribuidas'::text, null::numeric, null::text,
                        case when c = 0 then 'ok' when c <= 2 then 'warn' else 'bad' end;
  end if;

  -- 7) Monotributo: asociados en rojo o excedidos sobre los monotributistas
  if public.tiene_permiso('monotributo', 1) then
    select count(*), count(*) filter (where semaforo in ('rojo','excedido')) into n, k from public.monotributo_estado(p_fecha);
    return query select 7, 'monotributo_riesgo'::text, 'Monotributo en riesgo'::text, 'monotributo'::text, 'cantidad'::text, k::numeric, n::numeric, 'asociados monotributistas'::text,
                        public._pct(k, n), 'de los asociados en rojo o excedidos'::text, null::numeric, null::text,
                        case when n = 0 then 'neutral' when k = 0 then 'ok' when k * 100.0 / n < 20 then 'warn' else 'bad' end;
  end if;

  -- 8) Presupuestos: aprobación de lo decidido en los últimos 90 días
  if public.tiene_permiso('comercial', 1) then
    select coalesce(sum(neto) filter (where estado = 'aprobada'), 0), coalesce(sum(neto), 0) into a, d
      from public.presupuesto_linea where estado in ('aprobada','rechazada') and fecha_decision between p_fecha - 90 and p_fecha;
    select coalesce(sum(neto) filter (where estado = 'aprobada'), 0) into b
      from public.presupuesto_linea where estado in ('aprobada','rechazada') and fecha_decision between p_fecha - 180 and p_fecha - 91;
    return query select 8, 'presupuestos_aprobacion'::text, 'Presupuestos aprobados (90 días)'::text, 'comercial'::text, 'importe'::text, a, d, 'decidido en 90 días'::text,
                        public._pct(a, d), 'del importe decidido'::text, public._variacion(a, b), '90 días anteriores'::text, public._tono_alto_bueno(public._pct(a, d), 50, 30);
    select count(*), count(*) filter (where proximo_seguimiento < v_hoy) into n, k from public.presupuesto_resumen where estado = 'enviado';
    return query select 9, 'presupuestos_seguimiento'::text, 'Seguimientos vencidos'::text, 'comercial'::text, 'cantidad'::text, k::numeric, n::numeric, 'presupuestos enviados'::text,
                        public._pct(k, n), 'de los enviados'::text, null::numeric, null::text, public._tono_alto_malo(public._pct(k, n), 0, 20);
  end if;

  -- 10) Pagos a proveedores: saldo vencido sobre el total por pagar
  if public.tiene_permiso('costos', 1) then
    select coalesce(sum(saldo), 0), coalesce(sum(saldo) filter (where tramo not in ('a_vencer','sin_vencimiento')), 0) into d, a from public.facturas_proveedor_por_pagar;
    return query select 10, 'por_pagar_vencido'::text, 'Por pagar vencido'::text, 'costos'::text, 'importe'::text, a, d, 'total por pagar'::text,
                        public._pct(a, d), 'del total por pagar'::text, null::numeric, null::text, public._tono_alto_malo(public._pct(a, d), 10, 25);
    -- 11) Cuentas corrientes de asociados
    select coalesce(sum(saldo) filter (where saldo > 0), 0), coalesce(-sum(saldo) filter (where saldo < 0), 0) into a, d from public.saldo_cc_asociado;
    return query select 11, 'cc_asociados'::text, 'A favor de los asociados'::text, 'costos'::text, 'importe'::text, a, d, 'deuda de asociados con la Cooperativa'::text,
                        null::numeric, null::text, null::numeric, null::text, 'neutral'::text;
  end if;
end $$;

revoke execute on function public.kpi_panel(date) from public, anon;
grant execute on function public.kpi_panel(date) to authenticated, service_role;

insert into public.migraciones (version, descripcion) values ('0008', 'KPIs del panel con porcentaje y variación; apariencia configurable (color de la organización y modo de cada usuario)');
commit;
