\set ON_ERROR_STOP on
\set U1 '''00000000-0000-0000-0000-000000000001'''
\set U2 '''00000000-0000-0000-0000-000000000002'''
\set U3 '''00000000-0000-0000-0000-000000000003'''

-- ===== Preparación (como administrador de la base) =====
create table public.zz_ctx (k text primary key, v bigint);
create function public.zz(p text) returns bigint language sql stable as $$ select v from public.zz_ctx where k = p $$;
create function public.zzset(p text, n bigint) returns void language sql as $$
  insert into public.zz_ctx values (p, n) on conflict (k) do update set v = excluded.v $$;

-- el puesto Operador también opera Comercial y Operaciones
insert into public.permiso_puesto select p.id, m, 2 from public.puesto p, (values ('comercial'),('operaciones')) x(m) where p.nombre = 'Operador';

do $$
declare cli bigint; cli2 bigint; est bigint; est2 bigint; s1 bigint; s2 bigint; ana bigint; rafa bigint; bruno bigint; um bigint;
begin
  insert into public.cliente (razon_social, nro_doc, condicion_iva) values ('Cliente Comercial SA', '30755555556', 'Resp. Inscripto') returning id into cli;
  insert into public.cliente (razon_social, nro_doc, condicion_iva) values ('Otro Cliente SA', '30766666667', 'Exento') returning id into cli2;
  select id into est from public.establecimiento where cliente_id = cli and principal;
  select id into est2 from public.establecimiento where cliente_id = cli2 and principal;
  select id into um from public.lista_valor where lista = 'unidad_medida' and nombre = 'Mes';
  insert into public.servicio (nombre, descripcion, unidad_id) values ('Higiene mensual', 'Servicio mensual de higiene', um) returning id into s1;
  insert into public.servicio (nombre) values ('Capacitación') returning id into s2;
  insert into public.servicio_precio (servicio_id, vigente_desde, precio_ars) values (s1, public.hoy_ar() - 30, 100000), (s2, public.hoy_ar() - 30, 50000);
  insert into public.asociado (apellido_nombre, nro_doc, condicion_iva, vinculo) values ('Activa, Ana', '27300000001', 'Monotributo', 'socio_cooperativo') returning id into ana;
  insert into public.asociado (apellido_nombre, nro_doc, condicion_iva, vinculo) values ('RI, Rafa', '20300000002', 'Resp. Inscripto', 'ambos') returning id into rafa;
  insert into public.asociado (apellido_nombre, nro_doc, condicion_iva, vinculo, estado, fecha_baja) values ('Baja, Bruno', '20300000003', 'Exento', 'ambos', 'baja', public.hoy_ar()) returning id into bruno;
  perform public.zzset('cli', cli); perform public.zzset('cli2', cli2); perform public.zzset('est', est); perform public.zzset('est2', est2);
  perform public.zzset('s1', s1); perform public.zzset('s2', s2); perform public.zzset('ana', ana); perform public.zzset('rafa', rafa); perform public.zzset('bruno', bruno);
end $$;

-- ===== 1) IVA sugerido según el emisor =====
do $$ begin
  assert public.iva_sugerido_emisor('cooperativa') = 21, 'Cooperativa RI → 21';
  assert public.iva_sugerido_emisor('asociado', public.zz('ana')) = 0, 'Monotributo → 0';
  assert public.iva_sugerido_emisor('asociado', public.zz('rafa')) = 21, 'RI → 21';
  raise notice 'OK IVA sugerido por emisor';
end $$;

-- ===== 2) Presupuesto en borrador y sus líneas =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare p public.presupuesto; l public.presupuesto_linea; y text := extract(year from public.hoy_ar())::text; begin
  insert into public.presupuesto (cliente_id, establecimiento_id, emisor_tipo, emisor_asociado_id, iva_general, estado, version, codigo)
  values (public.zz('cli'), public.zz('est'), 'asociado', public.zz('ana'), 21, 'enviado', 7, 'PRE-FALSO') returning * into p;
  assert p.codigo = 'PRE-' || y || '-00001' and p.version = 1 and p.estado = 'borrador', 'un alta directa siempre es v1 borrador con código propio: ' || p.codigo || ' ' || p.estado;
  assert p.validez_dias = 30 and p.dias_seguimiento = 7 and p.iva_modo = 'por_linea', 'parámetros copiados de la Organización';
  perform public.zzset('p1', p.id);

  insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad) values (p.id, public.zz('s1'), 2) returning * into l;
  assert l.orden = 1 and l.precio_unitario = 100000 and l.precio_catalogo = 100000 and not l.precio_modificado, 'precio precargado del catálogo';
  assert l.descripcion = 'Servicio mensual de higiene' and l.unidad_id = (select unidad_id from public.servicio where id = public.zz('s1')), 'descripción y unidad vienen del servicio';
  assert l.neto = 200000 and l.iva_pct = 21 and l.establecimiento_id = public.zz('est'), 'neto, IVA y establecimiento heredados';
  perform public.zzset('l1', l.id);
  insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad, precio_unitario) values (p.id, public.zz('s2'), 1, 60000) returning * into l;
  assert l.orden = 2 and l.precio_modificado and l.neto = 60000, 'precio modificado en la línea queda marcado';
  perform public.zzset('l2', l.id);

  begin insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad, descuento_pct) values (p.id, public.zz('s1'), 1, 10); raise exception 'NO DEBIÓ';
  exception when check_violation then assert sqlerrm like '%descuentos%', sqlerrm; end;
  begin insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad, establecimiento_id) values (p.id, public.zz('s1'), 1, public.zz('est2')); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;
  begin insert into public.presupuesto (cliente_id, establecimiento_id) values (public.zz('cli'), public.zz('est2')); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;
  begin insert into public.presupuesto (cliente_id, establecimiento_id, emisor_tipo, emisor_asociado_id) values (public.zz('cli'), public.zz('est'), 'asociado', public.zz('bruno')); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;
  raise notice 'OK presupuesto en borrador';
end $$;
commit;

-- ===== 3) Totales: IVA por línea y en subtotal; descuentos =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare r record; p2 bigint; p3 bigint; begin
  select * into r from public.presupuesto_resumen where id = public.zz('p1');
  assert r.neto = 260000 and r.iva = 54600 and r.total = 314600 and r.lineas = 2 and r.lineas_pendientes = 2, 'totales por línea: ' || r.neto || ' ' || r.iva || ' ' || r.total;
  assert r.vence_el is null and r.proximo_seguimiento is null, 'sin vencimiento mientras es borrador';
  insert into public.presupuesto (cliente_id, establecimiento_id, iva_modo, iva_general) values (public.zz('cli'), public.zz('est'), 'en_subtotal', 10.5) returning id into p2;
  insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad) values (p2, public.zz('s1'), 1);
  select * into r from public.presupuesto_resumen where id = p2;
  assert r.iva = 10500 and r.total = 110500, 'IVA en el subtotal: ' || r.iva;
  update public.organizacion set usa_descuentos = true;
  insert into public.presupuesto (cliente_id, establecimiento_id) values (public.zz('cli'), public.zz('est')) returning id into p3;
  insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad, descuento_pct) values (p3, public.zz('s1'), 2, 10);
  select * into r from public.presupuesto_resumen where id = p3;
  assert r.neto = 180000, 'descuento por línea: ' || r.neto;
  update public.organizacion set usa_descuentos = false;
  raise notice 'OK totales, IVA y descuentos';
end $$;
commit;

-- ===== 4) Enviar y congelar =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare pv bigint; begin
  insert into public.presupuesto (cliente_id, establecimiento_id) values (public.zz('cli'), public.zz('est')) returning id into pv;
  begin perform public.enviar_presupuesto(pv); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%no tiene líneas%', sqlerrm; end;
  perform public.enviar_presupuesto(public.zz('p1'));
  assert (select estado from public.presupuesto where id = public.zz('p1')) = 'enviado' and (select fecha_envio from public.presupuesto where id = public.zz('p1')) = public.hoy_ar(), 'enviado hoy';
  begin update public.presupuesto set estado = 'procesado' where id = public.zz('p1'); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin update public.presupuesto_linea set precio_unitario = 1 where id = public.zz('l1'); raise exception 'NO DEBIÓ'; exception when check_violation then assert sqlerrm like '%nueva versión%', sqlerrm; end;
  begin update public.presupuesto set cliente_id = public.zz('cli2') where id = public.zz('p1'); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad) values (public.zz('p1'), public.zz('s1'), 1); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin delete from public.presupuesto where id = public.zz('p1'); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin update public.presupuesto_linea set estado = 'aprobada' where id = public.zz('l1'); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  update public.presupuesto set comentarios = 'Se envió por mail' where id = public.zz('p1');   -- los comentarios sí se pueden editar
  delete from public.presupuesto where id = pv;                                                  -- un borrador sí se puede borrar
  raise notice 'OK enviar y congelar';
end $$;
commit;

-- ===== 5) Seguimiento =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare r record; pb bigint; begin
  select * into r from public.presupuesto_resumen where id = public.zz('p1');
  assert r.vence_el = public.hoy_ar() + 30 and r.proximo_seguimiento = public.hoy_ar() + 7, 'vence = envío + validez; próximo = envío + días de seguimiento';
  insert into public.presupuesto_seguimiento (presupuesto_id, fecha, nota) values (public.zz('p1'), public.hoy_ar() + 3, 'Llamé al cliente');
  select * into r from public.presupuesto_resumen where id = public.zz('p1');
  assert r.proximo_seguimiento = public.hoy_ar() + 10, 'el próximo seguimiento parte del último';
  insert into public.presupuesto (cliente_id, establecimiento_id) values (public.zz('cli'), public.zz('est')) returning id into pb;
  begin insert into public.presupuesto_seguimiento (presupuesto_id, nota) values (pb, 'x'); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin insert into public.presupuesto_seguimiento (presupuesto_id, fecha) values (public.zz('p1'), public.hoy_ar() - 1); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  raise notice 'OK seguimiento';
end $$;
commit;

-- ===== 6) Decisión por línea: rechazar, aprobar (genera OT), procesar, reabrir =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare ot1 bigint; ot2 bigint; o public.ot; m bigint; r record; y text := extract(year from public.hoy_ar())::text; begin
  select id into m from public.lista_valor where lista = 'motivo_rechazo' and nombre = 'Precio';
  begin perform public.rechazar_linea(public.zz('l2'), null); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%obligatorio%', sqlerrm; end;
  perform public.rechazar_linea(public.zz('l2'), m, 'Lo vieron caro');
  assert (select estado from public.presupuesto_linea where id = public.zz('l2')) = 'rechazada', 'línea rechazada';
  assert (select estado from public.cliente where id = public.zz('cli')) = 'prospecto', 'el cliente sigue prospecto hasta la primera aprobación';

  ot1 := public.aprobar_linea(public.zz('l1'), public.hoy_ar() + 5, null, true, 50000);
  perform public.zzset('ot1', ot1);
  select * into o from public.ot where id = ot1;
  assert o.codigo = 'OT-' || y || '-00001' and o.origen = 'presupuesto' and o.estado = 'pendiente', 'OT creada: ' || o.codigo;
  assert o.neto = 200000 and o.responsable_id = public.zz('ana') and o.requiere_anticipo and o.anticipo_monto = 50000, 'datos de la OT';
  assert o.cliente_id = public.zz('cli') and o.servicio_id = public.zz('s1') and o.inicio_previsto = public.hoy_ar() + 5
     and o.periodo = date_trunc('month', public.hoy_ar() + 5)::date, 'cliente, servicio, inicio y período';
  assert (select estado from public.cliente where id = public.zz('cli')) = 'activo', 'el prospecto pasa a activo al aprobar';
  select * into r from public.presupuesto_resumen where id = public.zz('p1');
  assert r.estado = 'enviado' and r.lineas_pendientes = 0 or r.estado = 'procesado', 'estado tras decidir';
  assert r.estado = 'procesado' and r.lineas_aprobadas = 1 and r.lineas_rechazadas = 1 and r.proximo_seguimiento is null, 'procesado y sin seguimiento';
  begin perform public.aprobar_linea(public.zz('l1'), public.hoy_ar()); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like '%enviado%' or sqlerrm like '%decisión%', sqlerrm; end;

  perform public.reabrir_linea(public.zz('l2'));
  select * into r from public.presupuesto_resumen where id = public.zz('p1');
  assert r.estado = 'enviado' and r.lineas_pendientes = 1, 'reabrir una rechazada devuelve el presupuesto a enviado';
  assert (select motivo_rechazo_id from public.presupuesto_linea where id = public.zz('l2')) is null, 'se limpia el motivo';
  begin perform public.aprobar_linea(public.zz('l2'), public.hoy_ar() + 1, public.zz('bruno')); raise exception 'NO DEBIÓ';
  exception when check_violation then assert sqlerrm like '%baja%', sqlerrm; end;
  ot2 := public.aprobar_linea(public.zz('l2'), public.hoy_ar() + 1, public.zz('rafa'));
  perform public.zzset('ot2', ot2);
  assert (select responsable_id from public.ot where id = ot2) = public.zz('rafa'), 'responsable elegido al aprobar';
  assert (select estado from public.presupuesto where id = public.zz('p1')) = 'procesado', 'todas las líneas decididas → procesado';
  raise notice 'OK decisión por línea y generación de OT';
end $$;
commit;

-- configuración: reabrir líneas rechazadas desactivado
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare pr bigint; ln bigint; m bigint; begin
  select id into m from public.lista_valor where lista = 'motivo_rechazo' limit 1;
  insert into public.presupuesto (cliente_id, establecimiento_id) values (public.zz('cli'), public.zz('est')) returning id into pr;
  insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad) values (pr, public.zz('s2'), 1) returning id into ln;
  perform public.enviar_presupuesto(pr);
  perform public.rechazar_linea(ln, m);
  update public.organizacion set reabrir_linea_rechazada = false;
  begin perform public.reabrir_linea(ln); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%desactivada%', sqlerrm; end;
  update public.organizacion set reabrir_linea_rechazada = true;
  raise notice 'OK reapertura configurable';
end $$;
commit;

-- ===== 7) Nueva versión =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare pb bigint; pv bigint; r record; n int; pc bigint; la bigint; begin
  insert into public.presupuesto (cliente_id, establecimiento_id, comentarios) values (public.zz('cli'), public.zz('est'), 'versión 1') returning id into pb;
  insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad, precio_unitario) values (pb, public.zz('s1'), 1, 90000), (pb, public.zz('s2'), 3, null);
  perform public.enviar_presupuesto(pb);
  insert into public.presupuesto_seguimiento (presupuesto_id, nota) values (pb, 'seguimiento v1');
  pv := public.nueva_version_presupuesto(pb);
  select * into r from public.presupuesto where id = pv;
  assert r.codigo = (select codigo from public.presupuesto where id = pb) and r.version = 2 and r.estado = 'borrador' and r.fecha_envio is null, 'v2 en borrador con el mismo código';
  assert (select estado from public.presupuesto where id = pb) = 'reemplazado', 'la anterior queda reemplazada';
  select count(*) into n from public.presupuesto_linea where presupuesto_id = pv and estado = 'pendiente'; assert n = 2, 'líneas copiadas y pendientes';
  assert (select precio_unitario from public.presupuesto_linea where presupuesto_id = pv and orden = 1) = 90000
     and (select precio_modificado from public.presupuesto_linea where presupuesto_id = pv and orden = 1), 'conserva el precio modificado';
  select * into r from public.presupuesto_resumen where id = pb; assert r.proximo_seguimiento is null and r.vence_el is null, 'la reemplazada no tiene seguimiento';
  begin perform public.nueva_version_presupuesto(pb); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%enviado%', sqlerrm; end;
  update public.presupuesto_linea set cantidad = 5 where presupuesto_id = pv and orden = 1;      -- la nueva versión se edita libremente
  -- con líneas aprobadas no se puede versionar
  insert into public.presupuesto (cliente_id, establecimiento_id, emisor_tipo, emisor_asociado_id) values (public.zz('cli'), public.zz('est'), 'asociado', public.zz('ana')) returning id into pc;
  insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad) values (pc, public.zz('s1'), 1), (pc, public.zz('s2'), 1);
  perform public.enviar_presupuesto(pc);
  select id into la from public.presupuesto_linea where presupuesto_id = pc and orden = 1;
  perform public.aprobar_linea(la, public.hoy_ar());
  begin perform public.nueva_version_presupuesto(pc); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%aprobadas%', sqlerrm; end;
  raise notice 'OK nueva versión';
end $$;
commit;

-- ===== 8) OT directa y cambios de estado =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare o public.ot; id1 bigint; begin
  begin insert into public.ot (origen, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
        values ('directa', public.zz('cli'), public.zz('est'), public.zz('s1'), public.zz('ana'), public.hoy_ar(), 1000); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;                                                -- falta el motivo
  begin insert into public.ot (origen, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
        values ('presupuesto', public.zz('cli'), public.zz('est'), public.zz('s1'), public.zz('ana'), public.hoy_ar(), 1000); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;                                                -- no se arma una OT de presupuesto a mano
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto, estado, inicio_real)
  values ('directa', 'Pedido urgente por teléfono', public.zz('cli'), public.zz('est'), public.zz('s1'), public.zz('ana'), public.hoy_ar() + 3, 80000, 'cerrada', public.hoy_ar()) returning * into o;
  assert o.estado = 'pendiente' and o.inicio_real is null and o.autorizado_por = auth.uid(), 'directa: nace pendiente y registra quién autorizó';
  perform public.zzset('ot3', o.id);
  begin insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
        values ('directa', 'x', public.zz('cli'), public.zz('est2'), public.zz('s1'), public.zz('ana'), public.hoy_ar(), 1); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;                                                -- establecimiento de otro cliente
  begin insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
        values ('directa', 'x', public.zz('cli'), public.zz('est'), public.zz('s1'), public.zz('bruno'), public.hoy_ar(), 1); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;                                                -- responsable de baja
  begin update public.ot set estado = 'en_ejecucion' where id = o.id; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin perform public.cambiar_estado_ot(o.id, 'cerrada'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%Transición%', sqlerrm; end;
  perform public.cambiar_estado_ot(o.id, 'en_ejecucion');
  assert (select inicio_real from public.ot where id = o.id) = public.hoy_ar(), 'inicio real al pasar a ejecución';
  perform public.cambiar_estado_ot(o.id, 'finalizada');
  assert (select finalizada_en from public.ot where id = o.id) = public.hoy_ar(), 'fecha de finalización';
  perform public.cambiar_estado_ot(o.id, 'cerrada');
  assert (select cerrada_en from public.ot where id = o.id) is not null, 'cerrada con fecha';
  begin update public.ot set neto = 1 where id = o.id; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin insert into public.ot_equipo values (o.id, public.zz('rafa')); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin perform public.cambiar_estado_ot(o.id, 'finalizada'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%motivo%', sqlerrm; end;
  perform public.cambiar_estado_ot(o.id, 'finalizada', 'Faltó cargar un informe');
  assert (select estado from public.ot where id = o.id) = 'finalizada' and (select cerrada_en from public.ot where id = o.id) is null, 'reabierta';
  assert (select count(*) from public.log_auditoria where tabla = 'ot' and registro_id = o.id::text and campo = 'estado' and valor_anterior = 'cerrada' and motivo = 'Faltó cargar un informe') = 1, 'la reapertura queda auditada con motivo';
  -- equipo
  insert into public.ot_equipo values (o.id, public.zz('rafa'));
  begin insert into public.ot_equipo values (o.id, public.zz('bruno')); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  -- cancelar
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
  values ('directa', 'otra', public.zz('cli'), public.zz('est'), public.zz('s2'), public.zz('ana'), public.hoy_ar() + 9, 1000) returning id into id1;
  begin perform public.cambiar_estado_ot(id1, 'cancelada'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%motivo%', sqlerrm; end;
  perform public.cambiar_estado_ot(id1, 'cancelada', 'El cliente desistió');
  begin perform public.cambiar_estado_ot(id1, 'en_ejecucion'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%Transición%', sqlerrm; end;
  raise notice 'OK OT directa, estados, reapertura y equipo';
end $$;
commit;

-- ===== 9) Inicio automático de OT =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare a bigint; b bigint; c bigint; n int; begin
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
  values ('directa', 'prueba', public.zz('cli'), public.zz('est'), public.zz('s1'), public.zz('ana'), public.hoy_ar() - 1, 1000) returning id into a;
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
  values ('directa', 'prueba', public.zz('cli'), public.zz('est'), public.zz('s1'), public.zz('ana'), public.hoy_ar() + 10, 1000) returning id into b;
  n := public.iniciar_ots_vencidas();
  assert n >= 1, 'inició las vencidas';
  assert (select estado from public.ot where id = a) = 'en_ejecucion' and (select inicio_real from public.ot where id = a) = public.hoy_ar(), 'la vencida pasó a ejecución';
  assert (select estado from public.ot where id = b) = 'pendiente', 'la futura sigue pendiente';
  insert into public.ot (origen, motivo_directa, cliente_id, establecimiento_id, servicio_id, responsable_id, inicio_previsto, neto)
  values ('directa', 'prueba', public.zz('cli'), public.zz('est'), public.zz('s1'), public.zz('ana'), public.hoy_ar() - 2, 1000) returning id into c;
  update public.organizacion set inicio_auto_ot = false;
  assert public.iniciar_ots_vencidas() = 0 and (select estado from public.ot where id = c) = 'pendiente', 'con el inicio automático apagado no hace nada';
  update public.organizacion set inicio_auto_ot = true;
  raise notice 'OK inicio automático de OT';
end $$;
commit;

-- ===== 10) Servicios mensuales (SM) =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare s bigint; s2 bigint; o1 bigint; o2 bigint; o3 bigint; o public.ot; mes date := date_trunc('month', public.hoy_ar())::date; n int; begin
  insert into public.sm (cliente_id, establecimiento_id, servicio_id, dia_generacion, dia_inicio, fecha_inicio, responsable_id)
  values (public.zz('cli'), public.zz('est'), public.zz('s1'), 1, 15, (mes - interval '2 months')::date, public.zz('ana')) returning id into s;
  assert (select codigo from public.sm where id = s) = 'SM-00001', 'código SM';
  insert into public.sm_precio (sm_id, vigente_desde, precio) values (s, (mes - interval '2 months')::date, 100000);
  begin insert into public.sm_precio (sm_id, vigente_desde, precio) values (s, mes + 3, 1); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;  -- no es primer día de mes

  o1 := public.generar_ot_sm(s, mes);
  select * into o from public.ot where id = o1;
  assert o.origen = 'sm' and o.periodo = mes and o.inicio_previsto = mes + 14 and o.neto = 100000 and o.responsable_id = public.zz('ana'), 'OT del período: inicio el día 15';
  begin perform public.generar_ot_sm(s, mes); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%Ya existe%', sqlerrm; end;
  perform public.cambiar_estado_ot(o1, 'cancelada', 'Generada por error');
  o2 := public.generar_ot_sm(s, mes);
  assert o2 <> o1, 'cancelada la OT, el período se puede regenerar';

  begin insert into public.sm_precio (sm_id, vigente_desde, precio) values (s, mes, 90000); raise exception 'NO DEBIÓ';
  exception when check_violation then assert sqlerrm like '%hacia adelante%', sqlerrm; end;   -- retroactivo
  insert into public.sm_precio (sm_id, vigente_desde, precio) values (s, (mes + interval '1 month')::date, 120000);
  assert public.sm_precio_en(s, mes) = 100000 and public.sm_precio_en(s, (mes + interval '1 month')::date) = 120000, 'precio por período';
  o3 := public.generar_ot_sm(s, (mes + interval '1 month')::date);
  assert (select neto from public.ot where id = o3) = 120000, 'el mes siguiente usa el precio nuevo';
  begin perform public.generar_ot_sm(s, (mes - interval '5 months')::date); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%anterior al inicio%', sqlerrm; end;
  update public.sm_precio set precio = 1 where sm_id = s; get diagnostics n = row_count; assert n = 0, 'los precios del SM no se modifican';
  update public.sm set estado = 'suspendido' where id = s;
  begin perform public.generar_ot_sm(s, (mes + interval '2 months')::date); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%suspendido%', sqlerrm; end;
  update public.sm set estado = 'activo' where id = s;
  perform public.zzset('sm1', s);
  assert (select ultimo_periodo_generado from public.sm_resumen where id = s) = (mes + interval '1 month')::date and (select precio_vigente from public.sm_resumen where id = s) = 100000, 'resumen del SM';

  -- generación automática
  insert into public.sm (cliente_id, establecimiento_id, servicio_id, dia_generacion, dia_inicio, fecha_inicio, responsable_id)
  values (public.zz('cli'), public.zz('est'), public.zz('s2'), 1, 5, mes, public.zz('rafa')) returning id into s2;
  insert into public.sm_precio (sm_id, vigente_desde, precio) values (s2, mes, 50000);
  update public.organizacion set generar_sm_auto = false;
  assert public.generar_ots_sm_pendientes() = 0, 'con la generación automática apagada no hace nada';
  update public.organizacion set generar_sm_auto = true;
  assert public.generar_ots_sm_pendientes() = 1, 'genera solo el SM que no tenía OT del mes';
  assert public.generar_ots_sm_pendientes() = 0, 'es idempotente: no duplica';
  perform public.cambiar_estado_ot((select id from public.ot where sm_id = s2 and periodo = mes), 'cancelada', 'Prueba');
  assert public.generar_ots_sm_pendientes() = 0, 'lo automático no regenera un período cancelado';
  update public.organizacion set generar_sm_auto = false;
  raise notice 'OK servicios mensuales';
end $$;
commit;

-- ===== 11) Permisos =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ declare n int; begin
  select count(*) into n from public.presupuesto; assert n = 0, 'el lector (sin Comercial) no ve presupuestos';
  select count(*) into n from public.ot; assert n = 0, 'ni OT';
  begin perform public.enviar_presupuesto(public.zz('p1')); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform public.generar_ot_sm(public.zz('sm1')); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK sin permiso no se ve ni se opera';
end $$;
rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare pr bigint; n int; begin
  select count(*) into n from public.presupuesto; assert n > 0, 'el operador ve presupuestos';
  insert into public.presupuesto (cliente_id, establecimiento_id, emisor_tipo, emisor_asociado_id) values (public.zz('cli'), public.zz('est'), 'asociado', public.zz('ana')) returning id into pr;
  insert into public.presupuesto_linea (presupuesto_id, servicio_id, cantidad) values (pr, public.zz('s1'), 1);
  perform public.enviar_presupuesto(pr);
  delete from public.presupuesto where id = pr; get diagnostics n = row_count; assert n = 0, 'el operador no borra';
  begin perform public.cambiar_estado_ot(public.zz('ot3'), 'cerrada'); perform public.cambiar_estado_ot(public.zz('ot3'), 'finalizada', 'x'); raise exception 'NO DEBIÓ';
  exception when insufficient_privilege then null; end;                                            -- reabrir una cerrada exige administración
  raise notice 'OK operador: opera pero no administra';
end $$;
rollback;
begin; set local role anon;
do $$ begin
  begin perform public.enviar_presupuesto(1); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform public.cambiar_estado_ot(1, 'cerrada'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK un visitante anónimo no ejecuta funciones';
end $$;
rollback;

-- ===== 12) Auditoría =====
do $$ declare n int; begin
  select count(*) into n from public.log_auditoria where tabla = 'presupuesto_linea' and campo = 'estado' and valor_nuevo = 'aprobada' and usuario_id = '00000000-0000-0000-0000-000000000001';
  assert n >= 2, 'las aprobaciones quedan auditadas con su autor (' || n || ')';
  raise notice 'OK auditoría comercial';
end $$;

drop function public.zzset(text, bigint); drop function public.zz(text); drop table public.zz_ctx;
\echo 'COMERCIAL Y OPERACIONES: todas las pruebas pasaron'
