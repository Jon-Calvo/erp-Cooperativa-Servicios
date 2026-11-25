'use client';

import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/components/AuthProvider';
import { Icono } from '@/components/Icono';
import { Panel } from '@/components/crud/Panel';
import { mensajeError } from '@/lib/errores';
import { supabase } from '@/lib/supabase';

interface Puesto { id: number; nombre: string; descripcion: string | null; activo: boolean }
interface Modulo { clave: string; nombre: string }
const NIVELES = [{ v: 0, n: 'Sin acceso' }, { v: 1, n: 'Solo lectura' }, { v: 2, n: 'Operar' }, { v: 3, n: 'Administrar' }];

export default function Puestos() {
  const { puede } = useAuth();
  const admin = puede('seguridad', 3);
  const [filas, setFilas] = useState<Puesto[] | null>(null);
  const [error, setError] = useState('');
  const [sel, setSel] = useState<Puesto | 'nuevo' | null>(null);

  const cargar = useCallback(async () => {
    const { data, error: err } = await supabase().from('puesto').select('*').order('nombre');
    if (err) { setError(mensajeError(err)); setFilas([]); return; }
    setFilas((data ?? []) as Puesto[]);
  }, []);
  useEffect(() => { void cargar(); }, [cargar]);

  return (
    <section className="card">
      <div className="tools">
        <h2 style={{ margin: 0 }}>Puestos y permisos</h2>
        {admin && <button className="btn p" style={{ marginLeft: 'auto' }} onClick={() => setSel('nuevo')}><Icono n="plus" />Nuevo puesto</button>}
      </div>
      {error && <div className="alert" role="alert">{error}</div>}
      {!filas && <div className="sk" />}
      {filas && (
        <div className="tw"><table className="tbl lista">
          <thead><tr><th>Puesto</th><th>Descripción</th><th>Estado</th></tr></thead>
          <tbody>
            {filas.map((p) => (
              <tr key={p.id} tabIndex={0} className="clic" onClick={() => setSel(p)} onKeyDown={(e) => { if (e.key === 'Enter') setSel(p); }}>
                <td><b>{p.nombre}</b></td><td className="muted">{p.descripcion}</td>
                <td><span className={`bd ${p.activo ? 'ok' : 'warn'}`}>{p.activo ? 'Activo' : 'Inactivo'}</span></td>
              </tr>
            ))}
          </tbody>
        </table></div>
      )}
      {sel && <Ficha p={sel} admin={admin} onCerrar={() => setSel(null)} onListo={() => { void cargar(); }} />}
    </section>
  );
}

function Ficha({ p, admin, onCerrar, onListo }: { p: Puesto | 'nuevo'; admin: boolean; onCerrar: () => void; onListo: () => void }) {
  const nuevo = p === 'nuevo';
  const orig = nuevo ? null : p;
  const [id, setId] = useState<number | null>(orig?.id ?? null);
  const [nombre, setNombre] = useState(orig?.nombre ?? '');
  const [desc, setDesc] = useState(orig?.descripcion ?? '');
  const [activo, setActivo] = useState(orig?.activo ?? true);
  const [mods, setMods] = useState<Modulo[]>([]);
  const [niv, setNiv] = useState<Record<string, number>>({});
  const [err, setErr] = useState('');
  const [ok, setOk] = useState('');
  const esDirector = orig?.nombre === 'Director';

  useEffect(() => {
    if (id == null) return;
    const sb = supabase();
    void Promise.all([sb.from('modulo').select('clave, nombre').order('orden'), sb.from('permiso_puesto').select('modulo, nivel').eq('puesto_id', id)]).then(([m, n]) => {
      setMods((m.data ?? []) as Modulo[]);
      setNiv(Object.fromEntries(((n.data ?? []) as { modulo: string; nivel: number }[]).map((x) => [x.modulo, x.nivel])));
    });
  }, [id]);

  const guardar = async () => {
    setErr(''); setOk('');
    if (!nombre.trim()) { setErr('Completá el nombre del puesto.'); return; }
    const sb = supabase();
    if (id == null) {
      const { data, error } = await sb.from('puesto').insert({ nombre: nombre.trim(), descripcion: desc.trim() || null, activo }).select().single();
      if (error) { setErr(/duplicate/i.test(error.message) ? 'Ya existe un puesto con ese nombre.' : mensajeError(error)); return; }
      setId((data as Puesto).id); setOk('Puesto creado. Ahora definí sus permisos.'); onListo();
    } else {
      const { data, error } = await sb.from('puesto').update({ nombre: nombre.trim(), descripcion: desc.trim() || null, activo }).eq('id', id).select();
      if (error) { setErr(/duplicate/i.test(error.message) ? 'Ya existe un puesto con ese nombre.' : mensajeError(error)); return; }
      if (!data || data.length === 0) { setErr('No tenés permiso para modificar puestos.'); return; }
      setOk('Cambios guardados.'); onListo();
    }
  };

  const poner = async (modulo: string, nivel: number) => {
    if (id == null) return;
    setErr(''); setOk('');
    const { error } = await supabase().from('permiso_puesto').upsert({ puesto_id: id, modulo, nivel }, { onConflict: 'puesto_id,modulo' });
    if (error) { setErr(mensajeError(error)); return; }
    setNiv((a) => ({ ...a, [modulo]: nivel }));
  };

  const borrar = async () => {
    if (id == null || !window.confirm(`¿Borrar el puesto "${nombre}"? Se le quita a quienes lo tengan.`)) return;
    const { error } = await supabase().from('puesto').delete().eq('id', id);
    if (error) { setErr(mensajeError(error)); return; }
    onListo(); onCerrar();
  };

  return (
    <Panel titulo={nuevo && id == null ? 'Nuevo puesto' : nombre || 'Puesto'} onCerrar={onCerrar}>
      {esDirector && <div className="alert info">El Director siempre tiene acceso total: no se renombra, no se desactiva y no se le quitan permisos.</div>}
      <div className="fgrid">
        <div className="field"><label htmlFor="pn">Nombre *</label><input id="pn" value={nombre} disabled={!admin || esDirector} onChange={(e) => setNombre(e.target.value)} /></div>
        <div className="field"><label className="chk" style={{ marginTop: 22 }}><input type="checkbox" checked={activo} disabled={!admin || esDirector} onChange={(e) => setActivo(e.target.checked)} /> Puesto activo</label></div>
        <div className="field full"><label htmlFor="pd">Descripción</label><input id="pd" value={desc} disabled={!admin || esDirector} onChange={(e) => setDesc(e.target.value)} /></div>
      </div>
      {err && <div className="alert" role="alert">{err}</div>}
      {ok && <div className="alert info" role="status">{ok}</div>}
      {admin && !esDirector && <div className="row"><button className="btn p" onClick={() => void guardar()}>{id == null ? 'Crear puesto' : 'Guardar cambios'}</button>
        {id != null && <button className="btn" onClick={() => void borrar()}>Borrar puesto</button>}</div>}
      {id != null && (
        <div className="sepa">
          <h4 style={{ margin: '0 0 6px' }}>Permisos por módulo</h4>
          <p className="muted" style={{ marginTop: 0, fontSize: 12 }}>Lectura: ver. Operar: crear y modificar. Administrar: además aprobar, revertir y configurar. Se aplican al elegirlos.</p>
          <div className="tw"><table className="tbl"><tbody>
            {mods.map((m) => (
              <tr key={m.clave}><td>{m.nombre}</td>
                <td><select value={niv[m.clave] ?? 0} disabled={!admin || esDirector} onChange={(e) => void poner(m.clave, Number(e.target.value))} aria-label={`Permiso en ${m.nombre}`}>
                  {NIVELES.map((n) => <option key={n.v} value={n.v}>{n.n}</option>)}</select></td></tr>
            ))}
          </tbody></table></div>
        </div>
      )}
    </Panel>
  );
}
