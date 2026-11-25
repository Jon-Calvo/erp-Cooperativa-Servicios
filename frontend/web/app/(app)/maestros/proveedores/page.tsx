'use client';

import { CuentasBancarias } from '@/components/maestros/Secundarios';
import { Maestro } from '@/components/crud/Maestro';
import { Pestanas } from '@/components/crud/Pestanas';
import { CAMPO_DOC, CONDICIONES_IVA } from '@/components/maestros/comunes';

const TIPOS = [{ valor: 'proveedor', etiqueta: 'Proveedor' }, { valor: 'subcontratista', etiqueta: 'Subcontratista' }, { valor: 'ambos', etiqueta: 'Ambos' }];

export default function Proveedores() {
  return (
    <Maestro titulo="Proveedores y subcontratistas" tabla="proveedor" modulo="maestros" etiquetaNuevo="Nuevo proveedor" usarRpc orden="nombre_fantasia"
      criticos={['nro_doc', 'tipo_doc', 'razon_social']} estadoCampo="estado" estadosOcultos={['inactivo']}
      busqueda={['codigo', 'nombre_fantasia', 'razon_social', 'nro_doc']} nombreRegistro={(f) => `${f.codigo} · ${f.nombre_fantasia}`}
      columnas={[
        { clave: 'codigo', etiqueta: 'Código' },
        { clave: 'nombre_fantasia', etiqueta: 'Nombre', render: (f) => <><b>{f.nombre_fantasia}</b>{f.razon_social ? <div className="muted" style={{ fontSize: 12 }}>{f.razon_social}</div> : null}</>, texto: (f) => `${f.nombre_fantasia} ${f.razon_social ?? ''}` },
        { clave: 'nro_doc', etiqueta: 'Documento', render: (f) => `${f.tipo_doc} ${f.nro_doc}` },
        { clave: 'tipo', etiqueta: 'Tipo', render: (f) => TIPOS.find((t) => t.valor === f.tipo)?.etiqueta ?? '' },
        { clave: 'estado', etiqueta: 'Estado', render: (f) => <span className={`bd ${f.estado === 'activo' ? 'ok' : 'warn'}`}>{f.estado}</span> }]}
      campos={[
        { nombre: 'nombre_fantasia', etiqueta: 'Nombre de fantasía', requerido: true },
        { nombre: 'razon_social', etiqueta: 'Razón social', ayuda: 'Cambiarla exige indicar un motivo.' },
        ...CAMPO_DOC,
        { nombre: 'condicion_iva', etiqueta: 'Condición ante IVA', tipo: 'select', opciones: CONDICIONES_IVA, requerido: true },
        { nombre: 'tipo', etiqueta: 'Tipo', tipo: 'select', opciones: TIPOS, defecto: 'proveedor', requerido: true, ayuda: 'Los subcontratos solo ofrecen subcontratistas.' },
        { nombre: 'contacto_nombre', etiqueta: 'Contacto' },
        { nombre: 'telefono', etiqueta: 'Teléfono', tipo: 'telefono' },
        { nombre: 'email', etiqueta: 'E-mail', tipo: 'email' },
        { nombre: 'estado', etiqueta: 'Estado', tipo: 'select', opciones: [{ valor: 'activo', etiqueta: 'Activo' }, { valor: 'inactivo', etiqueta: 'Inactivo' }], defecto: 'activo', requerido: true },
        { nombre: 'observacion', etiqueta: 'Observación', tipo: 'area' }]}
      detalle={(f) => <Pestanas items={[{ titulo: 'Cuentas bancarias', contenido: <CuentasBancarias titularTipo="proveedor" titularId={f.id} /> }]} />} />
  );
}
