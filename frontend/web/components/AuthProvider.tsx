'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase';
import { aplicarMarca, aplicarModo } from '@/lib/theme';
import type { Perfil, Permisos } from '@/lib/types';

type Estado = 'cargando' | 'sin_sesion' | 'sin_perfil' | 'inactivo' | 'error' | 'ok';

interface AuthCtx {
  estado: Estado;
  error: string;
  session: Session | null;
  perfil: Perfil | null;
  permisos: Permisos;
  /** ¿tiene al menos ese nivel en el módulo? (1 lectura · 2 operar · 3 administrar) */
  puede: (modulo: string, nivel?: number) => boolean;
  refrescar: () => Promise<void>;
  cerrarSesion: () => Promise<void>;
}

const Ctx = createContext<AuthCtx | null>(null);

export function useAuth(): AuthCtx {
  const c = useContext(Ctx);
  if (!c) throw new Error('useAuth debe usarse dentro de <AuthProvider>.');
  return c;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [perfil, setPerfil] = useState<Perfil | null>(null);
  const [permisos, setPermisos] = useState<Permisos>({});
  const [estado, setEstado] = useState<Estado>('cargando');
  const [error, setError] = useState('');

  const cargar = useCallback(async (s: Session | null) => {
    if (!s) { setPerfil(null); setPermisos({}); setEstado('sin_sesion'); return; }
    try {
      const sb = supabase();
      const [p, m] = await Promise.all([sb.rpc('mi_perfil'), sb.rpc('mis_permisos')]);
      const fallo = p.error ?? m.error;
      if (fallo) { setError(fallo.message); setEstado('error'); return; }
      const fila = (p.data as Perfil[] | null)?.[0];
      if (!fila) { setPerfil(null); setEstado('sin_perfil'); return; }
      setPerfil(fila);
      setPermisos(Object.fromEntries(((m.data ?? []) as { modulo: string; nivel: number }[]).map((x) => [x.modulo, x.nivel])));
      aplicarMarca(fila.tema_color, fila.tema_color_personalizado);
      aplicarModo(fila.modo_tema);
      setEstado(fila.activo ? 'ok' : 'inactivo');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error desconocido');
      setEstado('error');
    }
  }, []);

  useEffect(() => {
    let sb;
    try { sb = supabase(); } catch (e) { setError(e instanceof Error ? e.message : 'Configuración incompleta'); setEstado('error'); return; }
    sb.auth.getSession().then(({ data }) => { setSession(data.session); void cargar(data.session); });
    const { data: sub } = sb.auth.onAuthStateChange((_evento, s) => {
      setSession(s);
      // no se hacen llamadas a Supabase dentro del callback: se difieren
      setTimeout(() => { void cargar(s); }, 0);
    });
    return () => sub.subscription.unsubscribe();
  }, [cargar]);

  const valor = useMemo<AuthCtx>(() => ({
    estado, error, session, perfil, permisos,
    puede: (modulo, nivel = 1) => (permisos[modulo] ?? 0) >= nivel,
    refrescar: () => cargar(session),
    cerrarSesion: async () => { await supabase().auth.signOut(); },
  }), [estado, error, session, perfil, permisos, cargar]);

  return <Ctx.Provider value={valor}>{children}</Ctx.Provider>;
}
