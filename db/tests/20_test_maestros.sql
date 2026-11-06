\set ON_ERROR_STOP on
\set U1 '''00000000-0000-0000-0000-000000000001'''
\set U2 '''00000000-0000-0000-0000-000000000002'''
\set U3 '''00000000-0000-0000-0000-000000000003'''
\set U4 '''00000000-0000-0000-0000-000000000004'''

-- Preparación: lector (maestros 1), operador (maestros 2), inactivo; administrador = Director
delete from public.permiso_usuario;

-- 1) Datos iniciales
do $$ declare n int; begin
  select count(*) into n from public.lista_valor where lista = 'categoria_monotributo'; assert n = 11, 'categorías A–K';
  select count(*) into n from public.lista_valor where lista = 'tipo_comprobante'; assert n = 12, 'tipos de comprobante';
  assert (select afecta_margen_distribuible from public.categoria_gasto where nombre = 'Subcontrataciones'), 'subcontrataciones afecta margen';
  assert not (select afecta_margen_distribuible from public.categoria_gasto where nombre = 'Gastos bancarios'), 'gastos bancarios no afectan';
  raise notice 'OK datos iniciales';
end $$;

-- 2) Cliente: código, establecimiento y contacto principal automáticos; documento único; listas atadas
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare c public.cliente; n int; v_banco bigint; v_tipo bigint; begin
  select id into v_tipo from public.lista_valor where lista = 'tipo_cliente' and nombre = 'Empresa';
  insert into public.cliente (razon_social, tipo_cliente_id, nro_doc, condicion_iva, domicilio_fiscal, telefono, email)
  values ('Minera Sur SA', v_tipo, '30711111112', 'Resp. Inscripto', 'Calle 1 123', '221-555', 'a@b.com') returning * into c;
  assert c.codigo = 'CLI-00001' and c.estado = 'prospecto', 'código y estado inicial: ' || c.codigo;
  select count(*) into n from public.establecimiento where cliente_id = c.id and principal; assert n = 1, 'establecimiento principal automático';
  select count(*) into n from public.contacto where cliente_id = c.id and principal; assert n = 1, 'contacto principal automático';
  assert (select direccion from public.establecimiento where cliente_id = c.id) = 'Calle 1 123', 'dirección heredada del domicilio fiscal';
  -- documento duplicado
  begin insert into public.cliente (razon_social, nro_doc, condicion_iva) values ('Otra', '30711111112', 'Exento'); raise exception 'NO DEBIÓ';
  exception when unique_violation then null; end;
  -- documento con guiones o letras
  begin insert into public.cliente (razon_social, nro_doc, condicion_iva) values ('Otra', '30-71111111-2', 'Exento'); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;
  -- un valor de otra lista no se puede usar
  select id into v_banco from public.lista_valor where lista = 'banco' limit 1;
  begin insert into public.cliente (razon_social, tipo_cliente_id, nro_doc, condicion_iva) values ('Otra', v_banco, '20111111112', 'Exento'); raise exception 'NO DEBIÓ';
  exception when foreign_key_violation then null; end;
  raise notice 'OK cliente';
end $$;
commit;

-- 3) Establecimiento y contacto: un solo principal, coherencia con el cliente
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare c1 bigint; c2 bigint; e2 bigint; e_otro bigint; k bigint; begin
  select id into c1 from public.cliente where codigo = 'CLI-00001';
  insert into public.cliente (razon_social, nro_doc, condicion_iva) values ('Cliente Dos', '30722222223', 'Exento') returning id into c2;
  insert into public.establecimiento (cliente_id, nombre) values (c1, 'Planta Norte') returning id into e2;
  select id into e_otro from public.establecimiento where cliente_id = c2 limit 1;
  begin update public.establecimiento set principal = true where id = e2; raise exception 'NO DEBIÓ';
  exception when unique_violation then null; end;
  perform public.marcar_establecimiento_principal(e2);
  assert (select count(*) from public.establecimiento where cliente_id = c1 and principal) = 1, 'sigue habiendo un solo principal';
  assert (select principal from public.establecimiento where id = e2), 'el nuevo es el principal';
  begin insert into public.contacto (cliente_id, establecimiento_id, nombre) values (c1, e_otro, 'X'); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;
  insert into public.contacto (cliente_id, establecimiento_id, nombre, rol) values (c1, e2, 'Laura', 'Compras') returning id into k;
  perform public.marcar_contacto_principal(k);
  assert (select count(*) from public.contacto where cliente_id = c1 and principal) = 1, 'un contacto principal';
  raise notice 'OK establecimientos y contactos';
end $$;
commit;

-- 4) Campos críticos: motivo y permiso
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ begin
  begin update public.cliente set nro_doc = '30799999999' where codigo = 'CLI-00001'; raise exception 'NO DEBIÓ';
  exception when check_violation then assert sqlerrm like '%motivo%', sqlerrm; end;
  perform public.set_motivo('Corrección de CUIT cargado mal');
  update public.cliente set nro_doc = '30799999999' where codigo = 'CLI-00001';
  assert (select count(*) from public.log_auditoria where tabla = 'cliente' and campo = 'nro_doc'
            and valor_anterior = '30711111112' and valor_nuevo = '30799999999' and motivo like 'Corrección%') = 1, 'auditoría con motivo';
  update public.cliente set telefono = '221-999' where codigo = 'CLI-00001';  -- campo común: no pide motivo
  raise notice 'OK campos críticos (administrador)';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  perform public.set_motivo('Quiero cambiarlo');
  begin update public.cliente set razon_social = 'Nombre nuevo' where codigo = 'CLI-00001'; raise exception 'NO DEBIÓ';
  exception when insufficient_privilege then null; end;
  update public.cliente set observacion = 'nota del operador' where codigo = 'CLI-00001';  -- operar sí puede cambiar lo común
  assert (select observacion from public.cliente where codigo = 'CLI-00001') = 'nota del operador';
  raise notice 'OK campos críticos (operador sin administración)';
end $$;
rollback;

-- 5) RLS: lector, operador, inactivo
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ declare n int; begin
  select count(*) into n from public.cliente; assert n = 2, 'lector ve clientes';
  begin insert into public.cliente (razon_social, nro_doc, condicion_iva) values ('X', '30733333334', 'Exento'); raise exception 'NO DEBIÓ';
  exception when insufficient_privilege then null; end;
  update public.cliente set observacion = 'x'; get diagnostics n = row_count; assert n = 0, 'lector no modifica';
  raise notice 'OK lector';
end $$;
rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare n int; begin
  insert into public.cliente (razon_social, nro_doc, condicion_iva) values ('Cliente Operador', '30744444445', 'Exento');
  delete from public.cliente where razon_social = 'Cliente Operador'; get diagnostics n = row_count; assert n = 0, 'el operador no borra';
  raise notice 'OK operador';
end $$;
rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U4, true) as _ \gset
do $$ declare n int; begin select count(*) into n from public.cliente; assert n = 0, 'inactivo no ve nada'; raise notice 'OK inactivo'; end $$;
rollback;

-- 6) Asociado
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare a public.asociado; begin
  insert into public.asociado (apellido_nombre, nro_doc, condicion_iva, vinculo)
  values ('Gómez, Ana', '27111111112', 'Monotributo', 'socio_cooperativo') returning * into a;
  assert a.codigo = 'ASO-00001' and a.estado = 'activo' and a.periodicidad_control = 'semestral', 'valores por defecto';
  begin update public.asociado set estado = 'baja' where id = a.id; raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;
  update public.asociado set estado = 'baja', fecha_baja = public.hoy_ar() where id = a.id;
  begin insert into public.asociado (apellido_nombre, nro_doc, condicion_iva, vinculo) values ('Otro', '27111111112', 'Exento', 'ambos'); raise exception 'NO DEBIÓ';
  exception when unique_violation then null; end;
  begin insert into public.asociado (apellido_nombre, nro_doc, condicion_iva, vinculo) values ('Otro', '27111111119', 'Exento', 'otro'); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;
  update public.usuario set asociado_id = a.id where id = '00000000-0000-0000-0000-000000000001';
  raise notice 'OK asociado';
end $$;
commit;

-- 7) Proveedor
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare p public.proveedor; begin
  insert into public.proveedor (nombre_fantasia, nro_doc, condicion_iva, tipo) values ('Taller Pérez', '20222222223', 'Monotributo', 'subcontratista') returning * into p;
  assert p.codigo = 'PRV-00001', p.codigo;
  begin insert into public.proveedor (nombre_fantasia, nro_doc, condicion_iva, tipo) values ('Otro', '20222222223', 'Exento', 'ambos'); raise exception 'NO DEBIÓ';
  exception when unique_violation then null; end;
  raise notice 'OK proveedor';
end $$;
commit;

-- 8) Cuentas bancarias
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare a bigint; b bigint; banco bigint; ca bigint; begin
  select id into banco from public.lista_valor where lista = 'banco' limit 1;
  select id into a from public.asociado limit 1;
  -- cuentas propias de la Cooperativa identificadas por número de cuenta
  insert into public.cuenta_bancaria (titular_tipo, banco_id, nro_cuenta, tipo_cuenta, principal) values ('cooperativa', banco, '439-0251987', 'CC', true);
  insert into public.cuenta_bancaria (titular_tipo, banco_id, nro_cuenta, tipo_cuenta) values ('cooperativa', banco, '439-0299077', 'CC');
  begin insert into public.cuenta_bancaria (titular_tipo, banco_id, nro_cuenta, principal) values ('cooperativa', banco, '439-0000001', true); raise exception 'NO DEBIÓ';
  exception when unique_violation then null; end;   -- ya hay una principal
  begin insert into public.cuenta_bancaria (titular_tipo, banco_id, nro_cuenta) values ('cooperativa', banco, '439-0251987'); raise exception 'NO DEBIÓ';
  exception when unique_violation then null; end;   -- número repetido
  begin insert into public.cuenta_bancaria (titular_tipo, titular_id, banco_id) values ('cooperativa', 1, banco); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;    -- la Cooperativa no lleva titular_id
  begin insert into public.cuenta_bancaria (titular_tipo, banco_id) values ('asociado', banco); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;    -- los demás sí lo exigen
  begin insert into public.cuenta_bancaria (titular_tipo, titular_id, banco_id) values ('asociado', 99999, banco); raise exception 'NO DEBIÓ';
  exception when foreign_key_violation then null; end;   -- titular inexistente
  begin insert into public.cuenta_bancaria (titular_tipo, titular_id, cbu) values ('asociado', a, '123'); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;    -- CBU mal formado
  insert into public.cuenta_bancaria (titular_tipo, titular_id, banco_id, cbu, alias, principal) values ('asociado', a, banco, '0070376320000001727951', 'ana.gomez', true) returning id into ca;
  insert into public.cuenta_bancaria (titular_tipo, titular_id, banco_id, cbu) values ('asociado', a, banco, '2850101340095507550958') returning id into b;
  perform public.marcar_cuenta_principal(b);
  assert (select count(*) from public.cuenta_bancaria where titular_tipo = 'asociado' and principal) = 1 and (select principal from public.cuenta_bancaria where id = b), 'cambio atómico de principal';
  perform public.set_motivo('Cambio de banco');
  update public.cuenta_bancaria set cbu = '0140999999999999999999' where id = ca;
  assert (select count(*) from public.log_auditoria where tabla = 'cuenta_bancaria' and campo = 'cbu' and motivo = 'Cambio de banco') = 1, 'cambio de CBU auditado con motivo';
  raise notice 'OK cuentas bancarias';
end $$;
commit;

-- 9) Servicios y precios versionados
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare s bigint; r record; n int; begin
  insert into public.servicio (nombre, descripcion) values ('Visita de seguridad', 'Visita mensual') returning id into s;
  assert (select codigo from public.servicio where id = s) = 'SRV-00001', 'código de servicio';
  select * into r from public.servicio_vigente where servicio_id = s; assert r.precio_ars is null, 'sin precios todavía';
  insert into public.servicio_precio (servicio_id, vigente_desde, precio_ars, precio_usd) values
    (s, public.hoy_ar() - 60, 100000, 100), (s, public.hoy_ar() - 5, 120000, 110), (s, public.hoy_ar() + 30, 150000, 120);
  select * into r from public.servicio_vigente where servicio_id = s;
  assert r.precio_ars = 120000 and r.precio_usd = 110, 'precio vigente = el último con fecha <= hoy, vio ' || r.precio_ars;
  update public.servicio_precio set precio_ars = 1 where servicio_id = s; get diagnostics n = row_count; assert n = 0, 'los precios no se modifican';
  delete from public.servicio_precio where servicio_id = s; get diagnostics n = row_count; assert n = 0, 'ni se borran';
  begin insert into public.servicio_precio (servicio_id, vigente_desde, precio_ars) values (s, public.hoy_ar() - 5, 1); raise exception 'NO DEBIÓ';
  exception when unique_violation then null; end;
  raise notice 'OK servicios y precios versionados';
end $$;
commit;

-- 10) Tipos de cambio, plantillas, adjuntos
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare p1 bigint; p2 bigint; begin
  insert into public.tipo_cambio (fecha, valor) values (public.hoy_ar(), 1350.50);
  begin insert into public.tipo_cambio (fecha, valor) values (public.hoy_ar() + 1, 0); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;
  insert into public.tipo_cambio_promedio (periodo, valor) values (date_trunc('month', public.hoy_ar())::date, 1320);
  begin insert into public.tipo_cambio_promedio (periodo, valor) values (date_trunc('month', public.hoy_ar())::date + 3, 1320); raise exception 'NO DEBIÓ';
  exception when check_violation then null; end;
  insert into public.plantilla_presupuesto (nombre, predeterminada) values ('Explicativa', true) returning id into p1;
  insert into public.plantilla_presupuesto (nombre, diseno) values ('Compacta', 'compacto') returning id into p2;
  begin update public.plantilla_presupuesto set predeterminada = true where id = p2; raise exception 'NO DEBIÓ';
  exception when unique_violation then null; end;
  perform public.marcar_plantilla_predeterminada(p2);
  assert (select count(*) from public.plantilla_presupuesto where predeterminada) = 1, 'una sola predeterminada';
  insert into public.documento_adjunto (entidad, registro_id, nombre, storage_path) values ('cliente', 1, 'contrato.pdf', 'adjuntos/cliente/1/contrato.pdf');
  raise notice 'OK tipos de cambio, plantillas y adjuntos';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ begin
  insert into public.documento_adjunto (entidad, registro_id, nombre, storage_path) values ('cliente', 1, 'nota.pdf', 'x');   -- cualquier usuario activo adjunta
  begin insert into public.categoria_gasto (nombre) values ('Nueva'); raise exception 'NO DEBIÓ';
  exception when insufficient_privilege then null; end;     -- catálogos sensibles: solo administración
  raise notice 'OK permisos de catálogos y adjuntos';
end $$;
rollback;

-- 11) Auditoría general
do $$ declare n int; begin
  select count(*) into n from public.log_auditoria where tabla in ('cliente','asociado','proveedor','cuenta_bancaria','servicio') and operacion = 'alta';
  assert n >= 7, 'altas auditadas: ' || n;
  raise notice 'OK auditoría de maestros';
end $$;
\echo 'MAESTROS: todas las pruebas pasaron'
