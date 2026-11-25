'use client';

import { PreciosServicio } from '@/components/maestros/Secundarios';
import { Maestro } from '@/components/crud/Maestro';
import type { Fila } from '@/components/crud/tipos';
import { fmtMoneda } from '@/lib/format';
import { nombreDe } from '@/lib/listas';
import { supabase } from '@/lib/supabase';

/** Trae los servicios con su precio vigente hoy. */
async function cargarServicios(): Promise<Fila[]> {
  const sb = supabase();
  const [s, v] = await Promise.all([sb.from('servicio').select('*').order('nombre').limit(1000), sb.from('servicio_vigente').select('servicio_id, precio_ars, precio_usd, vigente_desde')]);
  if (s.error) throw s.error;
  const precios = new Map<number, Fila>(((v.data ?? []) as Fila[]).map((x) => [x.servicio_id as number, x]));
  return ((s.data ?? []) as Fila[]).map((f) => ({ ...f, precio_ars: precios.get(f.id)?.precio_ars ?? null, precio_usd: precios.get(f.id)?.precio_usd ?? null, vigente_desde: precios.get(f.id)?.vigente_desde ?? null }));
}

export default function Servicios() {
  return (
    <Maestro titulo="Servicios" tabla="servicio" modulo="maestros" etiquetaNuevo="Nuevo servicio" usarRpc cargar={cargarServicios}
      estadoCampo="estado" estadosOcultos={['inactivo']} busqueda={['codigo', 'nombre', 'subcategoria', 'descripcion']}
      nombreRegistro={(f) => `${f.codigo} · ${f.nombre}`}
      columnas={[
        { clave: 'codigo', etiqueta: 'Código' },
        { clave: 'nombre', etiqueta: 'Servicio', render: (f, l) => <><b>{f.nombre}</b><div className="muted" style={{ fontSize: 12 }}>{nombreDe(l, 'categoria_servicio', f.categoria_id)}{f.subcategoria ? ` · ${f.subcategoria}` : ''}</div></>, texto: (f, l) => `${f.nombre} ${nombreDe(l, 'categoria_servicio', f.categoria_id)}` },
        { clave: 'unidad', etiqueta: 'Unidad', render: (f, l) => nombreDe(l, 'unidad_medida', f.unidad_id) },
        { clave: 'precio_ars', etiqueta: 'Precio vigente', alinear: 'der', render: (f) => (f.precio_ars == null ? <span className="muted">sin precio</span> : fmtMoneda(f.precio_ars)) },
        { clave: 'estado', etiqueta: 'Estado', render: (f) => <span className={`bd ${f.estado === 'activo' ? 'ok' : 'warn'}`}>{f.estado}</span> }]}
      campos={[
        { nombre: 'nombre', etiqueta: 'Nombre', requerido: true, completo: true },
        { nombre: 'categoria_id', etiqueta: 'Categoría', lista: 'categoria_servicio' },
        { nombre: 'subcategoria', etiqueta: 'Subcategoría' },
        { nombre: 'unidad_id', etiqueta: 'Unidad de medida', lista: 'unidad_medida' },
        { nombre: 'estado', etiqueta: 'Estado', tipo: 'select', opciones: [{ valor: 'activo', etiqueta: 'Activo' }, { valor: 'inactivo', etiqueta: 'Inactivo' }], defecto: 'activo', requerido: true },
        { nombre: 'descripcion', etiqueta: 'Descripción (se precarga en las líneas del presupuesto)', tipo: 'area' },
        { nombre: 'actualizar_a_dolar', etiqueta: 'Actualizar el precio con el valor del dólar', tipo: 'check' }]}
      detalle={(f, recargar) => <PreciosServicio servicioId={f.id} alCambiar={recargar} />} />
  );
}
