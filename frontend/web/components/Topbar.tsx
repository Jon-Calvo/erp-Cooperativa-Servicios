'use client';

import { usePathname } from 'next/navigation';
import { useState } from 'react';
import { tituloDeRuta } from '@/lib/menu';
import { supabase } from '@/lib/supabase';
import { aplicarModo } from '@/lib/theme';
import type { ModoTema } from '@/lib/types';
import { useAuth } from './AuthProvider';
import { Icono } from './Icono';

const MODOS: { modo: ModoTema; icono: string; nombre: string }[] = [
  { modo: 'claro', icono: 'sun', nombre: 'Claro' },
  { modo: 'sistema', icono: 'gear', nombre: 'Sistema' },
  { modo: 'oscuro', icono: 'moon', nombre: 'Oscuro' },
];

export function Topbar({ onAbrir }: { onAbrir: () => void }) {
  const ruta = usePathname();
  const { perfil, cerrarSesion, refrescar } = useAuth();
  const [modo, setModo] = useState<ModoTema | null>(null);
  const actual = modo ?? perfil?.modo_tema ?? 'sistema';
  const iniciales = (perfil?.nombre ?? '?').split(/[\s@.]+/).filter(Boolean).slice(0, 2).map((p) => p[0].toUpperCase()).join('');

  const elegir = async (m: ModoTema) => {
    setModo(m);
    aplicarModo(m);                                           // se ve al instante
    const { error } = await supabase().rpc('set_modo_tema', { p_modo: m });
    if (!error) void refrescar();
  };

  return (
    <header className="top">
      <button className="ic menu-m" onClick={onAbrir} aria-label="Abrir menú"><Icono n="menu" /></button>
      <div className="ttl"><h1>{tituloDeRuta(ruta)}</h1><span>{perfil?.nombre}</span></div>
      <div className="ctl">
        <div className="modo" role="group" aria-label="Modo de color">
          {MODOS.map((x) => (
            <button key={x.modo} aria-pressed={actual === x.modo} aria-label={x.nombre} title={x.nombre} onClick={() => void elegir(x.modo)}>
              <Icono n={x.icono} />
            </button>
          ))}
        </div>
        <div className="av" title={perfil?.nombre}>{iniciales}</div>
        <button className="ic" onClick={() => void cerrarSesion()} aria-label="Cerrar sesión" title="Cerrar sesión"><Icono n="salir" /></button>
      </div>
    </header>
  );
}
