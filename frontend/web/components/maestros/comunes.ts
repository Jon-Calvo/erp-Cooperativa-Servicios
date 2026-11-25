import type { CampoDef } from '@/components/crud/tipos';

export const TIPOS_DOC = [{ valor: 'CUIT', etiqueta: 'CUIT' }, { valor: 'CUIL', etiqueta: 'CUIL' }, { valor: 'DNI', etiqueta: 'DNI' }, { valor: 'Pasaporte', etiqueta: 'Pasaporte' }];
export const CONDICIONES_IVA = ['Resp. Inscripto', 'Monotributo', 'Exento', 'Consumidor Final'].map((c) => ({ valor: c, etiqueta: c }));
export const soloDigitos = (t: string) => t.replace(/\D/g, '');

/** Documento: se guarda sin guiones ni puntos; cambiarlo exige un motivo. */
export const CAMPO_DOC: CampoDef[] = [
  { nombre: 'tipo_doc', etiqueta: 'Tipo de documento', tipo: 'select', opciones: TIPOS_DOC, defecto: 'CUIT', requerido: true },
  { nombre: 'nro_doc', etiqueta: 'Número de documento', requerido: true, patron: /^\d{7,11}$/, normalizar: soloDigitos,
    mensajePatron: 'El documento va solo con números (7 a 11 dígitos), sin guiones ni puntos.', ayuda: 'Se guarda sin guiones. Cambiarlo exige indicar un motivo.' },
];
