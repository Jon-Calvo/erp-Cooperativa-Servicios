'use client';

import { useEffect, type ReactNode } from 'react';
import { Icono } from '../Icono';

/** Panel lateral (detalle) o ventana centrada (formularios secundarios). */
export function Panel({ titulo, onCerrar, centrado, children }: { titulo: string; onCerrar: () => void; centrado?: boolean; children: ReactNode }) {
  useEffect(() => {
    const tecla = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); onCerrar(); } };
    window.addEventListener('keydown', tecla);
    return () => window.removeEventListener('keydown', tecla);
  }, [onCerrar]);
  return (
    <div className={`ov${centrado ? ' centro' : ''}`} onMouseDown={(e) => { if (e.target === e.currentTarget) onCerrar(); }} role="presentation">
      <section className={centrado ? 'mdl' : 'dr wide'} role="dialog" aria-modal="true" aria-label={titulo}>
        <div className="head"><h3>{titulo}</h3><button className="ic" onClick={onCerrar} aria-label="Cerrar"><Icono n="cerrar" /></button></div>
        {children}
      </section>
    </div>
  );
}
