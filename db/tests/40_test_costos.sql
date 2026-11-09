\set ON_ERROR_STOP on
\set U1 '''00000000-0000-0000-0000-000000000001'''
\set U2 '''00000000-0000-0000-0000-000000000002'''
\set U3 '''00000000-0000-0000-0000-000000000003'''

-- ===== Preparación (como administrador de la base) =====
create table public.zz_ctx (k text primary key, v bigint);
create function public.zz(p text) returns bigint language sql stable as $$ select v from public.zz_ctx where k = p $$;
create function public.zzset(p text, n bigint) returns void language sql as $$
  insert into public.zz_ctx values (p, n) on conflict (k) do update set v = excluded.v $$;
create function public.sal(p bigint) returns numeric language sql stable as
$$ select coalesce(sum(importe), 0) from public.movimiento_cc_asociado where asociado_id = p $$;

do $$
declare cli bigint; est bigint; s1 bigint; ana bigint; rafa bigint; bruno bigint; p1 bigint; p2 bigint; p3 bigint; b bigint; o bigint; k text;
begin
  select id into cli from public.cliente where nro_doc = '30755555556';
  select id into est from public.establecimiento where cliente_id = cli and principal;
  select id into s1 from public.servicio where nombre = 'Higiene mensual';
  select id into ana from public.asociado where nro_doc = '27300000001';
  select id into rafa from public.asociado where nro_doc = '20300000002';
  select id into bruno from public.asociado where nro_doc = '20300000003';
  insert into public.proveedor (nombre_fantasia, nro_doc, condicion_iva, tipo) values ('Proveedor Común', '20400000001', 'Resp. Inscripto', 'proveedor') returning id into p1;
  insert into public.proveedor (nombre_fantasia, nro_doc, condicion_iva, tipo) values ('Subcontratista Uno', '20400000002', 'Monotributo', 'subcontratista') returning id into p2;
  insert into public.proveedor (nombre_fantasia, nro_doc, condicion_iva, tipo) values ('Otro Proveedor', '20400000003', 'Resp. Inscripto', 'proveedor') returning id into p3;
  select id into b from public.lista_valor where lista = 'banco' limit 1;
  insert into public.cuenta_bancaria (titular_tipo, titular_id, banco_id, cbu) values ('proveedor', p1, b, '0170000000000000000001') returning id into o; perform public.zzset('cta_p1', o);
  insert into public.cuenta_bancaria (titular_tipo, titular_id, banco_id, cbu) values ('proveedor', p3, b, '0170000000000000000002') returning id into o; perform public.zzset('cta_p3', o);
  insert into public.cuenta_bancaria (titular_tipo, titular_id, banco_id, cbu) values ('asociado', ana, b, '0170000000000000000003') returning id into o; perform public.zzset('cta_ana', o);
  select id into o from public.cuenta_bancaria where nro_cuenta = '439-0251987'; perform public.zzset('cta_coop', o);
  select id into o from public.cuenta_bancaria where nro_cuenta = '439-0299077'; perform public.zzset('cta_coop2', o);
  perform public.zzset('cli', cli); perform public.zzset('est', est); perform public.zzset('ana', ana); perform public.zzset('rafa', rafa); perform public.zzset('bruno', bruno);
  perform public.zzset('p1', p1); perform public.zzset('p2', p2); perform public.zzset('p3', p3);
  perform public.zzset('cat_ins', (select id from public.categoria_gasto where nombre = 'Insumos y materiales'));
  perform public.zzset('cat_ban', (select id from public.categoria_gasto where nombre = 'Gastos bancarios'));
  perform public.zzset('fa', (select id from public.lista_valor where lista = 'tipo_comprobante' and nombre = 'Factura A'));
  -- OT de prueba (todas directas y abiertas)
  foreach k in array array['oa','ob','oc','od','oe','of'] loop
    insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
    values ('directa', 'prueba de costos', cli, est, s1, ana, public.hoy_ar(), 100000) returning id into o;
    perform public.zzset(k, o);
  end loop;
end $$;

-- ===== 1) Gasto operativo con factura de proveedor y concepto sin factura =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare g bigint; r record; fp record; n int; y text := extract(year from public.hoy_ar())::text; it record; begin
  g := public.crear_gasto('operativo', public.zz('oa'), public.hoy_ar(), null, 'ot', null, 'compra de insumos', jsonb_build_array(
        jsonb_build_object('categoria_id', public.zz('cat_ins'), 'descripcion', 'Cascos', 'discriminado', true, 'neto', 10000, 'iva', 2100,
                           'proveedor_id', public.zz('p1'), 'nro_factura', '0001-100', 'tipo_comprobante_id', public.zz('fa')),
        jsonb_build_object('categoria_id', public.zz('cat_ins'), 'descripcion', 'Ficha', 'total', 5000)));
  perform public.zzset('g1', g);
  select * into r from public.gasto where id = g;
  assert r.codigo = 'GAS-' || y || '-00001' and r.aprobacion = 'aprobado' and not r.anulado, 'gasto creado y aprobado (config sin aprobación): ' || r.codigo || ' ' || r.aprobacion;
  select * into it from public.gasto_item where gasto_id = g and orden = 1;
  assert it.total = 12100 and it.costo_neto = 10000 and it.afecta_margen and it.factura_proveedor_id is not null, 'concepto con IVA discriminado';
  select * into fp from public.factura_proveedor_resumen where id = it.factura_proveedor_id;
  assert fp.proveedor_id = public.zz('p1') and fp.neto = 10000 and fp.iva = 2100 and fp.total = 12100 and fp.vencimiento is null and fp.estado = 'pendiente', 'se generó la factura de proveedor';
  assert fp.codigo like 'FPR-' || y || '-%', fp.codigo;
  perform public.zzset('fp1', fp.id);
  assert (select factura_proveedor_id from public.gasto_item where gasto_id = g and orden = 2) is null, 'el concepto sin número queda sin factura';
  select * into r from public.gasto_resumen where id = g;
  assert r.total = 17100 and r.total_sin_factura = 5000 and r.costo_margen = 15000 and r.pago_estado = 'pendiente', 'resumen: ' || r.total || ' ' || r.total_sin_factura || ' ' || r.costo_margen || ' ' || r.pago_estado;
  select * into r from public.ot_costos where ot_id = public.zz('oa');
  assert r.gastos_total = 17100 and r.costo_margen = 15000, 'costos de la OT';
  select count(*) into n from public.movimiento_cc_asociado where origen_tipo = 'gasto' and origen_id = g; assert n = 0, 'pagó la Cooperativa: sin movimientos de asociados';

  begin perform public.crear_gasto('operativo', public.zz('oa'), null, null, 'ot', null, null, '[]'::jsonb); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%al menos un concepto%', sqlerrm; end;
  begin perform public.crear_gasto('operativo', public.zz('oa'), null, null, 'ot', null, null, jsonb_build_array(jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 0))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%mayor a cero%', sqlerrm; end;
  begin perform public.crear_gasto('operativo', null, null, null, 'ot', null, null, jsonb_build_array(jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 1))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%necesita una OT%', sqlerrm; end;
  begin perform public.crear_gasto('general', public.zz('oa'), null, null, 'cooperativa', null, null, jsonb_build_array(jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 1))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%no lleva OT%', sqlerrm; end;
  begin perform public.crear_gasto('operativo', public.zz('oa'), null, null, 'cooperativa', null, null, jsonb_build_array(jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 1))); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin perform public.crear_gasto('operativo', public.zz('oa'), null, null, 'asociado', null, null, jsonb_build_array(jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 1))); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin perform public.crear_gasto('operativo', public.zz('oa'), null, public.zz('bruno'), 'ot', null, null, jsonb_build_array(jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 1))); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  raise notice 'OK gasto operativo con factura y concepto sin factura';
end $$;
commit;

-- ===== 2) Dos gastos sobre la misma factura; pagador asociado + factura existente =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare g bigint; r record; begin
  g := public.crear_gasto('operativo', public.zz('oa'), null, null, 'ot', null, null, jsonb_build_array(
        jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 12100, 'proveedor_id', public.zz('p1'), 'nro_factura', '0001-100')));
  perform public.zzset('g2', g);
  assert (select factura_proveedor_id from public.gasto_item where gasto_id = g) = public.zz('fp1'), 'se vincula a la factura existente';
  select * into r from public.factura_proveedor_resumen where id = public.zz('fp1');
  assert r.imputado = 24200 and r.imputado_excede, 'la factura queda imputada de más: alerta';
  begin perform public.crear_gasto('operativo', public.zz('oa'), null, public.zz('ana'), 'ot', null, null, jsonb_build_array(
        jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 100, 'proveedor_id', public.zz('p1'), 'nro_factura', '0001-100'))); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%ya está registrada%', sqlerrm; end;
  raise notice 'OK factura compartida';
end $$;
commit;

-- ===== 3) Gasto pagado por un asociado: cuenta corriente =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare g bigint; a0 numeric; r0 numeric; r record; fpid bigint; begin
  a0 := public.sal(public.zz('ana')); r0 := public.sal(public.zz('rafa'));
  g := public.crear_gasto('operativo', public.zz('ob'), null, public.zz('ana'), 'ot', null, null, jsonb_build_array(
        jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 8000, 'proveedor_id', public.zz('p3'), 'nro_factura', '0002-5')));
  perform public.zzset('g3', g);
  select factura_proveedor_id into fpid from public.gasto_item where gasto_id = g;
  select * into r from public.factura_proveedor_resumen where id = fpid;
  assert r.estado = 'pagada' and r.pagado = 8000, 'si pagó un asociado la factura queda pagada';
  assert (select origen from public.factura_proveedor_pago where factura_id = fpid) = 'asociado', 'pago registrado como pagado por el asociado';
  assert public.sal(public.zz('ana')) - a0 = 8000, 'la Cooperativa le debe al asociado lo que pagó';
  assert (select pago_estado from public.gasto_resumen where id = g) = 'pagado', 'gasto pagado';
  perform public.zzset('fp3', fpid);
  -- imputación a otro asociado: ana pagó, rafa lo asume
  a0 := public.sal(public.zz('ana'));
  g := public.crear_gasto('operativo', public.zz('ob'), null, public.zz('ana'), 'asociado', public.zz('rafa'), null, jsonb_build_array(
        jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 3000)));
  assert public.sal(public.zz('ana')) - a0 = 3000 and public.sal(public.zz('rafa')) - r0 = -3000, 'ana +3.000 y rafa −3.000';
  assert (select afecta_margen from public.gasto_item where gasto_id = g) = false, 'un gasto a cargo de un asociado no afecta el margen de la OT';
  -- el mismo asociado paga y asume: no hay movimientos
  a0 := public.sal(public.zz('ana'));
  g := public.crear_gasto('operativo', public.zz('ob'), null, public.zz('ana'), 'asociado', public.zz('ana'), null, jsonb_build_array(
        jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 2000)));
  assert public.sal(public.zz('ana')) = a0, 'paga y asume el mismo: sin movimientos';
  raise notice 'OK gasto pagado por asociado y cuenta corriente';
end $$;
commit;

-- ===== 4) Aprobación de gastos (configurable) =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare g bigint; antes numeric; begin
  update public.organizacion set aprobar_gastos = true;
  select costo_margen into antes from public.ot_costos where ot_id = public.zz('ob');
  g := public.crear_gasto('operativo', public.zz('ob'), null, null, 'ot', null, null, jsonb_build_array(jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 7000)));
  perform public.zzset('g4', g);
  assert (select aprobacion from public.gasto where id = g) = 'registrado', 'con aprobación activa nace registrado';
  assert (select costo_margen from public.ot_costos where ot_id = public.zz('ob')) = antes, 'un gasto sin aprobar no descuenta del margen';
  assert (select gastos_total from public.ot_costos where ot_id = public.zz('ob')) >= 7000, 'pero figura en los gastos de la OT';
  begin perform public.pagar_gasto_sf(g); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%aprobarse%', sqlerrm; end;
  update public.organizacion set aprobar_gastos = false;
  raise notice 'OK gasto registrado sin aprobar';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  begin perform public.aprobar_gasto(public.zz('g4')); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK aprobar exige administración';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare antes numeric; begin
  select costo_margen into antes from public.ot_costos where ot_id = public.zz('ob');
  perform public.aprobar_gasto(public.zz('g4'));
  assert (select costo_margen from public.ot_costos where ot_id = public.zz('ob')) = antes + 7000, 'aprobado: ahora descuenta del margen';
  begin perform public.aprobar_gasto(public.zz('g4')); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%ya está aprobado%', sqlerrm; end;
  raise notice 'OK aprobación de gastos';
end $$;
commit;

-- ===== 5) Pagos: conceptos sin factura y factura de proveedor =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare pa bigint; pb bigint; begin
  begin perform public.pagar_gasto_sf(public.zz('g1'), public.hoy_ar(), null, public.zz('cta_p1')); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;   -- cuenta de origen que no es de la Cooperativa
  begin perform public.pagar_gasto_sf(public.zz('g2')); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%tienen factura%', sqlerrm; end;
  perform public.pagar_gasto_sf(public.zz('g1'), public.hoy_ar(), null, public.zz('cta_coop'), null);
  assert (select pagado_sf from public.gasto where id = public.zz('g1')), 'conceptos sin factura pagados';
  assert (select pago_estado from public.gasto_resumen where id = public.zz('g1')) = 'parcial', 'falta pagar la factura: parcial';
  begin perform public.pagar_gasto_sf(public.zz('g1')); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%ya están pagados%', sqlerrm; end;
  begin perform public.pagar_gasto_sf(public.zz('g3')); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%asociado%', sqlerrm; end;

  pa := public.registrar_pago_factura(public.zz('fp1'), 5000, public.hoy_ar(), null, public.zz('cta_coop'), public.zz('cta_p1'));
  perform public.zzset('pa', pa);
  assert (select estado from public.factura_proveedor_resumen where id = public.zz('fp1')) = 'parcial', 'pago parcial';
  begin perform public.registrar_pago_factura(public.zz('fp1'), 8000); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%supera el saldo%', sqlerrm; end;
  begin perform public.registrar_pago_factura(public.zz('fp1'), 100, public.hoy_ar(), null, null, public.zz('cta_p3')); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;   -- cuenta de otro proveedor
  pb := public.registrar_pago_factura(public.zz('fp1'), 7100);
  perform public.zzset('pb', pb);
  assert (select estado from public.factura_proveedor_resumen where id = public.zz('fp1')) = 'pagada', 'pagada';
  assert (select pago_estado from public.gasto_resumen where id = public.zz('g1')) = 'pagado', 'el gasto queda pagado';
  begin perform public.registrar_pago_factura(public.zz('fp1'), 1); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%supera el saldo%', sqlerrm; end;
  raise notice 'OK pagos';
end $$;
commit;

-- ===== 6) Reversión de pagos =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  begin perform public.revertir_pago_factura(public.zz('pb'), 'error'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform public.revertir_pago_gasto_sf(public.zz('g1'), 'error'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK revertir pagos exige administración';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare pas bigint; begin
  begin perform public.revertir_pago_factura(public.zz('pb'), null); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%motivo%', sqlerrm; end;
  perform public.revertir_pago_factura(public.zz('pb'), 'Se pagó dos veces');
  assert (select estado from public.factura_proveedor_resumen where id = public.zz('fp1')) = 'parcial', 'al revertir, la factura recupera el saldo';
  assert (select pago_estado from public.gasto_resumen where id = public.zz('g1')) = 'parcial', 'y el gasto deja de estar pagado';
  begin perform public.revertir_pago_factura(public.zz('pb'), 'otra vez'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%ya está anulado%', sqlerrm; end;
  select id into pas from public.factura_proveedor_pago where origen = 'asociado' limit 1;
  begin perform public.revertir_pago_factura(pas, 'x'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%revirtiendo el gasto%', sqlerrm; end;
  perform public.revertir_pago_gasto_sf(public.zz('g1'), 'Pago mal imputado');
  assert not (select pagado_sf from public.gasto where id = public.zz('g1')), 'pago sin factura revertido';
  assert (select count(*) from public.log_auditoria where tabla = 'factura_proveedor_pago' and campo = 'anulado' and motivo is not null or tabla = 'gasto' and campo = 'pagado_sf' and motivo = 'Pago mal imputado') >= 1, 'la reversión queda auditada';
  raise notice 'OK reversión de pagos';
end $$;
commit;

-- ===== 7) Revertir (anular) gastos =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare a0 numeric; n int; g bigint; r record; begin
  -- g1 todavía tiene un pago de la Cooperativa en la factura
  begin perform public.anular_gasto(public.zz('g1'), 'cargado mal'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%pagos de la Cooperativa%', sqlerrm; end;
  perform public.revertir_pago_factura(public.zz('pa'), 'Se revierte todo');
  begin perform public.anular_gasto(public.zz('g1'), null); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%motivo%', sqlerrm; end;
  perform public.anular_gasto(public.zz('g1'), 'Se cargó dos veces');
  assert (select anulado from public.gasto where id = public.zz('g1')), 'gasto anulado (no se borra)';
  assert (select costo_margen from public.ot_costos where ot_id = public.zz('oa')) = 0 + (select coalesce(sum(i.costo_neto),0) from public.gasto_item i join public.gasto g2 on g2.id = i.gasto_id where g2.ot_id = public.zz('oa') and not g2.anulado and i.afecta_margen), 'el gasto anulado deja de contar';
  assert (select estado from public.factura_proveedor_resumen where id = public.zz('fp1')) <> 'anulada', 'la factura sigue: g2 también la usa';
  perform public.anular_gasto(public.zz('g2'), 'Era el mismo gasto');
  assert (select estado from public.factura_proveedor_resumen where id = public.zz('fp1')) = 'anulada', 'sin gastos que la usen, la factura generada queda anulada';
  assert (select gastos_total from public.ot_costos where ot_id = public.zz('oa')) = 0, 'la OT queda sin gastos';
  begin perform public.anular_gasto(public.zz('g1'), 'otra vez'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%ya está anulado%', sqlerrm; end;

  -- gasto pagado por asociado: se contrarresta su cuenta y la factura queda anulada
  a0 := public.sal(public.zz('ana'));
  perform public.anular_gasto(public.zz('g3'), 'Factura mal cargada');
  assert public.sal(public.zz('ana')) = a0 - 8000, 'se contrarresta la cuenta corriente del asociado';
  select count(*) into n from public.movimiento_cc_asociado where origen_tipo = 'gasto' and origen_id = public.zz('g3'); assert n = 2, 'el libro conserva el movimiento y su contrapartida';
  assert (select estado from public.factura_proveedor_resumen where id = public.zz('fp3')) = 'anulada', 'factura pagada por el asociado anulada';
  -- el mismo número de factura se puede volver a cargar
  g := public.crear_gasto('operativo', public.zz('ob'), null, null, 'ot', null, null, jsonb_build_array(
        jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 8000, 'proveedor_id', public.zz('p3'), 'nro_factura', '0002-5')));
  assert (select factura_proveedor_id from public.gasto_item where gasto_id = g) <> public.zz('fp3'), 'el número liberado se reutiliza en una factura nueva';
  raise notice 'OK revertir gastos';
end $$;
commit;

-- ===== 8) OT cerrada o cancelada =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare g bigint; begin
  g := public.crear_gasto('operativo', public.zz('oc'), null, null, 'ot', null, null, jsonb_build_array(jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 1000)));
  perform public.zzset('gc', g);
  perform public.cambiar_estado_ot(public.zz('oc'), 'en_ejecucion'); perform public.cambiar_estado_ot(public.zz('oc'), 'finalizada'); perform public.cambiar_estado_ot(public.zz('oc'), 'cerrada');
  begin perform public.crear_gasto('operativo', public.zz('oc'), null, null, 'ot', null, null, jsonb_build_array(jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 1))); raise exception 'NO DEBIÓ';
  exception when check_violation then assert sqlerrm like '%no admite nuevos gastos%', sqlerrm; end;
  begin perform public.anular_gasto(public.zz('gc'), 'x'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%reabrila%', sqlerrm; end;
  perform public.cambiar_estado_ot(public.zz('oc'), 'finalizada', 'Reabierta para corregir gastos');
  perform public.anular_gasto(public.zz('gc'), 'Gasto mal cargado');   -- reabierta, ahora sí
  -- una OT con gastos no se cancela
  perform public.crear_gasto('operativo', public.zz('od'), null, null, 'ot', null, null, jsonb_build_array(jsonb_build_object('categoria_id', public.zz('cat_ins'), 'total', 1)));
  begin perform public.cambiar_estado_ot(public.zz('od'), 'cancelada', 'desistió'); raise exception 'NO DEBIÓ'; exception when check_violation then assert sqlerrm like '%gastos cargados%', sqlerrm; end;
  raise notice 'OK OT cerrada y cancelación con gastos';
end $$;
commit;

-- ===== 9) Subcontratos =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare s bigint; g bigint; r record; a0 numeric; begin
  begin insert into public.subcontrato (ot_id, proveedor_id, costo_contratado) values (public.zz('oe'), public.zz('p1'), 1000); raise exception 'NO DEBIÓ'; exception when check_violation then assert sqlerrm like '%subcontratista%', sqlerrm; end;
  insert into public.subcontrato (ot_id, proveedor_id, costo_presupuestado, costo_contratado) values (public.zz('oe'), public.zz('p2'), 90000, 100000) returning id into s;
  g := public.registrar_pago_subcontrato(s, 30000);
  select * into r from public.subcontrato_resumen where id = s; assert r.costo_real = 30000 and r.saldo = 70000, 'real y saldo: ' || r.costo_real || ' ' || r.saldo;
  assert (select clase from public.gasto where id = g) = 'operativo' and (select ot_id from public.gasto where id = g) = public.zz('oe') and (select pagado_sf from public.gasto where id = g), 'genera el gasto de la OT, pagado';
  assert (select costo_margen from public.ot_costos where ot_id = public.zz('oe')) = 30000, 'el subcontrato es costo de la OT';
  begin perform public.revertir_pago_gasto_sf(g, 'x'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%revirtiendo el gasto%', sqlerrm; end;
  perform public.anular_gasto(g, 'Pago duplicado');
  select * into r from public.subcontrato_resumen where id = s; assert r.costo_real = 0 and r.saldo = 100000, 'al revertir el gasto baja el costo real del subcontrato';
  a0 := public.sal(public.zz('ana'));
  g := public.registrar_pago_subcontrato(s, 20000, public.hoy_ar(), public.zz('ana'));
  assert public.sal(public.zz('ana')) - a0 = 20000, 'si pagó un asociado, se refleja en su cuenta';
  update public.subcontrato set estado = 'cerrado' where id = s;
  begin perform public.registrar_pago_subcontrato(s, 1); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%cerrado%', sqlerrm; end;
  raise notice 'OK subcontratos';
end $$;
commit;

-- ===== 10) Liquidaciones y facturas de asociados =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare f bigint; l bigint; a0 numeric; r record; begin
  a0 := public.sal(public.zz('ana'));
  -- la factura que un asociado le hace a la Cooperativa se carga como factura normal
  insert into public.factura_proveedor (emisor_tipo, asociado_id, nro_comprobante, fecha, neto, total) values ('asociado', public.zz('ana'), '0004-77', public.hoy_ar(), 400000, 400000) returning id into f;
  perform public.zzset('fa1', f);
  begin insert into public.factura_proveedor (emisor_tipo, asociado_id, nro_comprobante, fecha, neto, total) values ('asociado', public.zz('ana'), '0004-77', public.hoy_ar(), 1, 1); raise exception 'NO DEBIÓ'; exception when unique_violation then null; end;
  begin insert into public.factura_proveedor (emisor_tipo, asociado_id, nro_comprobante, fecha, neto, iva, total) values ('asociado', public.zz('ana'), '0004-78', public.hoy_ar(), 100, 21, 100); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin insert into public.factura_proveedor (emisor_tipo, proveedor_id, asociado_id, nro_comprobante, fecha, neto, total) values ('asociado', public.zz('p1'), public.zz('ana'), 'x', public.hoy_ar(), 1, 1); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin perform public.registrar_pago_factura(f, 1000); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%liquidación%', sqlerrm; end;
  -- liquidación aplicada a la factura
  l := public.registrar_liquidacion(public.zz('ana'), 'a_asociado', 150000, public.hoy_ar(), f, null, public.zz('cta_coop'), public.zz('cta_ana'));
  perform public.zzset('liq1', l);
  select * into r from public.factura_proveedor_resumen where id = f; assert r.estado = 'parcial' and r.pagado = 150000, 'la liquidación se aplica como pago de la factura';
  assert public.sal(public.zz('ana')) - a0 = -150000, 'descuenta de lo que la Cooperativa le debe';
  assert (select origen from public.factura_proveedor_pago where liquidacion_id = l) = 'liquidacion', 'pago de origen liquidación';
  begin update public.factura_proveedor set total = 1, neto = 1 where id = f; raise exception 'NO DEBIÓ'; exception when check_violation then assert sqlerrm like '%pagos o gastos%', sqlerrm; end;
  begin perform public.registrar_liquidacion(public.zz('ana'), 'a_asociado', 300000, public.hoy_ar(), f, null, public.zz('cta_coop'), public.zz('cta_ana')); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%supera el saldo%', sqlerrm; end;
  begin perform public.registrar_liquidacion(public.zz('ana'), 'a_asociado', 1000, public.hoy_ar(), f, null, public.zz('cta_coop'), public.zz('cta_p1')); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;   -- destino que no es del asociado
  begin perform public.registrar_liquidacion(public.zz('rafa'), 'a_asociado', 1000, public.hoy_ar(), f); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%no es de ese asociado%', sqlerrm; end;
  begin perform public.registrar_liquidacion(public.zz('ana'), 'de_asociado', 1000, public.hoy_ar(), f); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%le paga al asociado%', sqlerrm; end;
  -- transferencia sin factura y pago del asociado a la Cooperativa
  a0 := public.sal(public.zz('ana'));
  l := public.registrar_liquidacion(public.zz('ana'), 'a_asociado', 5000, public.hoy_ar(), null, null, public.zz('cta_coop'), public.zz('cta_ana'));
  perform public.zzset('liq2', l);
  assert public.sal(public.zz('ana')) - a0 = -5000, 'liquidación sin factura';
  a0 := public.sal(public.zz('ana'));
  perform public.registrar_liquidacion(public.zz('ana'), 'de_asociado', 2000, public.hoy_ar(), null, null, public.zz('cta_ana'), public.zz('cta_coop'));
  assert public.sal(public.zz('ana')) - a0 = 2000, 'el asociado le paga a la Cooperativa: suma a su favor';
  raise notice 'OK liquidaciones y facturas de asociados';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  begin perform public.revertir_liquidacion(public.zz('liq1'), 'error'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK revertir liquidación exige administración';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare a0 numeric; begin
  a0 := public.sal(public.zz('ana'));
  perform public.revertir_liquidacion(public.zz('liq1'), 'Transferencia rechazada');
  assert public.sal(public.zz('ana')) - a0 = 150000, 'la cuenta vuelve a su saldo';
  assert (select estado from public.factura_proveedor_resumen where id = public.zz('fa1')) = 'pendiente', 'la factura del asociado vuelve a pendiente';
  assert (select anulada from public.liquidacion where id = public.zz('liq1')), 'liquidación anulada, no borrada';
  begin perform public.revertir_liquidacion(public.zz('liq1'), 'otra vez'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%ya está anulada%', sqlerrm; end;
  perform public.anular_factura_proveedor(public.zz('fa1'), 'Factura emitida por error');
  assert (select estado from public.factura_proveedor_resumen where id = public.zz('fa1')) = 'anulada', 'factura sin pagos se puede anular';
  raise notice 'OK reversión de liquidaciones';
end $$;
commit;

-- ===== 11) Nada de plata se toca directo =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare n int; begin
  begin insert into public.gasto (clase, imputacion) values ('general', 'cooperativa'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin insert into public.movimiento_cc_asociado (asociado_id, importe, concepto, origen_tipo) values (public.zz('ana'), 1, 'x', 'manual'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin update public.gasto set fecha = public.hoy_ar() - 3 where id = public.zz('g3'); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  update public.gasto set observacion = 'nota' where id = public.zz('g3');
  update public.movimiento_cc_asociado set importe = 0; get diagnostics n = row_count; assert n = 0, 'el libro no se modifica';
  delete from public.movimiento_cc_asociado; get diagnostics n = row_count; assert n = 0, 'ni se borra';
  delete from public.gasto; get diagnostics n = row_count; assert n = 0, 'los gastos no se borran';
  begin update public.factura_proveedor set anulada = true where id = public.zz('fp1'); exception when check_violation then null; end;
  begin insert into public.factura_proveedor_pago (factura_id, importe, origen) values (public.zz('fp1'), 1, 'cooperativa'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK nada se toca directo';
end $$;
commit;

-- ===== 12) Permisos =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ declare n int; begin
  select count(*) into n from public.gasto; assert n = 0, 'el lector (sin Costos) no ve gastos';
  select count(*) into n from public.factura_proveedor; assert n = 0, 'ni facturas';
  select count(*) into n from public.movimiento_cc_asociado; assert n = 0, 'ni cuentas corrientes';
  begin perform public.crear_gasto('general', null, null, null, 'cooperativa', null, null, jsonb_build_array(jsonb_build_object('categoria_id', public.zz('cat_ban'), 'total', 1))); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK sin permiso no se ve ni se opera';
end $$; rollback;
update public.usuario set asociado_id = public.zz('ana') where id = '00000000-0000-0000-0000-000000000002';
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ declare n int; m int; begin
  select count(*) into n from public.movimiento_cc_asociado; select count(*) into m from public.movimiento_cc_asociado where asociado_id = public.zz('ana');
  assert n = m and n > 0, 'un usuario vinculado a un asociado ve solo su propia cuenta corriente (' || n || ' de ' || m || ')';
  select count(*) into n from public.gasto; assert n = 0, 'pero no ve los gastos';
  raise notice 'OK cada asociado ve su cuenta corriente';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare g bigint; begin
  g := public.crear_gasto('general', null, null, null, 'cooperativa', null, 'comisión bancaria', jsonb_build_array(
        jsonb_build_object('categoria_id', public.zz('cat_ban'), 'descripcion', 'Comisión', 'discriminado', true, 'neto', 600, 'iva', 126)));
  assert (select afecta_margen from public.gasto_item where gasto_id = g) = false, 'gastos bancarios no afectan el margen';
  perform public.anular_gasto(g, 'Prueba');
  raise notice 'OK el operador carga y revierte gastos';
end $$; rollback;
begin; set local role anon;
do $$ begin
  begin perform public.crear_gasto('general', null, null, null, 'cooperativa', null, null, '[]'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform public.registrar_liquidacion(1, 'a_asociado', 1); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK un visitante anónimo no ejecuta funciones';
end $$; rollback;

-- ===== 13) Auditoría =====
do $$ declare n int; begin
  select count(*) into n from public.log_auditoria where tabla = 'gasto' and campo = 'anulado' and valor_nuevo = 'true' and motivo is not null; assert n >= 3, 'anulaciones auditadas con motivo: ' || n;
  raise notice 'OK auditoría de costos';
end $$;

drop function public.sal(bigint); drop function public.zzset(text, bigint); drop function public.zz(text); drop table public.zz_ctx;
\echo 'COSTOS Y GASTOS: todas las pruebas pasaron'
