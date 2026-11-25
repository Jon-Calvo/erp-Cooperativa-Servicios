# Historial de cambios

## frontend-0.2 · Usuarios, puestos y maestros
Pantallas de **Usuarios** (alta, puestos, asociado vinculado, activar o desactivar y excepciones de permisos), **Puestos y permisos** (matriz por módulo) y los maestros **Clientes** (con establecimientos, contactos y cuentas bancarias), **Asociados**, **Proveedores y subcontratistas** y **Servicios** (con precios versionados). Componente genérico de maestros: búsqueda, ver inactivos, alta, edición, motivo obligatorio al cambiar datos críticos, solo lectura según permisos y mensajes de error claros. Pruebas de lógica y de interfaz con un Supabase simulado (`npm run test:logica`, `npm run test:ui`).

## db-0010 · Alta de usuarios, protección del Director y actualización de maestros
`lista_usuarios`, `alta_usuario` (para quien ya se creó en Authentication) y `set_puestos_usuario`. Siempre queda al menos un Director activo con acceso total: el puesto Director no se renombra, no se desactiva, no se borra y no se le quitan permisos. `actualizar_con_motivo`: modifica un maestro en una sola operación con el motivo que exigen los campos críticos.

## frontend-0.1 · Base de la aplicación web
Next.js 14 conectado a Supabase: inicio de sesión, menú lateral en cascada filtrado por permisos, modo claro / sistema / oscuro por usuario, color de la organización, panel de indicadores con detalle desglosado, configuración de apariencia y de umbrales. Guía de despliegue en Vercel en `frontend/web/README.md`.

## db-0009 · KPIs configurables, detalle desglosado y perfil
Umbrales de los semáforos editables por la organización (`kpi_umbral`). `kpi_detalle`: cada indicador se desglosa en grupos con importe y porcentaje, y debajo las filas que los componen (por ejemplo, la facturación del mes en facturado, OT finalizadas pendientes de facturar y servicios mensuales pendientes). `mis_permisos()` y `mi_perfil()` para armar el menú y aplicar color y modo.

## db-0008 · KPIs del panel y apariencia
Indicadores calculados en la base (`kpi_panel`): cada uno con importe o cantidad, porcentaje que lo pone en contexto, variación contra el período anterior y tono (ok, aviso, malo, neutral): facturación del mes, cobranza del mes, cartera vencida, margen de las OT, OT del mes finalizadas, cobranzas por distribuir, monotributo en riesgo, presupuestos aprobados y seguimientos vencidos, por pagar vencido y cuentas corrientes de asociados. Cada usuario ve solo los de los módulos que puede leer. Apariencia: color de la aplicación configurable por la organización (azul por defecto; verde, violeta, naranja, grafito o un color personalizado) y modo claro, sistema u oscuro por usuario.

## db-0007 · Monotributo, calendario y reportes
Control de monotributo: período anual o semestral desde el aniversario de cada asociado, límites versionados, acumulado (facturas emitidas con sus ND y NC, facturas a la Cooperativa, transferencias sin factura, ingresos externos y ajustes, sin contar dos veces un mismo pago), semáforo (sin límite, verde, amarillo, rojo, excedido), proyección al elegir el emisor de una factura y detalle. Calendario unificado con eventos derivados del estado de cada entidad (presupuestos, OT, SM, facturas, cobranzas, costos, matrículas, monotributo) y recordatorios manuales privados o compartidos. Reportes: facturas por cobrar y por pagar con tramos de vencimiento, libro de IVA ventas (por alícuota) y libro de IVA compras.

## db-0006 · Distribución
Reglas de reparto por OT, versionadas (porcentaje, importe fijo y residual; la Cooperativa puede participar; cada asociado como socio o profesional). Distribución de cada cobranza por OT (cada cobro parcial genera su instancia) en modo proporcional o costos primero; regla distinta solo para un cobro o como nueva versión, con motivo. Efectivo retenido por el asociado que cobró, retenciones absorbidas por el emisor, IVA y tributos cobrados por otro asociado. Ajuste automático cuando cambian los costos (alta, aprobación o reversión de un gasto), reversión proporcional cuando se resuelve una nota de crédito, reversión de cobranzas con su reparto, regalías en un solo paso y distribución automática opcional. Validación del monto de anticipo (neto, hasta el neto de la OT). Vistas de pendientes de distribuir y resumen financiero por OT.

## db-0005 · Facturación y cobranza
Facturas, notas de crédito y de débito (el sistema solo registra lo emitido en ARCA; unicidad por emisor, tipo, punto de venta y número; facturas internas sin CAE). Estados calculados: borrador, emitida, parcial, cobrada, acreditada, crédito a resolver. Borradores automáticos por anticipo y por OT de SM. Cobranzas con retenciones separadas (IVA / Ganancias-IIBB-otras), aplicación a facturas, sobrante a la cuenta corriente del cliente, aplicación de saldo a favor, reparto del cobro entre las OT de cada factura, reversión de cobranzas. Resolución del crédito de una nota de crédito (saldo a favor o devolución). Vistas de facturación y cobranza por OT. Deja ganchos (`hook_*`) para la Distribución.

## db-0004 · Costos y gastos
Gastos con conceptos (IVA discriminado o importe total), aprobación configurable y reversión con motivo (el gasto se anula, no se borra). Facturas de proveedor generadas o vinculadas desde los conceptos, con pagos parciales y cuenta de destino; las facturas de un asociado a la Cooperativa se cargan igual y se pagan con una liquidación. Subcontratos con costo contratado, real y saldo. Cuenta corriente de asociados como libro de movimientos (solo se agregan filas, lo anulado se contrarresta). Liquidaciones a asociados. Reversión de pagos de facturas, de conceptos sin factura y de liquidaciones. Vistas de costos por OT, resumen de gastos y facturas. Gancho `costos_cambiaron` para recalcular la distribución cuando exista (0005).

## db-0003 · Comercial y Operaciones
Presupuestos con versiones (mismo código, versión aparte), líneas con precio precargado y editable, descuentos opcionales, IVA por línea o en el subtotal, seguimiento y decisión por línea (aprobar genera la OT; rechazar exige motivo; reabrir). Órdenes de trabajo con estados controlados por funciones, reapertura auditada, equipo y OT directa con motivo. Servicios mensuales con precio versionado solo hacia adelante y generación de OT por período. Inicio automático de OT y generación automática de SM como funciones programables.

## db-0002 · Maestros
Condiciones y medios de pago, categorías de gasto, tipos de cambio (diario y promedio mensual), plantillas de presupuesto, clientes (con establecimiento y contacto principal automáticos), contactos, cuentas bancarias (un titular, una principal, número de cuenta para cuentas propias), asociados, proveedores y subcontratistas, servicios con precios versionados, documentos adjuntos. Campos críticos (documento, razón social, CBU) exigen permiso de administración y motivo.

## db-0001 · Fundaciones
Registro de migraciones, numeración de códigos (`PREFIJO-AAAA-NNNNN` y `PREFIJO-NNNNN`), listas editables, Organización con historial de condición ante IVA, usuarios, puestos y permisos (Puesto × Módulo × Nivel con excepciones por usuario), auditoría de cambios y utilidades para preparar tablas (RLS, auditoría, fecha de modificación).

## Próximos
Presupuestos y OT · pantallas de catálogos (listas editables, condiciones de pago, medios, categorías de gasto, tipos de cambio, plantillas) · Gastos, Facturación, Cobranzas, Distribución, Monotributo y Calendario ·  Costos y gastos  · Frontend · Bancos y Conciliación · Contabilidad.
