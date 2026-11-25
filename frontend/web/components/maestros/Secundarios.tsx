'use client';

import { useState } from 'react';
import { Maestro } from '@/components/crud/Maestro';
import type { Fila } from '@/components/crud/tipos';
import { fmtMoneda } from '@/lib/format';
import { nombreDe } from '@/lib/listas';
import { mensajeError } from '@/lib/errores';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/components/AuthProvider';

const ESTADOS_ACTIVO = [{ valor: 'activo', etiqueta: 'Activo' }, { valor: 'inactivo', etiqueta: 'Inactivo' }];
const principal = (f: Fila) => (f.principal ? <span className="bd ok">Principal</span> : null);

async function rpcOK(nombre: string, args: Fila) {
  const { error } = await supabase().rpc(nombre, args);
  if (error) throw error;
}

export function Establecimientos({ clienteId }: { clienteId: number }) {
  return (
    <Maestro embebido tabla="establecimiento" modulo="maestros" etiquetaNuevo="Nuevo establecimiento" filtros={{ cliente_id: clienteId }}
      fijos={{ cliente_id: clienteId }} estadoCampo="estado" nombreRegistro={(f) => f.nombre}
      columnas={[
        { clave: 'nombre', etiqueta: 'Establecimiento', render: (f) => <>{f.nombre} {principal(f)}</>, texto: (f) => f.nombre },
        { clave: 'direccion', etiqueta: 'Dirección' },
        { clave: 'localidad', etiqueta: 'Localidad', render: (f, l) => nombreDe(l, 'localidad', f.localidad_id) },
        { clave: 'estado', etiqueta: 'Estado' }]}
      campos={[
        { nombre: 'nombre', etiqueta: 'Nombre', requerido: true },
        { nombre: 'direccion', etiqueta: 'Dirección' },
        { nombre: 'localidad_id', etiqueta: 'Localidad y código postal', lista: 'localidad' },
        { nombre: 'actividad_id', etiqueta: 'Actividad / rubro', lista: 'actividad' },
        { nombre: 'contacto_local', etiqueta: 'Contacto local' },
        { nombre: 'estado', etiqueta: 'Estado', tipo: 'select', opciones: ESTADOS_ACTIVO, defecto: 'activo', requerido: true },
        { nombre: 'observacion', etiqueta: 'Observación', tipo: 'area' }]}
      acciones={[{ etiqueta: 'Hacer principal', visible: (f) => !f.principal, ejecutar: (f) => rpcOK('marcar_establecimiento_principal', { p_id: f.id }) }]} />
  );
}

export function Contactos({ clienteId }: { clienteId: number }) {
  return (
    <Maestro embebido tabla="contacto" modulo="maestros" etiquetaNuevo="Nuevo contacto" filtros={{ cliente_id: clienteId }}
      fijos={{ cliente_id: clienteId }} estadoCampo="estado" nombreRegistro={(f) => f.nombre}
      columnas={[
        { clave: 'nombre', etiqueta: 'Contacto', render: (f) => <>{f.nombre} {principal(f)}</>, texto: (f) => f.nombre },
        { clave: 'rol', etiqueta: 'Rol' }, { clave: 'telefono', etiqueta: 'Teléfono' }, { clave: 'email', etiqueta: 'E-mail' }]}
      campos={[
        { nombre: 'nombre', etiqueta: 'Nombre', requerido: true },
        { nombre: 'rol', etiqueta: 'Rol' },
        { nombre: 'telefono', etiqueta: 'Teléfono', tipo: 'telefono' },
        { nombre: 'email', etiqueta: 'E-mail', tipo: 'email' },
        { nombre: 'establecimiento_id', etiqueta: 'Establecimiento (opcional)', tipo: 'select',
          cargarOpciones: async () => {
            const { data } = await supabase().from('establecimiento').select('id, nombre').eq('cliente_id', clienteId).order('nombre');
            return ((data ?? []) as Fila[]).map((e) => ({ valor: e.id, etiqueta: e.nombre }));
          } },
        { nombre: 'estado', etiqueta: 'Estado', tipo: 'select', opciones: ESTADOS_ACTIVO, defecto: 'activo', requerido: true }]}
      acciones={[{ etiqueta: 'Hacer principal', visible: (f) => !f.principal, ejecutar: (f) => rpcOK('marcar_contacto_principal', { p_id: f.id }) }]} />
  );
}

export function CuentasBancarias({ titularTipo, titularId }: { titularTipo: 'cliente' | 'asociado' | 'proveedor'; titularId: number }) {
  return (
    <Maestro embebido tabla="cuenta_bancaria" modulo="maestros" etiquetaNuevo="Nueva cuenta" usarRpc criticos={['cbu']}
      filtros={{ titular_tipo: titularTipo, titular_id: titularId }} fijos={{ titular_tipo: titularTipo, titular_id: titularId }}
      estadoCampo="estado" nombreRegistro={(f) => f.alias || f.cbu || 'Cuenta'}
      columnas={[
        { clave: 'banco', etiqueta: 'Banco', render: (f, l) => <>{nombreDe(l, 'banco', f.banco_id)} {principal(f)}</>, texto: (f, l) => nombreDe(l, 'banco', f.banco_id) },
        { clave: 'cbu', etiqueta: 'CBU' }, { clave: 'alias', etiqueta: 'Alias' }, { clave: 'estado', etiqueta: 'Estado' }]}
      campos={[
        { nombre: 'banco_id', etiqueta: 'Banco', lista: 'banco' },
        { nombre: 'cbu', etiqueta: 'CBU (22 dígitos)', patron: /^\d{22}$/, mensajePatron: 'El CBU tiene que tener 22 dígitos.', normalizar: (t) => t.replace(/\D/g, ''), ayuda: 'Cambiarlo exige indicar un motivo.' },
        { nombre: 'alias', etiqueta: 'Alias' },
        { nombre: 'nro_cuenta', etiqueta: 'Número de cuenta' },
        { nombre: 'tipo_cuenta', etiqueta: 'Tipo', tipo: 'select', opciones: [{ valor: 'CC', etiqueta: 'Cuenta corriente' }, { valor: 'CA', etiqueta: 'Caja de ahorro' }] },
        { nombre: 'moneda', etiqueta: 'Moneda', tipo: 'select', opciones: [{ valor: 'ARS', etiqueta: 'Pesos' }, { valor: 'USD', etiqueta: 'Dólares' }], defecto: 'ARS', requerido: true },
        { nombre: 'estado', etiqueta: 'Estado', tipo: 'select', opciones: [{ valor: 'activa', etiqueta: 'Activa' }, { valor: 'inactiva', etiqueta: 'Inactiva' }], defecto: 'activa', requerido: true },
        { nombre: 'observacion', etiqueta: 'Observación', tipo: 'area' }]}
      acciones={[{ etiqueta: 'Hacer principal', visible: (f) => !f.principal, ejecutar: (f) => rpcOK('marcar_cuenta_principal', { p_id: f.id }) }]} />
  );
}

/** Los precios de un servicio no se modifican: se agrega uno nuevo con su fecha de vigencia. */
export function PreciosServicio({ servicioId, alCambiar }: { servicioId: number; alCambiar: () => void }) {
  const { puede } = useAuth();
  const [clave, setClave] = useState(0);
  const [desde, setDesde] = useState(new Date().toISOString().slice(0, 10));
  const [ars, setArs] = useState('');
  const [usd, setUsd] = useState('');
  const [err, setErr] = useState('');
  const [ok, setOk] = useState('');

  const agregar = async () => {
    setErr(''); setOk('');
    if (!desde) { setErr('Indicá desde cuándo rige el precio.'); return; }
    if (ars === '' && usd === '') { setErr('Cargá al menos un precio (en pesos o en dólares).'); return; }
    if ((ars !== '' && Number(ars) < 0) || (usd !== '' && Number(usd) < 0)) { setErr('Los precios no pueden ser negativos.'); return; }
    const { error } = await supabase().from('servicio_precio').insert({ servicio_id: servicioId, vigente_desde: desde, precio_ars: ars === '' ? 0 : Number(ars), precio_usd: usd === '' ? 0 : Number(usd) });
    if (error) { setErr(/duplicate/i.test(error.message) ? 'Ya hay un precio con esa fecha de vigencia.' : mensajeError(error)); return; }
    setArs(''); setUsd(''); setOk('Precio agregado.'); setClave((c) => c + 1); alCambiar();
  };

  return (
    <div>
      <h4 style={{ margin: '0 0 8px' }}>Precios (sin IVA)</h4>
      <p className="muted" style={{ marginTop: 0, fontSize: 12 }}>Un precio no se modifica: se agrega uno nuevo con su fecha de vigencia. Los presupuestos ya armados conservan el precio con el que se hicieron.</p>
      <Maestro key={clave} embebido tabla="servicio_precio" modulo="__solo_lectura__" orden="vigente_desde" filtros={{ servicio_id: servicioId }}
        columnas={[
          { clave: 'vigente_desde', etiqueta: 'Vigente desde' },
          { clave: 'precio_ars', etiqueta: 'Pesos', alinear: 'der', render: (f) => fmtMoneda(f.precio_ars) },
          { clave: 'precio_usd', etiqueta: 'Dólares', alinear: 'der', render: (f) => (f.precio_usd ? `US$ ${f.precio_usd}` : '—') }]}
        campos={[]} />
      {puede('maestros', 2) && (
        <div className="row" style={{ alignItems: 'flex-end', marginTop: 10 }}>
          <div className="field"><label htmlFor="pd">Vigente desde</label><input id="pd" type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></div>
          <div className="field"><label htmlFor="pa">Pesos</label><input id="pa" type="number" min={0} step="any" value={ars} onChange={(e) => setArs(e.target.value)} /></div>
          <div className="field"><label htmlFor="pu">Dólares</label><input id="pu" type="number" min={0} step="any" value={usd} onChange={(e) => setUsd(e.target.value)} /></div>
          <button className="btn p" onClick={() => void agregar()}>Agregar precio</button>
        </div>
      )}
      {err && <div className="alert" role="alert" style={{ marginTop: 8 }}>{err}</div>}
      {ok && <div className="alert info" role="status" style={{ marginTop: 8 }}>{ok}</div>}
    </div>
  );
}
