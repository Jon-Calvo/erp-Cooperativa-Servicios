'use client';

import { useEffect, useState } from 'react';
import type { Listas } from '@/lib/listas';
import type { CampoDef, Fila, Opcion } from './tipos';

export { estaVacio, valoresIniciales, valoresDe, valorParaGuardar, validar } from '@/lib/formularios';

interface Props {
  campos: CampoDef[];
  valores: Fila;
  onCambio: (nombre: string, valor: unknown) => void;
  listas: Listas;
  deshabilitado?: boolean;
  esNuevo?: boolean;
}

export function Formulario({ campos, valores, onCambio, listas, deshabilitado, esNuevo }: Props) {
  const [cargadas, setCargadas] = useState<Record<string, Opcion[]>>({});
  useEffect(() => {
    let vigente = true;
    campos.filter((c) => c.cargarOpciones).forEach((c) => {
      c.cargarOpciones!().then((o) => { if (vigente) setCargadas((m) => ({ ...m, [c.nombre]: o })); }).catch(() => undefined);
    });
    return () => { vigente = false; };
    // se cargan una sola vez al abrir el formulario
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const opcionesDe = (c: CampoDef): Opcion[] =>
    c.opciones ?? (c.lista ? (listas[c.lista] ?? []).map((o) => ({ valor: o.valor, etiqueta: o.etiqueta })) : cargadas[c.nombre] ?? []);

  return (
    <div className="fgrid">
      {campos.filter((c) => !c.visibleSi || c.visibleSi(valores)).map((c) => {
        const id = `f-${c.nombre}`;
        const off = deshabilitado || c.soloLectura || (c.soloAlta && !esNuevo);
        const req = c.requerido || c.requeridoSi?.(valores);
        const v = valores[c.nombre];
        return (
          <div key={c.nombre} className={`field${c.completo || c.tipo === 'area' ? ' full' : ''}`}>
            {c.tipo === 'check' ? (
              <label className="chk"><input id={id} type="checkbox" checked={!!v} disabled={off} onChange={(e) => onCambio(c.nombre, e.target.checked)} /> {c.etiqueta}</label>
            ) : (
              <>
                <label htmlFor={id}>{c.etiqueta}{req ? ' *' : ''}</label>
                {c.tipo === 'area' ? (
                  <textarea id={id} rows={3} value={String(v ?? '')} disabled={off} onChange={(e) => onCambio(c.nombre, e.target.value)} />
                ) : c.tipo === 'select' || c.lista ? (
                  <select id={id} value={String(v ?? '')} disabled={off} onChange={(e) => onCambio(c.nombre, e.target.value === '' ? '' : (typeof opcionesDe(c)[0]?.valor === 'number' ? Number(e.target.value) : e.target.value))}>
                    <option value="">{req ? 'Elegí una opción' : '— sin definir —'}</option>
                    {opcionesDe(c).map((o) => <option key={String(o.valor)} value={String(o.valor)}>{o.etiqueta}</option>)}
                  </select>
                ) : (
                  <input id={id} type={c.tipo === 'fecha' ? 'date' : c.tipo === 'numero' ? 'number' : c.tipo === 'email' ? 'email' : c.tipo === 'telefono' ? 'tel' : 'text'}
                         step={c.tipo === 'numero' ? 'any' : undefined} value={String(v ?? '')} disabled={off} onChange={(e) => onCambio(c.nombre, e.target.value)} />
                )}
              </>
            )}
            {c.ayuda && <small className="ayuda">{c.ayuda}</small>}
          </div>
        );
      })}
    </div>
  );
}
