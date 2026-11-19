'use client';

import { useState } from 'react';
import { useAuth } from '@/components/AuthProvider';
import { supabase } from '@/lib/supabase';
import { aplicarMarca } from '@/lib/theme';
import type { TemaColor } from '@/lib/types';

const COLORES: { k: TemaColor; n: string; c: string }[] = [
  { k: 'azul', n: 'Azul', c: '#2456D6' },
  { k: 'verde', n: 'Verde', c: '#1F7A4A' },
  { k: 'violeta', n: 'Violeta', c: '#6D45D9' },
  { k: 'naranja', n: 'Naranja', c: '#C2410C' },
  { k: 'grafito', n: 'Grafito', c: '#334155' },
];
const HEX = /^#[0-9a-f]{6}$/i;

export default function Apariencia() {
  const { perfil, puede, refrescar } = useAuth();
  const admin = puede('organizacion', 3);
  const [tema, setTema] = useState<TemaColor>(perfil?.tema_color ?? 'azul');
  const [hex, setHex] = useState(perfil?.tema_color_personalizado ?? '#0F766E');
  const [ok, setOk] = useState('');
  const [error, setError] = useState('');
  const [guardando, setGuardando] = useState(false);
  if (!perfil) return null;

  const sinGuardar = tema !== perfil.tema_color || (tema === 'personalizado' && hex.toLowerCase() !== (perfil.tema_color_personalizado ?? '').toLowerCase());

  const elegir = (t: TemaColor) => { if (!admin) return; setOk(''); setTema(t); aplicarMarca(t, hex); };
  const cambiarHex = (h: string) => {
    setHex(h);
    if (admin && HEX.test(h)) { setOk(''); setTema('personalizado'); aplicarMarca('personalizado', h); }
  };
  const cancelar = () => {
    setTema(perfil.tema_color); setHex(perfil.tema_color_personalizado ?? '#0F766E');
    aplicarMarca(perfil.tema_color, perfil.tema_color_personalizado); setError(''); setOk('');
  };
  const guardar = async () => {
    setError(''); setOk(''); setGuardando(true);
    const { data, error: err } = await supabase().from('organizacion')
      .update({ tema_color: tema, tema_color_personalizado: HEX.test(hex) ? hex : null }).eq('id', true).select();
    setGuardando(false);
    if (err) { setError(err.message); return; }
    if (!data || data.length === 0) { setError('No tenés permiso para cambiar la apariencia: hace falta Administrar en Organización.'); return; }
    await refrescar();
    setOk('Listo: el color quedó guardado para toda la organización.');
  };

  return (
    <div className="cfg">
      <section className="card apar">
        <h2>Color de la aplicación <span className="pill">Predeterminado: Azul</span></h2>
        <p>Lo define la organización y lo ven todos los usuarios. El modo claro, sistema u oscuro lo elige cada uno con los íconos de la barra superior.</p>
        {!admin && <div className="alert info" style={{ marginBottom: 12 }}>Solo quien administra la organización puede cambiar el color.</div>}
        <div className="sw" role="group" aria-label="Color de la aplicación">
          {COLORES.map((x) => (
            <button key={x.k} aria-pressed={tema === x.k} disabled={!admin} onClick={() => elegir(x.k)}>
              <i style={{ background: x.c }} />{x.n}{x.k === 'azul' ? <span className="pill">Predeterminado</span> : null}
            </button>
          ))}
          <label className="cp" title="Color personalizado">
            <input type="color" value={HEX.test(hex) ? hex : '#0F766E'} disabled={!admin} onChange={(e) => cambiarHex(e.target.value)} aria-label="Color personalizado" />
            <input type="text" value={hex} maxLength={7} disabled={!admin} onChange={(e) => cambiarHex(e.target.value)} aria-label="Código del color" />
          </label>
        </div>
        {error && <div className="alert" role="alert" style={{ marginTop: 12 }}>{error}</div>}
        {ok && <div className="alert info" role="status" style={{ marginTop: 12 }}>{ok}</div>}
        {admin && (
          <div className="row" style={{ marginTop: 14 }}>
            <button className="btn p" disabled={!sinGuardar || guardando} onClick={() => void guardar()}>{guardando ? 'Guardando…' : 'Guardar'}</button>
            <button className="btn" disabled={!sinGuardar || guardando} onClick={cancelar}>Cancelar</button>
          </div>
        )}
      </section>
    </div>
  );
}
