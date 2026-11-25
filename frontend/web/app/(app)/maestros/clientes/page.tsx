'use client';

import { CuentasBancarias, Contactos, Establecimientos } from '@/components/maestros/Secundarios';
import { Maestro } from '@/components/crud/Maestro';
import { Pestanas } from '@/components/crud/Pestanas';
import { CAMPO_DOC, CONDICIONES_IVA } from '@/components/maestros/comunes';
import { nombreDe } from '@/lib/listas';
import { supabase } from '@/lib/supabase';

const ESTADOS = [{ valor: 'prospecto', etiqueta: 'Prospecto' }, { valor: 'activo', etiqueta: 'Activo' }, { valor: 'inactivo', etiqueta: 'Inactivo' }];
const tono = (e: string) => (e === 'activo' ? 'ok' : e === 'prospecto' ? 'info' : 'warn');

export default function Clientes() {
  return (
    <Maestro titulo="Clientes" tabla="cliente" modulo="maestros" etiquetaNuevo="Nuevo cliente" usarRpc orden="razon_social"
      criticos={['nro_doc', 'tipo_doc', 'razon_social']} estadoCampo="estado" estadosOcultos={['inactivo']}
      busqueda={['codigo', 'razon_social', 'nombre_fantasia', 'nro_doc']} nuevo={{ estado: 'prospecto' }}
      nombreRegistro={(f) => `${f.codigo} · ${f.razon_social}`}
      columnas={[
        { clave: 'codigo', etiqueta: 'Código' },
        { clave: 'razon_social', etiqueta: 'Razón social', render: (f) => <><b>{f.razon_social}</b>{f.nombre_fantasia ? <div className="muted" style={{ fontSize: 12 }}>{f.nombre_fantasia}</div> : null}</>, texto: (f) => `${f.razon_social} ${f.nombre_fantasia ?? ''}` },
        { clave: 'nro_doc', etiqueta: 'Documento', render: (f) => `${f.tipo_doc} ${f.nro_doc}` },
        { clave: 'tipo', etiqueta: 'Tipo', render: (f, l) => nombreDe(l, 'tipo_cliente', f.tipo_cliente_id) },
        { clave: 'estado', etiqueta: 'Estado', render: (f) => <span className={`bd ${tono(f.estado)}`}>{f.estado}</span> }]}
      campos={[
        { nombre: 'razon_social', etiqueta: 'Razón social', requerido: true, completo: true, ayuda: 'Cambiarla exige indicar un motivo.' },
        { nombre: 'nombre_fantasia', etiqueta: 'Nombre de fantasía' },
        { nombre: 'tipo_cliente_id', etiqueta: 'Tipo de cliente', lista: 'tipo_cliente' },
        ...CAMPO_DOC,
        { nombre: 'condicion_iva', etiqueta: 'Condición ante IVA', tipo: 'select', opciones: CONDICIONES_IVA, requerido: true },
        { nombre: 'domicilio_fiscal', etiqueta: 'Domicilio fiscal', completo: true },
        { nombre: 'condicion_pago_id', etiqueta: 'Condición de pago', tipo: 'select',
          cargarOpciones: async () => { const { data } = await supabase().from('condicion_pago').select('id, nombre').eq('activo', true).order('dias'); return (data ?? []).map((c) => ({ valor: c.id as number, etiqueta: c.nombre as string })); } },
        { nombre: 'estado', etiqueta: 'Estado', tipo: 'select', opciones: ESTADOS, requerido: true, ayuda: 'Un prospecto pasa a activo al aprobarse su primer presupuesto.' },
        { nombre: 'telefono', etiqueta: 'Teléfono', tipo: 'telefono' },
        { nombre: 'email', etiqueta: 'E-mail', tipo: 'email' },
        { nombre: 'observacion', etiqueta: 'Observación', tipo: 'area' }]}
      detalle={(f) => (
        <Pestanas items={[
          { titulo: 'Establecimientos', contenido: <Establecimientos clienteId={f.id} /> },
          { titulo: 'Contactos', contenido: <Contactos clienteId={f.id} /> },
          { titulo: 'Cuentas bancarias', contenido: <CuentasBancarias titularTipo="cliente" titularId={f.id} /> }]} />
      )} />
  );
}
