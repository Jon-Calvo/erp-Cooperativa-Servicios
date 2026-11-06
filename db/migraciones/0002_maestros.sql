-- =====================================================================
-- 0002 · MAESTROS
-- Condiciones y medios de pago, categorías de gasto, clientes,
-- establecimientos, contactos, cuentas bancarias, asociados,
-- proveedores/subcontratistas, servicios (con precios versionados),
-- tipos de cambio, plantillas de presupuesto y documentos adjuntos.
-- Requiere haber aplicado 0001. Pegar TODO el archivo en SQL Editor → Run.
-- =====================================================================
begin;

do $$ begin
  if not exists (select 1 from public.migraciones where version = '0001') then
    raise exception 'Falta aplicar la migración 0001 antes de esta.';
  end if;
  if exists (select 1 from public.migraciones where version = '0002') then
    raise exception 'La migración 0002 ya fue aplicada: no se puede correr dos veces.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Listas editables: definición y valores iniciales (se pueden cambiar desde la app)
-- ---------------------------------------------------------------------
insert into public.lista (clave, nombre) values
  ('tipo_cliente',          'Tipo de cliente'),
  ('actividad',             'Actividad / rubro'),
  ('especialidad',          'Especialidad'),
  ('banco',                 'Banco'),
  ('localidad',             'Localidad – código postal'),
  ('tipo_comprobante',      'Tipo de comprobante'),
  ('motivo_rechazo',        'Motivo de rechazo de presupuesto'),
  ('categoria_monotributo', 'Categoría de monotributo'),
  ('unidad_medida',         'Unidad de medida'),
  ('categoria_servicio',    'Categoría de servicio');

insert into public.lista_valor (lista, nombre, orden) values
  ('tipo_cliente','Empresa',1),('tipo_cliente','Pyme',2),('tipo_cliente','Organismo público',3),('tipo_cliente','Particular',4),
  ('actividad','Industria',1),('actividad','Comercio',2),('actividad','Construcción',3),('actividad','Servicios',4),('actividad','Agro',5),('actividad','Salud',6),('actividad','Educación',7),('actividad','Otra',99),
  ('especialidad','Ingeniero/a en Seguridad e Higiene',1),('especialidad','Licenciado/a en Higiene y Seguridad',2),('especialidad','Técnico/a en Seguridad e Higiene',3),('especialidad','Médico/a laboral',4),('especialidad','Administrativo/a',5),
  ('banco','Banco de la Nación Argentina',1),('banco','Banco de la Provincia de Buenos Aires',2),('banco','Banco Galicia',3),('banco','Banco Santander',4),('banco','BBVA',5),('banco','Banco Macro',6),('banco','Banco Credicoop',7),('banco','ICBC',8),('banco','Banco Ciudad',9),
  ('motivo_rechazo','Precio',1),('motivo_rechazo','Plazo',2),('motivo_rechazo','Eligió otro proveedor',3),('motivo_rechazo','Sin presupuesto',4),('motivo_rechazo','Postergado',5),('motivo_rechazo','Otro',99),
  ('unidad_medida','Hora',1),('unidad_medida','Jornada',2),('unidad_medida','Visita',3),('unidad_medida','Mes',4),('unidad_medida','Informe',5),('unidad_medida','Unidad',6),('unidad_medida','Global',7),
  ('categoria_servicio','Higiene y seguridad',1),('categoria_servicio','Capacitación',2),('categoria_servicio','Mediciones',3),('categoria_servicio','Legajo técnico',4),('categoria_servicio','Asesoramiento',5),('categoria_servicio','Otros',99);

insert into public.lista_valor (lista, nombre, orden, datos) values
  ('localidad','La Plata (B1900)',1,   '{"localidad":"La Plata","cp":"B1900","provincia":"Buenos Aires"}'),
  ('localidad','Berisso (B1923)',2,    '{"localidad":"Berisso","cp":"B1923","provincia":"Buenos Aires"}'),
  ('localidad','Ensenada (B1925)',3,   '{"localidad":"Ensenada","cp":"B1925","provincia":"Buenos Aires"}'),
  ('localidad','Quilmes (B1878)',4,    '{"localidad":"Quilmes","cp":"B1878","provincia":"Buenos Aires"}'),
  ('localidad','Avellaneda (B1870)',5, '{"localidad":"Avellaneda","cp":"B1870","provincia":"Buenos Aires"}'),
  ('localidad','Ciudad de Buenos Aires (C1000)',6, '{"localidad":"Ciudad Autónoma de Buenos Aires","cp":"C1000","provincia":"CABA"}');

insert into public.lista_valor (lista, nombre, orden)
select 'categoria_monotributo', chr(64 + n), n from generate_series(1, 11) n;   -- A a K

-- Tipos de comprobante: "datos" indica clase y letra (se usan en facturación)
insert into public.lista_valor (lista, nombre, orden, datos) values
  ('tipo_comprobante','Factura A',1,        '{"clase":"factura","letra":"A"}'),
  ('tipo_comprobante','Factura B',2,        '{"clase":"factura","letra":"B"}'),
  ('tipo_comprobante','Factura C',3,        '{"clase":"factura","letra":"C"}'),
  ('tipo_comprobante','Factura E',4,        '{"clase":"factura","letra":"E"}'),
  ('tipo_comprobante','Nota de crédito A',5,'{"clase":"nc","letra":"A"}'),
  ('tipo_comprobante','Nota de crédito B',6,'{"clase":"nc","letra":"B"}'),
  ('tipo_comprobante','Nota de crédito C',7,'{"clase":"nc","letra":"C"}'),
  ('tipo_comprobante','Nota de débito A',8, '{"clase":"nd","letra":"A"}'),
  ('tipo_comprobante','Nota de débito B',9, '{"clase":"nd","letra":"B"}'),
  ('tipo_comprobante','Nota de débito C',10,'{"clase":"nd","letra":"C"}'),
  ('tipo_comprobante','Recibo',11,          '{"clase":"recibo","letra":""}'),
  ('tipo_comprobante','Ticket / otro',12,   '{"clase":"otro","letra":""}');

-- ---------------------------------------------------------------------
-- Catálogos simples
-- ---------------------------------------------------------------------
create table public.condicion_pago (
  id bigint generated always as identity primary key,
  nombre text not null unique check (btrim(nombre) <> ''),
  dias   int  not null default 0 check (dias >= 0),
  activo boolean not null default true,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now()
);
insert into public.condicion_pago (nombre, dias) values ('Contado',0),('15 días',15),('30 días',30),('45 días',45),('60 días',60);

create table public.medio_pago (
  id bigint generated always as identity primary key,
  nombre text not null unique check (btrim(nombre) <> ''),
  dias_acreditacion int not null default 0 check (dias_acreditacion >= 0),
  activo boolean not null default true,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now()
);
insert into public.medio_pago (nombre, dias_acreditacion) values ('Efectivo',0),('Transferencia',0),('E-cheq',0),('Cheque',2);

create table public.categoria_gasto (
  id bigint generated always as identity primary key,
  nombre text not null unique check (btrim(nombre) <> ''),
  afecta_margen_distribuible boolean not null default true,
  cuenta_contable text,
  activo boolean not null default true,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now()
);
insert into public.categoria_gasto (nombre, afecta_margen_distribuible) values
  ('Subcontrataciones', true), ('Viáticos y traslados', true), ('Insumos y materiales', true),
  ('Alquiler de equipos', true), ('Honorarios profesionales', true),
  ('Gastos bancarios', false), ('Impuestos y tasas', false), ('Administración', false);

create table public.tipo_cambio (               -- dólar oficial, uno por día
  fecha date primary key,
  valor numeric(18,6) not null check (valor > 0),
  creado_por uuid default auth.uid(),
  actualizado_en timestamptz not null default now()
);
create table public.tipo_cambio_promedio (      -- promedio mensual cargado aparte (no se calcula del diario)
  periodo date primary key check (periodo = date_trunc('month', periodo)::date),
  valor numeric(18,6) not null check (valor > 0),
  creado_por uuid default auth.uid(),
  actualizado_en timestamptz not null default now()
);

create table public.plantilla_presupuesto (
  id bigint generated always as identity primary key,
  nombre text not null unique check (btrim(nombre) <> ''),
  diseno text not null default 'explicativo' check (diseno in ('explicativo','compacto','otro')),
  imagen_cabecera_path text, imagen_pie_path text, marca_agua_path text,
  texto_condiciones text,
  predeterminada boolean not null default false,
  activo boolean not null default true,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now()
);
create unique index plantilla_unica_predeterminada on public.plantilla_presupuesto (predeterminada) where predeterminada;

-- ---------------------------------------------------------------------
-- Clientes, establecimientos y contactos
-- ---------------------------------------------------------------------
create table public.cliente (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  razon_social text not null check (btrim(razon_social) <> ''),
  nombre_fantasia text,
  tipo_cliente_id bigint,
  tipo_cliente_lista text generated always as ('tipo_cliente') stored,
  tipo_doc text not null default 'CUIT' check (tipo_doc in ('CUIT','CUIL','DNI','Pasaporte')),
  nro_doc text not null check (nro_doc ~ '^[0-9]{7,11}$'),          -- solo dígitos, sin guiones
  condicion_iva text not null check (condicion_iva in ('Resp. Inscripto','Monotributo','Exento','Consumidor Final')),
  domicilio_fiscal text,
  condicion_pago_id bigint references public.condicion_pago (id),
  estado text not null default 'prospecto' check (estado in ('prospecto','activo','inactivo')),
  telefono text, email text,
  observacion text,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  unique (tipo_doc, nro_doc),
  foreign key (tipo_cliente_id, tipo_cliente_lista) references public.lista_valor (id, lista)
);

create table public.establecimiento (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  cliente_id bigint not null references public.cliente (id),
  nombre text not null check (btrim(nombre) <> ''),
  direccion text,
  localidad_id bigint, localidad_lista text generated always as ('localidad') stored,
  actividad_id bigint, actividad_lista text generated always as ('actividad') stored,
  contacto_local text,
  principal boolean not null default false,
  estado text not null default 'activo' check (estado in ('activo','inactivo')),
  observacion text,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  foreign key (localidad_id, localidad_lista) references public.lista_valor (id, lista),
  foreign key (actividad_id, actividad_lista) references public.lista_valor (id, lista)
);
create unique index establecimiento_un_principal on public.establecimiento (cliente_id) where principal;
create index on public.establecimiento (cliente_id);

create table public.contacto (
  id bigint generated always as identity primary key,
  cliente_id bigint not null references public.cliente (id),
  establecimiento_id bigint references public.establecimiento (id),
  nombre text not null check (btrim(nombre) <> ''),
  rol text, telefono text, email text,
  principal boolean not null default false,
  estado text not null default 'activo' check (estado in ('activo','inactivo')),
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now()
);
create unique index contacto_un_principal on public.contacto (cliente_id) where principal;
create index on public.contacto (cliente_id);

create or replace function public.trg_contacto_coherencia() returns trigger
language plpgsql as
$$
begin
  if new.establecimiento_id is not null
     and not exists (select 1 from public.establecimiento e where e.id = new.establecimiento_id and e.cliente_id = new.cliente_id) then
    raise exception 'El establecimiento no pertenece a ese cliente.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger trg_coherencia before insert or update on public.contacto
  for each row execute function public.trg_contacto_coherencia();

-- Al crear un cliente se generan su Establecimiento principal y su Contacto principal
create or replace function public.trg_cliente_alta() returns trigger
language plpgsql security definer set search_path = public as
$$
begin
  insert into public.establecimiento (cliente_id, nombre, direccion, principal)
  values (new.id, 'Establecimiento principal', new.domicilio_fiscal, true);
  insert into public.contacto (cliente_id, nombre, telefono, email, principal)
  values (new.id, 'Contacto principal', new.telefono, new.email, true);
  return new;
end $$;
create trigger trg_cliente_alta after insert on public.cliente
  for each row execute function public.trg_cliente_alta();

-- ---------------------------------------------------------------------
-- Asociados y proveedores / subcontratistas
-- ---------------------------------------------------------------------
create table public.asociado (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  apellido_nombre text not null check (btrim(apellido_nombre) <> ''),
  tipo_doc text not null default 'CUIT' check (tipo_doc in ('CUIT','CUIL','DNI','Pasaporte')),
  nro_doc text not null check (nro_doc ~ '^[0-9]{7,11}$'),
  dni text,
  condicion_iva text not null check (condicion_iva in ('Resp. Inscripto','Monotributo','Exento','Consumidor Final')),
  fecha_nacimiento date,
  vinculo text not null check (vinculo in ('socio_cooperativo','monotributista_autonomo','ambos')),
  especialidad_id bigint, especialidad_lista text generated always as ('especialidad') stored,
  matricula text, venc_matricula date,
  logo_path text, firma_path text, texto_firma text,
  telefono text, email text, domicilio text,
  localidad_id bigint, localidad_lista text generated always as ('localidad') stored,
  estado text not null default 'activo' check (estado in ('activo','inactivo','baja')),   -- baja: no recibe nuevas asignaciones
  fecha_alta date not null default public.hoy_ar(),
  fecha_baja date,
  observacion text,
  categoria_monotributo_id bigint, categoria_monotributo_lista text generated always as ('categoria_monotributo') stored,
  periodicidad_control text not null default 'semestral' check (periodicidad_control in ('semestral','anual')),
  aniversario_periodo date,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  unique (tipo_doc, nro_doc),
  check (estado <> 'baja' or fecha_baja is not null),
  foreign key (especialidad_id, especialidad_lista) references public.lista_valor (id, lista),
  foreign key (localidad_id, localidad_lista) references public.lista_valor (id, lista),
  foreign key (categoria_monotributo_id, categoria_monotributo_lista) references public.lista_valor (id, lista)
);

-- Usuario (cuenta de acceso) y Asociado (persona del negocio) son cosas distintas; se vinculan opcionalmente
alter table public.usuario add column asociado_id bigint references public.asociado (id);
create unique index usuario_un_asociado on public.usuario (asociado_id) where asociado_id is not null;

create table public.proveedor (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  nombre_fantasia text not null check (btrim(nombre_fantasia) <> ''),
  razon_social text,
  tipo_doc text not null default 'CUIT' check (tipo_doc in ('CUIT','CUIL','DNI','Pasaporte')),
  nro_doc text not null check (nro_doc ~ '^[0-9]{7,11}$'),
  condicion_iva text not null check (condicion_iva in ('Resp. Inscripto','Monotributo','Exento','Consumidor Final')),
  tipo text not null default 'proveedor' check (tipo in ('proveedor','subcontratista','ambos')),
  contacto_nombre text, telefono text, email text,
  estado text not null default 'activo' check (estado in ('activo','inactivo')),
  observacion text,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  unique (tipo_doc, nro_doc)
);

-- ---------------------------------------------------------------------
-- Cuentas bancarias: un solo titular por cuenta (Cooperativa, cliente,
-- establecimiento, asociado o proveedor). Una principal por titular.
-- ---------------------------------------------------------------------
create table public.cuenta_bancaria (
  id bigint generated always as identity primary key,
  titular_tipo text not null check (titular_tipo in ('cooperativa','cliente','establecimiento','asociado','proveedor')),
  titular_id bigint,
  banco_id bigint, banco_lista text generated always as ('banco') stored,
  cbu text check (cbu ~ '^[0-9]{22}$'),
  alias text,
  nro_cuenta text,                                   -- p. ej. 439-0299077 (los extractos de transferencias propias lo traen en lugar del CBU)
  tipo_cuenta text check (tipo_cuenta in ('CC','CA')),
  moneda text not null default 'ARS' check (moneda in ('ARS','USD')),
  principal boolean not null default false,
  estado text not null default 'activa' check (estado in ('activa','inactiva')),
  observacion text,
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  check ((titular_tipo = 'cooperativa') = (titular_id is null)),
  foreign key (banco_id, banco_lista) references public.lista_valor (id, lista)
);
create unique index cuenta_un_principal on public.cuenta_bancaria (titular_tipo, coalesce(titular_id, 0)) where principal;
create unique index cuenta_cbu_unico on public.cuenta_bancaria (cbu) where cbu is not null;
create unique index cuenta_nro_unico on public.cuenta_bancaria (nro_cuenta) where nro_cuenta is not null;
create index on public.cuenta_bancaria (titular_tipo, titular_id);

create or replace function public.trg_cuenta_titular() returns trigger
language plpgsql security definer set search_path = public as
$$
declare v_ok boolean; v_tabla text;
begin
  if new.titular_tipo = 'cooperativa' then return new; end if;
  if new.titular_id is null then
    raise exception 'Falta indicar el titular de la cuenta (%).', new.titular_tipo using errcode = '23514';
  end if;
  v_tabla := new.titular_tipo;
  execute format('select exists (select 1 from public.%I where id = $1)', v_tabla) into v_ok using new.titular_id;
  if not v_ok then
    raise exception 'El titular (% id %) no existe.', new.titular_tipo, new.titular_id using errcode = '23503';
  end if;
  return new;
end $$;
create trigger trg_titular before insert or update of titular_tipo, titular_id on public.cuenta_bancaria
  for each row execute function public.trg_cuenta_titular();

-- ---------------------------------------------------------------------
-- Servicios y sus precios (se versionan: nunca se pisa un precio)
-- ---------------------------------------------------------------------
create table public.servicio (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  categoria_id bigint, categoria_lista text generated always as ('categoria_servicio') stored,
  subcategoria text,
  nombre text not null check (btrim(nombre) <> ''),
  descripcion text,
  unidad_id bigint, unidad_lista text generated always as ('unidad_medida') stored,
  actualizar_a_dolar boolean not null default false,
  estado text not null default 'activo' check (estado in ('activo','inactivo')),
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now(),
  foreign key (categoria_id, categoria_lista) references public.lista_valor (id, lista),
  foreign key (unidad_id, unidad_lista) references public.lista_valor (id, lista)
);

create table public.servicio_precio (
  id bigint generated always as identity primary key,
  servicio_id bigint not null references public.servicio (id),
  vigente_desde date not null,
  precio_ars numeric(18,2) not null default 0 check (precio_ars >= 0),     -- sin IVA
  precio_usd numeric(18,2) not null default 0 check (precio_usd >= 0),     -- sin IVA
  creado_por uuid default auth.uid(),
  creado_en timestamptz not null default now(),
  unique (servicio_id, vigente_desde)
);

create view public.servicio_vigente with (security_invoker = true) as
select distinct on (s.id)
       s.id as servicio_id, s.codigo, s.nombre, s.estado, s.actualizar_a_dolar,
       p.precio_ars, p.precio_usd, p.vigente_desde
  from public.servicio s
  left join public.servicio_precio p on p.servicio_id = s.id and p.vigente_desde <= public.hoy_ar()
 order by s.id, p.vigente_desde desc nulls last;

-- ---------------------------------------------------------------------
-- Documentos adjuntos (genérico: sirve a todos los módulos)
-- ---------------------------------------------------------------------
create table public.documento_adjunto (
  id bigint generated always as identity primary key,
  entidad text not null,                 -- nombre de la tabla a la que pertenece
  registro_id bigint not null,
  nombre text not null,
  storage_path text not null,
  tipo_mime text, tamano_bytes bigint,
  subido_por uuid default auth.uid(),
  creado_en timestamptz not null default now(), actualizado_en timestamptz not null default now()
);
create index on public.documento_adjunto (entidad, registro_id);

-- ---------------------------------------------------------------------
-- Códigos automáticos
-- ---------------------------------------------------------------------
create trigger trg_codigo before insert on public.cliente         for each row execute function public.trg_codigo('CLI','f');
create trigger trg_codigo before insert on public.establecimiento for each row execute function public.trg_codigo('EST','f');
create trigger trg_codigo before insert on public.asociado        for each row execute function public.trg_codigo('ASO','f');
create trigger trg_codigo before insert on public.proveedor       for each row execute function public.trg_codigo('PRV','f');
create trigger trg_codigo before insert on public.servicio        for each row execute function public.trg_codigo('SRV','f');

-- Campos críticos: exigen Administrar + motivo (ver public.set_motivo)
create trigger trg_criticos before update on public.cliente
  for each row execute function public.trg_campos_criticos('nro_doc','tipo_doc','razon_social');
create trigger trg_criticos before update on public.asociado
  for each row execute function public.trg_campos_criticos('nro_doc','tipo_doc','apellido_nombre');
create trigger trg_criticos before update on public.proveedor
  for each row execute function public.trg_campos_criticos('nro_doc','tipo_doc','razon_social');
create trigger trg_criticos before update on public.cuenta_bancaria
  for each row execute function public.trg_campos_criticos('cbu');

-- ---------------------------------------------------------------------
-- Auditoría, fecha de modificación y permisos (RLS)
-- ---------------------------------------------------------------------
select public.preparar_tabla('condicion_pago',        'maestros', 'id',      true, 3, false);
select public.preparar_tabla('medio_pago',            'maestros', 'id',      true, 3, false);
select public.preparar_tabla('categoria_gasto',       'maestros', 'id',      true, 3, false);
select public.preparar_tabla('tipo_cambio',           'maestros', 'fecha',   true, 2, false);
select public.preparar_tabla('tipo_cambio_promedio',  'maestros', 'periodo', true, 2, false);
select public.preparar_tabla('plantilla_presupuesto', 'maestros', 'id',      true, 3, false);
select public.preparar_tabla('cliente',               'maestros', 'id',      false, 2, false);
select public.preparar_tabla('establecimiento',       'maestros', 'id',      false, 2, false);
select public.preparar_tabla('contacto',              'maestros', 'id',      false, 2, false);
select public.preparar_tabla('asociado',              'maestros', 'id',      false, 2, false);
select public.preparar_tabla('proveedor',             'maestros', 'id',      false, 2, false);
select public.preparar_tabla('cuenta_bancaria',       'maestros', 'id',      false, 2, false);
select public.preparar_tabla('servicio',              'maestros', 'id',      false, 2, false);
select public.preparar_tabla('servicio_precio',       'maestros', 'id',      false, 2, false);
select public.preparar_tabla('documento_adjunto',     'maestros', 'id',      true,  2, true);

-- Los precios de servicios se versionan: solo se insertan (sin modificar ni borrar)
drop policy p_upd on public.servicio_precio;
-- Cualquier usuario activo puede adjuntar documentos (cada módulo restringirá lo suyo más adelante)
drop policy p_ins on public.documento_adjunto;
create policy p_ins on public.documento_adjunto for insert to authenticated with check (public.es_usuario_activo());
drop policy p_upd on public.documento_adjunto;
create policy p_upd on public.documento_adjunto for update to authenticated
  using (subido_por = auth.uid() or public.tiene_permiso('maestros', 3)) with check (subido_por = auth.uid() or public.tiene_permiso('maestros', 3));

-- ---------------------------------------------------------------------
-- Funciones para cambiar el elemento "principal" de forma atómica
-- ---------------------------------------------------------------------
create or replace function public.marcar_cuenta_principal(p_id bigint) returns void
language plpgsql as
$$
declare v record;
begin
  select titular_tipo, titular_id into v from public.cuenta_bancaria where id = p_id;
  if not found then raise exception 'No existe la cuenta %', p_id; end if;
  update public.cuenta_bancaria set principal = false
   where titular_tipo = v.titular_tipo and titular_id is not distinct from v.titular_id and principal and id <> p_id;
  update public.cuenta_bancaria set principal = true where id = p_id;
end $$;

create or replace function public.marcar_contacto_principal(p_id bigint) returns void
language plpgsql as
$$
declare v_cli bigint;
begin
  select cliente_id into v_cli from public.contacto where id = p_id;
  if not found then raise exception 'No existe el contacto %', p_id; end if;
  update public.contacto set principal = false where cliente_id = v_cli and principal and id <> p_id;
  update public.contacto set principal = true where id = p_id;
end $$;

create or replace function public.marcar_establecimiento_principal(p_id bigint) returns void
language plpgsql as
$$
declare v_cli bigint;
begin
  select cliente_id into v_cli from public.establecimiento where id = p_id;
  if not found then raise exception 'No existe el establecimiento %', p_id; end if;
  update public.establecimiento set principal = false where cliente_id = v_cli and principal and id <> p_id;
  update public.establecimiento set principal = true where id = p_id;
end $$;

create or replace function public.marcar_plantilla_predeterminada(p_id bigint) returns void
language plpgsql as
$$
begin
  update public.plantilla_presupuesto set predeterminada = false where predeterminada and id <> p_id;
  update public.plantilla_presupuesto set predeterminada = true where id = p_id;
end $$;

insert into public.migraciones (version, descripcion) values ('0002', 'Maestros: catálogos, clientes, establecimientos, contactos, cuentas, asociados, proveedores, servicios, tipos de cambio, plantillas, adjuntos');
commit;
