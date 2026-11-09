\set ON_ERROR_STOP on
\set U1 '''00000000-0000-0000-0000-000000000001'''
\set U2 '''00000000-0000-0000-0000-000000000002'''
\set U3 '''00000000-0000-0000-0000-000000000003'''

-- ===== Preparación =====
create table public.zz_ctx (k text primary key, v bigint);
create function public.zz(p text) returns bigint language sql stable as $$ select v from public.zz_ctx where k = p $$;
create function public.zzset(p text, n bigint) returns void language sql as $$
  insert into public.zz_ctx values (p, n) on conflict (k) do update set v = excluded.v $$;
create function public.zzfa(p text) returns record language sql stable as $$ select * from public.factura_resumen where id = public.zz(p) $$;
-- Crea y emite un comprobante. p_lines = [{ot, neto, iva}]
create function public.zz_emitir(p_cli bigint, p_lines jsonb, p_clase text default 'factura', p_origen bigint default null, p_asoc bigint default null) returns bigint
language plpgsql as $$
declare f bigint; l jsonb; tipo bigint; n int;
begin
  select id into tipo from public.lista_valor where lista = 'tipo_comprobante'
     and nombre = case p_clase when 'factura' then 'Factura A' when 'nc' then 'Nota de crédito A' else 'Nota de débito A' end;
  insert into public.factura (clase, cliente_id, factura_origen_id, emisor_tipo, emisor_asociado_id)
  values (p_clase, p_cli, p_origen, case when p_asoc is null then 'cooperativa' else 'asociado' end, p_asoc) returning id into f;
  for l in select * from jsonb_array_elements(p_lines) loop
    insert into public.factura_linea (factura_id, ot_id, neto, iva_pct) values (f, (l ->> 'ot')::bigint, (l ->> 'neto')::numeric, coalesce((l ->> 'iva')::numeric, 21));
  end loop;
  select coalesce(max(numero::int), 0) + 1 into n from public.factura;
  perform public.emitir_factura(f, '1', n::text, 'CAE' || n, null, tipo);
  return f;
end $$;

insert into public.permiso_puesto select p.id, m, 2 from public.puesto p, (values ('facturacion'),('cobranza')) x(m) where p.nombre = 'Operador';

do $$
declare cli bigint; cli2 bigint; est bigint; est2 bigint; s1 bigint; ana bigint; cp bigint; b bigint; o bigint; k text;
begin
  select id into cli from public.cliente where nro_doc = '30755555556';
  select id into cli2 from public.cliente where nro_doc = '30766666667';
  select id into est from public.establecimiento where cliente_id = cli and principal;
  select id into est2 from public.establecimiento where cliente_id = cli2 and principal;
  select id into s1 from public.servicio where nombre = 'Higiene mensual';
  select id into ana from public.asociado where nro_doc = '27300000001';
  select id into cp from public.condicion_pago where nombre = '30 días';
  update public.cliente set condicion_pago_id = cp where id = cli;
  select id into b from public.lista_valor where lista = 'banco' limit 1;
  insert into public.cuenta_bancaria (titular_tipo, titular_id, banco_id, cbu) values ('cliente', cli, b, '0170000000000000000010') returning id into o; perform public.zzset('cta_cli', o);
  insert into public.cuenta_bancaria (titular_tipo, titular_id, banco_id, cbu) values ('cliente', cli2, b, '0170000000000000000011') returning id into o; perform public.zzset('cta_cli2', o);
  select id into o from public.cuenta_bancaria where cbu = '0170000000000000000003'; perform public.zzset('cta_ana', o);
  select id into o from public.cuenta_bancaria where nro_cuenta = '439-0251987'; perform public.zzset('cta_coop', o);
  perform public.zzset('transf', (select id from public.medio_pago where nombre = 'Transferencia'));
  perform public.zzset('cheque', (select id from public.medio_pago where nombre = 'Cheque'));
  perform public.zzset('cli', cli); perform public.zzset('cli2', cli2); perform public.zzset('est', est); perform public.zzset('s1', s1); perform public.zzset('ana', ana);
  foreach k in array array['o1','o2','o5'] loop
    insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
    values ('directa', 'prueba facturación', cli, est, s1, ana, public.hoy_ar(), 100000) returning id into o; perform public.zzset(k, o);
  end loop;
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
  values ('directa', 'prueba facturación', cli2, est2, s1, ana, public.hoy_ar(), 100000) returning id into o; perform public.zzset('o3', o);
end $$;

-- ===== 1) Borradores automáticos =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare oa bigint; ob bigint; f record; l record; n int; sm bigint; pr bigint; ln bigint; s bigint; begin
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto, requiere_anticipo, anticipo_monto)
  values ('directa', 'con anticipo', public.zz('cli'), public.zz('est'), public.zz('s1'), public.zz('ana'), public.hoy_ar(), 100000, true, 20000) returning id into oa;
  select f2.*, l2.neto as l_neto, l2.iva_pct into f from public.factura f2 join public.factura_linea l2 on l2.factura_id = f2.id where l2.ot_id = oa;
  assert f.estado_doc = 'borrador' and f.origen_borrador = 'anticipo' and f.emisor_tipo = 'cooperativa' and f.l_neto = 20000 and f.iva_pct = 21, 'borrador de anticipo con el IVA de la Cooperativa';
  assert f.vencimiento = f.fecha + 30, 'vence según la condición de pago del cliente';
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
  values ('directa', 'sin anticipo', public.zz('cli'), public.zz('est'), public.zz('s1'), public.zz('ana'), public.hoy_ar(), 5000) returning id into ob;
  select count(*) into n from public.factura_linea where ot_id = ob; assert n = 0, 'sin anticipo no hay borrador';
  perform public.cambiar_estado_ot(oa, 'cancelada', 'Se desistió');
  select count(*) into n from public.factura_linea where ot_id = oa; assert n = 0, 'al cancelar la OT se descarta su borrador';

  insert into public.sm (cliente_id, establecimiento_id, servicio_id, dia_generacion, dia_inicio, fecha_inicio, responsable_id)
  values (public.zz('cli'), public.zz('est'), public.zz('s1'), 1, 10, public.hoy_ar() - 40, public.zz('ana')) returning id into sm;
  insert into public.sm_precio (sm_id, vigente_desde, precio) values (sm, date_trunc('month', public.hoy_ar() - 40)::date, 80000);
  ob := public.generar_ot_sm(sm, public.hoy_ar());
  select f2.origen_borrador, l2.neto into f from public.factura f2 join public.factura_linea l2 on l2.factura_id = f2.id where l2.ot_id = ob;
  assert f.origen_borrador = 'sm' and f.neto = 80000, 'la OT del SM genera su factura en borrador';

  insert into public.presupuesto (cliente_id, establecimiento_id, emisor_tipo, emisor_asociado_id) values (public.zz('cli'), public.zz('est'), 'asociado', public.zz('ana')) returning id into pr;
  insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad, precio_unitario) values (pr, public.zz('s1'), 1, 90000) returning id into ln;
  perform public.enviar_presupuesto(pr);
  ob := public.aprobar_linea(ln, public.hoy_ar(), null, true, null);
  select f2.emisor_tipo, f2.emisor_asociado_id, l2.neto, l2.iva_pct into f from public.factura f2 join public.factura_linea l2 on l2.factura_id = f2.id where l2.ot_id = ob;
  assert f.emisor_tipo = 'asociado' and f.emisor_asociado_id = public.zz('ana') and f.neto = 90000 and f.iva_pct = 0, 'anticipo desde presupuesto: emite el asociado y el IVA sigue su condición';
  raise notice 'OK borradores automáticos';
end $$;
commit;

-- ===== 2) Factura manual: borrador, emisión, unicidad, inmutabilidad =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare f bigint; f2 bigint; r record; t public.factura_total; tfa bigint; tnc bigint; begin
  select id into tfa from public.lista_valor where lista = 'tipo_comprobante' and nombre = 'Factura A';
  select id into tnc from public.lista_valor where lista = 'tipo_comprobante' and nombre = 'Nota de crédito A';
  insert into public.factura (cliente_id, emisor_tipo, emisor_asociado_id) values (public.zz('cli'), 'asociado', public.zz('ana')) returning id into f;
  insert into public.factura_linea (factura_id, ot_id, descripcion, neto, iva_pct) values (f, public.zz('o1'), 'a', 40000, 21), (f, public.zz('o2'), 'b', 60000, 21);
  perform public.zzset('f1', f);
  select * into t from public.factura_total where id = f; assert t.neto = 100000 and t.iva = 21000 and t.total = 121000, 'totales del comprobante';
  update public.factura_linea set descripcion = 'editada' where factura_id = f and orden = 1;      -- el borrador se edita
  begin perform public.emitir_factura(f, '1', '101', 'CAE1'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%tipo de comprobante%', sqlerrm; end;
  begin perform public.emitir_factura(f, '1', '101', null, null, tfa); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%CAE%', sqlerrm; end;
  begin perform public.emitir_factura(f, '1', '101', 'CAE101', null, tnc); raise exception 'NO DEBIÓ'; exception when check_violation then assert sqlerrm like '%no corresponde%', sqlerrm; end;
  begin insert into public.factura_linea (factura_id, ot_id, neto, iva_pct) values (f, public.zz('o3'), 1, 21); raise exception 'NO DEBIÓ'; exception when check_violation then assert sqlerrm like '%no pertenece al cliente%', sqlerrm; end;
  perform public.emitir_factura(f, '1', '101', 'CAE101', null, tfa);
  select * into r from public.factura_resumen where id = f;
  assert r.estado = 'emitida' and r.punto_venta = '00001' and r.numero = '00000101' and r.saldo = 121000 and r.vencimiento = r.fecha + 30, 'emitida, con punto de venta y número normalizados y su vencimiento';
  insert into public.factura (cliente_id, emisor_tipo, emisor_asociado_id) values (public.zz('cli'), 'asociado', public.zz('ana')) returning id into f2;
  insert into public.factura_linea (factura_id, ot_id, neto, iva_pct) values (f2, public.zz('o1'), 1000, 21);
  begin perform public.emitir_factura(f2, '1', '101', 'CAE102', null, tfa); raise exception 'NO DEBIÓ'; exception when unique_violation then null; end;
  perform public.emitir_factura(f2, '1', '102', 'CAE102', null, tfa);       -- otro número: sí
  begin update public.factura_linea set neto = 1 where factura_id = f; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin update public.factura set numero = '9' where id = f; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  update public.factura set observacion = 'enviada por mail' where id = f;
  begin perform public.emitir_factura(f); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%ya está emitido%', sqlerrm; end;
  insert into public.factura (cliente_id) values (public.zz('cli')) returning id into f2;
  begin perform public.emitir_factura(f2, '1', '5', 'C', null, tfa); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%no tiene líneas%', sqlerrm; end;
  -- factura interna (regalías): sin punto de venta ni CAE
  insert into public.factura (cliente_id, modo) values (public.zz('cli'), 'interna') returning id into f2;
  insert into public.factura_linea (factura_id, ot_id, neto, iva_pct) values (f2, public.zz('o2'), 500, 0);
  perform public.emitir_factura(f2, null, null, null, null, (select id from public.lista_valor where lista = 'tipo_comprobante' and nombre = 'Ticket / otro'));
  assert (select estado from public.factura_resumen where id = f2) = 'emitida', 'la interna se emite sin CAE';
  raise notice 'OK factura: borrador, emisión, unicidad e inmutabilidad';
end $$;
commit;

-- ===== 3) Cobranzas: parcial, total, retenciones, sobrante =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare c1 bigint; c2 bigint; r record; f2 bigint; f3 bigint; fd bigint; n int; c record; begin
  c1 := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 60500, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz('f1'), 'importe', 60500)),
                                  p_cuenta_destino := public.zz('cta_coop'), p_medio_id := public.zz('transf'));
  perform public.zzset('c1', c1);
  select * into r from public.factura_resumen where id = public.zz('f1');
  assert r.estado = 'parcial' and r.cobrado = 60500 and r.saldo = 60500, 'cobro parcial: ' || r.estado;
  select * into c from public.cobranza_ot where cobranza_id = c1 and ot_id = public.zz('o1');
  assert c.neto = 20000 and c.iva = 4200, 'reparto del cobro entre OT (o1): ' || c.neto || ' ' || c.iva;
  select * into c from public.cobranza_ot where cobranza_id = c1 and ot_id = public.zz('o2');
  assert c.neto = 30000 and c.iva = 6300, 'reparto del cobro entre OT (o2)';
  assert (select sum(neto + iva + otros) from public.cobranza_ot where cobranza_id = c1) = 60500, 'el reparto suma exacto';

  begin perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 70000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz('f1'), 'importe', 70000))); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%supera su saldo%', sqlerrm; end;
  begin perform public.registrar_cobranza(p_cliente := public.zz('cli2'), p_importe := 100, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz('f1'), 'importe', 100))); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%no es de ese cliente%', sqlerrm; end;
  begin perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 100, p_aplicaciones := '[]'::jsonb); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%a qué facturas%', sqlerrm; end;
  begin perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 0, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz('f1'), 'importe', 100))); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%no tiene importe%', sqlerrm; end;
  begin perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 50, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz('f1'), 'importe', 100))); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%supera lo cobrado%', sqlerrm; end;
  select id into fd from public.factura where estado_doc = 'borrador' and cliente_id = public.zz('cli') limit 1;
  begin perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 100, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', fd, 'importe', 100))); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%facturas emitidas%', sqlerrm; end;
  begin perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 100, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz('f1'), 'importe', 100)), p_cuenta_destino := public.zz('cta_ana')); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;                                          -- la cuenta no es de la Cooperativa

  c2 := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 60500, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz('f1'), 'importe', 60500)),
                                  p_medio_id := public.zz('cheque'), p_fecha_cobro := public.hoy_ar());
  assert (select estado from public.factura_resumen where id = public.zz('f1')) = 'cobrada', 'cobrada';
  assert (select fecha_disponibilidad from public.cobranza where id = c2) = public.hoy_ar() + 2, 'disponibilidad = cobro + días de acreditación del medio';

  -- retenciones
  f2 := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o1'), 'neto', 100000)));
  begin perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 100000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f2, 'importe', 121000)), p_ret_iva := 21001); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%retención de IVA%', sqlerrm; end;
  begin perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 1, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f2, 'importe', 100002)), p_ret_otras := 100001); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%Ganancias/IIBB%', sqlerrm; end;
  c2 := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 100000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f2, 'importe', 121000)), p_ret_iva := 10000, p_ret_otras := 11000);
  assert (select estado from public.factura_resumen where id = f2) = 'cobrada' and (select sobrante from public.cobranza where id = c2) = 0, 'las retenciones cancelan saldo';
  assert (select ret_iva from public.cobranza where id = c2) = 10000 and (select ret_otras from public.cobranza where id = c2) = 11000, 'retenciones separadas';

  -- sobrante a cuenta corriente del cliente, cobrado por un asociado
  f3 := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o2'), 'neto', 10000, 'iva', 0)));
  c2 := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 15000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f3, 'importe', 10000)),
                                  p_receptor_asociado := public.zz('ana'), p_cuenta_destino := public.zz('cta_ana'));
  assert (select sobrante from public.cobranza where id = c2) = 5000 and (select receptor_asociado_id from public.cobranza where id = c2) = public.zz('ana'), 'sobrante y receptor asociado';
  assert public.saldo_cliente(public.zz('cli')) = 5000, 'el sobrante queda a favor del cliente';
  perform public.zzset('f3', f3); perform public.zzset('c_sob', c2);
  raise notice 'OK cobranzas';
end $$;
commit;

-- ===== 4) Aplicar saldo a favor =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare f4 bigint; cs bigint; begin
  f4 := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o2'), 'neto', 8000, 'iva', 0)));
  begin perform public.aplicar_saldo_favor(public.zz('cli'), jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 8000))); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%no alcanza%', sqlerrm; end;
  cs := public.aplicar_saldo_favor(public.zz('cli'), jsonb_build_array(jsonb_build_object('factura_id', f4, 'importe', 5000)));
  assert (select tipo from public.cobranza where id = cs) = 'saldo_favor' and (select estado from public.factura_resumen where id = f4) = 'parcial', 'el saldo se aplica como una cobranza sin efectivo';
  assert public.saldo_cliente(public.zz('cli')) = 0, 'el saldo a favor se consume';
  perform public.zzset('f4', f4); perform public.zzset('c_sf', cs);
  raise notice 'OK saldo a favor';
end $$;
commit;

-- ===== 5) Revertir cobranzas =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare fx bigint; fy bigint; c bigint; cs bigint; r record; begin
  fx := public.zz_emitir(public.zz('cli2'), jsonb_build_array(jsonb_build_object('ot', public.zz('o3'), 'neto', 50000)));
  c := public.registrar_cobranza(p_cliente := public.zz('cli2'), p_importe := 70000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', fx, 'importe', 60500)));
  assert public.saldo_cliente(public.zz('cli2')) = 9500, 'sobrante 9.500';
  fy := public.zz_emitir(public.zz('cli2'), jsonb_build_array(jsonb_build_object('ot', public.zz('o3'), 'neto', 8000, 'iva', 0)));
  cs := public.aplicar_saldo_favor(public.zz('cli2'), jsonb_build_array(jsonb_build_object('factura_id', fy, 'importe', 8000)));
  begin perform public.revertir_cobranza(c, 'error'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%ya se aplicó%', sqlerrm; end;
  begin perform public.revertir_cobranza(cs, null); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%motivo%', sqlerrm; end;
  perform public.revertir_cobranza(cs, 'Se aplicó a la factura equivocada');
  assert public.saldo_cliente(public.zz('cli2')) = 9500 and (select estado from public.factura_resumen where id = fy) = 'emitida', 'revertir la aplicación devuelve el saldo al cliente y la factura queda sin cobrar';
  perform public.revertir_cobranza(c, 'Cobranza cargada dos veces');
  select * into r from public.factura_resumen where id = fx;
  assert r.estado = 'emitida' and r.cobrado = 0, 'la factura recupera su saldo';
  assert public.saldo_cliente(public.zz('cli2')) = 0, 'el sobrante se revierte';
  assert (select cobrado_neto from public.ot_cobranza where ot_id = public.zz('o3')) = 0, 'la OT ya no figura cobrada';
  assert (select anulada from public.cobranza where id = c), 'la cobranza queda anulada, no borrada';
  begin perform public.revertir_cobranza(c, 'otra vez'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%ya está anulada%', sqlerrm; end;
  perform public.zzset('c_rev', c);
  raise notice 'OK revertir cobranzas';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  begin perform public.revertir_cobranza(public.zz('c1'), 'x'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK revertir cobranzas exige administración';
end $$; rollback;

-- ===== 6) Notas de crédito y de débito =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare f5 bigint; nc1 bigint; nc2 bigint; fd bigint; r record; res bigint; n int; f6 bigint; f7 bigint; nd bigint; a0 numeric; tfa bigint; begin
  f5 := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o5'), 'neto', 100000)));
  perform public.zzset('f5', f5);
  perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 121000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f5, 'importe', 121000)));
  assert (select estado from public.factura_resumen where id = f5) = 'cobrada', 'factura cobrada';
  perform public.zzset('c_nc', (select max(id) from public.cobranza));
  -- validaciones de la NC
  begin perform public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o5'), 'neto', 100001)), 'nc', f5); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%supera lo facturado%', sqlerrm; end;
  begin insert into public.factura (clase, cliente_id, factura_origen_id) values ('nc', public.zz('cli2'), f5); raise exception 'NO DEBIÓ';
  exception when check_violation then assert sqlerrm like '%mismo cliente%', sqlerrm; end;
  insert into public.factura (cliente_id) values (public.zz('cli')) returning id into fd;
  insert into public.factura_linea (factura_id, ot_id, neto, iva_pct) values (fd, public.zz('o5'), 100, 21);
  begin perform public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o5'), 'neto', 10)), 'nc', fd); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%no está emitida%', sqlerrm; end;

  nc1 := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o5'), 'neto', 30000)), 'nc', f5);
  select * into r from public.factura_resumen where id = f5;
  assert r.total_vigente = 84700 and r.nc_total = 36300 and r.estado = 'credito_a_resolver' and r.credito_a_resolver = 36300, 'la NC baja lo vigente aunque esté cobrada: ' || r.estado || ' ' || r.credito_a_resolver;
  assert (select estado from public.factura_resumen where id = nc1) = 'emitida', 'la NC figura emitida';
  begin perform public.resolver_credito_factura(f5, 40000, 'saldo_favor'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%supera el crédito%', sqlerrm; end;
  res := public.resolver_credito_factura(f5, 36300, 'saldo_favor');
  assert (select estado from public.factura_resumen where id = f5) = 'cobrada' and public.saldo_cliente(public.zz('cli')) = 36300, 'crédito dejado como saldo a favor';
  select * into r from public.factura_credito_resuelto_ot where resuelto_id = res; assert r.neto = 30000 and r.iva = 6300, 'lo resuelto se reparte en las OT';
  assert (select cobrado_neto from public.ot_cobranza where ot_id = public.zz('o5')) = 70000, 'la OT queda con 70.000 cobrados';

  nc2 := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o5'), 'neto', 70000)), 'nc', f5);
  begin perform public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o5'), 'neto', 1)), 'nc', f5); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%supera lo facturado%', sqlerrm; end;
  select * into r from public.factura_resumen where id = f5; assert r.total_vigente = 0 and r.credito_a_resolver = 84700 and r.estado = 'credito_a_resolver', 'acreditada del todo pero con crédito a resolver';
  begin perform public.resolver_credito_factura(f5, 84700, 'devolucion', public.hoy_ar(), null, null, public.zz('cta_coop'), public.zz('cta_ana')); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;                                                -- la cuenta destino debe ser del cliente
  perform public.resolver_credito_factura(f5, 84700, 'devolucion', public.hoy_ar(), public.zz('transf'), null, public.zz('cta_coop'), public.zz('cta_cli'));
  assert (select estado from public.factura_resumen where id = f5) = 'acreditada', 'devuelto: factura acreditada';
  assert (select count(*) from public.devolucion_cliente where cliente_id = public.zz('cli') and importe = 84700) = 1, 'devolución registrada';
  begin perform public.resolver_credito_factura(f5, 1, 'saldo_favor'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%supera el crédito%', sqlerrm; end;

  -- devolución pagada por un asociado
  f6 := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o2'), 'neto', 10000, 'iva', 0)));
  perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 10000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f6, 'importe', 10000)));
  perform public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o2'), 'neto', 10000, 'iva', 0)), 'nc', f6);
  select coalesce(sum(importe), 0) into a0 from public.movimiento_cc_asociado where asociado_id = public.zz('ana');
  perform public.resolver_credito_factura(f6, 10000, 'devolucion', public.hoy_ar(), null, public.zz('ana'), public.zz('cta_ana'), public.zz('cta_cli'));
  assert (select sum(importe) from public.movimiento_cc_asociado where asociado_id = public.zz('ana')) - a0 = 10000, 'si devolvió un asociado, la Cooperativa le debe ese importe';

  -- nota de débito
  f7 := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o2'), 'neto', 10000, 'iva', 0)));
  perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 10000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f7, 'importe', 10000)));
  nd := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', public.zz('o2'), 'neto', 5000, 'iva', 0)), 'nd', f7);
  select * into r from public.factura_resumen where id = f7;
  assert r.total_vigente = 15000 and r.saldo = 5000 and r.estado = 'parcial', 'la ND aumenta el saldo aunque esté cobrada: ' || r.estado;
  perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 5000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f7, 'importe', 5000)));
  assert (select estado from public.factura_resumen where id = f7) = 'cobrada', 'se cobra la diferencia';
  raise notice 'OK notas de crédito y de débito';
end $$;
commit;

-- ===== 7) Estado de facturación por OT =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare o bigint; r record; begin
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
  values ('directa', 'prueba', public.zz('cli'), public.zz('est'), public.zz('s1'), public.zz('ana'), public.hoy_ar(), 100000) returning id into o;
  select * into r from public.ot_facturacion where ot_id = o; assert r.estado_facturacion = 'sin_facturar', 'sin facturar';
  perform public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 40000)));
  select * into r from public.ot_facturacion where ot_id = o; assert r.estado_facturacion = 'parcial' and r.pct_facturado = 40, 'parcial 40%';
  perform public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 60000)));
  select * into r from public.ot_facturacion where ot_id = o; assert r.estado_facturacion = 'completa', 'completa';
  perform public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 1000)));
  select * into r from public.ot_facturacion where ot_id = o; assert r.estado_facturacion = 'excedida', 'excedida';
  raise notice 'OK estado de facturación por OT';
end $$;
commit;

-- ===== 8) Nada de plata se toca directo; permisos =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare n int; begin
  begin insert into public.cobranza (cliente_id) values (public.zz('cli')); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  update public.cobranza set observacion = 'x'; get diagnostics n = row_count; assert n = 0, 'las cobranzas no se editan a mano';
  begin insert into public.movimiento_cc_cliente (cliente_id, importe, concepto, origen_tipo) values (public.zz('cli'), 1, 'x', 'manual'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  update public.factura set observacion = 'nota' where id = public.zz('f1');
  begin update public.factura set cae = 'X' where id = public.zz('f1'); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  delete from public.factura where id = public.zz('f1'); get diagnostics n = row_count; assert n = 0, 'el operador no borra facturas';
  raise notice 'OK nada se toca directo';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare fd bigint; n int; begin
  begin delete from public.factura where id = public.zz('f1'); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  insert into public.factura (cliente_id) values (public.zz('cli')) returning id into fd;
  delete from public.factura where id = fd; get diagnostics n = row_count; assert n = 1, 'un borrador sí se borra';
  raise notice 'OK una emitida no se borra';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ declare n int; begin
  select count(*) into n from public.factura; assert n = 0, 'el lector (sin Facturación) no ve comprobantes';
  select count(*) into n from public.cobranza; assert n = 0, 'ni cobranzas';
  begin perform public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 1, p_aplicaciones := '[]'::jsonb); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform public.emitir_factura(public.zz('f1')); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK sin permiso no se ve ni se opera';
end $$; rollback;
begin; set local role anon;
do $$ begin
  begin perform public.registrar_cobranza(p_cliente := 1, p_importe := 1, p_aplicaciones := '[]'::jsonb); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform public.revertir_cobranza(1, 'x'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK un visitante anónimo no ejecuta funciones';
end $$; rollback;

-- ===== 9) Auditoría =====
do $$ declare n int; begin
  select count(*) into n from public.log_auditoria where tabla = 'cobranza' and campo = 'anulada' and valor_nuevo = 'true' and motivo is not null; assert n >= 2, 'reversiones auditadas con motivo: ' || n;
  select count(*) into n from public.log_auditoria where tabla = 'factura' and campo = 'estado_doc' and valor_nuevo = 'emitida'; assert n >= 5, 'emisiones auditadas';
  raise notice 'OK auditoría de facturación y cobranza';
end $$;

drop function public.zz_emitir(bigint, jsonb, text, bigint, bigint); drop function public.zzfa(text); drop function public.zzset(text, bigint); drop function public.zz(text); drop table public.zz_ctx;
\echo 'FACTURACIÓN Y COBRANZA: todas las pruebas pasaron'
