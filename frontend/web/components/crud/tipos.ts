import type { ReactNode } from 'react';
import type { Listas } from '@/lib/listas';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Fila = Record<string, any>;
export interface Opcion { valor: string | number; etiqueta: string }

export interface CampoDef {
  nombre: string;
  etiqueta: string;
  tipo?: 'texto' | 'email' | 'telefono' | 'numero' | 'fecha' | 'area' | 'check' | 'select';
  requerido?: boolean;
  /** opciones fijas */
  opciones?: Opcion[];
  /** clave de una lista editable (lista_valor) */
  lista?: string;
  /** opciones que se cargan de la base */
  cargarOpciones?: () => Promise<Opcion[]>;
  patron?: RegExp;
  mensajePatron?: string;
  ayuda?: string;
  completo?: boolean;
  soloLectura?: boolean;
  /** solo se completa al crear */
  soloAlta?: boolean;
  defecto?: unknown;
  /** transforma el texto antes de guardar (por ejemplo, dejar solo dígitos) */
  normalizar?: (v: string) => string;
  /** el campo solo se muestra si esta condición se cumple */
  visibleSi?: (v: Fila) => boolean;
  /** el campo es obligatorio si esta condición se cumple */
  requeridoSi?: (v: Fila) => boolean;
}

export interface ColumnaDef {
  clave: string;
  etiqueta: string;
  render?: (f: Fila, listas: Listas) => ReactNode;
  /** texto para la búsqueda */
  texto?: (f: Fila, listas: Listas) => string;
  alinear?: 'der';
}

export interface AccionDef {
  etiqueta: string;
  visible?: (f: Fila) => boolean;
  ejecutar: (f: Fila) => Promise<void>;
}
