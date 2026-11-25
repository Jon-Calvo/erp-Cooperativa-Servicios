'use client';

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { mensajeError } from '@/lib/errores';
import { useListas } from '@/lib/listas';
import { supabase } from '@/lib/supabase';
import { useAuth } from '../AuthProvider';
import { Icono } from '../Icono';
import { Formulario, estaVacio, valoresDe, valoresIniciales, validar, valorParaGuardar } from './Campo';
import { Panel } from './Panel';
import type { AccionDef, CampoDef, ColumnaDef, Fila } from './tipos';

export interface MaestroProps {
  titulo?: string;
  tabla: string;
  /** módulo cuyo permiso gobierna la pantalla (2 = puede crear y modificar) */
  modulo: string;
  columnas: ColumnaDef[];
  campos: CampoDef[];
  /** columnas donde busca el cuadro de búsqueda */
  busqueda?: string[];
  orden?: string;
  /** valores iniciales de un registro nuevo */
  nuevo?: Fila;
  /** valores fijos (por ejemplo, el cliente al que pertenece) */
  fijos?: Fila;
  /** filtros de igualdad para la lista */
  filtros?: Fila;
  /** campos críticos: cambiarlos exige un motivo (se actualizan con actualizar_con_motivo) */
  criticos?: string[];
  usarRpc?: boolean;
  detalle?: (fila: Fila, recargar: () => void) => ReactNode;
  acciones?: AccionDef[];
  cargar?: () => Promise<Fila[]>;
  estadoCampo?: string;
  estadosOcultos?: string[];
  embebido?: boolean;
  etiquetaNuevo?: string;
  nombreRegistro?: (f: Fila) => string;
  validarExtra?: (v: Fila) => string | null;
  /** se ejecuta después de crear un registro */
  alGuardar?: () => void;
}

export function Maestro(p: MaestroProps) {
  const { puede } = useAuth();
  const editable = puede(p.modulo, 2);
  const pr = useRef(p);
  pr.current = p;
  const claves = useMemo(() => [...new Set(p.campos.map((c) => c.lista).filter(Boolean) as string[])], [p.campos]);
  const listas = useListas(claves);

  const [filas, setFilas] = useState<Fila[] | null>(null);
  const [error, setError] = useState('');
  const [q, setQ] = useState('');
  const [verInactivos, setVerInactivos] = useState(false);
  const [sel, setSel] = useState<Fila | 'nuevo' | null>(null);
  const filtrosKey = JSON.stringify(p.filtros ?? {});

  const cargar = useCallback(async () => {
    const c = pr.current;
    setError('');
    try {
      if (c.cargar) { setFilas(await c.cargar()); return; }
      let consulta = supabase().from(c.tabla).select('*');
      for (const [k, v] of Object.entries(c.filtros ?? {})) consulta = consulta.eq(k, v as never);
      const { data, error: err } = await consulta.order(c.orden ?? 'id', { ascending: true }).limit(1000);
      if (err) throw err;
      setFilas((data ?? []) as Fila[]);
    } catch (e) { setError(mensajeError(e)); setFilas([]); }
  }, []);
  useEffect(() => { void cargar(); }, [cargar, filtrosKey, p.tabla]);

  const ocultos = p.estadosOcultos ?? ['baja', 'inactivo', 'inactiva'];
  const visibles = useMemo(() => {
    const t = q.trim().toLowerCase();
    return (filas ?? []).filter((f) => {
      if (p.estadoCampo && !verInactivos && ocultos.includes(String(f[p.estadoCampo]))) return false;
      if (!t) return true;
      const texto = [...(p.busqueda ?? []).map((k) => String(f[k] ?? '')), ...p.columnas.map((c) => c.texto?.(f, listas) ?? '')].join(' ').toLowerCase();
      return texto.includes(t);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filas, q, verInactivos, listas]);

  const ejecutar = async (a: AccionDef, f: Fila) => {
    try { await a.ejecutar(f); await cargar(); } catch (e) { setError(mensajeError(e)); }
  };

  return (
    <section className={p.embebido ? 'emb' : 'card'}>
      <div className="tools">
        {!p.embebido && p.titulo && <h2 style={{ margin: 0 }}>{p.titulo}</h2>}
        <input className="busca" type="search" placeholder="Buscar…" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Buscar" />
        {p.estadoCampo && <label className="chk"><input type="checkbox" checked={verInactivos} onChange={(e) => setVerInactivos(e.target.checked)} /> Ver inactivos</label>}
        <span className="muted" style={{ marginLeft: 'auto' }}>{filas ? `${visibles.length} registro${visibles.length === 1 ? '' : 's'}` : ''}</span>
        {editable && p.campos.length > 0 && <button className="btn p" onClick={() => setSel('nuevo')}><Icono n="plus" />{p.etiquetaNuevo ?? 'Nuevo'}</button>}
      </div>
      {error && <div className="alert" role="alert" style={{ marginBottom: 10 }}>{error}</div>}
      {!filas && <div className="sk" />}
      {filas && (
        <div className="tw">
          <table className="tbl lista">
            <thead><tr>{p.columnas.map((c) => <th key={c.clave} className={c.alinear === 'der' ? 'r' : ''}>{c.etiqueta}</th>)}{p.acciones && <th />}</tr></thead>
            <tbody>
              {visibles.map((f) => (
                <tr key={f.id} tabIndex={p.campos.length > 0 ? 0 : undefined} className={p.campos.length > 0 ? 'clic' : undefined} onClick={() => { if (p.campos.length > 0) setSel(f); }} onKeyDown={(e) => { if (e.key === 'Enter' && p.campos.length > 0) setSel(f); }}>
                  {p.columnas.map((c) => <td key={c.clave} className={c.alinear === 'der' ? 'r' : ''}>{c.render ? c.render(f, listas) : String(f[c.clave] ?? '')}</td>)}
                  {p.acciones && (
                    <td onClick={(e) => e.stopPropagation()} style={{ whiteSpace: 'nowrap' }}>
                      {editable && p.acciones.filter((a) => !a.visible || a.visible(f)).map((a) => (
                        <button key={a.etiqueta} className="btn sm" onClick={() => void ejecutar(a, f)}>{a.etiqueta}</button>
                      ))}
                    </td>
                  )}
                </tr>
              ))}
              {visibles.length === 0 && <tr><td colSpan={p.columnas.length + (p.acciones ? 1 : 0)} className="muted" style={{ textAlign: 'center', padding: 24 }}>No hay registros para mostrar.</td></tr>}
            </tbody>
          </table>
        </div>
      )}
      {sel && (
        <Ficha p={p} sel={sel} listas={listas} editable={editable} centrado={!!p.embebido}
               onCerrar={() => setSel(null)} onRecargar={cargar} onSel={setSel} />
      )}
    </section>
  );
}

function Ficha({ p, sel, listas, editable, centrado, onCerrar, onRecargar, onSel }: {
  p: MaestroProps; sel: Fila | 'nuevo'; listas: ReturnType<typeof useListas>; editable: boolean; centrado: boolean;
  onCerrar: () => void; onRecargar: () => Promise<void>; onSel: (f: Fila) => void;
}) {
  const nuevo = sel === 'nuevo';
  const original: Fila = nuevo ? {} : sel;
  const [v, setV] = useState<Fila>(() => (nuevo ? valoresIniciales(p.campos, p.nuevo) : valoresDe(p.campos, original)));
  const [motivo, setMotivo] = useState('');
  const [err, setErr] = useState('');
  const [ok, setOk] = useState('');
  const [guardando, setGuardando] = useState(false);

  const cambios = useMemo(() => {
    const r: Fila = {};
    for (const c of p.campos) {
      if (c.soloLectura || (c.soloAlta && !nuevo)) continue;
      if (c.visibleSi && !c.visibleSi(v)) continue;
      const nv = valorParaGuardar(c, v[c.nombre]);
      const ov = valorParaGuardar(c, original[c.nombre] ?? (c.tipo === 'check' ? false : ''));
      if (JSON.stringify(nv) !== JSON.stringify(ov)) r[c.nombre] = nv;
    }
    return r;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [v]);
  const criticoCambiado = !nuevo && p.usarRpc && (p.criticos ?? []).some((k) => k in cambios);

  const guardar = async () => {
    setErr(''); setOk('');
    const e1 = validar(p.campos, v) ?? p.validarExtra?.(v) ?? null;
    if (e1) { setErr(e1); return; }
    if (criticoCambiado && estaVacio(motivo)) { setErr('Indicá el motivo del cambio: modificás un dato crítico.'); return; }
    setGuardando(true);
    try {
      const sb = supabase();
      if (nuevo) {
        const carga: Fila = {};
        for (const c of p.campos) if (!(c.visibleSi && !c.visibleSi(v))) carga[c.nombre] = valorParaGuardar(c, v[c.nombre]);
        const { data, error } = await sb.from(p.tabla).insert({ ...carga, ...(p.fijos ?? {}) }).select().single();
        if (error) throw error;
        await onRecargar(); p.alGuardar?.();
        if (p.detalle) { onSel(data as Fila); } else onCerrar();
      } else {
        if (Object.keys(cambios).length === 0) { setOk('No hay cambios para guardar.'); setGuardando(false); return; }
        if (p.usarRpc) {
          const { error } = await sb.rpc('actualizar_con_motivo', { p_tabla: p.tabla, p_id: original.id, p_cambios: cambios, p_motivo: criticoCambiado ? motivo.trim() : null });
          if (error) throw error;
        } else {
          const { data, error } = await sb.from(p.tabla).update(cambios).eq('id', original.id).select();
          if (error) throw error;
          if (!data || data.length === 0) throw new Error('No tenés permiso para modificar este registro.');
        }
        await onRecargar();
        const { data: fresco } = await sb.from(p.tabla).select('*').eq('id', original.id).single();
        if (fresco) onSel({ ...original, ...(fresco as Fila) });
        setMotivo(''); setOk('Cambios guardados.');
      }
    } catch (e) { setErr(mensajeError(e)); }
    setGuardando(false);
  };

  const titulo = nuevo ? (p.etiquetaNuevo ?? 'Nuevo registro') : (p.nombreRegistro?.(original) ?? String(original.codigo ?? original.nombre ?? `#${original.id}`));
  return (
    <Panel titulo={titulo} onCerrar={onCerrar} centrado={centrado}>
      {!editable && <div className="alert info">Tu usuario puede ver este registro pero no modificarlo.</div>}
      <Formulario campos={p.campos} valores={v} listas={listas} deshabilitado={!editable} esNuevo={nuevo}
                  onCambio={(n, valor) => { setOk(''); setV((a) => ({ ...a, [n]: valor })); }} />
      {criticoCambiado && (
        <div className="field full"><label htmlFor="motivo">Motivo del cambio *</label>
          <input id="motivo" value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Por qué se modifica este dato" />
          <small className="ayuda">Este cambio queda registrado en la auditoría con tu usuario y este motivo.</small></div>
      )}
      {err && <div className="alert" role="alert">{err}</div>}
      {ok && <div className="alert info" role="status">{ok}</div>}
      {editable && (
        <div className="row">
          <button className="btn p" disabled={guardando} onClick={() => void guardar()}>{guardando ? 'Guardando…' : nuevo ? 'Crear' : 'Guardar cambios'}</button>
          <button className="btn" onClick={onCerrar}>{nuevo ? 'Cancelar' : 'Cerrar'}</button>
        </div>
      )}
      {!nuevo && p.detalle && <div className="sepa">{p.detalle(original, () => void onRecargar())}</div>}
    </Panel>
  );
}
