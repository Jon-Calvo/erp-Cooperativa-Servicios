'use client';

import { useEffect, useMemo, useState } from 'react';
import { fmtMoneda, fmtNumero, fmtPct } from '@/lib/format';
import { supabase } from '@/lib/supabase';
import type { Kpi, KpiDetalleFila } from '@/lib/types';
import { principal, referencia } from './KpiCard';
import { Icono } from './Icono';

export function KpiDetalle({ kpi, fecha, onCerrar }: { kpi: Kpi; fecha: string; onCerrar: () => void }) {
  const [filas, setFilas] = useState<KpiDetalleFila[] | null>(null);
  const [error, setError] = useState('');
  const [abiertos, setAbiertos] = useState<Record<string, boolean>>({});

  useEffect(() => {
    let vigente = true;
    setFilas(null); setError('');
    supabase().rpc('kpi_detalle', { p_clave: kpi.clave, p_fecha: fecha }).then(({ data, error: err }) => {
      if (!vigente) return;
      if (err) setError(err.message); else setFilas((data ?? []) as KpiDetalleFila[]);
    });
    return () => { vigente = false; };
  }, [kpi.clave, fecha]);

  useEffect(() => {
    const tecla = (e: KeyboardEvent) => { if (e.key === 'Escape') onCerrar(); };
    window.addEventListener('keydown', tecla);
    return () => window.removeEventListener('keydown', tecla);
  }, [onCerrar]);

  const grupos = useMemo(() => (filas ?? []).filter((f) => f.nivel === 1), [filas]);
  const itemsDe = (g: string) => (filas ?? []).filter((f) => f.nivel === 2 && f.grupo === g);
  const esCantidad = kpi.unidad === 'cantidad' || grupos.every((g) => g.importe == null);

  return (
    <div className="ov" onClick={onCerrar} role="presentation">
      <aside className="dr" role="dialog" aria-modal="true" aria-label={`Detalle de ${kpi.titulo}`} onClick={(e) => e.stopPropagation()}>
        <div className="head">
          <div><h3>{kpi.titulo}</h3><div className="muted">{principal(kpi)}{kpi.pct != null ? ` · ${fmtPct(kpi.pct)} ${kpi.pct_etiqueta ?? ''}` : ''}</div>
            <div className="muted" style={{ fontSize: 12 }}>{referencia(kpi)}</div></div>
          <button className="ic" onClick={onCerrar} aria-label="Cerrar"><Icono n="cerrar" /></button>
        </div>
        {error && <div className="alert">{error}</div>}
        {!filas && !error && <div className="sk" />}
        {filas && grupos.length === 0 && <div className="alert info">No hay datos para mostrar en este período.</div>}
        {grupos.map((g) => {
          const items = itemsDe(g.grupo);
          const abierto = !!abiertos[g.grupo];
          return (
            <section className="gr" key={g.grupo}>
              <button className="gh" onClick={() => setAbiertos((a) => ({ ...a, [g.grupo]: !a[g.grupo] }))} aria-expanded={abierto} disabled={items.length === 0}>
                <div className="l1"><b>{g.concepto}</b><span>{esCantidad || g.importe == null ? fmtNumero(g.cantidad) : fmtMoneda(g.importe)}</span></div>
                <div className="l2">
                  <span>{g.cantidad != null && !esCantidad ? `${fmtNumero(g.cantidad)} ${g.cantidad === 1 ? 'registro' : 'registros'}` : ''}</span>
                  <span>{fmtPct(g.pct)}{items.length > 0 ? (abierto ? ' · ocultar ▴' : ' · ver detalle ▾') : ''}</span>
                </div>
                {g.pct != null && <div className="bar"><i className="bg-neutral" style={{ width: `${Math.max(0, Math.min(100, g.pct))}%` }} /></div>}
              </button>
              {abierto && items.map((it) => (
                <div className="gi" key={`${g.grupo}-${it.orden}`}>
                  <span>{it.concepto}</span>
                  <span>{it.importe != null ? fmtMoneda(it.importe) : ''}{it.pct != null ? ` · ${fmtPct(it.pct)}` : ''}</span>
                </div>
              ))}
            </section>
          );
        })}
        {filas && filas.filter((f) => f.nivel === 2).length >= 50 && (
          <p className="muted" style={{ fontSize: 12, margin: 0 }}>Cada grupo muestra hasta 50 filas, las de mayor importe primero.</p>
        )}
      </aside>
    </div>
  );
}
