'use client';

import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/components/AuthProvider';
import { supabase } from '@/lib/supabase';
import type { KpiUmbral } from '@/lib/types';

interface Fila extends KpiUmbral { _ok: string; _aviso: string; _msg: string; _err: boolean }

const regla = (u: KpiUmbral) => u.sentido === 'alto_bueno'
  ? `Verde desde el valor "ok", amarillo desde "aviso", rojo por debajo (un valor alto es bueno).`
  : `Verde hasta el valor "ok", amarillo hasta "aviso", rojo por encima (un valor alto es malo).`;

export default function Indicadores() {
  const { puede } = useAuth();
  const admin = puede('organizacion', 3);
  const [filas, setFilas] = useState<Fila[] | null>(null);
  const [error, setError] = useState('');

  const cargar = useCallback(async () => {
    const { data, error: err } = await supabase().from('kpi_umbral').select('*').order('nombre');
    if (err) { setError(err.message); return; }
    setFilas(((data ?? []) as KpiUmbral[]).map((u) => ({ ...u, _ok: String(u.ok), _aviso: String(u.aviso), _msg: '', _err: false })));
  }, []);
  useEffect(() => { void cargar(); }, [cargar]);

  const poner = (clave: string, cambio: Partial<Fila>) => setFilas((fs) => (fs ?? []).map((f) => (f.clave === clave ? { ...f, ...cambio, _msg: '' } : f)));

  const guardar = async (f: Fila) => {
    const ok = Number(f._ok), aviso = Number(f._aviso);
    if (!Number.isFinite(ok) || !Number.isFinite(aviso) || ok < 0 || aviso < 0) { poner(f.clave, { _msg: 'Los valores deben ser números de 0 en adelante.', _err: true }); return; }
    if (f.sentido === 'alto_bueno' && ok < aviso) { poner(f.clave, { _msg: 'En este indicador "ok" debe ser mayor o igual que "aviso".', _err: true }); return; }
    if (f.sentido === 'alto_malo' && ok > aviso) { poner(f.clave, { _msg: 'En este indicador "ok" debe ser menor o igual que "aviso".', _err: true }); return; }
    const { data, error: err } = await supabase().from('kpi_umbral').update({ ok, aviso }).eq('clave', f.clave).select();
    if (err) { poner(f.clave, { _msg: err.message, _err: true }); return; }
    if (!data || data.length === 0) { poner(f.clave, { _msg: 'No tenés permiso para cambiar los umbrales.', _err: true }); return; }
    poner(f.clave, { ok, aviso, _msg: 'Guardado.', _err: false });
  };

  return (
    <div className="cfg">
      <section className="card">
        <h2>Umbrales de los indicadores</h2>
        <p className="muted" style={{ marginTop: 0 }}>Definen cuándo cada indicador se ve verde, amarillo o rojo. Los valores iniciales son una propuesta para ajustar a la realidad de la cooperativa.</p>
        {!admin && <div className="alert info" style={{ marginBottom: 12 }}>Solo quien administra la organización puede cambiar los umbrales.</div>}
        {error && <div className="alert">{error}</div>}
        {!filas && !error && <div className="sk" />}
        {filas && (
          <div className="tw">
            <table className="tbl">
              <thead><tr><th>Indicador</th><th>Unidad</th><th>Ok</th><th>Aviso</th><th /></tr></thead>
              <tbody>
                {filas.map((f) => (
                  <tr key={f.clave}>
                    <td><b>{f.nombre}</b><div className="muted" style={{ fontSize: 12 }}>{regla(f)}</div>
                      {f._msg && <div style={{ fontSize: 12 }} className={f._err ? 't-bad' : 't-ok'} role="status">{f._msg}</div>}</td>
                    <td>{f.unidad === 'porcentaje' ? '%' : 'cantidad'}</td>
                    <td><input type="number" min={0} step="any" value={f._ok} disabled={!admin} onChange={(e) => poner(f.clave, { _ok: e.target.value })} aria-label={`${f.nombre}: valor ok`} /></td>
                    <td><input type="number" min={0} step="any" value={f._aviso} disabled={!admin} onChange={(e) => poner(f.clave, { _aviso: e.target.value })} aria-label={`${f.nombre}: valor de aviso`} /></td>
                    <td><button className="btn" disabled={!admin || (f._ok === String(f.ok) && f._aviso === String(f.aviso))} onClick={() => void guardar(f)}>Guardar</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
