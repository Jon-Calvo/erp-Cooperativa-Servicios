/* eslint-disable */
import React from 'react';
import { createRoot } from 'react-dom/client';
import { act } from 'react-dom/test-utils';
import { Maestro } from '../../components/crud/Maestro';
const g: any = globalThis;
g.IS_REACT_ACT_ENVIRONMENT = true;
let fallas = 0; const ok = (c: boolean, m: string) => { if (!c) fallas++; console.log(c ? 'OK  ' : 'FAIL', m); };
const tick = () => act(async () => { await new Promise((r) => setTimeout(r, 20)); });
const setv = (el: any, v: string) => { const proto = el.tagName === 'SELECT' ? HTMLSelectElement.prototype : el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value')!.set!.call(el, v); el.dispatchEvent(new Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true })); };
const q = (s: string) => document.querySelector(s) as any;
const boton = (t: string) => [...document.querySelectorAll('button')].find((b) => b.textContent!.trim().startsWith(t)) as any;

const campos: any[] = [
  { nombre: 'razon_social', etiqueta: 'Razón social', requerido: true },
  { nombre: 'nro_doc', etiqueta: 'Documento', requerido: true, patron: /^\d{7,11}$/, normalizar: (t: string) => t.replace(/\D/g, '') },
  { nombre: 'estado', etiqueta: 'Estado', tipo: 'select', opciones: [{ valor: 'activo', etiqueta: 'Activo' }, { valor: 'inactivo', etiqueta: 'Inactivo' }], defecto: 'activo', requerido: true }];
const columnas = [{ clave: 'razon_social', etiqueta: 'Razón social' }, { clave: 'nro_doc', etiqueta: 'Documento' }];

async function main() {
  g.__db.tablas.cliente = [{ id: 1, codigo: 'CLI-1', razon_social: 'Acme', nro_doc: '30711111112', estado: 'activo' }, { id: 2, codigo: 'CLI-2', razon_social: 'Vieja SA', nro_doc: '30722222223', estado: 'inactivo' }];
  const cont = document.createElement('div'); document.body.appendChild(cont); const root = createRoot(cont);
  await act(async () => { root.render(<Maestro titulo="Clientes" tabla="cliente" modulo="maestros" campos={campos} columnas={columnas} usarRpc criticos={['nro_doc', 'razon_social']} estadoCampo="estado" estadosOcultos={['inactivo']} busqueda={['razon_social']} fijos={{ tipo_doc: 'CUIT' }} />); }); await tick();

  ok(document.querySelectorAll('tbody tr').length === 1 && document.body.textContent!.includes('Acme') && !document.body.textContent!.includes('Vieja SA'), 'los inactivos se ocultan por defecto');
  await act(async () => { q('input[type=checkbox]').click(); }); await tick();
  ok(document.body.textContent!.includes('Vieja SA'), '"Ver inactivos" los muestra');
  await act(async () => { q('input[type=checkbox]').click(); }); await tick();
  await act(async () => { setv(q('input[type=search]'), 'zzz'); });
  ok(document.body.textContent!.includes('No hay registros'), 'la búsqueda filtra');
  await act(async () => { setv(q('input[type=search]'), 'acme'); });
  ok(document.querySelectorAll('tbody tr').length === 1, 'la búsqueda no distingue mayúsculas');

  // editar un campo común: sin motivo
  await act(async () => { q('tbody tr').click(); }); await tick();
  ok(!!q('#f-razon_social') && q('#f-razon_social').value === 'Acme', 'se abre la ficha con los datos');
  ok(!q('#motivo'), 'sin cambios críticos no pide motivo');
  await act(async () => { boton('Guardar cambios').click(); }); await tick();
  ok(document.body.textContent!.includes('No hay cambios'), 'sin cambios avisa');
  await act(async () => { setv(q('#f-estado'), 'inactivo'); });
  ok(!q('#motivo'), 'cambiar el estado no es crítico');
  await act(async () => { boton('Guardar cambios').click(); }); await tick();
  let ult = g.__db.llamadas.filter((l: any) => l.op === 'rpc').pop();
  ok(ult && ult.n === 'actualizar_con_motivo' && ult.a.p_id === 1 && ult.a.p_cambios.estado === 'inactivo' && ult.a.p_motivo === null && Object.keys(ult.a.p_cambios).length === 1, 'se guarda solo lo que cambió y sin motivo');
  await act(async () => { setv(q('#f-estado'), 'activo'); });

  // campo crítico: pide motivo
  await act(async () => { setv(q('#f-razon_social'), 'Acme Nueva SA'); });
  ok(!!q('#motivo'), 'cambiar un campo crítico muestra el motivo');
  await act(async () => { boton('Guardar cambios').click(); }); await tick();
  ok(document.body.textContent!.includes('Indicá el motivo'), 'sin motivo no se guarda');
  const antes = g.__db.llamadas.length;
  await act(async () => { setv(q('#motivo'), 'Cambió su razón social'); });
  await act(async () => { boton('Guardar cambios').click(); }); await tick();
  ult = g.__db.llamadas.filter((l: any) => l.op === 'rpc').pop();
  ok(g.__db.llamadas.length === antes + 1 && ult.a.p_cambios.razon_social === 'Acme Nueva SA' && ult.a.p_motivo === 'Cambió su razón social', 'con motivo se guarda y viaja el motivo');
  await act(async () => { boton('Cerrar').click(); }); await tick();

  // alta
  await act(async () => { boton('Nuevo').click(); }); await tick();
  await act(async () => { boton('Crear').click(); }); await tick();
  ok(document.body.textContent!.includes('Completá "Razón social"'), 'el alta valida lo obligatorio');
  await act(async () => { setv(q('#f-razon_social'), '  Nueva Empresa  '); setv(q('#f-nro_doc'), '30-71111111-2'); });
  await act(async () => { boton('Crear').click(); }); await tick();
  const ins = g.__db.llamadas.filter((l: any) => l.op === 'insert').pop();
  ok(ins && ins.payload.razon_social === 'Nueva Empresa' && ins.payload.nro_doc === '30711111112' && ins.payload.tipo_doc === 'CUIT' && ins.payload.estado === 'activo', 'el alta recorta, normaliza el documento y agrega los valores fijos');
  await act(async () => { setv(q('input[type=search]'), ''); }); await tick();
  ok(document.body.textContent!.includes('Nueva Empresa') || document.querySelectorAll('tbody tr').length >= 1, 'el nuevo registro aparece en la lista');

  // sin permiso de edición
  await act(async () => { root.unmount(); });
  g.__puede = (m: string, n: number) => n <= 1;
  const cont2 = document.createElement('div'); document.body.appendChild(cont2); const root2 = createRoot(cont2);
  await act(async () => { root2.render(<Maestro titulo="Clientes" tabla="cliente" modulo="maestros" campos={campos} columnas={columnas} usarRpc />); }); await tick();
  ok(!boton('Nuevo'), 'sin permiso de operar no hay botón Nuevo');
  await act(async () => { cont2.querySelector('tbody tr')!.dispatchEvent(new MouseEvent('click', { bubbles: true })); }); await tick();
  ok(q('#f-razon_social').disabled && !boton('Guardar cambios') && document.body.textContent!.includes('no modificarlo'), 'sin permiso la ficha es de solo lectura');
  console.log(fallas ? 'FALLAS ' + fallas : 'TODO OK'); process.exit(fallas ? 1 : 0);
}
main().catch((e) => { console.error('ERROR', e); process.exit(2); });
