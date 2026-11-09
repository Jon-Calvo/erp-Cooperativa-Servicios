# Historial de cambios

## db-0004 · Costos y gastos
Gastos con conceptos (IVA discriminado o importe total), aprobación configurable y reversión con motivo (el gasto se anula, no se borra). Facturas de proveedor generadas o vinculadas desde los conceptos, con pagos parciales y cuenta de destino; las facturas de un asociado a la Cooperativa se cargan igual y se pagan con una liquidación. Subcontratos con costo contratado, real y saldo. Cuenta corriente de asociados como libro de movimientos (solo se agregan filas, lo anulado se contrarresta). Liquidaciones a asociados. Reversión de pagos de facturas, de conceptos sin factura y de liquidaciones. Vistas de costos por OT, resumen de gastos y facturas. Gancho `costos_cambiaron` para recalcular la distribución cuando exista (0005).

## db-0003 · Comercial y Operaciones
Presupuestos con versiones (mismo código, versión aparte), líneas con precio precargado y editable, descuentos opcionales, IVA por línea o en el subtotal, seguimiento y decisión por línea (aprobar genera la OT; rechazar exige motivo; reabrir). Órdenes de trabajo con estados controlados por funciones, reapertura auditada, equipo y OT directa con motivo. Servicios mensuales con precio versionado solo hacia adelante y generación de OT por período. Inicio automático de OT y generación automática de SM como funciones programables.

## db-0002 · Maestros
Condiciones y medios de pago, categorías de gasto, tipos de cambio (diario y promedio mensual), plantillas de presupuesto, clientes (con establecimiento y contacto principal automáticos), contactos, cuentas bancarias (un titular, una principal, número de cuenta para cuentas propias), asociados, proveedores y subcontratistas, servicios con precios versionados, documentos adjuntos. Campos críticos (documento, razón social, CBU) exigen permiso de administración y motivo.

## db-0001 · Fundaciones
Registro de migraciones, numeración de códigos (`PREFIJO-AAAA-NNNNN` y `PREFIJO-NNNNN`), listas editables, Organización con historial de condición ante IVA, usuarios, puestos y permisos (Puesto × Módulo × Nivel con excepciones por usuario), auditoría de cambios y utilidades para preparar tablas (RLS, auditoría, fecha de modificación).

## Próximos
0004 Costos y gastos · 0005 Facturación, cobranza y distribución · Frontend · Bancos y Conciliación · Contabilidad.
