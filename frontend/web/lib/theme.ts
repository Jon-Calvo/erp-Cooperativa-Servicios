import type { ModoTema, TemaColor } from './types';

/** Modo claro / sistema / oscuro (por usuario). */
export function aplicarModo(modo: ModoTema): void {
  const r = document.documentElement;
  if (modo === 'sistema') r.removeAttribute('data-theme');
  else r.setAttribute('data-theme', modo === 'claro' ? 'light' : 'dark');
  try { localStorage.setItem('erp-modo', modo); } catch { /* sin almacenamiento */ }
}

/** Color de la aplicación (lo define la organización). */
export function aplicarMarca(tema: TemaColor, hex?: string | null): void {
  const r = document.documentElement;
  r.setAttribute('data-brand', tema);
  let tinta = '#FFFFFF';
  if (tema === 'personalizado' && hex && /^#[0-9a-f]{6}$/i.test(hex)) {
    const R = parseInt(hex.slice(1, 3), 16), G = parseInt(hex.slice(3, 5), 16), B = parseInt(hex.slice(5, 7), 16);
    tinta = (0.2126 * R + 0.7152 * G + 0.0722 * B) / 255 > 0.6 ? '#0B0F14' : '#FFFFFF';
    r.style.setProperty('--cp', hex);
    r.style.setProperty('--cp-ink', tinta);
  } else {
    r.style.removeProperty('--cp');
    r.style.removeProperty('--cp-ink');
  }
  try { localStorage.setItem('erp-marca', JSON.stringify({ t: tema, h: hex ?? null, i: tinta })); } catch { /* sin almacenamiento */ }
}

/** Script que corre antes de pintar para evitar el parpadeo de color o modo. */
export const SCRIPT_INICIAL = `(function(){try{var d=document.documentElement,m=localStorage.getItem('erp-modo');
if(m==='claro')d.setAttribute('data-theme','light');else if(m==='oscuro')d.setAttribute('data-theme','dark');
var b=JSON.parse(localStorage.getItem('erp-marca')||'null');
if(b&&b.t){d.setAttribute('data-brand',b.t);if(b.t==='personalizado'&&b.h){d.style.setProperty('--cp',b.h);d.style.setProperty('--cp-ink',b.i||'#fff')}}}catch(e){}})();`;
