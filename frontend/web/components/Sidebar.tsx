'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState } from 'react';
import { MENU } from '@/lib/menu';
import { useAuth } from './AuthProvider';
import { Icono } from './Icono';

interface Props { abierto: boolean; mini: boolean; onMini: () => void; onCerrar: () => void }

export function Sidebar({ abierto, mini, onMini, onCerrar }: Props) {
  const ruta = usePathname();
  const { perfil, puede } = useAuth();
  const [abiertos, setAbiertos] = useState<Record<string, boolean>>({});

  // abre solo el grupo de la pantalla actual
  useEffect(() => {
    for (const s of MENU) for (const i of s.items) {
      if (i.hijos?.some((h) => h.href === ruta)) setAbiertos((a) => ({ ...a, [i.etiqueta]: true }));
    }
  }, [ruta]);

  const alternar = (e: string) => {
    if (mini && window.innerWidth > 980) onMini();
    setAbiertos((a) => ({ ...a, [e]: !a[e] }));
  };

  return (
    <>
      <aside className="sb" aria-label="Navegación principal" data-abierto={abierto}>
        <div className="brand">
          <div className="logo">{(perfil?.razon_social || 'C').trim().charAt(0).toUpperCase()}</div>
          <div><b>{perfil?.razon_social || 'Cooperativa'}</b><small>Seguridad e Higiene</small></div>
        </div>
        <nav className="nav">
          {MENU.map((sec) => {
            const items = sec.items.filter((i) => !i.modulo || puede(i.modulo));
            const visibles = items.map((i) => ({ ...i, hijos: i.hijos?.filter((h) => !h.modulo || puede(h.modulo)) }))
              .filter((i) => i.href || (i.hijos && i.hijos.length > 0));
            if (visibles.length === 0) return null;
            return (
              <div key={sec.titulo}>
                <div className="sec">{sec.titulo}</div>
                {visibles.map((i) => {
                  if (!i.hijos) {
                    return (
                      <Link key={i.etiqueta} href={i.href!} title={i.etiqueta} onClick={onCerrar}
                            className={`it${ruta === i.href ? ' on' : ''}`}>
                        <Icono n={i.icono} /><span className="lb">{i.etiqueta}</span>
                      </Link>
                    );
                  }
                  const idGrupo = `g-${i.etiqueta.replace(/\W/g, '')}`;
                  const abierto = !!abiertos[i.etiqueta];
                  const activo = i.hijos.some((h) => h.href === ruta);
                  return (
                    <div key={i.etiqueta}>
                      <button className={`it${activo ? ' on' : ''}`} aria-expanded={abierto} aria-controls={idGrupo}
                              title={i.etiqueta} onClick={() => alternar(i.etiqueta)}>
                        <Icono n={i.icono} /><span className="lb">{i.etiqueta}</span><Icono n="chev" clase="ch" />
                      </button>
                      <div className={`grp${abierto ? ' open' : ''}`} id={idGrupo}>
                        <div><div className="sub">
                          {i.hijos.map((h) => (
                            <Link key={h.href} href={h.href} onClick={onCerrar} className={`it${ruta === h.href ? ' on' : ''}`}>{h.etiqueta}</Link>
                          ))}
                        </div></div>
                      </div>
                    </div>
                  );
                })}
              </div>
            );
          })}
        </nav>
        <div className="foot">
          <button className="it" onClick={onMini} aria-label="Contraer menú"><Icono n="panel" /><span className="lb">Contraer menú</span></button>
        </div>
      </aside>
      <div className="scrim" onClick={onCerrar} />
    </>
  );
}
