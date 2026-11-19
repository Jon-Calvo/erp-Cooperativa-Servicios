'use client';

import { useCallback, useEffect, useState } from 'react';
import { KpiCard } from '@/components/KpiCard';
import { KpiDetalle } from '@/components/KpiDetalle';
import { Icono } from '@/components/Icono';
import { inicioDeMes, nombreDeMes, sumarMeses } from '@/lib/format';
import { supabase } from '@/lib/supabase';
import type { Kpi } from '@/lib/types';

export default function Panel() {
  const [mes, setMes] = useState(() => inicioDeMes(new Date()));
  const [kpis, setKpis] = useState<Kpi[] | null>(null);
  const [error, setError] = useState('');
  const [abierto, setAbierto] = useState<Kpi | null>(null);

  const cargar = useCallback(async (fecha: string) => {
    setKpis(null); setError('');
    const { data, error: err } = await supabase().rpc('kpi_panel', { p_fecha: fecha });
    if (err) setError(err.message); else setKpis((data ?? []) as Kpi[]);
  }, []);

  useEffect(() => { void cargar(mes); }, [mes, cargar]);

  const esMesActual = mes === inicioDeMes(new Date());
  // para el mes en curso se consulta con la fecha de hoy; para meses pasados, con su primer día
  const fechaConsulta = esMesActual ? new Date().toISOString().slice(0, 10) : mes;

  return (
    <>
      <div className="head">
        <h2>Indicadores</h2>
        <div className="mes">
          <button className="ic" onClick={() => setMes(sumarMeses(mes, -1))} aria-label="Mes anterior"><Icono n="chev" clase="rev" /></button>
          <b>{nombreDeMes(mes)}</b>
          <button className="ic" onClick={() => setMes(sumarMeses(mes, 1))} aria-label="Mes siguiente" disabled={esMesActual}><Icono n="chev" /></button>
        </div>
      </div>
      {error && <div className="alert">{error} <button className="btn" onClick={() => void cargar(mes)}>Reintentar</button></div>}
      {!kpis && !error && <section className="kpis">{Array.from({ length: 6 }, (_, i) => <div className="sk" key={i} />)}</section>}
      {kpis && kpis.length === 0 && (
        <div className="alert info">Todavía no hay indicadores para mostrar: tu usuario no tiene permisos de lectura en los módulos operativos.</div>
      )}
      {kpis && kpis.length > 0 && (
        <section className="kpis" aria-label="Indicadores">
          {kpis.map((k) => <KpiCard key={k.clave} kpi={k} onAbrir={() => setAbierto(k)} />)}
        </section>
      )}
      {abierto && <KpiDetalle kpi={abierto} fecha={fechaConsulta} onCerrar={() => setAbierto(null)} />}
    </>
  );
}
