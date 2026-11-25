'use client';

import { CuentasBancarias } from '@/components/maestros/Secundarios';
import { Maestro } from '@/components/crud/Maestro';
import { Pestanas } from '@/components/crud/Pestanas';
import { nombreDe } from '@/lib/listas';
import { CAMPO_DOC, CONDICIONES_IVA } from '@/components/maestros/comunes';

const VINCULOS = [{ valor: 'socio_cooperativo', etiqueta: 'Socio cooperativo' }, { valor: 'monotributista_autonomo', etiqueta: 'Monotributista / autónomo' }, { valor: 'ambos', etiqueta: 'Ambos' }];
const ESTADOS = [{ valor: 'activo', etiqueta: 'Activo' }, { valor: 'inactivo', etiqueta: 'Inactivo' }, { valor: 'baja', etiqueta: 'Baja' }];
const tono = (e: string) => (e === 'activo' ? 'ok' : e === 'baja' ? 'bad' : 'warn');

export default function Asociados() {
  return (
    <Maestro titulo="Asociados" tabla="asociado" modulo="maestros" etiquetaNuevo="Nuevo asociado" usarRpc orden="apellido_nombre"
      criticos={['nro_doc', 'tipo_doc', 'apellido_nombre']} estadoCampo="estado" estadosOcultos={['baja']}
      busqueda={['codigo', 'apellido_nombre', 'nro_doc', 'matricula']}
      nombreRegistro={(f) => `${f.codigo} · ${f.apellido_nombre}`}
      columnas={[
        { clave: 'codigo', etiqueta: 'Código' },
        { clave: 'apellido_nombre', etiqueta: 'Apellido y nombre', render: (f) => <b>{f.apellido_nombre}</b>, texto: (f) => f.apellido_nombre },
        { clave: 'nro_doc', etiqueta: 'Documento', render: (f) => `${f.tipo_doc} ${f.nro_doc}` },
        { clave: 'vinculo', etiqueta: 'Vínculo', render: (f) => VINCULOS.find((v) => v.valor === f.vinculo)?.etiqueta ?? '' },
        { clave: 'especialidad', etiqueta: 'Especialidad', render: (f, l) => nombreDe(l, 'especialidad', f.especialidad_id) },
        { clave: 'estado', etiqueta: 'Estado', render: (f) => <span className={`bd ${tono(f.estado)}`}>{f.estado}</span> }]}
      campos={[
        { nombre: 'apellido_nombre', etiqueta: 'Apellido y nombre', requerido: true, completo: true, ayuda: 'Cambiarlo exige indicar un motivo.' },
        ...CAMPO_DOC,
        { nombre: 'dni', etiqueta: 'DNI' },
        { nombre: 'fecha_nacimiento', etiqueta: 'Fecha de nacimiento', tipo: 'fecha' },
        { nombre: 'condicion_iva', etiqueta: 'Condición ante IVA', tipo: 'select', opciones: CONDICIONES_IVA, requerido: true, ayuda: 'Define el IVA sugerido cuando emite presupuestos y facturas.' },
        { nombre: 'vinculo', etiqueta: 'Vínculo con la Cooperativa', tipo: 'select', opciones: VINCULOS, requerido: true },
        { nombre: 'especialidad_id', etiqueta: 'Especialidad', lista: 'especialidad' },
        { nombre: 'matricula', etiqueta: 'Matrícula' },
        { nombre: 'venc_matricula', etiqueta: 'Vencimiento de la matrícula', tipo: 'fecha', ayuda: 'Genera un recordatorio en el Calendario.' },
        { nombre: 'telefono', etiqueta: 'Teléfono', tipo: 'telefono' },
        { nombre: 'email', etiqueta: 'E-mail', tipo: 'email' },
        { nombre: 'domicilio', etiqueta: 'Domicilio', completo: true },
        { nombre: 'localidad_id', etiqueta: 'Localidad y código postal', lista: 'localidad' },
        { nombre: 'estado', etiqueta: 'Estado', tipo: 'select', opciones: ESTADOS, defecto: 'activo', requerido: true, ayuda: 'Una baja no recibe nuevas asignaciones.' },
        { nombre: 'fecha_baja', etiqueta: 'Fecha de baja', tipo: 'fecha', visibleSi: (v) => v.estado === 'baja', requeridoSi: (v) => v.estado === 'baja' },
        { nombre: 'categoria_monotributo_id', etiqueta: 'Categoría de monotributo', lista: 'categoria_monotributo', visibleSi: (v) => v.condicion_iva === 'Monotributo' },
        { nombre: 'periodicidad_control', etiqueta: 'Control del monotributo', tipo: 'select', opciones: [{ valor: 'semestral', etiqueta: 'Semestral' }, { valor: 'anual', etiqueta: 'Anual' }], defecto: 'semestral', visibleSi: (v) => v.condicion_iva === 'Monotributo' },
        { nombre: 'aniversario_periodo', etiqueta: 'Aniversario del período', tipo: 'fecha', visibleSi: (v) => v.condicion_iva === 'Monotributo', ayuda: 'Desde esta fecha corre su período de control; sin fecha, rige el año calendario.' },
        { nombre: 'observacion', etiqueta: 'Observación', tipo: 'area' }]}
      detalle={(f) => <Pestanas items={[{ titulo: 'Cuentas bancarias', contenido: <CuentasBancarias titularTipo="asociado" titularId={f.id} /> }]} />} />
  );
}
