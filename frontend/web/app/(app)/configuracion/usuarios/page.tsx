'use client';

import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/components/AuthProvider';
import { Icono } from '@/components/Icono';
import { Panel } from '@/components/crud/Panel';
import { mensajeError } from '@/lib/errores';
import { supabase } from '@/lib/supabase';

interface Usuario { usuario_id: string; email: string | null; nombre: string; activo: boolean; asociado_id: number | null; asociado: string | null; puestos: string[]; puestos_ids: number[]; ultimo_ingreso: string | null }
interface Puesto { id: number; nombre: string }
interface Modulo { clave: string; nombre: string }
interface Asociado { id: number; apellido_nombre: string }
const NIVELES = [{ v: 0, n: 'Sin acceso' }, { v: 1, n: 'Solo lectura' }, { v: 2, n: 'Operar' }, { v: 3, n: 'Administrar' }];

const fecha = (iso: string | null) => (iso ? new Date(iso).toLocaleString('es-AR', { dateStyle: 'short', timeStyle: 'short' }) : 'Nunca');

export default function Usuarios() {
  const { puede, perfil, refrescar } = useAuth();
  const admin = puede('seguridad', 3);
  const [filas, setFilas] = useState<Usuario[] | null>(null);
  const [puestos, setPuestos] = useState<Puesto[]>([]);
  const [asociados, setAsociados] = useState<Asociado[]>([]);
  const [error, setError] = useState('');
  const [sel, setSel] = useState<Usuario | 'nuevo' | null>(null);

  const cargar = useCallback(async () => {
    setError('');
    const sb = supabase();
    const [u, p, a] = await Promise.all([sb.rpc('lista_usuarios'), sb.from('puesto').select('id, nombre').order('nombre'), sb.from('asociado').select('id, apellido_nombre').neq('estado', 'baja').order('apellido_nombre')]);
    if (u.error) { setError(mensajeError(u.error)); setFilas([]); return; }
    setFilas((u.data ?? []) as Usuario[]); setPuestos((p.data ?? []) as Puesto[]); setAsociados((a.data ?? []) as Asociado[]);
  }, []);
  useEffect(() => { void cargar(); }, [cargar]);

  return (
    <section className="card">
      <div className="tools">
        <h2 style={{ margin: 0 }}>Usuarios</h2>
        <span className="muted" style={{ marginLeft: 'auto' }}>{filas ? `${filas.length} usuario${filas.length === 1 ? '' : 's'}` : ''}</span>
        {admin && <button className="btn p" onClick={() => setSel('nuevo')}><Icono n="plus" />Alta de usuario</button>}
      </div>
      {error && <div className="alert" role="alert">{error}</div>}
      {!filas && <div className="sk" />}
      {filas && (
        <div className="tw"><table className="tbl lista">
          <thead><tr><th>Usuario</th><th>Puestos</th><th>Asociado</th><th>Último ingreso</th><th>Estado</th></tr></thead>
          <tbody>
            {filas.map((u) => (
              <tr key={u.usuario_id} tabIndex={0} className="clic" onClick={() => setSel(u)} onKeyDown={(e) => { if (e.key === 'Enter') setSel(u); }}>
                <td><b>{u.nombre}</b><div className="muted" style={{ fontSize: 12 }}>{u.email}</div></td>
                <td>{u.puestos.length ? u.puestos.map((x) => <span key={x} className="pill" style={{ marginRight: 4 }}>{x}</span>) : <span className="muted">sin puestos</span>}</td>
                <td>{u.asociado ?? <span className="muted">—</span>}</td>
                <td>{fecha(u.ultimo_ingreso)}</td>
                <td><span className={`bd ${u.activo ? 'ok' : 'warn'}`}>{u.activo ? 'Activo' : 'Inactivo'}</span></td>
              </tr>
            ))}
          </tbody>
        </table></div>
      )}
      {sel === 'nuevo' && <Alta puestos={puestos} asociados={asociados} onCerrar={() => setSel(null)} onListo={() => { setSel(null); void cargar(); }} />}
      {sel && sel !== 'nuevo' && (
        <Edicion u={sel} puestos={puestos} asociados={asociados} admin={admin} esYo={sel.usuario_id === perfil?.usuario_id}
                 onCerrar={() => setSel(null)} onListo={async () => { await cargar(); await refrescar(); }} />
      )}
    </section>
  );
}

function ChecksPuestos({ puestos, valor, onCambio, off }: { puestos: Puesto[]; valor: number[]; onCambio: (v: number[]) => void; off?: boolean }) {
  return (
    <div className="checks">
      {puestos.map((p) => (
        <label key={p.id} className="chk"><input type="checkbox" disabled={off} checked={valor.includes(p.id)}
          onChange={(e) => onCambio(e.target.checked ? [...valor, p.id] : valor.filter((x) => x !== p.id))} /> {p.nombre}</label>
      ))}
    </div>
  );
}

function Alta({ puestos, asociados, onCerrar, onListo }: { puestos: Puesto[]; asociados: Asociado[]; onCerrar: () => void; onListo: () => void }) {
  const [email, setEmail] = useState('');
  const [nombre, setNombre] = useState('');
  const [ps, setPs] = useState<number[]>([]);
  const [asoc, setAsoc] = useState('');
  const [err, setErr] = useState('');
  const [enviando, setEnviando] = useState(false);
  const dar = async () => {
    setErr('');
    if (!email.trim()) { setErr('Indicá el e-mail.'); return; }
    setEnviando(true);
    const { error } = await supabase().rpc('alta_usuario', { p_email: email.trim(), p_nombre: nombre.trim() || null, p_puestos: ps, p_asociado_id: asoc ? Number(asoc) : null });
    setEnviando(false);
    if (error) { setErr(mensajeError(error)); return; }
    onListo();
  };
  return (
    <Panel titulo="Alta de usuario" onCerrar={onCerrar} centrado>
      <div className="alert info">Primero creá a la persona en Supabase → <b>Authentication → Users → Add user</b> (e-mail y contraseña). Después completá acá su alta en el sistema.</div>
      <div className="fgrid">
        <div className="field full"><label htmlFor="ae">E-mail (el mismo de Authentication) *</label><input id="ae" type="email" value={email} onChange={(e) => setEmail(e.target.value)} /></div>
        <div className="field full"><label htmlFor="an">Nombre</label><input id="an" value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="Si lo dejás vacío se usa el e-mail" /></div>
        <div className="field full"><label>Puestos</label><ChecksPuestos puestos={puestos} valor={ps} onCambio={setPs} /></div>
        <div className="field full"><label htmlFor="aa">Asociado vinculado (opcional)</label>
          <select id="aa" value={asoc} onChange={(e) => setAsoc(e.target.value)}><option value="">— ninguno —</option>{asociados.map((a) => <option key={a.id} value={a.id}>{a.apellido_nombre}</option>)}</select>
          <small className="ayuda">Un asociado vinculado ve su propia cuenta corriente y su monotributo.</small></div>
      </div>
      {err && <div className="alert" role="alert">{err}</div>}
      <div className="row"><button className="btn p" disabled={enviando} onClick={() => void dar()}>{enviando ? 'Guardando…' : 'Dar de alta'}</button><button className="btn" onClick={onCerrar}>Cancelar</button></div>
    </Panel>
  );
}

function Edicion({ u, puestos, asociados, admin, esYo, onCerrar, onListo }: { u: Usuario; puestos: Puesto[]; asociados: Asociado[]; admin: boolean; esYo: boolean; onCerrar: () => void; onListo: () => Promise<void> }) {
  const [nombre, setNombre] = useState(u.nombre);
  const [activo, setActivo] = useState(u.activo);
  const [asoc, setAsoc] = useState(u.asociado_id ? String(u.asociado_id) : '');
  const [ps, setPs] = useState<number[]>(u.puestos_ids);
  const [mods, setMods] = useState<Modulo[]>([]);
  const [exc, setExc] = useState<Record<string, number>>({});
  const [err, setErr] = useState('');
  const [ok, setOk] = useState('');
  const [guardando, setGuardando] = useState(false);

  useEffect(() => {
    const sb = supabase();
    void Promise.all([sb.from('modulo').select('clave, nombre').order('orden'), sb.from('permiso_usuario').select('modulo, nivel').eq('usuario_id', u.usuario_id)]).then(([m, e]) => {
      setMods((m.data ?? []) as Modulo[]);
      setExc(Object.fromEntries(((e.data ?? []) as { modulo: string; nivel: number }[]).map((x) => [x.modulo, x.nivel])));
    });
  }, [u.usuario_id]);

  const guardar = async () => {
    setErr(''); setOk(''); setGuardando(true);
    try {
      const sb = supabase();
      const { data, error } = await sb.from('usuario').update({ nombre: nombre.trim() || u.nombre, activo, asociado_id: asoc ? Number(asoc) : null }).eq('id', u.usuario_id).select();
      if (error) throw error;
      if (!data || data.length === 0) throw new Error('No tenés permiso para modificar usuarios.');
      const r = await sb.rpc('set_puestos_usuario', { p_usuario: u.usuario_id, p_puestos: ps });
      if (r.error) throw r.error;
      await onListo(); setOk('Cambios guardados.');
    } catch (e) { setErr(mensajeError(e)); }
    setGuardando(false);
  };

  const cambiarExc = async (modulo: string, valor: string) => {
    setErr(''); setOk('');
    const sb = supabase();
    try {
      if (valor === '') {
        const { error } = await sb.from('permiso_usuario').delete().eq('usuario_id', u.usuario_id).eq('modulo', modulo); if (error) throw error;
        setExc((a) => { const b = { ...a }; delete b[modulo]; return b; });
      } else {
        const { error } = await sb.from('permiso_usuario').upsert({ usuario_id: u.usuario_id, modulo, nivel: Number(valor) }, { onConflict: 'usuario_id,modulo' }); if (error) throw error;
        setExc((a) => ({ ...a, [modulo]: Number(valor) }));
      }
      await onListo();
    } catch (e) { setErr(mensajeError(e)); }
  };

  return (
    <Panel titulo={u.nombre} onCerrar={onCerrar}>
      <div className="muted">{u.email}</div>
      {!admin && <div className="alert info">Podés ver este usuario pero no modificarlo.</div>}
      <div className="fgrid">
        <div className="field full"><label htmlFor="en">Nombre</label><input id="en" value={nombre} disabled={!admin} onChange={(e) => setNombre(e.target.value)} /></div>
        <div className="field"><label className="chk"><input type="checkbox" checked={activo} disabled={!admin || esYo} onChange={(e) => setActivo(e.target.checked)} /> Usuario activo</label>
          {esYo && <small className="ayuda">No podés desactivarte a vos mismo.</small>}</div>
        <div className="field"><label htmlFor="ea">Asociado vinculado</label>
          <select id="ea" value={asoc} disabled={!admin} onChange={(e) => setAsoc(e.target.value)}><option value="">— ninguno —</option>{asociados.map((a) => <option key={a.id} value={a.id}>{a.apellido_nombre}</option>)}</select></div>
        <div className="field full"><label>Puestos</label><ChecksPuestos puestos={puestos} valor={ps} onCambio={setPs} off={!admin} />
          <small className="ayuda">Los permisos salen de sus puestos; si tiene varios, rige el mayor nivel de cada módulo. Siempre debe quedar un Director activo.</small></div>
      </div>
      {err && <div className="alert" role="alert">{err}</div>}
      {ok && <div className="alert info" role="status">{ok}</div>}
      {admin && <div className="row"><button className="btn p" disabled={guardando} onClick={() => void guardar()}>{guardando ? 'Guardando…' : 'Guardar cambios'}</button></div>}
      <div className="sepa">
        <h4 style={{ margin: '0 0 6px' }}>Excepciones de permisos de esta persona</h4>
        <p className="muted" style={{ marginTop: 0, fontSize: 12 }}>Pisan lo que dan sus puestos, módulo por módulo. Se aplican al elegirlas.</p>
        <div className="tw"><table className="tbl">
          <tbody>
            {mods.map((m) => (
              <tr key={m.clave}><td>{m.nombre}</td>
                <td><select value={exc[m.clave] === undefined ? '' : String(exc[m.clave])} disabled={!admin} onChange={(e) => void cambiarExc(m.clave, e.target.value)} aria-label={`Excepción en ${m.nombre}`}>
                  <option value="">Según sus puestos</option>{NIVELES.map((n) => <option key={n.v} value={n.v}>{n.n}</option>)}</select></td></tr>
            ))}
          </tbody>
        </table></div>
      </div>
    </Panel>
  );
}
