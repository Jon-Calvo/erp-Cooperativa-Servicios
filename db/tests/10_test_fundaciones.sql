\set ON_ERROR_STOP on
\set U1 '''00000000-0000-0000-0000-000000000001'''
\set U2 '''00000000-0000-0000-0000-000000000002'''
\set U3 '''00000000-0000-0000-0000-000000000003'''
\set U4 '''00000000-0000-0000-0000-000000000004'''

-- 1) Antes del administrador inicial nadie tiene permisos
do $$ begin assert not public.tiene_permiso('maestros',1), 'sin usuarios no debe haber permisos'; end $$;

-- 2) Numeración
do $$ declare a text; b text; c text; d text; y text := extract(year from public.hoy_ar())::text; begin
  a := public.siguiente_codigo('TST'); b := public.siguiente_codigo('TST');
  c := public.siguiente_codigo('DOC', true); d := public.siguiente_codigo('DOC', true);
  assert a = 'TST-00001' and b = 'TST-00002', 'maestro continuo: ' || a || ' ' || b;
  assert c = 'DOC-' || y || '-00001' and d = 'DOC-' || y || '-00002', 'documento con año: ' || c || ' ' || d;
  raise notice 'OK numeración (% % % %)', a, b, c, d;
end $$;

-- 3) Condición ante IVA de la Cooperativa con historial
do $$ begin
  assert public.condicion_iva_coop() = 'Resp. Inscripto', 'hoy es Resp. Inscripto';
  insert into public.organizacion_condicion_iva values (date '2099-01-01', 'Exento');
  assert public.condicion_iva_coop(date '2099-02-01') = 'Exento', 'condición futura';
  assert public.condicion_iva_coop() = 'Resp. Inscripto', 'hoy sigue igual';
  assert public.condicion_iva_coop(date '2010-05-05') = 'Resp. Inscripto', 'histórico';
  delete from public.organizacion_condicion_iva where desde = date '2099-01-01';
  raise notice 'OK condición IVA con historial';
end $$;

-- 4) Administrador inicial
select public.inicializar_admin('admin@coop.test');
do $$ begin
  begin perform public.inicializar_admin('admin@coop.test'); raise exception 'NO DEBIÓ';
  exception when others then assert sqlerrm like 'Ya hay usuarios%', sqlerrm; end;
  raise notice 'OK administrador inicial una sola vez';
end $$;
begin; set local role authenticated;
do $$ begin
  begin perform public.inicializar_admin('x@y.z'); raise exception 'NO DEBIÓ';
  exception when insufficient_privilege then null; end;
  raise notice 'OK un usuario común no puede crear administradores';
end $$; rollback;

-- 5) Puestos, permisos y excepciones
insert into public.puesto (nombre) values ('Lector'), ('Operador');
insert into public.usuario (id, nombre, activo) values (:U2, 'Lector', true), (:U3, 'Operador', true), (:U4, 'Inactivo', false);
insert into public.usuario_puesto select :U2, id from public.puesto where nombre = 'Lector';
insert into public.usuario_puesto select :U3, id from public.puesto where nombre = 'Operador';
insert into public.usuario_puesto select :U4, id from public.puesto where nombre = 'Operador';
insert into public.permiso_puesto select p.id, 'maestros', 1 from public.puesto p where nombre = 'Lector';
insert into public.permiso_puesto select p.id, 'maestros', 2 from public.puesto p where nombre = 'Operador';
insert into public.permiso_puesto select p.id, 'costos',   2 from public.puesto p where nombre = 'Operador';

begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true);
do $$ begin
  assert public.tiene_permiso('maestros',3) and public.tiene_permiso('contabilidad',3), 'Director: todo';
  raise notice 'OK Director con acceso total'; end $$; rollback;

begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true);
do $$ begin
  assert public.tiene_permiso('maestros',1) and not public.tiene_permiso('maestros',2), 'lector: solo lectura';
  assert not public.tiene_permiso('costos',1), 'lector sin costos';
  raise notice 'OK permisos por puesto'; end $$; rollback;

-- excepción por usuario: sube a operar en costos y baja a 0 en maestros
insert into public.permiso_usuario values (:U2, 'costos', 2), (:U3, 'maestros', 0);
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true);
do $$ begin assert public.tiene_permiso('costos',2), 'excepción sube'; end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U3, true);
do $$ begin assert not public.tiene_permiso('maestros',1), 'excepción baja a 0 aunque el puesto dé 2';
  assert public.tiene_permiso('costos',2), 'el resto sigue por puesto';
  raise notice 'OK excepciones por usuario'; end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U4, true);
do $$ begin assert not public.tiene_permiso('costos',1), 'usuario inactivo sin permisos'; raise notice 'OK usuario inactivo'; end $$; rollback;

-- 6) RLS
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true);
do $$ declare n int; begin
  insert into public.lista (clave, nombre) values ('x','X');  -- debe fallar: lector no administra listas
  raise exception 'NO DEBIÓ';
exception when insufficient_privilege then null; end $$;
rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U2, true);
do $$ declare n int; begin
  select count(*) into n from public.usuario; assert n = 1, 'cada usuario ve solo su fila, ve ' || n;
  select count(*) into n from public.organizacion; assert n = 1, 'lectura libre de organización';
  begin perform * from public.contador; exception when insufficient_privilege then null; end;
  select count(*) into n from public.contador; assert n = 0, 'contador no se puede leer';
  select count(*) into n from public.log_auditoria; assert n = 0, 'sin permiso de auditoría no ve el log';
  raise notice 'OK RLS de lectura'; end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true);
do $$ declare n int; begin
  insert into public.lista (clave, nombre) values ('x','X');
  update public.puesto set descripcion = 'cambio auditado' where nombre = 'Operador';
  select count(*) into n from public.usuario; assert n = 4, 'el administrador ve todos: ' || n;
  select count(*) into n from public.log_auditoria where tabla = 'puesto' and campo = 'descripcion' and usuario_id = auth.uid();
  assert n = 1, 'el cambio queda en la auditoría con su autor';
  raise notice 'OK administración y auditoría'; end $$; rollback;

-- 7) Un visitante anónimo no puede consumir números ni usar utilidades de administración
begin; set local role anon;
do $$ begin
  begin perform public.siguiente_codigo('HACK'); raise exception 'NO DEBIÓ';
  exception when insufficient_privilege then null; end;
  raise notice 'OK anónimo sin acceso a la numeración';
end $$; rollback;
begin; set local role authenticated; select set_config('request.jwt.claim.sub', :U1, true) as _ \gset
do $$ begin
  begin perform public.preparar_tabla('lista','maestros'); raise exception 'NO DEBIÓ';
  exception when insufficient_privilege then null; end;
  raise notice 'OK las utilidades de administración no se exponen';
end $$; rollback;

\echo 'FUNDACIONES: todas las pruebas pasaron'
