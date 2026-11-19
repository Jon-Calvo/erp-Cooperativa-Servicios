const moneda = new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS', maximumFractionDigits: 0 });
const numero = new Intl.NumberFormat('es-AR', { maximumFractionDigits: 1 });

export const fmtMoneda = (v: number | null | undefined): string => (v == null ? '—' : moneda.format(v));
export const fmtNumero = (v: number | null | undefined): string => (v == null ? '—' : numero.format(v));
export const fmtPct = (v: number | null | undefined): string => (v == null ? '—' : `${numero.format(v)}%`);

/** Primer día del mes de una fecha, en formato AAAA-MM-DD */
export const inicioDeMes = (d: Date): string =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;

export const nombreDeMes = (iso: string): string => {
  const [a, m] = iso.split('-').map(Number);
  return new Date(a, m - 1, 1).toLocaleDateString('es-AR', { month: 'long', year: 'numeric' });
};

export const sumarMeses = (iso: string, n: number): string => {
  const [a, m] = iso.split('-').map(Number);
  return inicioDeMes(new Date(a, m - 1 + n, 1));
};
