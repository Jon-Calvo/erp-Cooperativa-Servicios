\set ON_ERROR_STOP on
\set U1 '''00000000-0000-0000-0000-000000000001'''
\set U2 '''00000000-0000-0000-0000-000000000002'''
\set U3 '''00000000-0000-0000-0000-000000000003'''

-- ===== Preparación =====
create table public.zz_ctx (k text primary key, v bigint);
create function public.zz(p text) returns bigint language sql stable as $$ select v from public.zz_ctx where k = p $$;
create function public.zzset(p text, n bigint) returns void language sql as $$
  insert into public.zz_ctx values (p, n) on conflict (k) do update set v = excluded.v $$;
create function public.sal(p bigint) returns numeric language sql stable as
$$ select coalesce(sum(importe), 0) from public.movimiento_cc_asociado where asociado_id = p $$;
create function public.zz_ot(p_neto numeric, p_modo text default 'proporcional', p_modalidad text default 'servicio', p_cli bigint default null) returns bigint
language plpgsql as $$
declare v bigint; c bigint := coalesce(p_cli, public.zz('cli')); e bigint;
begin
  select id into e from public.establecimiento where cliente_id = c and principal;
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto, modo_dist_parcial, modalidad)
  values ('directa', 'prueba distribución', c, e, public.zz('s1'), public.zz('ana'), public.hoy_ar(), p_neto, p_modo, p_modalidad) returning id into v;
  return v;
end $$;
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
create function public.zz_gasto(p_ot bigint, p_total numeric, p_afecta boolean default true) returns bigint
language sql as $$
  select public.crear_gasto('operativo', p_ot, null, null, 'ot', null, null, jsonb_build_array(jsonb_build_object(
     'categoria_id', (select id from public.categoria_gasto where nombre = 'Insumos y materiales'), 'total', p_total, 'afecta_margen', p_afecta))) $$;
-- Escenario completo: OT + costos + regla 50/50 (ana/paz) + factura + cobranza + distribución. Devuelve la cobranza.
create function public.zz_esc(p_emisor bigint, p_receptor bigint, p_neto numeric, p_iva numeric, p_importe numeric,
    p_ret_o numeric default 0, p_ret_i numeric default 0, p_costos numeric default 0) returns bigint
language plpgsql as $$
declare o bigint; f bigint; c bigint;
begin
  o := public.zz_ot(p_neto);
  if p_costos > 0 then perform public.zz_gasto(o, p_costos); end if;
  perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 50),
                                                       jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'porcentaje', 'valor', 50)));
  f := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', p_neto, 'iva', p_iva)), 'factura', null, p_emisor);
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := p_importe,
        p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', p_neto * (1 + p_iva / 100))),
        p_receptor_asociado := p_receptor, p_cuenta_destino := case when p_receptor is not null then public.zz('cta_ana') end,
        p_ret_iva := p_ret_i, p_ret_otras := p_ret_o);
  perform public.distribuir_cobranza(c);
  return c;
end $$;

insert into public.permiso_puesto select p.id, 'distribucion', 2 from public.puesto p where p.nombre = 'Operador';

do $$
declare cli bigint; s1 bigint; ana bigint; rafa bigint; paz bigint; bruno bigint; o bigint;
begin
  select id into cli from public.cliente where nro_doc = '30755555556';
  select id into s1 from public.servicio where nombre = 'Higiene mensual';
  select id into ana from public.asociado where nro_doc = '27300000001';
  select id into rafa from public.asociado where nro_doc = '20300000002';
  select id into bruno from public.asociado where nro_doc = '20300000003';
  insert into public.asociado (apellido_nombre, nro_doc, condicion_iva, vinculo) values ('Paz, Pablo', '27300000009', 'Monotributo', 'monotributista_autonomo') returning id into paz;
  perform public.zzset('cli', cli); perform public.zzset('s1', s1); perform public.zzset('ana', ana); perform public.zzset('rafa', rafa); perform public.zzset('paz', paz); perform public.zzset('bruno', bruno);
  select id into o from public.cuenta_bancaria where cbu = '0170000000000000000003'; perform public.zzset('cta_ana', o);
end $$;

-- ===== 1) Reglas de distribución =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare o bigint; r1 bigint; r2 bigint; n int; v record;
  begin
  o := public.zz_ot(100000); perform public.zzset('o_regla', o);
  begin perform public.definir_regla_ot(o, '[]'::jsonb); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%al menos un participante%', sqlerrm; end;
  begin perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 90))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%deben sumar 100%', sqlerrm; end;
  begin perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'residual'), jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'residual'))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%solo puede haber un%' or sqlerrm like '%Solo puede haber un%', sqlerrm; end;
  begin perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'fijo', 'valor', 1000), jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'porcentaje', 'valor', 100))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%residual%', sqlerrm; end;
  begin perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 50), jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 50))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%más de una vez%', sqlerrm; end;
  begin perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('bruno'), 'tipo', 'porcentaje', 'valor', 100))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%baja%', sqlerrm; end;
  begin perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('rafa'), 'tipo', 'porcentaje', 'valor', 100))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%cómo participa%', sqlerrm; end;
  begin perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', -5))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%mayor a cero%', sqlerrm; end;

  r1 := public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 60),
                                                    jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'porcentaje', 'valor', 40)));
  assert (select como from public.regla_distribucion_parte where regla_id = r1 and asociado_id = public.zz('ana')) = 'socio'
     and (select como from public.regla_distribucion_parte where regla_id = r1 and asociado_id = public.zz('paz')) = 'profesional', '"como" se completa según el vínculo';
  begin perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'residual'))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%exige un motivo%', sqlerrm; end;
  r2 := public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('rafa'), 'tipo', 'porcentaje', 'valor', 30, 'como', 'profesional'),
                                                    jsonb_build_object('asociado_id', null, 'tipo', 'residual')), 'Acuerdo nuevo');
  select * into v from public.regla_distribucion_vigente where ot_id = o; assert v.version = 2 and v.regla_id = r2, 'la vigente es la última versión';
  update public.regla_distribucion_parte set valor = 1 where regla_id = r1; get diagnostics n = row_count; assert n = 0, 'las reglas no se modifican';
  delete from public.regla_distribucion where id = r1; get diagnostics n = row_count; assert n = 0, 'ni se borran';
  perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 100)), 'Vuelve a uno', 'costos_primero');
  assert (select modo_dist_parcial from public.ot where id = o) = 'costos_primero', 'el modo se define con la regla';
  raise notice 'OK reglas de distribución';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  begin perform public.definir_regla_ot(public.zz('o_regla'), jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 100)), 'x'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK definir reglas exige administración';
end $$; rollback;

-- ===== 2) Modo proporcional, cobros parciales =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare oa bigint; ob bigint; f bigint; c bigint; a0 numeric; p0 numeric; d record; n int; c2 bigint; begin
  a0 := public.sal(public.zz('ana')); p0 := public.sal(public.zz('paz'));
  oa := public.zz_ot(100000);
  perform public.zz_gasto(oa, 20000);
  f := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', oa, 'neto', 100000)));
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 121000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 121000)));
  assert exists (select 1 from public.cobranza_pendiente_distribuir where cobranza_id = c), 'la cobranza figura pendiente de distribuir';
  begin perform public.distribuir_cobranza(c); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%no tiene regla%', sqlerrm; end;
  n := public.distribuir_cobranza(c, jsonb_build_array(jsonb_build_object('ot_id', oa, 'partes', jsonb_build_array(
        jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 50),
        jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'porcentaje', 'valor', 50)))));
  assert n = 1, 'una distribución';
  select * into d from public.distribucion where cobranza_id = c;
  assert d.base = 100000 and d.costo_descontado = 20000 and d.resultado = 80000 and d.tipo = 'cobro' and not d.variante, 'base 100.000, costos 20.000, resultado 80.000';
  assert public.sal(public.zz('ana')) - a0 = 40000 and public.sal(public.zz('paz')) - p0 = 40000, 'cada uno recibe 40.000';
  assert not exists (select 1 from public.cobranza_pendiente_distribuir where cobranza_id = c), 'ya no está pendiente';
  assert (select count(*) from public.regla_distribucion where ot_id = oa) = 1, 'el primer cobro creó la v1';
  begin perform public.distribuir_cobranza(c); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%ya fue distribuida%', sqlerrm; end;
  assert (select codigo from public.distribucion where id = d.id) like 'DIS-%', 'código de distribución';

  -- cobros parciales: cada uno genera su instancia
  a0 := public.sal(public.zz('ana'));
  ob := public.zz_ot(100000);
  perform public.definir_regla_ot(ob, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 50), jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'porcentaje', 'valor', 50)));
  f := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', ob, 'neto', 100000, 'iva', 0)));
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 50000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 50000)));
  perform public.distribuir_cobranza(c);
  c2 := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 50000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 50000)));
  perform public.distribuir_cobranza(c2);
  assert (select count(*) from public.distribucion where ot_id = ob and tipo = 'cobro') = 2, 'dos cobros, dos instancias';
  assert public.sal(public.zz('ana')) - a0 = 50000, 'suma 50.000 de los dos cobros';
  raise notice 'OK modo proporcional y cobros parciales';
end $$;
commit;

-- ===== 3) Costos primero =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare o bigint; f bigint; c1 bigint; c2 bigint; a0 numeric; d record; begin
  a0 := public.sal(public.zz('ana'));
  o := public.zz_ot(100000, 'costos_primero');
  perform public.zz_gasto(o, 30000);
  perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 100)));
  f := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 100000, 'iva', 0)));
  c1 := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 50000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 50000)));
  perform public.distribuir_cobranza(c1);
  select * into d from public.distribucion where cobranza_id = c1; assert d.costo_descontado = 30000 and d.resultado = 20000, 'el primer cobro absorbe los costos';
  c2 := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 50000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 50000)));
  perform public.distribuir_cobranza(c2);
  select * into d from public.distribucion where cobranza_id = c2; assert d.costo_descontado = 0 and d.resultado = 50000, 'el segundo cobro ya no descuenta costos';
  assert public.sal(public.zz('ana')) - a0 = 70000, 'total repartido 70.000 = 100.000 − 30.000';
  raise notice 'OK costos primero';
end $$;
commit;

-- ===== 4) Importes fijos y residual =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare o bigint; f bigint; c bigint; a0 numeric; p0 numeric; d bigint; begin
  a0 := public.sal(public.zz('ana')); p0 := public.sal(public.zz('paz'));
  o := public.zz_ot(100000);
  perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'fijo', 'valor', 10000), jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'residual')));
  f := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 100000, 'iva', 0)));
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 50000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 50000)));
  perform public.distribuir_cobranza(c);
  assert public.sal(public.zz('ana')) - a0 = 5000 and public.sal(public.zz('paz')) - p0 = 45000, 'el fijo se prorratea por lo cobrado: 5.000 / 45.000';
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 50000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 50000)));
  perform public.distribuir_cobranza(c);
  assert public.sal(public.zz('ana')) - a0 = 10000 and public.sal(public.zz('paz')) - p0 = 90000, 'al terminar, el fijo suma 10.000 en total';
  -- porcentaje + fijo + Cooperativa como residual
  a0 := public.sal(public.zz('ana'));
  o := public.zz_ot(100000);
  perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 50),
        jsonb_build_object('asociado_id', public.zz('rafa'), 'tipo', 'fijo', 'valor', 4000, 'como', 'socio'), jsonb_build_object('asociado_id', null, 'tipo', 'residual')));
  f := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 100000, 'iva', 0)));
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 100000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 100000)));
  perform public.distribuir_cobranza(c);
  select id into d from public.distribucion where cobranza_id = c;
  assert (select monto from public.distribucion_parte where distribucion_id = d and asociado_id = public.zz('rafa')) = 4000
     and (select monto from public.distribucion_parte where distribucion_id = d and asociado_id is null) = 46000
     and public.sal(public.zz('ana')) - a0 = 50000, '50% + fijo 4.000 + la Cooperativa se queda con el resto (46.000)';
  assert (select sum(monto) from public.distribucion_parte where distribucion_id = d) = 100000, 'suma exacta';
  raise notice 'OK fijos y residual';
end $$;
commit;

-- ===== 5) Cambiar la regla en un cobro: solo este cobro o nueva versión =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare o bigint; f bigint; c bigint; a0 numeric; p0 numeric; v int; pr jsonb; r70 jsonb; r60 jsonb; i int; begin
  o := public.zz_ot(100000);
  f := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 100000, 'iva', 0)));
  pr  := jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 50), jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'porcentaje', 'valor', 50));
  r70 := jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 70), jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'porcentaje', 'valor', 30));
  r60 := jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 60), jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'porcentaje', 'valor', 40));
  a0 := public.sal(public.zz('ana'));
  -- cobro 1: regla inicial
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 20000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 20000)));
  perform public.distribuir_cobranza(c, jsonb_build_array(jsonb_build_object('ot_id', o, 'partes', pr)));
  assert public.sal(public.zz('ana')) - a0 = 10000, 'cobro 1: 50%';
  -- cobro 2: variante solo para este cobro
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 20000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 20000)));
  begin perform public.distribuir_cobranza(c, jsonb_build_array(jsonb_build_object('ot_id', o, 'partes', r70, 'alcance', 'solo_este_cobro'))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%exige un motivo%', sqlerrm; end;
  begin perform public.distribuir_cobranza(c, jsonb_build_array(jsonb_build_object('ot_id', o, 'partes', r70, 'motivo', 'Acuerdo'))); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%solo para este cobro%', sqlerrm; end;
  a0 := public.sal(public.zz('ana'));
  perform public.distribuir_cobranza(c, jsonb_build_array(jsonb_build_object('ot_id', o, 'partes', r70, 'alcance', 'solo_este_cobro', 'motivo', 'Acuerdo puntual')));
  assert public.sal(public.zz('ana')) - a0 = 14000 and (select variante from public.distribucion where cobranza_id = c), 'cobro 2: 70% solo esta vez';
  assert (select count(*) from public.regla_distribucion where ot_id = o) = 1, 'no se creó una versión nueva';
  -- cobro 3: vuelve a la v1
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 20000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 20000)));
  a0 := public.sal(public.zz('ana')); perform public.distribuir_cobranza(c);
  assert public.sal(public.zz('ana')) - a0 = 10000, 'cobro 3: vuelve a la v1';
  -- cobro 4: nueva versión
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 20000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 20000)));
  a0 := public.sal(public.zz('ana'));
  perform public.distribuir_cobranza(c, jsonb_build_array(jsonb_build_object('ot_id', o, 'partes', r60, 'alcance', 'nueva_version', 'motivo', 'Nuevo acuerdo')));
  assert public.sal(public.zz('ana')) - a0 = 12000 and (select count(*) from public.regla_distribucion where ot_id = o) = 2, 'cobro 4: nueva versión 60%';
  -- cobro 5: usa la v2
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 20000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 20000)));
  a0 := public.sal(public.zz('ana')); perform public.distribuir_cobranza(c);
  assert public.sal(public.zz('ana')) - a0 = 12000, 'cobro 5: sigue con la v2';
  raise notice 'OK regla por cobro o como nueva versión';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare o bigint; f bigint; c bigint; begin
  o := public.zz_ot(100000);
  perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 100)));
  f := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 100000, 'iva', 0)));
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 10000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 10000)));
  perform public.zzset('o_op', o); perform public.zzset('c_op', c);
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  begin perform public.distribuir_cobranza(public.zz('c_op'), jsonb_build_array(jsonb_build_object('ot_id', public.zz('o_op'), 'partes', jsonb_build_array(jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'porcentaje', 'valor', 100)), 'alcance', 'solo_este_cobro', 'motivo', 'x'))); raise exception 'NO DEBIÓ';
  exception when insufficient_privilege then null; end;
  perform public.distribuir_cobranza(public.zz('c_op'));                            -- con la regla vigente, el operador sí distribuye
  assert exists (select 1 from public.distribucion where cobranza_id = public.zz('c_op')), 'el operador distribuye con la regla vigente';
  raise notice 'OK cambiar la regla exige administración; distribuir con la vigente no';
end $$;
commit;

-- ===== 6) Efectivo retenido, retenciones, IVA =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare a0 numeric; p0 numeric; c bigint; mv numeric; begin
  -- a) el emisor es ana y también cobró: absorbe la retención y rinde el efectivo
  a0 := public.sal(public.zz('ana')); p0 := public.sal(public.zz('paz'));
  c := public.zz_esc(public.zz('ana'), public.zz('ana'), 100000, 0, 90000, 10000, 0, 20000);
  assert public.sal(public.zz('ana')) - a0 = -60000 and public.sal(public.zz('paz')) - p0 = 40000, 'a) ana: +40.000 −90.000 −10.000 = −60.000; paz +40.000';
  select coalesce(sum(importe), 0) into mv from public.movimiento_cc_asociado where origen_tipo = 'cobranza' and origen_id = c and asociado_id = public.zz('ana');
  assert mv = -100000, 'a) movimientos de la cobranza: −90.000 de efectivo y −10.000 de retención';
  -- b) emite la Cooperativa con IVA y cobra ana: debe rendir todo el efectivo (incluye el IVA)
  a0 := public.sal(public.zz('ana')); p0 := public.sal(public.zz('paz'));
  perform public.zz_esc(null, public.zz('ana'), 100000, 21, 121000);
  assert public.sal(public.zz('ana')) - a0 = -71000 and public.sal(public.zz('paz')) - p0 = 50000, 'b) emite la Cooperativa: ana −71.000 (50.000 − 121.000)';
  -- c) emite paz con IVA y cobra ana: ana rinde todo y le debe el IVA a paz
  a0 := public.sal(public.zz('ana')); p0 := public.sal(public.zz('paz'));
  perform public.zz_esc(public.zz('paz'), public.zz('ana'), 100000, 21, 121000);
  assert public.sal(public.zz('ana')) - a0 = -71000 and public.sal(public.zz('paz')) - p0 = 71000, 'c) emite paz: paz recibe además los 21.000 de IVA';
  -- d) emite y cobra ana con IVA: se queda con el IVA, que es suyo
  a0 := public.sal(public.zz('ana')); p0 := public.sal(public.zz('paz'));
  perform public.zz_esc(public.zz('ana'), public.zz('ana'), 100000, 21, 121000);
  assert public.sal(public.zz('ana')) - a0 = -50000 and public.sal(public.zz('paz')) - p0 = 50000, 'd) emisor y receptor: no rinde el IVA';
  -- e) sobrante cobrado por un asociado
  a0 := public.sal(public.zz('ana'));
  perform public.zz_esc(null, public.zz('ana'), 100000, 0, 120000);
  assert public.sal(public.zz('ana')) - a0 = -70000, 'e) rinde también el sobrante (20.000): +50.000 −120.000';
  -- f) retención de IVA: no se rinde lo que el cliente retuvo
  a0 := public.sal(public.zz('ana'));
  perform public.zz_esc(null, public.zz('ana'), 100000, 21, 111000, 0, 10000);
  assert public.sal(public.zz('ana')) - a0 = -61000, 'f) con retención de IVA: +50.000 −111.000';
  raise notice 'OK efectivo retenido y retenciones';
end $$;
commit;

-- ===== 7) Costos posteriores a la distribución: ajuste automático =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare c bigint; o bigint; a0 numeric; p0 numeric; g bigint; n int; r record; begin
  o := public.zz_ot(100000);
  a0 := public.sal(public.zz('ana')); p0 := public.sal(public.zz('paz'));
  perform public.zz_gasto(o, 500);      -- antes de repartir: no hay nada que ajustar
  assert not exists (select 1 from public.distribucion where ot_id = o), 'sin distribuciones no hay ajuste';
  -- (el costo inicial de 500 ya existe al distribuir)
  perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 50), jsonb_build_object('asociado_id', public.zz('paz'), 'tipo', 'porcentaje', 'valor', 50)));
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 100000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 100000, 'iva', 0))), 'importe', 100000)));
  perform public.distribuir_cobranza(c);
  select * into r from public.distribucion where cobranza_id = c; assert r.resultado = 99500, 'resultado 99.500';
  a0 := public.sal(public.zz('ana')); p0 := public.sal(public.zz('paz'));
  g := public.zz_gasto(o, 10000);
  select * into r from public.distribucion where ot_id = o and tipo = 'ajuste_costos' and not anulada;
  assert r.resultado = -10000 and r.base = 0 and r.costo_descontado = 10000, 'un gasto posterior genera un ajuste −10.000';
  assert public.sal(public.zz('ana')) - a0 = -5000 and public.sal(public.zz('paz')) - p0 = -5000, 'las cuentas se actualizan solas (−5.000 / −5.000)';
  perform public.zz_gasto(o, 4000, false);
  select count(*) into n from public.distribucion where ot_id = o and tipo = 'ajuste_costos'; assert n = 1, 'un gasto que no afecta margen no ajusta nada';
  perform public.anular_gasto(g, 'Se cargó por error');
  assert public.sal(public.zz('ana')) = a0 and public.sal(public.zz('paz')) = p0, 'al revertir el gasto vuelven los saldos';
  assert (select distribuido from public.ot_resumen_financiero where ot_id = o) = 99500, 'distribuido 99.500';
  -- costos primero: el costo posterior no se descuenta dos veces
  o := public.zz_ot(100000, 'costos_primero');
  perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 100)));
  a0 := public.sal(public.zz('ana'));
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 50000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 100000, 'iva', 0))), 'importe', 50000)));
  perform public.distribuir_cobranza(c);
  perform public.zz_gasto(o, 30000);
  assert (select resultado from public.distribucion where ot_id = o and tipo = 'ajuste_costos') = -30000, 'ajuste −30.000';
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 50000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', (select factura_id from public.cobranza_aplicacion where cobranza_id = c), 'importe', 50000)));
  perform public.distribuir_cobranza(c);
  assert public.sal(public.zz('ana')) - a0 = 70000, 'total 70.000 = 100.000 − 30.000: sin doble descuento';
  raise notice 'OK ajuste automático por costos posteriores';
end $$;
commit;

-- ===== 8) Revertir una cobranza distribuida =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare c bigint; o bigint; a0 numeric; p0 numeric; n int; begin
  a0 := public.sal(public.zz('ana')); p0 := public.sal(public.zz('paz'));
  c := public.zz_esc(null, public.zz('ana'), 100000, 0, 100000, 0, 0, 20000);
  select ot_id into o from public.cobranza_ot where cobranza_id = c limit 1;
  perform public.zz_gasto(o, 10000);                                              -- ajuste posterior: −10.000
  assert public.sal(public.zz('ana')) - a0 <> 0, 'hay movimientos';
  perform public.revertir_cobranza(c, 'Cobranza cargada dos veces');
  assert public.sal(public.zz('ana')) = a0 and public.sal(public.zz('paz')) = p0, 'al revertir, ambas cuentas vuelven a su saldo';
  select count(*) into n from public.distribucion where cobranza_id = c and not anulada; assert n = 0, 'distribución anulada';
  assert (select distribuido from public.ot_resumen_financiero where ot_id = o) = 0, 'la OT queda sin distribuido';
  assert (select cobrado_neto from public.ot_cobranza where ot_id = o) = 0, 'y sin cobrado';
  -- se vuelve a cobrar: ahora el costo es 30.000
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 100000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', (select factura_id from public.cobranza_aplicacion where cobranza_id = c limit 1), 'importe', 100000)));
  perform public.distribuir_cobranza(c);
  assert (select resultado from public.distribucion where cobranza_id = c and not anulada) = 70000, 'al volver a cobrar se reparten 70.000';
  assert (select distribuido from public.ot_resumen_financiero where ot_id = o) = 70000, 'y el total distribuido de la OT es 70.000';
  raise notice 'OK revertir cobranza con distribución';
end $$;
commit;

-- ===== 9) Nota de crédito: se revierte proporcionalmente la distribución =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare c bigint; f bigint; o bigint; a0 numeric; p0 numeric; r record; begin
  a0 := public.sal(public.zz('ana')); p0 := public.sal(public.zz('paz'));
  c := public.zz_esc(null, null, 100000, 0, 100000, 0, 0, 20000);
  select factura_id into f from public.cobranza_aplicacion where cobranza_id = c;
  select ot_id into o from public.cobranza_ot where cobranza_id = c limit 1;
  assert public.sal(public.zz('ana')) - a0 = 40000, 'distribuido 80.000';
  perform public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 30000, 'iva', 0)), 'nc', f);
  perform public.resolver_credito_factura(f, 30000, 'saldo_favor');
  select * into r from public.distribucion where ot_id = o and tipo = 'ajuste_nc';
  assert r.base = -30000 and r.resultado = -24000, 'ajuste por NC: base −30.000, resultado −24.000 (con los costos proporcionales)';
  assert public.sal(public.zz('ana')) - a0 = 28000 and public.sal(public.zz('paz')) - p0 = 28000, 'cada asociado devuelve 12.000';
  -- costos primero
  a0 := public.sal(public.zz('ana'));
  o := public.zz_ot(100000, 'costos_primero');
  perform public.zz_gasto(o, 30000);
  perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 100)));
  f := public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 100000, 'iva', 0)));
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 100000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', f, 'importe', 100000)));
  perform public.distribuir_cobranza(c);
  perform public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o, 'neto', 30000, 'iva', 0)), 'nc', f);
  perform public.resolver_credito_factura(f, 30000, 'devolucion', public.hoy_ar(), null, null, (select id from public.cuenta_bancaria where nro_cuenta = '439-0251987'), (select id from public.cuenta_bancaria where cbu = '0170000000000000000010'));
  select * into r from public.distribucion where ot_id = o and tipo = 'ajuste_nc';
  assert r.base = -30000 and r.resultado = -30000 and r.costo_descontado = 0, 'costos primero: devuelve los 30.000 netos (los costos ya estaban cubiertos)';
  assert public.sal(public.zz('ana')) - a0 = 40000, 'queda 100.000 − 30.000 de costos − 30.000 devueltos = 40.000';
  raise notice 'OK nota de crédito y reparto';
end $$;
commit;

-- ===== 10) Regalía =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare o bigint; c bigint; a0 numeric; d bigint; ot2 bigint; begin
  o := public.zz_ot(50000, 'proporcional', 'regalia');
  begin perform public.facturar_cobrar_regalia(o); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%regla de distribución%', sqlerrm; end;
  perform public.definir_regla_ot(o, jsonb_build_array(jsonb_build_object('asociado_id', null, 'tipo', 'porcentaje', 'valor', 30), jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 70)));
  a0 := public.sal(public.zz('ana'));
  c := public.facturar_cobrar_regalia(o);
  assert public.sal(public.zz('ana')) - a0 = 35000, 'ana recibe el 70% de 50.000';
  select id into d from public.distribucion where cobranza_id = c; assert (select monto from public.distribucion_parte where distribucion_id = d and asociado_id is null) = 15000, 'la Cooperativa el 30%';
  assert (select modo from public.factura f join public.factura_linea l on l.factura_id = f.id where l.ot_id = o) = 'interna', 'factura interna';
  assert (select estado_facturacion from public.ot_facturacion where ot_id = o) = 'completa' and (select cobrado_neto from public.ot_cobranza where ot_id = o) = 50000, 'OT facturada y cobrada';
  begin perform public.facturar_cobrar_regalia(o); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%ya tiene facturación%', sqlerrm; end;
  ot2 := public.zz_ot(1000);
  begin perform public.facturar_cobrar_regalia(ot2); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%no es una regalía%', sqlerrm; end;
  raise notice 'OK regalía';
end $$;
commit;

-- ===== 11) Distribución automática (configurable) =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare o1 bigint; o2 bigint; c bigint; begin
  update public.organizacion set distribuir_al_cobrar = true;
  o1 := public.zz_ot(10000);
  perform public.definir_regla_ot(o1, jsonb_build_array(jsonb_build_object('asociado_id', public.zz('ana'), 'tipo', 'porcentaje', 'valor', 100)));
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 10000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o1, 'neto', 10000, 'iva', 0))), 'importe', 10000)));
  assert exists (select 1 from public.distribucion where cobranza_id = c), 'con la opción activa, distribuye sola con la regla vigente';
  o2 := public.zz_ot(10000);
  c := public.registrar_cobranza(p_cliente := public.zz('cli'), p_importe := 10000, p_aplicaciones := jsonb_build_array(jsonb_build_object('factura_id', public.zz_emitir(public.zz('cli'), jsonb_build_array(jsonb_build_object('ot', o2, 'neto', 10000, 'iva', 0))), 'importe', 10000)));
  assert not exists (select 1 from public.distribucion where cobranza_id = c) and exists (select 1 from public.cobranza_pendiente_distribuir where cobranza_id = c), 'sin regla queda pendiente, sin error';
  update public.organizacion set distribuir_al_cobrar = false;
  raise notice 'OK distribución automática configurable';
end $$;
commit;

-- ===== 12) Anticipo: el monto es neto y no supera el de la OT =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare e bigint; begin
  select id into e from public.establecimiento where cliente_id = public.zz('cli') and principal;
  begin insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto, requiere_anticipo, anticipo_monto)
        values ('directa', 'x', public.zz('cli'), e, public.zz('s1'), public.zz('ana'), public.hoy_ar(), 100, true, 200); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto, requiere_anticipo, anticipo_monto)
        values ('directa', 'x', public.zz('cli'), e, public.zz('s1'), public.zz('ana'), public.hoy_ar(), 100, false, 50); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto, requiere_anticipo, anticipo_monto)
  values ('directa', 'x', public.zz('cli'), e, public.zz('s1'), public.zz('ana'), public.hoy_ar(), 100, true, 40);
  assert (select l.neto from public.factura_linea l join public.factura f on f.id = l.factura_id where f.origen_borrador = 'anticipo' and l.neto = 40 limit 1) = 40, 'el borrador sale por el monto indicado';
  raise notice 'OK anticipo con monto indicado';
end $$;
commit;

-- ===== 13) Permisos =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare n int; begin
  begin insert into public.distribucion (ot_id, tipo, base, resultado) values (public.zz('o_regla'), 'cobro', 1, 1); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  update public.distribucion set resultado = 0; get diagnostics n = row_count; assert n = 0, 'las distribuciones no se editan';
  delete from public.distribucion; get diagnostics n = row_count; assert n = 0, 'ni se borran';
  raise notice 'OK nada se toca directo';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ declare n int; begin
  select count(*) into n from public.distribucion; assert n = 0, 'el lector (sin Distribución) no ve nada';
  select count(*) into n from public.regla_distribucion; assert n = 0, 'ni reglas';
  begin perform public.distribuir_cobranza(1); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK sin permiso no se ve ni se opera';
end $$; rollback;
begin; set local role anon;
do $$ begin
  begin perform public.distribuir_cobranza(1); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform public.facturar_cobrar_regalia(1); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK un visitante anónimo no ejecuta funciones';
end $$; rollback;

-- ===== 14) Consistencia global =====
do $$ declare n int; begin
  -- toda distribución reparte exactamente su resultado
  select count(*) into n from public.distribucion d where not d.anulada and abs(d.resultado - (select coalesce(sum(monto), 0) from public.distribucion_parte p where p.distribucion_id = d.id)) > 0.005;
  assert n = 0, 'todas las distribuciones reparten exactamente su resultado (' || n || ' con diferencia)';
  select count(*) into n from public.log_auditoria where tabla = 'distribucion' and operacion = 'alta'; assert n > 10, 'distribuciones auditadas';
  raise notice 'OK consistencia';
end $$;

drop function public.zz_esc(bigint, bigint, numeric, numeric, numeric, numeric, numeric, numeric); drop function public.zz_gasto(bigint, numeric, boolean);
drop function public.zz_emitir(bigint, jsonb, text, bigint, bigint); drop function public.zz_ot(numeric, text, text, bigint);
drop function public.sal(bigint); drop function public.zzset(text, bigint); drop function public.zz(text); drop table public.zz_ctx;
\echo 'DISTRIBUCIÓN: todas las pruebas pasaron'
