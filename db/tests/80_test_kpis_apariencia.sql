\set ON_ERROR_STOP on
\set U1 '''00000000-0000-0000-0000-000000000001'''
\set U2 '''00000000-0000-0000-0000-000000000002'''
\set U3 '''00000000-0000-0000-0000-000000000003'''

-- ===== Preparación =====
create table public.zz_ctx (k text primary key, v bigint);
create function public.zz(p text) returns bigint language sql stable as $$ select v from public.zz_ctx where k = p $$;
create function public.zzset(p text, n bigint) returns void language sql as $$
  insert into public.zz_ctx values (p, n) on conflict (k) do update set v = excluded.v $$;
create function public.zz_ot(p_neto numeric, p_inicio date) returns bigint
language plpgsql as $$
declare v bigint; e bigint;
begin
  select id into e from public.establecimiento where cliente_id = public.zz('cli') and principal;
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
  values ('directa', 'prueba KPI', public.zz('cli'), e, public.zz('s1'), public.zz('ana'), p_inicio, p_neto) returning id into v;
  return v;
end $$;
create function public.zz_emitir(p_ot bigint, p_neto numeric, p_fecha date, p_clase text default 'factura', p_origen bigint default null) returns bigint
language plpgsql as $$
declare f bigint; tipo bigint; n int;
begin
  select id into tipo from public.lista_valor where lista = 'tipo_comprobante' and nombre = case p_clase when 'factura' then 'Factura A' else 'Nota de crédito A' end;
  insert into public.factura (clase, cliente_id, factura_origen_id, fecha) values (p_clase, public.zz('cli'), p_origen, p_fecha) returning id into f;
  insert into public.factura_linea (factura_id, ot_id, neto, iva_pct) values (f, p_ot, p_neto, 0);
  select coalesce(max(numero::int), 0) + 1 into n from public.factura;
  perform public.emitir_factura(f, '1', n::text, 'CAE' || n, null, tipo);
  return f;
end $$;

do $$
declare cli bigint; s1 bigint; ana bigint;
begin
  select id into cli from public.cliente where nro_doc = '30755555556';
  select id into s1 from public.servicio where nombre = 'Higiene mensual';
  select id into ana from public.asociado where nro_doc = '27300000001';
  perform public.zzset('cli', cli); perform public.zzset('s1', s1); perform public.zzset('ana', ana);
end $$;

-- ===== 1) Apariencia =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare n int; begin
  assert (select tema_color from public.organizacion) = 'azul', 'el azul es el color por defecto';
  begin update public.organizacion set tema_color = 'rojo'; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin update public.organizacion set tema_color = 'personalizado'; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin update public.organizacion set tema_color_personalizado = 'verde'; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  update public.organizacion set tema_color = 'personalizado', tema_color_personalizado = '#0F766E';
  assert (select tema_color_personalizado from public.organizacion) = '#0F766E', 'color personalizado válido';
  update public.organizacion set tema_color = 'violeta';
  update public.organizacion set tema_color = 'azul';
  assert (select count(*) from public.log_auditoria where tabla = 'organizacion' and campo = 'tema_color') >= 3, 'los cambios de apariencia quedan auditados';
  raise notice 'OK color de la organización';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare n int; begin
  assert (select tema_color from public.organizacion) = 'azul', 'cualquier usuario activo lee el color';
  update public.organizacion set tema_color = 'verde'; get diagnostics n = row_count; assert n = 0, 'solo la administración cambia el color';
  assert (select modo_tema from public.usuario where id = auth.uid()) = 'sistema', 'el modo por defecto es "sistema"';
  perform public.set_modo_tema('oscuro');
  assert (select modo_tema from public.usuario where id = auth.uid()) = 'oscuro', 'cada usuario elige su modo sin ser administrador';
  begin perform public.set_modo_tema('fucsia'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%claro, sistema u oscuro%', sqlerrm; end;
  perform public.set_modo_tema('claro'); perform public.set_modo_tema('sistema');
  raise notice 'OK modo claro / sistema / oscuro por usuario';
end $$;
commit;
begin; set local role anon;
do $$ begin
  begin perform public.set_modo_tema('claro'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform * from public.kpi_panel(); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK un visitante anónimo no accede';
end $$; rollback;

-- ===== 2) Avance de OT del mes (marzo de 2030, mes aislado) y datos del escenario =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare oa bigint; ob bigint; oc bigint; of_ bigint; r record; begin
  oa := public.zz_ot(1000000, date '2030-03-05'); ob := public.zz_ot(300000, date '2030-03-06'); oc := public.zz_ot(50000, date '2030-03-07');
  of_ := public.zz_ot(80000, date '2030-02-05');
  perform public.cambiar_estado_ot(oa, 'en_ejecucion'); perform public.cambiar_estado_ot(oa, 'finalizada');
  perform public.cambiar_estado_ot(ob, 'en_ejecucion'); perform public.cambiar_estado_ot(ob, 'finalizada'); perform public.cambiar_estado_ot(ob, 'cerrada');
  perform public.cambiar_estado_ot(of_, 'en_ejecucion'); perform public.cambiar_estado_ot(of_, 'finalizada');
  perform public.zzset('oa', oa); perform public.zzset('ob', ob); perform public.zzset('oc', oc); perform public.zzset('of', of_);
  select * into r from public.kpi_panel(date '2030-03-15') where clave = 'avance_ot';
  assert r.valor = 2 and r.referencia = 3 and r.pct = 66.7 and r.unidad = 'cantidad', 'OT del mes: 2 de 3 finalizadas (66,7%): ' || r.valor || ' ' || r.referencia || ' ' || r.pct;
  assert r.variacion_pct = 100.0 and r.comparado_con = 'mes anterior', 'el mes anterior tuvo 1 finalizada: +100%';
  raise notice 'OK avance de OT del mes';
end $$;
commit;

-- ===== 3) Facturación del mes: importe, % de lo que corresponde facturar y variación =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare f_feb bigint; f1 bigint; f2 bigint; r record; r2 record; r3 record; pend numeric; od bigint; esp numeric; begin
  f_feb := public.zz_emitir(public.zz('of'), 80000, date '2030-02-10');
  f1 := public.zz_emitir(public.zz('oa'), 100000, date '2030-03-10');
  f2 := public.zz_emitir(public.zz('oa'), 50000, date '2030-03-12');
  perform public.zz_emitir(public.zz('oa'), 10000, date '2030-03-20', 'nc', f1);
  perform public.zzset('f1', f1); perform public.zzset('f2', f2); perform public.zzset('f_feb', f_feb);
  select coalesce(sum(greatest(o.neto - x.facturado_neto, 0)), 0) into pend
    from public.ot o join public.ot_facturacion x on x.ot_id = o.id
   where o.estado <> 'cancelada' and (o.estado in ('finalizada','cerrada') or (o.origen = 'sm' and o.periodo between date '2030-03-01' and date '2030-03-31'));
  select * into r from public.kpi_panel(date '2030-03-15') where clave = 'facturacion_mes';
  assert r.valor = 140000 and r.unidad = 'importe' and r.modulo = 'facturacion', 'facturado del mes: 100.000 + 50.000 − 10.000 de NC = 140.000: ' || r.valor;
  assert r.referencia = 140000 + pend and r.pct = round(140000 * 100 / (140000 + pend), 1), 'porcentaje sobre lo que corresponde facturar: ' || r.pct;
  assert r.variacion_pct = round((140000 - 80000) * 100 / 80000.0, 1) and r.comparado_con = 'mes anterior', 'variación contra febrero (80.000): +75%';
  assert r.tono = case when r.pct >= 80 then 'ok' when r.pct >= 50 then 'warn' else 'bad' end, 'el tono sigue al porcentaje';
  -- una OT finalizada sin facturar aumenta lo que corresponde facturar y baja el porcentaje
  od := public.zz_ot(200000, date '2030-03-08');
  perform public.cambiar_estado_ot(od, 'en_ejecucion'); perform public.cambiar_estado_ot(od, 'finalizada');
  select * into r2 from public.kpi_panel(date '2030-03-15') where clave = 'facturacion_mes';
  assert r2.valor = 140000 and r2.referencia = r.referencia + 200000 and r2.pct < r.pct, 'lo finalizado sin facturar baja el %: ' || r2.pct || ' < ' || r.pct;
  -- al facturarla, el importe sube y el total de referencia no cambia: el % mejora
  perform public.zz_emitir(od, 200000, date '2030-03-25');
  select * into r3 from public.kpi_panel(date '2030-03-15') where clave = 'facturacion_mes';
  assert r3.valor = 340000 and r3.referencia = r2.referencia and r3.pct > r2.pct, 'al facturarla sube el %: ' || r3.pct;
  raise notice 'OK KPI de facturación';
end $$;
commit;

-- ===== 4) Cobranza del mes =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare c_feb bigint; c1 bigint; r record; exig numeric; begin
  c_feb := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 50000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz('f_feb'), 'importe', 50000)), p_fecha_cobro := date '2030-02-12');
  c1 := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 70000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz('f1'), 'importe', 70000)), p_fecha_cobro := date '2030-03-12');
  perform public.zzset('c1', c1);
  select coalesce(sum(saldo), 0) into exig from public.facturas_por_cobrar where vencimiento is null or vencimiento <= date '2030-03-31';
  select * into r from public.kpi_panel(date '2030-03-15') where clave = 'cobranza_mes';
  assert r.valor = 70000 and r.variacion_pct = 40.0, 'cobrado de marzo 70.000 contra 50.000 de febrero: +40%: ' || r.valor || ' ' || coalesce(r.variacion_pct::text, 'null');
  assert r.referencia = 70000 + exig and r.pct = round(70000 * 100 / (70000 + exig), 1), 'porcentaje sobre lo cobrable: ' || r.pct;
  assert r.tono = case when r.pct >= 80 then 'ok' when r.pct >= 50 then 'warn' else 'bad' end, 'el tono sigue al porcentaje';
  raise notice 'OK KPI de cobranza';
end $$;
commit;

-- ===== 5) Cartera vencida, margen, distribución, presupuestos, pagos, monotributo, cuentas =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare r record; tot numeric; ven numeric; n numeric; c numeric; k int; t int; p int; pm int; a numeric; d numeric; c2 bigint; begin
  select coalesce(sum(saldo), 0), coalesce(sum(saldo) filter (where tramo <> 'a_vencer'), 0) into tot, ven from public.facturas_por_cobrar;
  select * into r from public.kpi_panel(date '2030-03-15') where clave = 'cartera_vencida';
  assert r.valor = ven and r.referencia = tot and r.pct = round(ven * 100 / tot, 1) and r.variacion_pct is null, 'cartera vencida: ' || r.pct || '% del total por cobrar';
  assert r.tono = case when r.pct <= 10 then 'ok' when r.pct <= 25 then 'warn' else 'bad' end, 'tono de la cartera vencida (un % alto es malo)';

  select coalesce(sum(o.neto), 0), coalesce(sum(k2.costo_margen), 0) into n, c from public.ot o join public.ot_costos k2 on k2.ot_id = o.id where o.estado in ('en_ejecucion','finalizada','cerrada');
  select * into r from public.kpi_panel(date '2030-03-15') where clave = 'margen_ot';
  assert r.valor = n - c and r.referencia = n and r.pct = round((n - c) * 100 / n, 1), 'margen de las OT: ' || r.pct || '%';

  -- distribución: una cobranza de marzo distribuida y otra pendiente
  perform public.definir_regla_ot(public.zz('oa'), jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 100)));
  perform public.distribuir_cobranza(public.zz('c1'));
  c2 := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 20000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz('f2'), 'importe', 20000)), p_fecha_cobro := date '2030-03-14');
  select count(*) into p from public.cobranza_pendiente_distribuir;
  select * into r from public.kpi_panel(date '2030-03-15') where clave = 'distribucion_pendiente';
  assert r.referencia = 2 and r.pct = 50.0 and r.valor = p, 'cobranzas del mes distribuidas: 1 de 2 (50%), pendientes totales ' || p;
  assert r.tono = case when p = 0 then 'ok' when p <= 2 then 'warn' else 'bad' end, 'tono de lo pendiente de distribuir';
  perform public.distribuir_cobranza(c2);
  select * into r from public.kpi_panel(date '2030-03-15') where clave = 'distribucion_pendiente';
  assert r.pct = 100.0, 'distribuidas las dos: 100%';

  -- monotributo
  select count(*), count(*) filter (where semaforo in ('rojo','excedido')) into t, k from public.monotributo_estado();
  select * into r from public.kpi_panel() where clave = 'monotributo_riesgo';
  assert r.valor = k and r.referencia = t and r.pct = round(k * 100.0 / t, 1), 'monotributo en riesgo: ' || k || ' de ' || t;

  -- presupuestos
  select coalesce(sum(neto) filter (where estado = 'aprobada'), 0), coalesce(sum(neto), 0) into a, d
    from public.presupuesto_linea where estado in ('aprobada','rechazada') and fecha_decision between public.hoy_ar() - 90 and public.hoy_ar();
  select * into r from public.kpi_panel() where clave = 'presupuestos_aprobacion';
  assert r.valor = a and r.referencia = d and r.pct is not distinct from (case when d > 0 then round(a * 100 / d, 1) end), 'aprobación de presupuestos: ' || coalesce(r.pct::text, 'sin datos') || '%';
  select count(*), count(*) filter (where proximo_seguimiento < public.hoy_ar()) into t, k from public.presupuesto_resumen where estado = 'enviado';
  select * into r from public.kpi_panel() where clave = 'presupuestos_seguimiento';
  assert r.valor = k and r.referencia = t, 'seguimientos vencidos: ' || k || ' de ' || t;

  -- por pagar y cuentas corrientes de asociados
  select coalesce(sum(saldo), 0), coalesce(sum(saldo) filter (where tramo not in ('a_vencer','sin_vencimiento')), 0) into d, a from public.facturas_proveedor_por_pagar;
  select * into r from public.kpi_panel() where clave = 'por_pagar_vencido';
  assert r.valor = a and r.referencia = d, 'por pagar vencido';
  select coalesce(sum(saldo) filter (where saldo > 0), 0), coalesce(-sum(saldo) filter (where saldo < 0), 0) into a, d from public.saldo_cc_asociado;
  select * into r from public.kpi_panel() where clave = 'cc_asociados';
  assert r.valor = a and r.referencia = d and r.pct is null and r.tono = 'neutral', 'cuentas corrientes de asociados';
  raise notice 'OK demás KPIs';
end $$;
commit;

-- ===== 6) Forma de los resultados y permisos =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare n int; begin
  select count(*) into n from public.kpi_panel(); assert n = 11, 'el administrador ve los 11 indicadores: ' || n;
  assert not exists (select 1 from public.kpi_panel() where tono not in ('ok','warn','bad','neutral')), 'tonos válidos';
  assert not exists (select 1 from public.kpi_panel() where unidad not in ('importe','cantidad')), 'unidades válidas';
  assert not exists (select 1 from public.kpi_panel() where pct is not null and (pct < 0 or pct > 100)), 'los porcentajes van de 0 a 100';
  assert (select count(distinct clave) from public.kpi_panel()) = 11, 'sin indicadores repetidos';
  raise notice 'OK forma de los indicadores';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  assert exists (select 1 from public.kpi_panel() where clave = 'facturacion_mes') and exists (select 1 from public.kpi_panel() where clave = 'avance_ot'), 'el operador ve facturación y operaciones';
  assert not exists (select 1 from public.kpi_panel() where clave = 'monotributo_riesgo'), 'pero no el monotributo (sin permiso)';
  raise notice 'OK cada usuario ve los indicadores de sus módulos';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ declare n int; begin
  select count(*) into n from public.kpi_panel(); assert n = 0, 'el lector sin módulos operativos no ve indicadores: ' || n;
  raise notice 'OK sin permisos no hay indicadores';
end $$; rollback;

drop function public.zz_emitir(bigint, numeric, date, text, bigint); drop function public.zz_ot(numeric, date);
drop function public.zzset(text, bigint); drop function public.zz(text); drop table public.zz_ctx;
\echo 'KPIS Y APARIENCIA: todas las pruebas pasaron'
