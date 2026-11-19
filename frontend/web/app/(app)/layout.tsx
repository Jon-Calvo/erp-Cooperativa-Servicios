'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState, type ReactNode } from 'react';
import { useAuth } from '@/components/AuthProvider';
import { Sidebar } from '@/components/Sidebar';
import { Topbar } from '@/components/Topbar';

function Pantalla({ children }: { children: ReactNode }) {
  return <main className="center"><div className="card" style={{ maxWidth: 520, display: 'grid', gap: 14 }}>{children}</div></main>;
}

export default function AppLayout({ children }: { children: ReactNode }) {
  const router = useRouter();
  const { estado, error, perfil, cerrarSesion } = useAuth();
  const [mini, setMini] = useState(false);
  const [abierto, setAbierto] = useState(false);

  useEffect(() => { if (estado === 'sin_sesion') router.replace('/login'); }, [estado, router]);

  if (estado === 'cargando' || estado === 'sin_sesion') {
    return <main className="center"><div className="spin" role="status" aria-label="Cargando" /></main>;
  }
  if (estado === 'error') {
    return <Pantalla><h2 style={{ margin: 0 }}>No se pudo conectar</h2><div className="alert">{error}</div>
      <button className="btn" onClick={() => window.location.reload()}>Reintentar</button></Pantalla>;
  }
  if (estado === 'sin_perfil') {
    return <Pantalla><h2 style={{ margin: 0 }}>Tu usuario todavía no tiene perfil</h2>
      <p className="muted" style={{ margin: 0 }}>Iniciaste sesión, pero falta darte de alta en el sistema. Si sos el primer administrador, ejecutá en el SQL Editor de Supabase:</p>
      <code style={{ display: 'block', padding: 10, borderRadius: 10, background: 'var(--surface2)' }}>select public.inicializar_admin(&apos;tu@mail.com&apos;);</code>
      <p className="muted" style={{ margin: 0 }}>Si no, pedile a un administrador que te dé de alta.</p>
      <button className="btn" onClick={() => void cerrarSesion()}>Cerrar sesión</button></Pantalla>;
  }
  if (estado === 'inactivo') {
    return <Pantalla><h2 style={{ margin: 0 }}>Tu usuario está inactivo</h2>
      <p className="muted" style={{ margin: 0 }}>{perfil?.nombre}: pedile a un administrador que lo reactive.</p>
      <button className="btn" onClick={() => void cerrarSesion()}>Cerrar sesión</button></Pantalla>;
  }

  return (
    <div className={`app${mini ? ' mini' : ''}${abierto ? ' open' : ''}`}>
      <Sidebar abierto={abierto} mini={mini} onMini={() => setMini((m) => !m)} onCerrar={() => setAbierto(false)} />
      <div className="main">
        <Topbar onAbrir={() => setAbierto(true)} />
        <main className="cont">{children}</main>
      </div>
    </div>
  );
}
