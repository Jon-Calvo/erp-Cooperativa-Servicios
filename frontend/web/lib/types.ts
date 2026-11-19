export type TemaColor = 'azul' | 'verde' | 'violeta' | 'naranja' | 'grafito' | 'personalizado';
export type ModoTema = 'claro' | 'sistema' | 'oscuro';
export type Tono = 'ok' | 'warn' | 'bad' | 'neutral';

export interface Perfil {
  usuario_id: string;
  nombre: string;
  activo: boolean;
  modo_tema: ModoTema;
  asociado_id: number | null;
  puestos: string[];
  razon_social: string;
  tema_color: TemaColor;
  tema_color_personalizado: string | null;
}

/** nivel por módulo: 0 sin acceso · 1 lectura · 2 operar · 3 administrar */
export type Permisos = Record<string, number>;

export interface Kpi {
  orden: number;
  clave: string;
  titulo: string;
  modulo: string;
  unidad: 'importe' | 'cantidad';
  valor: number;
  referencia: number | null;
  referencia_etiqueta: string | null;
  pct: number | null;
  pct_etiqueta: string | null;
  variacion_pct: number | null;
  comparado_con: string | null;
  tono: Tono;
}

export interface KpiDetalleFila {
  orden: number;
  nivel: 1 | 2;
  grupo: string;
  concepto: string;
  cantidad: number | null;
  importe: number | null;
  pct: number | null;
  entidad: string | null;
  entidad_id: number | null;
}

export interface KpiUmbral {
  clave: string;
  nombre: string;
  sentido: 'alto_bueno' | 'alto_malo';
  unidad: 'porcentaje' | 'cantidad';
  ok: number;
  aviso: number;
}
