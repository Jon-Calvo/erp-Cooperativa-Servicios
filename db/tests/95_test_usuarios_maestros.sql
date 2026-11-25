\set ON_ERROR_STOP on
\set U1 '''00000000-0000-0000-0000-000000000001'''
\set U2 '''00000000-0000-0000-0000-000000000002'''
\set U3 '''00000000-0000-0000-0000-000000000003'''

insert into auth.users (id, email, last_sign_in_at) values
  ('00000000-0000-0000-0000-000000000006', 'nuevo@coop.test', now()),
  ('00000000-0000-0000-0000-000000000007', 'dir2@coop.test', null)
on conflict do nothing;

-- ===== 1) Lista de usuarios =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare r record; begin
  select * into r from public.lista_usuarios() where email = 'admin@coop.test';
  assert r.activo and 'Director' = any (r.puestos) and r.nombre is not null, 'el administrador figura con su e-mail y su puesto';
  assert (select count(*) from public.lista_usuarios()) >= 4, 'lista completa';
  raise notice 'OK lista de usuarios';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ begin
  begin perform * from public.lista_usuarios(); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform public.alta_usuario('nuevo@coop.test'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform public.set_puestos_usuario('00000000-0000-0000-0000-000000000002', '{}'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK sin permiso de Seguridad no se ve ni se da de alta a nadie';
end $$; rollback;
begin; set local role anon;
do $$ begin
  begin perform * from public.lista_usuarios(); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  begin perform public.actualizar_con_motivo('cliente', 1, '{"telefono":"1"}'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  raise notice 'OK un visitante anónimo no accede';
end $$; rollback;

-- ===== 2) Alta de usuarios =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare v uuid; lector bigint; oper bigint; dir bigint; r record; begin
  select id into lector from public.puesto where nombre = 'Lector'; select id into oper from public.puesto where nombre = 'Operador'; select id into dir from public.puesto where nombre = 'Director';
  v := public.alta_usuario('Nuevo@Coop.Test', 'Nuevo Usuario', array[lector]);
  assert v = '00000000-0000-0000-0000-000000000006', 'el e-mail se busca sin distinguir mayúsculas';
  select * into r from public.lista_usuarios() where usuario_id = v;
  assert r.nombre = 'Nuevo Usuario' and r.activo and r.puestos = array['Lector'] and r.email = 'nuevo@coop.test' and r.ultimo_ingreso is not null, 'alta con su puesto';
  begin perform public.alta_usuario('nuevo@coop.test'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%ya está dado de alta%', sqlerrm; end;
  begin perform public.alta_usuario('nadie@coop.test'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%Authentication%', sqlerrm; end;
  begin perform public.alta_usuario('  '); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%e-mail%', sqlerrm; end;
  begin perform public.alta_usuario('dir2@coop.test', 'Director dos', array[999999::bigint]); raise exception 'NO DEBIÓ'; exception when foreign_key_violation then null; end;
  assert not exists (select 1 from public.usuario where id = '00000000-0000-0000-0000-000000000007'), 'un alta con error no deja nada a medias';
  perform public.alta_usuario('dir2@coop.test', null, array[dir, oper]);
  assert (select nombre from public.usuario where id = '00000000-0000-0000-0000-000000000007') = 'dir2@coop.test', 'sin nombre se usa el e-mail';
  -- reemplazo de puestos
  perform public.set_puestos_usuario(v, array[oper]);
  assert (select puestos from public.lista_usuarios() where usuario_id = v) = array['Operador'], 'puestos reemplazados';
  perform public.set_puestos_usuario(v, array[oper, lector]);
  assert (select count(*) from public.usuario_puesto where usuario_id = v) = 2, 'puestos agregados';
  perform public.set_puestos_usuario(v, '{}');
  assert (select puestos from public.lista_usuarios() where usuario_id = v) = '{}', 'sin puestos';
  begin perform public.set_puestos_usuario('00000000-0000-0000-0000-0000000000ff', '{}'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%No existe el usuario%', sqlerrm; end;
  raise notice 'OK alta de usuarios y puestos';
end $$;
commit;

-- ===== 3) Siempre queda un Director activo (sin sesión: se prueba la regla, no el permiso) =====
do $$ declare dir bigint; begin
  select id into dir from public.puesto where nombre = 'Director';
  -- hay dos directores: se le puede quitar el puesto a uno
  perform public.set_puestos_usuario('00000000-0000-0000-0000-000000000007', '{}');
  assert not exists (select 1 from public.usuario_puesto where usuario_id = '00000000-0000-0000-0000-000000000007' and puesto_id = dir), 'se quitó el puesto a un director';
  -- ahora el administrador es el único: no se le puede quitar ni desactivar
  begin perform public.set_puestos_usuario('00000000-0000-0000-0000-000000000001', '{}'); raise exception 'NO DEBIÓ'; exception when check_violation then assert sqlerrm like '%al menos un Director%', sqlerrm; end;
  begin update public.usuario set activo = false where id = '00000000-0000-0000-0000-000000000001'; raise exception 'NO DEBIÓ'; exception when check_violation then assert sqlerrm like '%al menos un Director%', sqlerrm; end;
  begin delete from public.usuario_puesto where usuario_id = '00000000-0000-0000-0000-000000000001' and puesto_id = dir; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  -- con un segundo director activo sí se puede cambiar al primero
  perform public.set_puestos_usuario('00000000-0000-0000-0000-000000000007', array[dir]);
  update public.usuario set activo = false where id = '00000000-0000-0000-0000-000000000001';
  begin update public.usuario set activo = false where id = '00000000-0000-0000-0000-000000000007'; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  update public.usuario set activo = true where id = '00000000-0000-0000-0000-000000000001';
  -- un director inactivo no cuenta como "otro director"
  update public.usuario set activo = false where id = '00000000-0000-0000-0000-000000000007';
  begin update public.usuario set activo = false where id = '00000000-0000-0000-0000-000000000001'; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  update public.usuario set activo = true where id = '00000000-0000-0000-0000-000000000007';
  raise notice 'OK siempre queda un Director activo';
end $$;

-- ===== 4) El puesto Director es intocable =====
do $$ declare dir bigint; oper bigint; begin
  select id into dir from public.puesto where nombre = 'Director'; select id into oper from public.puesto where nombre = 'Operador';
  begin update public.puesto set nombre = 'Jefe' where id = dir; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin update public.puesto set activo = false where id = dir; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin delete from public.puesto where id = dir; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin update public.permiso_puesto set nivel = 2 where puesto_id = dir and modulo = 'maestros'; raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin delete from public.permiso_puesto where puesto_id = dir and modulo = 'maestros'; raise exception 'NO DEBIÓ'; exception when check_violation then assert sqlerrm like '%acceso total%', sqlerrm; end;
  update public.permiso_puesto set nivel = 3 where puesto_id = dir and modulo = 'maestros';       -- dejarlo igual sí
  update public.permiso_puesto set nivel = 1 where puesto_id = oper and modulo = 'costos'; update public.permiso_puesto set nivel = 2 where puesto_id = oper and modulo = 'costos';
  raise notice 'OK el Director no se toca; los demás puestos sí';
end $$;

-- ===== 5) Actualizar maestros con motivo =====
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ declare c bigint; r record; s bigint; cb bigint; begin
  select id into c from public.cliente where nro_doc = '30755555556';
  perform public.actualizar_con_motivo('cliente', c, '{"telefono":"221-111","observacion":"nota"}');
  select * into r from public.cliente where id = c; assert r.telefono = '221-111' and r.observacion = 'nota', 'campos comunes sin motivo';
  begin perform public.actualizar_con_motivo('cliente', c, '{"nro_doc":"30755555557"}'); raise exception 'NO DEBIÓ'; exception when check_violation then assert sqlerrm like '%motivo%', sqlerrm; end;
  perform public.actualizar_con_motivo('cliente', c, '{"nro_doc":"30755555557","telefono":"221-222"}', 'Corrección del CUIT');
  select * into r from public.cliente where id = c; assert r.nro_doc = '30755555557' and r.telefono = '221-222', 'campo crítico con motivo, junto con otros';
  assert (select count(*) from public.log_auditoria where tabla = 'cliente' and campo = 'nro_doc' and valor_nuevo = '30755555557' and motivo = 'Corrección del CUIT') = 1, 'queda auditado con su motivo';
  perform public.actualizar_con_motivo('cliente', c, '{"nro_doc":"30755555556"}', 'Se restablece el CUIT original');
  perform public.actualizar_con_motivo('cliente', c, '{"observacion":null}');
  assert (select observacion from public.cliente where id = c) is null, 'un valor vacío limpia el campo';
  perform public.actualizar_con_motivo('cliente', c, '{"telefono":"221-333","inventado":"x"}');
  assert (select telefono from public.cliente where id = c) = '221-333', 'las claves que no son columnas se ignoran';
  begin perform public.actualizar_con_motivo('cliente', c, '{"inventado":"x"}'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%No hay cambios%', sqlerrm; end;
  begin perform public.actualizar_con_motivo('cliente', c, '{"id":999}'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%No hay cambios%', sqlerrm; end;
  begin perform public.actualizar_con_motivo('usuario', 1, '{"activo":false}'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%no admite%', sqlerrm; end;
  begin perform public.actualizar_con_motivo('cliente', c, '[1]'); raise exception 'NO DEBIÓ'; exception when others then assert sqlerrm like '%objeto%', sqlerrm; end;
  begin perform public.actualizar_con_motivo('cliente', c, '{"estado":"borrado"}'); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  begin perform public.actualizar_con_motivo('cliente', 999999, '{"telefono":"1"}'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;
  select id into s from public.servicio where nombre = 'Higiene mensual';
  perform public.actualizar_con_motivo('servicio', s, '{"subcategoria":"Mensual"}');
  assert (select subcategoria from public.servicio where id = s) = 'Mensual', 'también servicios';
  select id into cb from public.cuenta_bancaria where cbu = '0170000000000000000010';
  begin perform public.actualizar_con_motivo('cuenta_bancaria', cb, '{"cbu":"0170000000000000000099"}'); raise exception 'NO DEBIÓ'; exception when check_violation then null; end;
  perform public.actualizar_con_motivo('cuenta_bancaria', cb, '{"cbu":"0170000000000000000099"}', 'Cambió de cuenta');
  perform public.actualizar_con_motivo('cuenta_bancaria', cb, '{"cbu":"0170000000000000000010"}', 'Se restablece');
  raise notice 'OK actualizar maestros con motivo';
end $$;
commit;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true) as _ \gset
do $$ declare c bigint; begin
  select id into c from public.cliente where nro_doc = '30755555556';
  perform public.actualizar_con_motivo('cliente', c, '{"telefono":"221-444"}');                        -- el operador cambia lo común
  begin perform public.actualizar_con_motivo('cliente', c, '{"razon_social":"Otra SA"}', 'quiero'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then null; end;   -- lo crítico exige administrar
  raise notice 'OK el operador no cambia campos críticos';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true) as _ \gset
do $$ declare c bigint; begin
  select id into c from public.cliente where nro_doc = '30755555556';
  begin perform public.actualizar_con_motivo('cliente', c, '{"telefono":"1"}'); raise exception 'NO DEBIÓ'; exception when insufficient_privilege then assert sqlerrm like '%no tenés permiso%', sqlerrm; end;
  raise notice 'OK el lector no modifica';
end $$; rollback;

\echo 'USUARIOS Y ACTUALIZACIÓN DE MAESTROS: todas las pruebas pasaron'
