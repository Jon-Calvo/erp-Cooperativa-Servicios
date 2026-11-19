'use client';

import { fmtMoneda, fmtNumero, fmtPct } from '@/lib/format';
import type { Kpi } from '@/lib/types';

/** Indicadores donde subir es malo: la variación se pinta al revés. */
const MENOR_ES_MEJOR = new Set(['cartera_vencida', 'por_pagar_vencido', 'presupuestos_seguimiento', 'distribucion_pendiente', 'monotributo_riesgo']);
/** Indicadores que se leen como "X de Y". */
const X_DE_Y = new Set(['avance_ot', 'monotributo_riesgo', 'presupuestos_seguimiento']);

export function principal(k: Kpi): string {
  if (X_DE_Y.has(k.clave)) return `${fmtNumero(k.valor)} de ${fmtNumero(k.referencia)}`;
  return k.unidad === 'importe' ? fmtMoneda(k.valor) : fmtNumero(k.valor);
}

export function referencia(k: Kpi): string {
  if (k.referencia == null) return '';
  const v = k.unidad === 'importe' && !X_DE_Y.has(k.clave) ? fmtMoneda(k.referencia) : fmtNumero(k.referencia);
  if (X_DE_Y.has(k.clave)) return k.referencia_etiqueta ?? '';
  return `${k.referencia_etiqueta ?? 'Referencia'}: ${v}`;
}

export function KpiCard({ kpi, onAbrir }: { kpi: Kpi; onAbrir: () => void }) {
  const v = kpi.variacion_pct;
  const bueno = v == null ? null : MENOR_ES_MEJOR.has(kpi.clave) ? v <= 0 : v >= 0;
  return (
    <button className="card kpi click" onClick={onAbrir} aria-label={`${kpi.titulo}: ver el detalle`}>
      <div className="kh">
        <small>{kpi.titulo}</small>
        {v != null && (
          <span className={`chip ${bueno ? 'ok' : 'bad'}`}>
            {v >= 0 ? '▲ +' : '▼ '}{fmtNumero(v)}% {kpi.comparado_con ? `vs. ${kpi.comparado_con}` : ''}
          </span>
        )}
      </div>
      <div className="n">{principal(kpi)}</div>
      {kpi.pct != null && (
        <>
          <div className="pr"><b className={`t-${kpi.tono}`}>{fmtPct(kpi.pct)}</b> {kpi.pct_etiqueta}</div>
          <div className="bar" role="img" aria-label={`${fmtPct(kpi.pct)} ${kpi.pct_etiqueta ?? ''}`}>
            <i className={`bg-${kpi.tono}`} style={{ width: `${Math.max(0, Math.min(100, kpi.pct))}%` }} />
          </div>
        </>
      )}
      <div className="d">{referencia(kpi)}</div>
      <div className="hint">Ver detalle ›</div>
    </button>
  );
}
