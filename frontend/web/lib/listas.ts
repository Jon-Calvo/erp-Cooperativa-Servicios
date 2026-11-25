'use client';

import { useEffect, useState } from 'react';
import { supabase } from './supabase';

export interface OpcionLista { valor: number; etiqueta: string; datos: Record<string, unknown> }
export type Listas = Record<string, OpcionLista[]>;

/** Carga las listas editables (tipo de cliente, rubro, banco, etc.) por su clave. */
export function useListas(claves: string[]): Listas {
  const [listas, setListas] = useState<Listas>({});
  const clave = [...claves].sort().join(',');
  useEffect(() => {
    if (!clave) return;
    let vigente = true;
    supabase().from('lista_valor').select('id, lista, nombre, datos, orden').in('lista', clave.split(',')).eq('activo', true)
      .order('orden').order('nombre').then(({ data }) => {
        if (!vigente) return;
        const r: Listas = {};
        for (const f of (data ?? []) as { id: number; lista: string; nombre: string; datos: Record<string, unknown> }[]) {
          (r[f.lista] ??= []).push({ valor: f.id, etiqueta: f.nombre, datos: f.datos });
        }
        setListas(r);
      });
    return () => { vigente = false; };
  }, [clave]);
  return listas;
}

export const nombreDe = (listas: Listas, lista: string, id: unknown): string =>
  listas[lista]?.find((o) => o.valor === id)?.etiqueta ?? '';
