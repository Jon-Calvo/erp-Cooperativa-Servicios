/* eslint-disable */
const g: any = globalThis;
const db = (g.__db ??= { tablas: {}, llamadas: [] as any[] });
function consulta(tabla: string) {
  const filtros: [string, any][] = []; let op = 'select'; let payload: any; let single = false;
  const api: any = {
    select() { return api; }, eq(k: string, v: any) { filtros.push([k, v]); return api; }, in() { return api; }, neq() { return api; },
    order() { return api; }, limit() { return api; }, single() { single = true; return api; },
    insert(p: any) { op = 'insert'; payload = p; return api; }, update(p: any) { op = 'update'; payload = p; return api; },
    then(res: any, rej: any) {
      const rows: any[] = (db.tablas[tabla] ??= []); let out: any[];
      if (op === 'select') out = rows.filter((f) => filtros.every(([k, v]) => f[k] === v));
      else if (op === 'insert') { const fila = { id: rows.length + 10, ...payload }; rows.push(fila); db.llamadas.push({ op, tabla, payload }); out = [fila]; }
      else { out = rows.filter((f) => filtros.every(([k, v]) => f[k] === v)); out.forEach((f) => Object.assign(f, payload)); db.llamadas.push({ op, tabla, payload }); }
      return Promise.resolve({ data: single ? out[0] : out, error: null }).then(res, rej);
    },
  };
  return api;
}
export function supabase() { return { from: consulta, rpc: async (n: string, a: any) => { db.llamadas.push({ op: 'rpc', n, a }); return { data: null, error: null }; } }; }
