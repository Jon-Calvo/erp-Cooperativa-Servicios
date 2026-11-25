import type { CampoDef, Fila } from '../components/crud/tipos';

export const estaVacio = (v: unknown): boolean => v === null || v === undefined || (typeof v === 'string' && v.trim() === '');

/** Valores iniciales de un formulario nuevo. */
export function valoresIniciales(campos: CampoDef[], base?: Fila): Fila {
  const r: Fila = {};
  for (const c of campos) r[c.nombre] = c.defecto ?? (c.tipo === 'check' ? false : '');
  return { ...r, ...(base ?? {}) };
}

/** Valores de un registro existente, listos para el formulario. */
export function valoresDe(campos: CampoDef[], fila: Fila): Fila {
  const r: Fila = {};
  for (const c of campos) r[c.nombre] = fila[c.nombre] ?? (c.tipo === 'check' ? false : '');
  return r;
}

/** Convierte el valor del formulario al que se guarda en la base. */
export function valorParaGuardar(c: CampoDef, v: unknown): unknown {
  if (c.tipo === 'check') return !!v;
  if (estaVacio(v)) return null;
  if (c.tipo === 'numero') return Number(v);
  if (c.tipo === 'select') return typeof v === 'string' && /^\d+$/.test(v) && c.opciones === undefined ? Number(v) : v;
  const t = String(v).trim();
  return c.normalizar ? c.normalizar(t) : t;
}

export function validar(campos: CampoDef[], v: Fila): string | null {
  for (const c of campos) {
    if (c.visibleSi && !c.visibleSi(v)) continue;
    const req = c.requerido || c.requeridoSi?.(v);
    if (req && c.tipo !== 'check' && estaVacio(v[c.nombre])) return `Completá "${c.etiqueta}".`;
    if (!estaVacio(v[c.nombre]) && c.patron) {
      const t = c.normalizar ? c.normalizar(String(v[c.nombre])) : String(v[c.nombre]);
      if (!c.patron.test(t)) return c.mensajePatron ?? `"${c.etiqueta}" no tiene un formato válido.`;
    }
    if (!estaVacio(v[c.nombre]) && c.tipo === 'numero' && !Number.isFinite(Number(v[c.nombre]))) return `"${c.etiqueta}" debe ser un número.`;
  }
  return null;
}

