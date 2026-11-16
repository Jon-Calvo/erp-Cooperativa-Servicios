\set ON_ERROR_STOP on
\set U1 '''00000000-0000-0000-0000-000000000001'''
\set U2 '''00000000-0000-0000-0000-000000000002'''
\set U3 '''00000000-0000-0000-0000-000000000003'''
\set U4 '''00000000-0000-0000-0000-000000000004'''
\set U5 '''00000000-0000-0000-0000-000000000005'''

-- ===== Preparación =====
create table public.zz_ctx (k text primary key, v bigint);
create function public.zz(p text) returns bigint language sql stable as $$ select v from public.zz_ctx where k = p $$;
create function public.zzset(p text, n bigint) returns void language sql as $$
  insert into public.zz_ctx values (p, n) on conflict (k) do update set v = excluded.v $$;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000005', 'sinperfil@coop.test') on conflict do nothing;

do $$
declare cli bigint; s1 bigint; ana bigint; e bigint; o bigint; sm bigint; f bigint; tipo bigint;
begin
  select id into cli from public.cliente where nro_doc = '30755555556';
  select id into s1 from public.servicio where nombre = 'Higiene mensual';
  select id into ana from public.asociado where nro_doc = '27300000001';
  select id into e from public.establecimiento where cliente_id = cli and principal;
  select id into tipo from public.lista_valor where lista = 'tipo_comprobante' and nombre = 'Factura A';
  -- escenario aislado en mayo de 2031
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
  values ('directa', 'prueba detalle', cli, e, s1, ana, date '2031-05-05', 500000) returning id into o;
  perform public.cambiar_estado_ot(o, 'en_ejecucion'); perform public.cambiar_estado_ot(o, 'finalizada');
  insert into public.factura (cliente_id, fecha) values (cli, date '2031-05-10') returning id into f;
  insert into public.factura_linea (factura_id, ot_id, neto, iva_pct) values (f, o, 200000, 0);
  perform public.emitir_factura(f, '1', '99001', 'CAE99001', null, tipo);
  insert into public.sm (cliente_id, establecimiento_id, servicio_id, dia_generacion, dia_inicio, fecha_inicio, responsable_id)
  values (cli, e, s1, 1, 5, date '2031-04-01', ana) returning id into sm;
  insert into public.sm_precio (sm_id, vigente_desde, precio) values (sm, date '2031-04-01', 30000);
  perform public.generar_ot_sm(sm, date '2031-05-10');
  perform public.zzset('o', o); perform public.zzset('f', f);
end $$;

-- ===== 1) Umbrales configurables =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare n int; r record; begin
  select count(*) into n from public.kpi_umbral; assert n = 9, 'nueve indicadores con umbral: ' || n;
  select * into r from public.kpi_umbral where clave = 'facturacion_mes'; assert r.ok = 80 and r.aviso = 50 and r.sentido = 'alto_bueno', 'valores iniciales';
  begin update public.kpi_umbral set ok = 40 where clave = 'facturacion_mes'; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;       -- en "alto bueno" el verde exige más que el amarillo
  begin update public.kpi_umbral set ok = 30 where clave = 'cartera_vencida'; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;       -- en "alto malo" el verde exige menos que el amarillo
  begin update public.kpi_umbral set aviso = -1 where clave = 'cartera_vencida'; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin insert into public.kpi_umbral (clave, nombre, sentido, ok, aviso) values ('inventado', 'x', 'alto_bueno', 2, 1); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  delete from public.kpi_umbral; get diagnostics n = row_count; assert n = 0, 'los umbrales no se borran';

  update public.kpi_umbral set ok = 0, aviso = 0 where clave = 'facturacion_mes';
  assert (select tono from public.kpi_panel(date '2031-05-15') where clave = 'facturacion_mes') = 'ok', 'con umbral 0 todo porcentaje es verde';
  update public.kpi_umbral set ok = 101, aviso = 100.5 where clave = 'facturacion_mes';
  assert (select tono from public.kpi_panel(date '2031-05-15') where clave = 'facturacion_mes') = 'bad', 'con umbral inalcanzable es rojo';
  update public.kpi_umbral set ok = 80, aviso = 50 where clave = 'facturacion_mes';

  update public.kpi_umbral set ok = 100, aviso = 100 where clave = 'cartera_vencida';
  assert (select tono from public.kpi_panel() where clave = 'cartera_vencida') = 'ok', 'cartera vencida con umbral 100% es verde';
  update public.kpi_umbral set ok = 10, aviso = 25 where clave = 'cartera_vencida';

  update public.kpi_umbral set ok = 100000, aviso = 200000 where clave = 'distribucion_pendiente';
  assert (select tono from public.kpi_panel() where clave = 'distribucion_pendiente') = 'ok', 'los umbrales por cantidad también se aplican';
  update public.kpi_umbral set ok = 0, aviso = 2 where clave = 'distribucion_pendiente';
  assert (select count(*) from public.log_auditoria where tabla = 'kpi_umbral' and campo = 'ok') >= 3, 'los cambios de umbral quedan auditados';
  raise notice 'OK umbrales configurables';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare n int; begin
  select count(*) into n from public.kpi_umbral; assert n = 9, 'cualquier usuario activo lee los umbrales';
  update public.kpi_umbral set ok = 99 where clave = 'cobranza_mes'; get diagnostics n = row_count; assert n = 0, 'solo la administración los cambia';
  raise notice 'OK permisos de umbrales';
end $$; rollback;

-- ===== 2) Detalle desglosado =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare r record; p record; g2 numeric; n2 int; v numeric; k text; n int; t numeric; items numeric; begin
  -- facturación del mes (mayo de 2031)
  select * into p from public.kpi_panel(date '2031-05-15') where clave = 'facturacion_mes';
  select * into r from public.kpi_detalle('facturacion_mes', date '2031-05-15') where nivel = 1 and grupo = 'Facturado del mes';
  assert r.importe = 200000 and r.cantidad = 1 and r.importe = p.valor, 'facturado del mes: 200.000';
  assert (select count(*) from public.kpi_detalle('facturacion_mes', date '2031-05-15') where nivel = 2 and grupo = 'Facturado del mes' and importe = 200000 and entidad = 'factura' and entidad_id = public.zz('f')) = 1, 'la factura figura en el detalle';
  select * into r from public.kpi_detalle('facturacion_mes', date '2031-05-15') where nivel = 1 and grupo = 'Servicios mensuales del período pendientes de facturar';
  assert r.importe = 30000 and r.cantidad = 1, 'el servicio mensual del período: 30.000 pendientes';
  select coalesce(sum(greatest(o.neto - x.facturado_neto, 0)), 0), count(*) filter (where o.neto - x.facturado_neto > 0) into g2, n2 from public.ot o join public.ot_facturacion x on x.ot_id = o.id where o.estado in ('finalizada','cerrada');
  select * into r from public.kpi_detalle('facturacion_mes', date '2031-05-15') where nivel = 1 and grupo = 'OT finalizadas o cerradas pendientes de facturar';
  assert r.importe = g2 and r.cantidad = n2 and r.importe >= 300000, 'OT finalizadas pendientes: ' || r.importe;
  assert exists (select 1 from public.kpi_detalle('facturacion_mes', date '2031-05-15') where nivel = 2 and entidad = 'ot' and entidad_id = public.zz('o') and importe = 300000), 'la OT de 500.000 con 200.000 facturados aparece con 300.000 pendientes';
  select sum(importe), sum(pct) into t, v from public.kpi_detalle('facturacion_mes', date '2031-05-15') where nivel = 1;
  assert t = p.referencia and abs(v - 100) <= 0.3, 'los grupos suman la referencia y el 100%: ' || t || ' ' || v;
  if n2 <= 50 then
    select sum(importe) into items from public.kpi_detalle('facturacion_mes', date '2031-05-15') where nivel = 2 and grupo = 'OT finalizadas o cerradas pendientes de facturar';
    assert items = g2, 'las filas suman el grupo';
  end if;

  -- coherencia general de todos los indicadores
  foreach k in array array['facturacion_mes','cobranza_mes','cartera_vencida','margen_ot','avance_ot','distribucion_pendiente','monotributo_riesgo','presupuestos_aprobacion','presupuestos_seguimiento','por_pagar_vencido','cc_asociados'] loop
    select count(*) into n from public.kpi_detalle(k, date '2031-05-15'); assert n > 0, k || ': sin filas';
    assert (select count(*) = count(distinct orden) from public.kpi_detalle(k, date '2031-05-15')), k || ': orden repetido';
    assert not exists (select 1 from public.kpi_detalle(k, date '2031-05-15') where nivel not in (1, 2)), k || ': nivel inválido';
    assert not exists (select 1 from public.kpi_detalle(k, date '2031-05-15') d where d.nivel = 2 and not exists (select 1 from public.kpi_detalle(k, date '2031-05-15') g where g.nivel = 1 and g.grupo = d.grupo)), k || ': fila sin grupo';
  end loop;

  -- cartera vencida: los tramos suman el total por cobrar
  select coalesce(sum(saldo), 0) into t from public.facturas_por_cobrar;
  select coalesce(sum(importe), 0), coalesce(sum(pct), 0) into v, items from public.kpi_detalle('cartera_vencida') where nivel = 1;
  assert v = t and (t = 0 or abs(items - 100) <= 0.5), 'cartera: los tramos suman el total por cobrar';

  -- avance de OT de mayo de 2031
  select * into r from public.kpi_detalle('avance_ot', date '2031-05-15') where nivel = 1 and grupo = 'Finalizadas o cerradas'; assert r.cantidad = 1 and r.pct = 50.0, 'una OT finalizada de dos';
  select * into r from public.kpi_detalle('avance_ot', date '2031-05-15') where nivel = 1 and grupo = 'Pendientes de iniciar'; assert r.cantidad = 1 and r.pct = 50.0, 'una OT pendiente de dos';
  select * into r from public.kpi_detalle('avance_ot', date '2031-05-15') where nivel = 1 and grupo = 'En ejecución'; assert r.cantidad = 0, 'ninguna en ejecución';

  -- monotributo, presupuestos, pagos y cuentas
  select count(*) into n from public.monotributo_estado();
  select coalesce(sum(cantidad), 0) into t from public.kpi_detalle('monotributo_riesgo') where nivel = 1; assert t = n, 'monotributo: los semáforos suman los asociados';
  select * into p from public.kpi_panel() where clave = 'presupuestos_aprobacion';
  select coalesce(sum(importe), 0) into t from public.kpi_detalle('presupuestos_aprobacion') where nivel = 1; assert t = p.referencia, 'presupuestos: aprobado + rechazado = decidido';
  select importe into t from public.kpi_detalle('presupuestos_aprobacion') where nivel = 1 and grupo = 'Aprobado'; assert t = p.valor, 'aprobado coincide con el panel';
  select * into p from public.kpi_panel() where clave = 'presupuestos_seguimiento';
  select coalesce(sum(cantidad), 0) into t from public.kpi_detalle('presupuestos_seguimiento') where nivel = 1; assert t = p.referencia, 'seguimientos: vencidos + al día = enviados';
  select * into p from public.kpi_panel() where clave = 'por_pagar_vencido';
  select coalesce(sum(importe), 0) into t from public.kpi_detalle('por_pagar_vencido') where nivel = 1; assert t = p.referencia, 'por pagar: los tramos suman el total';
  select * into p from public.kpi_panel() where clave = 'cc_asociados';
  select importe into t from public.kpi_detalle('cc_asociados') where nivel = 1 and grupo = 'A favor de los asociados'; assert t = p.valor, 'cuentas: a favor de asociados coincide';
  select importe into t from public.kpi_detalle('cc_asociados') where nivel = 1 and grupo = 'Deuda de asociados'; assert t = p.referencia, 'cuentas: deuda coincide';
  select * into p from public.kpi_panel(date '2031-05-15') where clave = 'distribucion_pendiente';
  select coalesce(sum(cantidad), 0) into t from public.kpi_detalle('distribucion_pendiente', date '2031-05-15') where nivel = 1 and grupo in ('Pendientes del mes', 'Pendientes de meses anteriores'); assert t = p.valor, 'distribución: los pendientes suman';

  begin perform * from public.kpi_detalle('inventado'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%No existe el indicador%', sqlerrm; end;
  raise notice 'OK detalle desglosado';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ declare k text; begin
  foreach k in array array['facturacion_mes','cobranza_mes','cartera_vencida','margen_ot','avance_ot','distribucion_pendiente','monotributo_riesgo','presupuestos_aprobacion','presupuestos_seguimiento','por_pagar_vencido','cc_asociados'] loop
    assert (select count(*) from public.kpi_detalle(k)) = 0, k || ': el lector no ve detalle';
  end loop;
  raise notice 'OK sin permisos no hay detalle';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  assert (select count(*) from public.kpi_detalle('facturacion_mes', date '2031-05-15')) > 0, 'el operador ve el detalle de facturación';
  assert (select count(*) from public.kpi_detalle('monotributo_riesgo')) = 0, 'pero no el de monotributo';
  raise notice 'OK el detalle respeta los permisos de cada módulo';
end $$; rollback;
begin; set local role anon;
do $$ begin
  begin perform * from public.kpi_detalle('margen_ot'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform * from public.mis_permisos(); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform * from public.mi_perfil(); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK un visitante anónimo no accede';
end $$; rollback;

-- ===== 3) Perfil y permisos del usuario =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare r record; begin
  assert (select count(*) from public.mis_permisos()) = (select count(*) from public.modulo), 'un permiso por módulo';
  assert not exists (select 1 from public.mis_permisos() where nivel <> 3), 'el Director administra todo';
  select * into r from public.mi_perfil();
  assert r.activo and 'Director' = any (r.puestos) and r.tema_color = 'azul' and r.modo_tema is not null and r.nombre is not null, 'perfil del administrador: ' || r.nombre;
  raise notice 'OK perfil del administrador';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  assert (select nivel from public.mis_permisos() where modulo = 'facturacion') = 2, 'operar en facturación';
  assert (select nivel from public.mis_permisos() where modulo = 'monotributo') = 0, 'sin monotributo';
  assert (select nivel from public.mis_permisos() where modulo = 'seguridad') = 0, 'sin seguridad';
  raise notice 'OK permisos del operador';
end $$; rollback;
insert into public.permiso_usuario values ('00000000-0000-0000-0000-000000000003', 'monotributo', 1);
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  assert (select nivel from public.mis_permisos() where modulo = 'monotributo') = 1, 'la excepción por usuario se refleja';
  raise notice 'OK excepciones por usuario';
end $$; rollback;
delete from public.permiso_usuario where usuario_id = '00000000-0000-0000-0000-000000000003' and modulo = 'monotributo';
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U4, true) as _ \gset
do $$ begin
  assert not exists (select 1 from public.mis_permisos() where nivel > 0), 'un usuario inactivo no tiene permisos';
  assert (select not activo from public.mi_perfil()), 'su perfil indica que está inactivo';
  raise notice 'OK usuario inactivo';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U5, true) as _ \gset
do $$ begin
  assert (select count(*) from public.mi_perfil()) = 0, 'sin perfil: no devuelve datos (el frontend lo avisa)';
  assert not exists (select 1 from public.mis_permisos() where nivel > 0), 'y sin permisos';
  raise notice 'OK usuario sin perfil';
end $$; rollback;

drop function public.zzset(text, bigint); drop function public.zz(text); drop table public.zz_ctx;
\echo 'KPIS CONFIGURABLES, DETALLE Y PERFIL: todas las pruebas pasaron'
