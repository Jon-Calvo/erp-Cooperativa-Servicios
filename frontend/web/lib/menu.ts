export interface ItemMenu {
  etiqueta: string;
  icono: string;
  href?: string;
  /** módulo cuyo permiso habilita el ítem (si no hay, lo ven todos) */
  modulo?: string;
  hijos?: { etiqueta: string; href: string; modulo?: string }[];
}
export interface SeccionMenu { titulo: string; items: ItemMenu[] }

export const MENU: SeccionMenu[] = [
  {
    titulo: 'OPERACIONES',
    items: [
      { etiqueta: 'Panel', icono: 'grid', href: '/panel' },
      { etiqueta: 'Comercial', icono: 'file', modulo: 'comercial', hijos: [
        { etiqueta: 'Presupuestos', href: '/comercial/presupuestos' },
        { etiqueta: 'Seguimiento', href: '/comercial/seguimiento' } ] },
      { etiqueta: 'Operaciones', icono: 'clip', modulo: 'operaciones', hijos: [
        { etiqueta: 'Órdenes de trabajo', href: '/operaciones/ot' },
        { etiqueta: 'Servicios mensuales', href: '/operaciones/sm' } ] },
      { etiqueta: 'Costos y gastos', icono: 'receipt', modulo: 'costos', hijos: [
        { etiqueta: 'Gastos', href: '/costos/gastos' },
        { etiqueta: 'Facturas de proveedor', href: '/costos/facturas-proveedor' },
        { etiqueta: 'Subcontratos', href: '/costos/subcontratos' },
        { etiqueta: 'Cuentas de asociados', href: '/costos/cuentas-asociados' } ] },
      { etiqueta: 'Facturación y cobranza', icono: 'wallet', modulo: 'facturacion', hijos: [
        { etiqueta: 'Facturas', href: '/facturacion/facturas' },
        { etiqueta: 'Cobranzas', href: '/facturacion/cobranzas', modulo: 'cobranza' },
        { etiqueta: 'Cuenta corriente de clientes', href: '/facturacion/cuenta-clientes', modulo: 'cobranza' } ] },
      { etiqueta: 'Distribución', icono: 'share', modulo: 'distribucion', hijos: [
        { etiqueta: 'Reglas por OT', href: '/distribucion/reglas' },
        { etiqueta: 'Distribuciones', href: '/distribucion/distribuciones' } ] },
      { etiqueta: 'Monotributo', icono: 'shield', href: '/monotributo', modulo: 'monotributo' },
      { etiqueta: 'Calendario', icono: 'cal', href: '/calendario', modulo: 'calendario' },
    ],
  },
  {
    titulo: 'RECURSOS',
    items: [
      { etiqueta: 'Maestros', icono: 'users', modulo: 'maestros', hijos: [
        { etiqueta: 'Clientes', href: '/maestros/clientes' },
        { etiqueta: 'Asociados', href: '/maestros/asociados' },
        { etiqueta: 'Proveedores', href: '/maestros/proveedores' },
        { etiqueta: 'Servicios', href: '/maestros/servicios' } ] },
      { etiqueta: 'Configuración', icono: 'gear', hijos: [
        { etiqueta: 'Apariencia', href: '/configuracion/apariencia' },
        { etiqueta: 'Indicadores', href: '/configuracion/indicadores' } ] },
    ],
  },
];

/** Título de la pantalla según la ruta. */
export function tituloDeRuta(ruta: string): string {
  for (const s of MENU) for (const i of s.items) {
    if (i.href === ruta) return i.etiqueta;
    for (const h of i.hijos ?? []) if (h.href === ruta) return h.etiqueta;
  }
  return 'ERP Cooperativa';
}
