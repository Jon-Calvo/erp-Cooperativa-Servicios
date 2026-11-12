\set ON_ERROR_STOP on
\set U1 '''00000000-0000-0000-0000-000000000001'''
\set U2 '''00000000-0000-0000-0000-000000000002'''
\set U3 '''00000000-0000-0000-0000-000000000003'''

-- ===== Preparación =====
create table public.zz_ctx (k text primary key, v bigint);
create function public.zz(p text) returns bigint language sql stable as $$ select v from public.zz_ctx where k = p $$;
create function public.zzset(p text, n bigint) returns void language sql as $$
  insert into public.zz_ctx values (p, n) on conflict (k) do update set v = excluded.v $$;
create function public.zz_ot(p_neto numeric, p_inicio date default null, p_anticipo boolean default false) returns bigint
language plpgsql as $$
declare v bigint; e bigint;
begin
  select id into e from public.establecimiento where cliente_id = public.zz('cli') and principal;
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto, requiere_anticipo)
  values ('directa', 'prueba', public.zz('cli'), e, public.zz('s1'), public.zz('ana'), coalesce(p_inicio, public.hoy_ar()), p_neto, p_anticipo) returning id into v;
  return v;
end $$;
create function public.zz_emitir(p_lines jsonb, p_clase text default 'factura', p_origen bigint default null, p_asoc bigint default null, p_fecha date default null, p_iva_default numeric default 21) returns bigint
language plpgsql as $$
declare f bigint; l jsonb; tipo bigint; n int;
begin
  select id into tipo from public.lista_valor where lista = 'tipo_comprobante'
     and nombre = case p_clase when 'factura' then 'Factura A' when 'nc' then 'Nota de crédito A' else 'Nota de débito A' end;
  insert into public.factura (clase, cliente_id, factura_origen_id, emisor_tipo, emisor_asociado_id, fecha)
  values (p_clase, public.zz('cli'), p_origen, case when p_asoc is null then 'cooperativa' else 'asociado' end, p_asoc, coalesce(p_fecha, public.hoy_ar())) returning id into f;
  for l in select * from jsonb_array_elements(p_lines) loop
    insert into public.factura_linea (factura_id, ot_id, neto, iva_pct) values (f, (l ->> 'ot')::bigint, (l ->> 'neto')::numeric, coalesce((l ->> 'iva')::numeric, p_iva_default));
  end loop;
  select coalesce(max(numero::int), 0) + 1 into n from public.factura;
  perform public.emitir_factura(f, '1', n::text, 'CAE' || n, null, tipo);
  return f;
end $$;
create function public.zz_fp(p_asoc bigint, p_total numeric, p_nro text, p_venc date default null, p_fecha date default null) returns bigint
language sql as $$
  insert into public.factura_proveedor (emisor_tipo, asociado_id, nro_comprobante, fecha, neto, total, vencimiento)
  values ('asociado', p_asoc, p_nro, coalesce(p_fecha, public.hoy_ar()), p_total, p_total, p_venc) returning id $$;
create function public.zz_ev(p_tipo text, p_id bigint) returns int language sql stable as
$$ select count(*)::int from public.calendario_eventos where tipo = p_tipo and entidad_id = p_id and not cumplido $$;
create function public.zz_evc(p_tipo text, p_id bigint) returns int language sql stable as
$$ select count(*)::int from public.calendario_eventos where tipo = p_tipo and entidad_id = p_id and cumplido $$;

insert into public.permiso_puesto select p.id, 'calendario', 2 from public.puesto p where p.nombre = 'Operador';

do $$
declare cli bigint; s1 bigint; ana bigint; rafa bigint; mt bigint; sl bigint; per bigint;
begin
  select id into cli from public.cliente where nro_doc = '30755555556';
  select id into s1 from public.servicio where nombre = 'Higiene mensual';
  select id into ana from public.asociado where nro_doc = '27300000001';
  select id into rafa from public.asociado where nro_doc = '20300000002';
  insert into public.asociado (apellido_nombre, nro_doc, condicion_iva, vinculo, periodicidad_control, aniversario_periodo)
  values ('Mono, Marta', '27400000001', 'Monotributo', 'monotributista_autonomo', 'anual', date_trunc('year', public.hoy_ar())::date) returning id into mt;
  insert into public.asociado (apellido_nombre, nro_doc, condicion_iva, vinculo) values ('SinLimite, Sol', '27400000002', 'Monotributo', 'monotributista_autonomo') returning id into sl;
  insert into public.asociado (apellido_nombre, nro_doc, condicion_iva, vinculo) values ('Periodo, Pedro', '27400000003', 'Monotributo', 'monotributista_autonomo') returning id into per;
  perform public.zzset('cli', cli); perform public.zzset('s1', s1); perform public.zzset('ana', ana); perform public.zzset('rafa', rafa);
  perform public.zzset('mt', mt); perform public.zzset('sl', sl); perform public.zzset('per', per);
end $$;

-- ===== 1) Períodos de control de cada asociado =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare r record; begin
  update public.asociado set periodicidad_control = 'anual', aniversario_periodo = date '2020-07-15' where id = public.zz('per');
  select * into r from public.monotributo_periodo(public.zz('per'), date '2026-03-10'); assert r.desde = date '2025-07-15' and r.hasta = date '2026-07-14', 'anual antes del aniversario: ' || r.desde || ' ' || r.hasta;
  select * into r from public.monotributo_periodo(public.zz('per'), date '2026-08-01'); assert r.desde = date '2026-07-15' and r.hasta = date '2027-07-14', 'anual después del aniversario';
  select * into r from public.monotributo_periodo(public.zz('per'), date '2026-07-15'); assert r.desde = date '2026-07-15', 'el día del aniversario ya es el período nuevo';
  update public.asociado set periodicidad_control = 'semestral' where id = public.zz('per');
  select * into r from public.monotributo_periodo(public.zz('per'), date '2026-03-10'); assert r.desde = date '2026-01-15' and r.hasta = date '2026-07-14', 'semestral: ' || r.desde || ' ' || r.hasta;
  select * into r from public.monotributo_periodo(public.zz('per'), date '2026-09-01'); assert r.desde = date '2026-07-15' and r.hasta = date '2027-01-14', 'semestral, segundo tramo';
  update public.asociado set periodicidad_control = 'anual', aniversario_periodo = null where id = public.zz('per');
  select * into r from public.monotributo_periodo(public.zz('per'), date '2026-05-05'); assert r.desde = date '2026-01-01' and r.hasta = date '2026-12-31', 'sin aniversario: año calendario';
  update public.asociado set aniversario_periodo = date '2020-01-31' where id = public.zz('per');
  select * into r from public.monotributo_periodo(public.zz('per'), date '2026-02-10'); assert r.desde = date '2026-01-28', 'el día 31 se toma como 28 para no fallar en febrero';
  raise notice 'OK períodos de control';
end $$;
commit;

-- ===== 2) Acumulado del período =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare o bigint; f bigint; fp bigint; r record; n int; liq1 bigint; ie bigint; begin
  insert into public.monotributo_limite (asociado_id, vigente_desde, limite) values (public.zz('mt'), date '2000-01-01', 1000000);
  o := public.zz_ot(500000); perform public.zzset('o_mt', o);
  f := public.zz_emitir(jsonb_build_array(jsonb_build_object('ot', o, 'neto', 100000, 'iva', 0)), 'factura', null, public.zz('mt'));
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.facturas = 100000 and r.total = 100000, 'factura emitida por el asociado';
  perform public.zz_emitir(jsonb_build_array(jsonb_build_object('ot', o, 'neto', 20000, 'iva', 0)), 'nd', f, public.zz('mt'));
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.facturas = 120000, 'la nota de débito suma: ' || r.facturas;
  perform public.zz_emitir(jsonb_build_array(jsonb_build_object('ot', o, 'neto', 10000, 'iva', 0)), 'nc', f, public.zz('mt'));
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.facturas = 110000, 'la nota de crédito resta: ' || r.facturas;
  fp := public.zz_fp(public.zz('mt'), 50000, '0009-1');
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.facturas_a_cooperativa = 50000 and r.total = 160000, 'factura del asociado a la Cooperativa';
  liq1 := public.registrar_liquidacion(public.zz('mt'), 'a_asociado', 30000, public.hoy_ar(), fp);
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.total = 160000 and r.transferencias = 0, 'lo pagado contra factura no se cuenta dos veces';
  perform public.registrar_liquidacion(public.zz('mt'), 'a_asociado', 25000);
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.transferencias = 25000 and r.total = 185000, 'la transferencia sin factura sí cuenta';
  perform public.registrar_liquidacion(public.zz('mt'), 'de_asociado', 7000);
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.total = 185000, 'lo que el asociado le paga a la Cooperativa no cuenta';
  insert into public.monotributo_ingreso_externo (asociado_id, fecha, tipo, importe, concepto) values (public.zz('mt'), public.hoy_ar(), 'factura_propia', 15000, 'Cliente particular');
  insert into public.monotributo_ingreso_externo (asociado_id, fecha, tipo, importe) values (public.zz('mt'), public.hoy_ar(), 'transferencia', 5000) returning id into ie;
  perform public.anular_ingreso_externo(ie, 'Cargado por error');
  insert into public.monotributo_ajuste (asociado_id, importe, motivo) values (public.zz('mt'), -5000, 'Calibración con ARCA');
  select * into r from public.monotributo_resumen(public.zz('mt'));
  assert r.externos = 15000 and r.ajustes = -5000 and r.total = 195000 and r.limite = 1000000 and r.pct = 19.5 and r.semaforo = 'verde', 'acumulado 195.000 = 19,5%: ' || r.total || ' ' || r.semaforo;
  select count(*) into n from public.monotributo_detalle(public.zz('mt')); assert n = 5, 'el detalle tiene 5 renglones: ' || n;
  perform public.revertir_liquidacion(liq1, 'Error');
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.total = 195000, 'revertir una liquidación aplicada a factura no cambia el acumulado (cuenta la factura)';
  perform public.registrar_liquidacion(public.zz('mt'), 'a_asociado', 1000);
  perform public.revertir_liquidacion((select max(id) from public.liquidacion where asociado_id = public.zz('mt') and not anulada and importe = 1000), 'Prueba');
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.total = 195000, 'una transferencia revertida deja de contar';
  raise notice 'OK acumulado de monotributo';
end $$;
commit;

-- ===== 3) Semáforo, límite versionado, proyección y estado general =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare r record; n int; begin
  select * into r from public.monotributo_proyeccion(800000) where asociado_id = public.zz('mt');
  assert r.pct_actual = 19.5 and r.pct_con_monto = 99.5 and r.semaforo_actual = 'verde' and r.semaforo_con_monto = 'rojo' and r.disponible = 805000, 'proyección: ' || r.pct_con_monto || ' ' || r.semaforo_con_monto;
  select * into r from public.monotributo_proyeccion(900000) where asociado_id = public.zz('mt'); assert r.semaforo_con_monto = 'excedido', 'con 900.000 más se excedería';
  insert into public.monotributo_ingreso_externo (asociado_id, fecha, tipo, importe) values (public.zz('mt'), public.hoy_ar(), 'factura_propia', 655000);
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.pct = 85 and r.semaforo = 'amarillo', 'amarillo desde el 80%: ' || r.pct;
  insert into public.monotributo_ingreso_externo (asociado_id, fecha, tipo, importe) values (public.zz('mt'), public.hoy_ar(), 'factura_propia', 110000);
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.pct = 96 and r.semaforo = 'rojo', 'rojo desde el 95%';
  insert into public.monotributo_ingreso_externo (asociado_id, fecha, tipo, importe) values (public.zz('mt'), public.hoy_ar(), 'factura_propia', 50000);
  select * into r from public.monotributo_resumen(public.zz('mt')); assert r.pct = 101 and r.semaforo = 'excedido', 'excedido';
  insert into public.monotributo_limite (asociado_id, vigente_desde, limite) values (public.zz('mt'), public.hoy_ar() + 30, 2000000);
  assert public.monotributo_limite_en(public.zz('mt')) = 1000000 and public.monotributo_limite_en(public.zz('mt'), public.hoy_ar() + 31) = 2000000, 'cada límite rige desde su fecha';
  update public.monotributo_limite set limite = 1; get diagnostics n = row_count; assert n = 0, 'los límites no se modifican';
  begin insert into public.monotributo_limite (asociado_id, vigente_desde, limite) values (public.zz('mt'), date '2000-01-01', 5); raise exception 'NO DEBIÓ'; exception when unique_violation then null; end;
  select * into r from public.monotributo_resumen(public.zz('sl')); assert r.semaforo = 'sin_limite', 'sin límite definido';
  select * into r from public.monotributo_resumen(public.zz('rafa')); assert r.semaforo = 'no_aplica', 'un asociado que no es monotributista no aplica';
  select count(*) into n from public.monotributo_estado() where asociado_id = public.zz('rafa'); assert n = 0, 'el estado general solo lista monotributistas';
  select count(*) into n from public.monotributo_estado() where asociado_id = public.zz('mt') and semaforo = 'excedido'; assert n = 1, 'estado general';
  update public.monotributo_ingreso_externo set importe = 1; get diagnostics n = row_count; assert n = 0, 'los ingresos externos no se editan';
  raise notice 'OK semáforo, límites y proyección';
end $$;
commit;

-- ===== 4) Permisos de monotributo =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ declare n int; begin
  perform * from public.monotributo_resumen(public.zz('ana'));
  begin perform * from public.monotributo_resumen(public.zz('mt')); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform * from public.monotributo_detalle(public.zz('mt')); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  select count(*) into n from public.monotributo_estado(); assert n <= 1, 've solo su propio estado: ' || n;
  select count(*) into n from public.monotributo_ingreso_externo; assert n = 0, 'no ve ingresos externos de otros';
  raise notice 'OK cada asociado ve solo lo suyo';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare n int; begin
  select count(*) into n from public.monotributo_proyeccion(1000);  assert n >= 1, 'quien factura puede consultar la proyección';
  begin perform * from public.monotributo_detalle(public.zz('mt')); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform public.anular_ingreso_externo(1, 'x'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin insert into public.monotributo_ajuste (asociado_id, importe, motivo) values (public.zz('mt'), 1, 'x'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK permisos de monotributo del operador';
end $$; rollback;
begin; set local role anon;
do $$ begin
  begin perform * from public.monotributo_estado(); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK un visitante anónimo no ve el monotributo';
end $$; rollback;

-- ===== 5) Calendario unificado =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare pr bigint; ln bigint; o bigint; f bigint; c bigint; fp bigint; sm bigint; e record; cod text; g bigint; a bigint; begin
  insert into public.presupuesto (cliente_id, establecimiento_id) values (public.zz('cli'), (select id from public.establecimiento where cliente_id = public.zz('cli') and principal)) returning id, codigo into pr, cod;
  insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad) values (pr, public.zz('s1'), 1) returning id into ln;
  assert public.zz_ev('presupuesto_seguimiento', pr) = 0, 'un borrador no genera recordatorios';
  perform public.enviar_presupuesto(pr);
  select * into e from public.calendario_eventos where tipo = 'presupuesto_seguimiento' and entidad_id = pr; assert e.fecha = public.hoy_ar() + 7, 'seguimiento a los 7 días';
  select * into e from public.calendario_eventos where tipo = 'presupuesto_vence' and entidad_id = pr; assert e.fecha = public.hoy_ar() + 30, 'vence a los 30 días';
  perform public.rechazar_linea(ln, (select id from public.lista_valor where lista = 'motivo_rechazo' limit 1));
  assert public.zz_ev('presupuesto_seguimiento', pr) = 0 and public.zz_ev('presupuesto_vence', pr) = 0, 'al procesarse, desaparecen';

  o := public.zz_ot(100000, public.hoy_ar() + 4);
  assert public.zz_ev('ot_inicio', o) = 1, 'inicio previsto de la OT';
  perform public.cambiar_estado_ot(o, 'en_ejecucion');
  assert public.zz_ev('ot_inicio', o) = 0 and public.zz_evc('ot_inicio', o) = 1, 'al iniciar queda cumplido';
  perform public.cambiar_estado_ot(o, 'finalizada');
  assert public.zz_ev('ot_facturar', o) = 1, 'finalizada sin facturar: alerta';
  f := public.zz_emitir(jsonb_build_array(jsonb_build_object('ot', o, 'neto', 100000, 'iva', 0)));
  assert public.zz_ev('ot_facturar', o) = 0, 'facturada completa: la alerta desaparece';

  assert public.zz_ev('factura_vence', f) = 1, 'vence la factura';
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 100000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 100000)), p_medio_id := (select id from public.medio_pago where nombre = 'Cheque'));
  assert public.zz_evc('factura_vence', f) = 1 and public.zz_ev('factura_vence', f) = 0, 'cobrada: queda cumplido';
  assert public.zz_ev('cobranza_disponible', c) = 1, 'fondos a acreditar en 2 días (cheque)';
  assert public.zz_ev('cobranza_distribuir', c) = 1, 'cobranza pendiente de distribuir';
  perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 100)));
  perform public.distribuir_cobranza(c);
  assert public.zz_ev('cobranza_distribuir', c) = 0, 'distribuida: desaparece';

  o := public.zz_ot(80000, null, true);
  select id into f from public.factura f2 where exists (select 1 from public.factura_linea l where l.factura_id = f2.id and l.ot_id = o);
  assert public.zz_ev('factura_borrador', f) = 1, 'borrador de anticipo para emitir';

  fp := public.zz_fp(public.zz('mt'), 10000, '0010-1', public.hoy_ar() + 5);
  assert public.zz_ev('factura_proveedor_vence', fp) = 1, 'vence la factura de proveedor';
  perform public.registrar_liquidacion(public.zz('mt'), 'a_asociado', 10000, public.hoy_ar(), fp);
  assert public.zz_evc('factura_proveedor_vence', fp) = 1, 'pagada: cumplido';

  insert into public.sm (cliente_id, establecimiento_id, servicio_id, dia_generacion, dia_inicio, fecha_inicio, fecha_fin, responsable_id)
  values (public.zz('cli'), (select id from public.establecimiento where cliente_id = public.zz('cli') and principal), public.zz('s1'), 1, 5, public.hoy_ar() - 40, public.hoy_ar() + 20, public.zz('ana')) returning id into sm;
  insert into public.sm_precio (sm_id, vigente_desde, precio) values (sm, date_trunc('month', public.hoy_ar() - 40)::date, 1000);
  assert public.zz_ev('sm_generar', sm) = 1 and public.zz_ev('sm_fin', sm) = 1, 'SM: generar el mes y aviso de fin';
  perform public.generar_ot_sm(sm);
  assert public.zz_ev('sm_generar', sm) = 0, 'generada la OT del mes, desaparece';
  select * into e from public.calendario_eventos where tipo = 'sm_fin' and entidad_id = sm; assert e.fecha = public.hoy_ar() + 20, 'fecha de fin del SM';

  update public.asociado set venc_matricula = public.hoy_ar() + 15 where id = public.zz('ana');
  assert public.zz_ev('matricula_vence', public.zz('ana')) = 1, 'vence la matrícula';
  assert public.zz_ev('monotributo_alerta', public.zz('mt')) = 1, 'alerta de monotributo (excedido)';
  select * into e from public.calendario_eventos where tipo = 'monotributo_cierre' and entidad_id = public.zz('mt'); assert e.fecha = (date_trunc('year', public.hoy_ar()) + interval '1 year - 1 day')::date, 'cierre del período';

  update public.organizacion set aprobar_gastos = true;
  g := public.crear_gasto('general', null, null, null, 'cooperativa', null, null, jsonb_build_array(jsonb_build_object('categoria_id', (select id from public.categoria_gasto where nombre = 'Administración'), 'total', 100)));
  assert public.zz_ev('gasto_aprobar', g) = 1, 'gasto por aprobar';
  perform public.aprobar_gasto(g);
  assert public.zz_ev('gasto_aprobar', g) = 0, 'aprobado: desaparece';
  update public.organizacion set aprobar_gastos = false;
  raise notice 'OK calendario derivado';
end $$;
commit;

begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ begin
  insert into public.recordatorio (fecha, titulo, compartido) values (public.hoy_ar() + 1, 'Privado de admin', false);
  insert into public.recordatorio (fecha, titulo, compartido) values (public.hoy_ar() + 1, 'Compartido', true);
  assert (select count(*) from public.calendario_eventos where tipo = 'manual' and titulo in ('Privado de admin','Compartido')) = 2, 'el administrador ve sus recordatorios';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare rid bigint; n int; begin
  assert (select count(*) from public.calendario_eventos where tipo = 'manual' and titulo = 'Compartido') = 1, 've los compartidos';
  assert (select count(*) from public.calendario_eventos where tipo = 'manual' and titulo = 'Privado de admin') = 0, 'no ve los privados de otros';
  insert into public.recordatorio (fecha, titulo) values (public.hoy_ar() + 2, 'Mío') returning id into rid;
  update public.recordatorio set cumplido = true where id = rid;
  assert (select cumplido_en from public.recordatorio where id = rid) is not null, 'al cumplirse registra cuándo';
  update public.recordatorio set titulo = 'ajeno' where titulo = 'Compartido'; get diagnostics n = row_count; assert n = 0, 'no edita los de otros';
  begin insert into public.recordatorio (fecha, titulo, usuario_id) values (public.hoy_ar(), 'x', '00000000-0000-0000-0000-000000000001'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  assert not exists (select 1 from public.calendario_eventos where tipo = 'monotributo_alerta'), 'sin permiso de monotributo no ve sus alertas';
  raise notice 'OK recordatorios manuales';
end $$;
commit;

-- ===== 6) Reportes =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare o bigint; f1 bigint; f2 bigint; f3 bigint; r record; fp1 bigint; fp2 bigint; fp3 bigint; fn bigint; fa bigint; nc bigint; n int; begin
  o := public.zz_ot(1000000);
  f1 := public.zz_emitir(jsonb_build_array(jsonb_build_object('ot', o, 'neto', 1000, 'iva', 0)), 'factura', null, null, public.hoy_ar() - 45);
  f2 := public.zz_emitir(jsonb_build_array(jsonb_build_object('ot', o, 'neto', 2000, 'iva', 0)));
  f3 := public.zz_emitir(jsonb_build_array(jsonb_build_object('ot', o, 'neto', 3000, 'iva', 0)), 'factura', null, null, public.hoy_ar() - 100);
  select * into r from public.facturas_por_cobrar where factura_id = f1; assert r.tramo = '1_30' and r.dias_vencida = 15 and r.saldo = 1000, 'vencida hace 15 días: tramo 1-30';
  select * into r from public.facturas_por_cobrar where factura_id = f2; assert r.tramo = 'a_vencer' and r.dias_vencida = 0, 'a vencer';
  select * into r from public.facturas_por_cobrar where factura_id = f3; assert r.tramo = 'mas_60', 'más de 60 días';
  perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 2000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f2, 'importe', 2000)));
  assert not exists (select 1 from public.facturas_por_cobrar where factura_id = f2), 'cobrada: sale del reporte';
  perform public.zz_emitir(jsonb_build_array(jsonb_build_object('ot', o, 'neto', 100, 'iva', 0)), 'nd', f1);
  select * into r from public.facturas_por_cobrar where factura_id = f1; assert r.saldo = 1100, 'la nota de débito aumenta lo por cobrar';

  fp1 := public.zz_fp(public.zz('mt'), 500, '0020-1', public.hoy_ar() - 40);
  fp2 := public.zz_fp(public.zz('mt'), 600, '0020-2');
  fp3 := public.zz_fp(public.zz('mt'), 700, '0020-3', public.hoy_ar() + 3);
  select * into r from public.facturas_proveedor_por_pagar where factura_id = fp1; assert r.tramo = '31_60' and r.dias_vencida = 40, 'proveedor: 31-60 días';
  select * into r from public.facturas_proveedor_por_pagar where factura_id = fp2; assert r.tramo = 'sin_vencimiento', 'sin vencimiento';
  select * into r from public.facturas_proveedor_por_pagar where factura_id = fp3; assert r.tramo = 'a_vencer', 'a vencer';
  perform public.registrar_liquidacion(public.zz('mt'), 'a_asociado', 700, public.hoy_ar(), fp3);
  assert not exists (select 1 from public.facturas_proveedor_por_pagar where factura_id = fp3), 'pagada: sale del reporte';

  fa := public.zz_emitir(jsonb_build_array(jsonb_build_object('ot', o, 'neto', 10000, 'iva', 21), jsonb_build_object('ot', o, 'neto', 20000, 'iva', 10.5)));
  select count(*) into n from public.libro_iva_ventas where comprobante_id = fa; assert n = 2, 'una fila por alícuota';
  select * into r from public.libro_iva_ventas where comprobante_id = fa and alicuota = 21; assert r.neto_gravado = 10000 and r.iva = 2100, 'IVA 21%';
  select * into r from public.libro_iva_ventas where comprobante_id = fa and alicuota = 10.5; assert r.neto_gravado = 20000 and r.iva = 2100, 'IVA 10,5%';
  nc := public.zz_emitir(jsonb_build_array(jsonb_build_object('ot', o, 'neto', 1000, 'iva', 21)), 'nc', fa);
  select * into r from public.libro_iva_ventas where comprobante_id = nc; assert r.neto_gravado = -1000 and r.iva = -210, 'la nota de crédito resta';
  fn := public.zz_emitir(jsonb_build_array(jsonb_build_object('ot', o, 'neto', 5000, 'iva', 21)), 'factura', null, public.zz('mt'));
  assert not exists (select 1 from public.libro_iva_ventas where comprobante_id = fn), 'las facturas de un asociado no son IVA de la Cooperativa';
  assert exists (select 1 from public.libro_iva_compras where comprobante_id = fp1), 'compras: factura de un asociado';
  perform public.anular_factura_proveedor(fp2, 'Duplicada');
  assert not exists (select 1 from public.libro_iva_compras where comprobante_id = fp2), 'las anuladas no figuran';
  raise notice 'OK reportes';
end $$;
commit;

-- ===== 7) Sin permisos no se ven los eventos de otros módulos =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ begin
  assert not exists (select 1 from public.calendario_eventos where tipo in ('factura_vence','ot_inicio','cobranza_disponible','gasto_aprobar')), 'el lector solo ve lo de los módulos que puede leer';
  assert (select count(*) from public.facturas_por_cobrar) = 0 and (select count(*) from public.libro_iva_ventas) = 0, 'ni los reportes de facturación';
  raise notice 'OK el calendario respeta los permisos';
end $$; rollback;

do $$ declare n int; begin
  select count(*) into n from public.log_auditoria where tabla = 'monotributo_ingreso_externo'; assert n >= 4, 'ingresos externos auditados';
  raise notice 'OK auditoría';
end $$;

drop function public.zz_evc(text, bigint); drop function public.zz_ev(text, bigint); drop function public.zz_fp(bigint, numeric, text, date, date);
drop function public.zz_emitir(jsonb, text, bigint, bigint, date, numeric); drop function public.zz_ot(numeric, date, boolean);
drop function public.zzset(text, bigint); drop function public.zz(text); drop table public.zz_ctx;
\echo 'MONOTRIBUTO, CALENDARIO Y REPORTES: todas las pruebas pasaron'
