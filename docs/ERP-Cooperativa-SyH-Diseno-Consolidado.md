# ERP Cooperativa de Seguridad e Higiene — Documento de Diseño Consolidado

> Estado: **etapa de planificación conceptual cerrada.** Este documento resume todo lo definido, módulo por módulo, incluyendo entidades, campos clave, reglas de negocio y decisiones ya cerradas. **Todavía no incluye código ni DDL de PostgreSQL** — es el modelo conceptual acordado, listo como base para el diseño de tablas.

---

## 1. Alcance y contexto del proyecto

- **Tipo de sistema:** uso exclusivo interno de la cooperativa (no multi-tenant / no SaaS).
- **Facturación:** convive con un sistema externo conectado a ARCA. Este ERP **no emite** comprobantes — solo **registra** los datos de lo ya facturado (número/CAE, cliente, monto, OT(s) relacionadas, quién factura, fechas) para análisis contable/financiero y seguimiento de cobros.
- **Frontend:** etapa futura, probablemente Vercel (plan gratuito), replicando el diseño de la app *Yacamba* (sidebar, menú lateral, modo claro/oscuro, patrón de páginas).
- **Naturaleza del "motor de distribución":** es una distribución económica **interna y libre**, no atada a las reglas formales de excedentes cooperativos (Ley 20.337). Ejemplo dado: en una OT, el 100% del resultado puede ir a un solo asociado, con la Cooperativa participando solo para facturar.
- **Participantes posibles en la distribución:** coexisten socios de la cooperativa y profesionales que facturan como monotributistas/autónomos.
- **Situación actual:** proyecto nuevo, sin migración de movimientos históricos (se usará un módulo de Saldos Iniciales para arrancar desde el estado actual).
- **Escala actual:** menos de 15 asociados, 30 clientes activos, ~40 OT/mes, cooperativa en expansión.
- **Estilo de trabajo:** módulo por módulo, sin código todavía, proponiendo proactivamente elementos fundamentales de trazabilidad/consistencia no mencionados explícitamente por el usuario.

---

## 2. Arquitectura de módulos y orden de construcción

```
0. NÚCLEO / MAESTROS
        │
1. ORGANIZACIÓN Y SEGURIDAD (usuarios, puestos, permisos)
        │
2. COMERCIAL (clientes, cotizaciones/presupuestos)
        │
3. OPERACIONES (OT, Servicios Mensuales, líneas de servicio)
        │
    ┌───┼────────────┐
    ▼   ▼            ▼
4. COSTOS/GASTOS  5. DISTRIBUCIÓN
    │   │            │
    └───┼────────────┘
        ▼
6. FACTURACIÓN Y COBRANZA (registro de lo emitido en ARCA + cobros)
        │
        ▼
   BANCOS Y CONCILIACIÓN (importación de extractos, conciliación)
        │
        ▼
   Control de Monotributo (transversal, hookea en Distribución)
        │
        ▼
7. CONTABILIDAD (plan de cuentas, motor de asientos, libro diario/mayor)
        │
        ▼
8. CONTROL DE GESTIÓN / BI

  (transversales, construidos EN PARALELO)
9. TRAZABILIDAD Y AUDITORÍA

  (diferido para una versión posterior)
10. SEGURIDAD E HIGIENE — se gestiona hoy en otra app; a integrar más adelante si se decide
```

Decisión de diseño transversal que se repite en todo el sistema: **versionar en vez de editar**. Reglas de distribución, precios de SM, límites de monotributo y cotizaciones nunca se sobreescriben — se crea una nueva versión con vigencia desde una fecha, y la anterior queda intacta para auditoría e historial.

---

## 3. Módulo 0 — Núcleo / Maestros

**Datos de la Cooperativa / Organización** *(singleton)* — razón social, nombre de fantasía, CUIT, condición ante IVA, domicilio, teléfono, e-mail, web, **logo (imagen)**, **firma digital (imagen) y texto de firma**, cuentas bancarias propias, textos por defecto para presupuestos (condiciones comerciales, pie), moneda base, fecha de inicio de actividades del sistema. Estos datos llenan los presupuestos cuando la Cooperativa es la emisora. Los parámetros de configuración (aprobación de gastos, umbrales de monotributo, validez, seguimiento, IVA, descuentos, generación de SM, etc.) viven en el panel de Configuración general.

**Cliente** — nombre de fantasía, razón social/nombre, **tipo de cliente** (lista editable: Empresa, Comercio, …), tipo de documento (CUIT/CUIL/DNI) + número, contacto general (teléfono, e-mail), condición ante IVA, domicilio fiscal, condición de pago por defecto, estado (activo/inactivo/prospecto), fecha de alta, contacto principal (nombre, teléfono, e-mail), observación. *(Campos revisados con el cliente final.)* **Regla:** al crear un Cliente el sistema genera automáticamente su **Establecimiento principal** (con el domicilio fiscal y el contacto principal como contacto local) y su **Contacto principal** — sin doble carga. Todo Cliente tiene siempre al menos un Establecimiento (lo exigen Presupuestos y OT).

**Establecimiento del Cliente** — cliente, nombre/identificador del sitio, dirección, actividad/rubro (**lista editable**), contacto local (nombre, teléfono, e-mail), `es_principal`. *(Crítico para Seguridad e Higiene: visitas, matrices de riesgo y vencimientos ocurren por establecimiento, no por cliente en abstracto.)* La dirección operativa vive acá; el domicilio fiscal vive en Cliente (pueden diferir).

**Contacto** *(nuevo)* — cliente, establecimiento (opcional), nombre, rol (Principal/Pagos/Técnico/Decisor), teléfono, e-mail, `es_principal`. Relación 1:N sin tope técnico; **límite blando configurable** (sugerido 5). Los campos "contacto principal" del formulario de Cliente son la vista de la fila principal de esta tabla (única fuente de verdad).

**Cuenta Bancaria de Tercero** *(nueva, polimórfica)* — titular (**uno solo por cuenta**: Cooperativa / Cliente / Establecimiento / Asociado / Proveedor-Subcontratista; si una persona es a la vez cliente y asociado, son dos registros con sus propias cuentas), banco, CBU, alias, `es_principal`, activa. 1:N; **límite blando configurable** (sugerido 5); una sola principal por titular (la primera cuenta queda como principal y marcar otra como principal reemplaza a la anterior). Los campos Banco/CBU/Alias de los formularios de Asociado y Proveedor cargan la cuenta principal de esta tabla.

**Asociado** — apellido y nombre, tipo de documento (CUIT/CUIL) + número, DNI, **condición ante IVA** (Monotributo / Exento / Resp. Inscripto — define el IVA sugerido cuando emite presupuestos), fecha de nacimiento, **tipo de vínculo** (socio cooperativo / monotributista-autónomo / ambos), especialidad (lista), matrícula profesional, **vencimiento de matrícula** (genera solo un Evento de Calendario de alerta), banco/CBU/alias (cuenta principal), teléfono, e-mail, domicilio, localidad – código postal (lista), **logo propio (opcional), firma digital (imagen) y texto de firma (nombre, título, matrícula)** para los presupuestos que emite, estado (activo/inactivo/baja — inactivo y baja bloquean automáticamente nuevas asignaciones), fecha de alta, fecha de baja, observación. Ampliado luego con: `categoría_monotributo`, `límite_facturación_vigente` (versionado), `periodicidad_control` (Semestral/Anual), `fecha_aniversario_período` (propia de cada asociado).

**Proveedor / Subcontratista** *(una sola tabla)* — nombre de fantasía, razón social, tipo (`Proveedor` / `Subcontratista` / `Ambos`), **tipo y número de documento** (CUIT/CUIL/DNI: es el dato fiscal con el que se identifica al proveedor; evita duplicados y permite cruzar sus facturas) y **condición ante IVA**, contacto (apellido y nombre, teléfono, e-mail), banco/CBU/alias (cuenta principal), estado (activo/inactivo/baja), fecha de alta, fecha de baja, observación. **Una sola tabla porque** los campos son idénticos, un mismo tercero puede vender materiales y además subcontratar (evita duplicados y CUIT repetidos), y el modelo de 3 niveles (presupuestado/contratado/real) vive en la entidad **Subcontrato**, no en el maestro. Las pantallas de Subcontrato solo ofrecen terceros de tipo Subcontratista o Ambos.

**Servicio/Actividad** — categoría, subcategoría (ambas como maestros chicos de consulta, para evitar variantes de escritura), nombre, descripción, unidad de medida, estado, `actualizar_a_dólar` (Sí/No), observación. **Precio versionado** en `Servicio_Precio`: precio de referencia ARS sin IVA, precio de referencia USD sin IVA, vigente desde. Si `actualizar_a_dólar = Sí`, el precio ARS se recalcula con el último Tipo de Cambio cargado desde el panel de **Configuración general**; cada recálculo crea una nueva versión (no pisa la anterior). Las líneas de Cotización guardan su propio precio (snapshot), así que los presupuestos ya emitidos no cambian. **Decisión:** la indexación es una **configuración general** (activada/desactivada). Si está activa, la vista de Servicios muestra los botones "Actualizar todos" y "Actualizar seleccionados" (solo para los servicios marcados `actualizar_a_dólar = Sí`); no se recalcula solo al cargar cada TC.

**Centro de Costo** — nombre, código, descripción.

**Categoría de Gasto** — nombre, deducible (sí/no), tipo (costo directo / gasto recuperable / no recuperable), cuenta contable asignada, **`afecta_margen_distribuible`** (sí/no, por defecto — ej. "Materiales" = no, "Honorarios" = sí; editable por excepción en el Gasto puntual).

**Medio de Pago** — nombre, `requiere_días_acreditación` (sí/no), `días_acreditación_default` (ej. 30 para e-cheq). Permite distinguir fecha de cobro vs. fecha de disponibilidad real de fondos (impacto en flujo de caja).

**Condición de Pago** — contado, 30/60/90 días, etc. Default en Cliente, editable por Factura.

**Jurisdicción Fiscal (IIBB)** — provincia, alícuota, aplica Convenio Multilateral (sí/no).

**Tipo de Cambio** — fecha, valor (referencia: **Oficial**). Un registro por día. Aparte, **Tipo de Cambio Promedio**: un valor por período (mes), cargado a mano como dato propio (no se calcula con los diarios) y mantenido separado de ellos; sirve para convertir los resultados del período en los reportes.

**Listas editables** *(nuevas)* — valores que el usuario administra sin tocar código: Tipo de cliente, Actividad/Rubro, Unidades de medida, Categoría de servicio, Motivos de rechazo de presupuesto, **Tipo de comprobante** (Factura A/B/C, Ticket, Nota de crédito y de débito…), **Especialidad** (de los asociados), **Bancos**, **Localidad – Código postal** y **Categorías de monotributo**. Se guardan en una sola tabla genérica (lista + valor + activo + orden) con integridad por lista. Los catálogos con atributos propios (Condición de pago con días, Medio de pago con días de acreditación, Subcategoría de servicio, Categoría de gasto) siguen en tablas propias.

**Plantilla de Presupuesto** *(propuesta de diseño, a integrar; confirmado: logo y firma por emisor)* — separa datos, diseño y texto:
- **Datos** (ya existen) más campos nuevos: `descripción` editable por línea (los dos modelos usan descripciones más específicas que el nombre del servicio, p. ej. "Capacitación al personal (14 empleados)"), `plazo_entrega`, `tipo_facturación` (se sugiere según la condición del emisor: Monotributo → Factura C; usa la lista Tipo de comprobante) y condición de pago.
- **Diseño**: dos diseños que se programan una sola vez. *Compacto*: tabla de líneas + condiciones con título fijo (Facturación, Validez, Condiciones de pago, Tiempo de entrega). *Explicativo*: texto narrativo (saludo, contexto), lista numerada de servicios con su descripción y "valor unitario + IVA", aclaración y leyenda de total.
- **Plantilla (dato configurable)**: elige el diseño; aporta imagen de cabecera, pie y marca de agua, y los **textos predeterminados** de cada bloque con variables (`{cliente}`, `{fecha}`, `{validez_dias}`, `{condicion_pago}`, `{plazo_entrega}`, `{total}`…). Cabecera *compuesta* (fondo de la plantilla + logo y datos del emisor) o *imagen completa fija*. Opción de mostrar IVA: no / "+ IVA" / discriminado.
- **Texto editable por presupuesto**: al crear el presupuesto, los textos de la plantilla se **copian** al presupuesto y se editan ahí sin tocar la plantilla (con "restaurar texto de la plantilla"). Cambios posteriores de la plantilla no alteran presupuestos ya enviados.
- **Por emisor**: logo, firma digital y texto de firma (nombre, título, matrícula) viven en la Cooperativa y en cada asociado; el PDF usa los del emisor elegido.
- **Salida**: al marcar como enviado se genera el PDF y se guarda como Documento Adjunto (lo exacto que se envió); puede regenerarse. Hasta integrarlo, el envío solo se marca. Agregar un modelo nuevo = cargar una plantilla (imágenes + textos), sin programar, salvo que requiera un diseño de página distinto.
- *Confirmado:* las frases de condiciones (validez, pago, entrega) se calculan desde los campos del presupuesto y son editables; la descripción larga del servicio precarga la línea; cada plantilla define cómo se muestra el IVA (no mostrar / "+ IVA" / discriminado); la vista previa de los diseños se hace al final del proyecto.
- *Base cargada hoy en el prototipo:* maestro de plantillas con imagen de cabecera, pie y marca de agua, texto de condiciones, predeterminada y activa.

**Documento Adjunto** *(genérico, reutilizable por todos los módulos)* — tipo de entidad, id de esa entidad, tipo de documento, nombre de archivo, fecha de carga, usuario.

---

## 3.5 Códigos de documentos y registros

Todo documento y registro tiene un **código legible, único e inmutable** (nunca se reutiliza, aunque se cancele). Es lo que se ve en pantallas y reportes para seguir la cadena; internamente las relaciones usan el id.

- **Formato confirmado:** `PREFIJO-AAAA-NNNNN` para documentos (reinicio anual, 5 dígitos) y `PREFIJO-NNNNN` para maestros (continuo). Ej.: `PRE-2026-00012` (la versión es un campo aparte: v1, v2…), `SM-00003`, `OT-2026-00045`, `GAS-2026-00130`, `FPR-2026-00021` (factura de proveedor), `FAC-2026-00018` (factura emitida: código interno distinto del número/CAE de ARCA), `COB-`, `LIQ-`, `ASI-`; maestros `CLI-`, `EST-`, `ASO-`, `PRV-`, `SRV-`.
- Cada documento guarda el código de su origen (la OT muestra su presupuesto; el gasto, su OT y su factura de proveedor), lo que hace visible la trazabilidad.
- Un contador por (prefijo, año) se incrementa de forma atómica al crear el registro.

## 4. Módulo 1 — Organización y Seguridad

**Usuario** — nombre, email, estado, asociado vinculado (opcional — un usuario puede no ser asociado de negocio y viceversa), fecha de alta/último acceso.

**Puesto** — Director, Asociado, Administrativo (ampliable).

**Usuario × Puesto** — relación **muchos-a-muchos real** (confirmado: el Director actualmente también es Asociado).

**Permiso** — Puesto × Módulo × Nivel (`Sin acceso / Solo lectura / Operar / Administrar`).

**Excepción de Permiso** — override puntual (Puesto o Usuario × Módulo × Sub-apartado × Nivel).

**Log de Acceso** — usuario, fecha/hora, resultado (éxito/fallo).

**Log de Auditoría** *(transversal)* — tabla, id de registro, campo, valor anterior, valor nuevo, usuario, fecha, motivo (opcional). Se activa especialmente en: bajas, montos, reglas de distribución, cambios de estado, reaperturas.

---

## 5. Módulo 2 — Comercial

**Cotización/Presupuesto** — N° interno (correlativo), cliente y **establecimiento de cabecera** (del Maestro; precarga su dirección, rubro y contacto local; cada línea toma ese establecimiento por defecto y puede cambiarse, así una cotización puede cubrir varios sitios), fecha de realización (modificable), fecha de validez, condición de pago propuesta, **contacto**: se elige de la **lista de contactos registrados** del cliente y del establecimiento (o el contacto local del establecimiento) y sus datos (nombre/celular/e-mail) quedan editables en el presupuesto, responsable, estado de cabecera (`Borrador → Enviado` — "Vencido" calculado si pasa la validez sin decisión), `versión`, `cotización_anterior_id` (versionado, no edición destructiva), `motivo_revisión`.

**Línea de Cotización** — servicio (del Maestro, trae el precio ARS por defecto), **descripción editable** (por defecto la del servicio; es la que se imprime), establecimiento, cantidad, **unidad** (Cantidad/Visita/Capacitación/Hora/etc.), tomada de la unidad de medida del servicio y **no editable en la línea**: si hace falta otra unidad, se cambia en el Servicio (así el maestro y los documentos son consistentes), precio unitario, `neto` (= cantidad × precio unitario, calculado), descuento, **alícuota de IVA por línea** (solo si el modo de IVA configurado es "por línea"). **Estado propio e independiente por línea**: `Pendiente / Aprobada / Rechazada` — obligatorio definir el estado de cada línea antes de poder cerrar el presupuesto. Totales: neto, IVA y total; el IVA se detalla **en cada línea o en el subtotal final según la configuración general** (se guarda el modo usado en cada presupuesto).

**Vigencia y seguimiento** *(solo mientras la cabecera esté `Enviado`)*: el presupuesto guarda `fecha_envio` y `validez_días` (tomada de la configuración al enviarlo). `vence_el = fecha_envio + validez_días`; `próximo_seguimiento = (último_seguimiento, o fecha_envio si no hubo) + días_de_seguimiento` (por defecto 7, configurable). **Registrar seguimiento** (llamar o escribir al cliente) guarda la fecha y una nota opcional en un historial de seguimientos; `último_seguimiento` es la fecha más reciente. Al dejar de estar `Enviado` (Procesado) el seguimiento y el vencimiento dejan de mostrarse; si se reabre una línea rechazada, se reanudan.

**Emisor, precios, descuentos y plantillas**: el presupuesto tiene un **emisor** elegible entre la Cooperativa y los asociados activos; sus datos llenan el documento. El **IVA sugerido es 0 %** cuando el emisor es **Exento o Monotributo** (según su condición ante IVA); siempre editable. El **precio unitario** viene precargado del servicio pero es **modificable en la línea** (se guarda el precio usado y se marca si difiere del catálogo). **Descuentos configurables** en Configuración (ninguno / por línea / global); el IVA se calcula sobre el neto con descuento. Al aprobar una línea se puede adjuntar la orden de compra o aceptación del cliente; al rechazarla se elige un **motivo** de la lista editable. Una **nueva versión** se abre con el mismo armado del presupuesto, precargado con la versión anterior (agregar o quitar servicios, cambiar precios y cantidades, etc.); conserva el código y, al guardar, la anterior queda `Reemplazada` y sin seguimiento.

**Al aprobar una línea** se dispara automáticamente la creación de una **OT**, solicitando: fecha de inicio (puede ser futura) y si **requiere anticipo**. Si requiere anticipo, se genera además automáticamente una **Factura en estado `Borrador`** (ver Módulo 6) como recordatorio accionable — aparece en Calendario y en "Facturas Pendientes de Completar" aunque la OT recién arranque más adelante. **La Factura Borrador lleva la fecha de la decisión (el día en que se aprobó la línea) y es la que genera el recordatorio de facturación; la OT aparece en el calendario con su fecha de inicio.**

**Estado de cabecera de la Cotización**: `Borrador → Enviado → Procesado` (Procesado = todas las líneas con decisión final, sin importar si la mezcla es aprobada/rechazada). Reabrir una línea **Rechazada** la vuelve a `Pendiente` y regresa la cabecera a `Enviado` (auditado). Una línea **Aprobada** no se reabre así — ya generó una OT real. **La posibilidad de reabrir líneas rechazadas es, en sí misma, una configuración activable/desactivable** (`Organización.permite_reapertura_líneas`) — si está apagada, una línea Rechazada queda cerrada en forma permanente.

**Línea de Costo Estimado** *(opcional, no visible al cliente)* — costo directo estimado por línea, con el mismo flag `afecta_margen_distribuible` que en Categoría de Gasto, para que el margen previsto sea comparable con el margen real que usa Distribución.

**PDF de cotización** — se guarda como Documento Adjunto (snapshot real de lo enviado, por versión) y además puede regenerarse dinámicamente a partir de los datos vivos.

---

## 6. Módulo 3 — Operaciones (OT y Servicios Mensuales)

**OT (Orden de Trabajo)** — número interno (correlativo propio, no fiscal), Cliente, **Establecimiento** (una OT por establecimiento — decisión arquitectónica: mejor granularidad operativa, de costos y de distribución; no impide facturación consolidada porque Factura ya soporta relación N:N con OT), Cotización de origen (opcional), responsable, fechas previstas/reales, estado (`Borrador → Autorizada → En ejecución → Pausada → Finalizada → Cerrada`, más `Cancelada` para las que nunca se ejecutaron), **`requiere_anticipo`** (sí/no, define si se generó una Factura Borrador asociada).

**`modalidad`** *(nuevo)* — `Servicio` (default) o **`Regalía/Préstamo de Servicio`**: la cooperativa cobra una regalía. Sigue requiriendo Regla de Distribución. Usa una **Factura Interna** (`tipo=Interna`, sin CAE) que, al confirmarse la Regla de Distribución, dispara automáticamente Cobranza + Instancia de Distribución en un solo paso (ver Módulo 6 y sección 13). El ingreso se aísla contablemente en `4.6 Ingresos por Regalías` en vez de mezclarse con Honorarios por Servicios.

- Si `cotización_id` es nulo → OT sin presupuesto previo: guarda `motivo_autorización`, `autorizado_por`, `fecha_autorización` (auditoría simple, sin circuito de aprobación).
- `Cerrada` bloquea nuevos Gastos y cambios de Regla de Distribución. Reapertura posible, queda en el Log de Auditoría.
- `modo_distribución_parcial`: `Proporcional` (default) o `Costos primero` — define cómo se descuentan los costos que afectan margen cuando hay cobros parciales.

**Línea de Servicio de la OT** — servicio, cantidad, precio, costo estimado, asociado/subcontratista asignado, regla de distribución vigente (puede variar por línea), estado de ejecución (`Pendiente/En curso/Completada`).

**SM (Servicio Mensual)** — Cliente, Establecimiento, Servicio, precio mensual de referencia (versionado, ver abajo), periodicidad, condición de pago, regla de distribución por defecto, `día_generación` (día del mes en que se genera el período automáticamente), fecha de inicio, `fecha_fin_prevista` (solo alerta de preaviso, no dispara el fin automáticamente), estado (`Activo/Suspendido/Finalizado`).

**SM_Precio** *(historial versionado)* — valor, vigente desde. Los ajustes (ej. por inflación) aplican solo desde el próximo período, nunca retroactivamente.

**Período de SM = una OT generada automáticamente**, con `sm_id` y `período` (ej. "2026-09") como campos adicionales de OT. Nace pre-cargada con establecimiento/servicio/precio/regla del SM y luego vive el mismo ciclo de vida que cualquier OT. Se genera automáticamente el día definido, con opción de marcarla `Cancelada` si el servicio no se prestó ese mes.

---

## 7. Módulo 4 — Costos y Gastos

**Gasto** — OT (línea de servicio), categoría de gasto, concepto, importe, fecha, proveedor (opcional), **`quien_pagó`**, **`tipo_imputación`** (polimórfico, 4 valores):
  - **OT**: costo directo, impacta el margen de esa OT.
  - **Cooperativa**: gasto interno, no imputable a cliente.
  - **Recuperable de Cliente**: la cooperativa lo paga primero, queda marcado `facturado` (sí/no) para incluirlo como ítem propio en una factura futura (separado de honorarios).
  - **Asociado**: pasa directo a su cuenta corriente (puede ser responsabilidad personal del asociado).

  Comprobante (Documento Adjunto). Dos ejes de estado independientes: **Aprobación** (`Registrado → Aprobado`, automática si `Organización.requiere_aprobación_gastos = false`) y **Pago** (`Pendiente → Pagado`). **Contabilizado** es un flag técnico (con fecha) que se activa al quedar Aprobado.

- **Regla automática:** si `quien_pagó ≠ quien_asume`, se genera un movimiento en la Cuenta Corriente correspondiente (Asociado o Cliente, según el caso).

**Cuenta Corriente de Asociado** — libro de movimientos (nunca un saldo editable): asociado, fecha, concepto, referencia, importe con signo. Saldo siempre calculado por suma.

**Cuenta Corriente de Cliente** — misma lógica, para anticipos/saldos a favor originados en cobranzas que no cierran exactamente contra facturas.

**Liquidación a Asociado** *(nueva, agregada en esta ronda)* — asociado, fecha, monto, medio de pago, movimientos de cuenta corriente que cancela (total o parcial — permite "dejar la cuenta en cero"), comprobante. Genera su propio asiento contable.

**Subcontrato** — entidad propia (no una categoría de gasto más) con costo presupuestado, costo contratado, costo real y **saldo a pagar** (contratado − real). Genera uno o varios Gastos/Pagos reales a medida que se abona.

---

### Carga de gastos (confirmado)

- **Gastos generales** (sin OT: alquiler, servicios, sueldos…) y **Gastos operativos** (vinculados a una OT) son dos vistas de la misma estructura. Imputación posible: operativos → OT / Recuperable de Cliente / Asociado; generales → Cooperativa / Asociado.
- **Carga de gastos** (cabecera, código `GAS-`): OT (o ninguna), fecha, quién pagó, imputación, estado de aprobación y de pago (**una carga = un pagador y una fecha**; si otra persona pagó un concepto, va en otra carga). Contiene **varias categorías y, dentro de cada una, varios conceptos**. Cada **concepto** lleva: categoría, descripción, importe, `afecta_margen` (heredado de la categoría, editable), **proveedor (opcional)**, **n.º de factura del proveedor (opcional)**, comprobante (archivo opcional).
- **IVA opcional**: el concepto puede cargarse con IVA discriminado (neto + alícuota + IVA + total) o solo con el total. Solo el IVA discriminado genera IVA crédito fiscal.
- **Factura de Proveedor** *(nuevo módulo, `FPR-`)*: proveedor, tipo y número de comprobante, fecha, neto, IVA, otros tributos, total, vencimiento, estado de pago, adjunto. Los conceptos se vinculan a ella; al cargar proveedor + n.º de factura en un concepto, el sistema agrupa por proveedor + número y valida que la suma imputada no supere el total. No siempre hay factura: un concepto sin factura sigue siendo un gasto válido. La Factura de Proveedor se usa para **todos** los gastos (operativos y generales); tiene **vencimiento** (aparece en el Calendario mientras haya saldo), admite **pagos parciales** y un campo de **percepciones / otros tributos**. Si quien pagó fue un asociado, la factura se considera pagada (la deuda con él queda en su cuenta corriente).

## 8. Módulo 5 — Distribución

**No hay catálogo de reglas para elegir.** En el formulario de la OT (o de cada línea) se arma la tabla de participantes directamente ahí — al guardar, el sistema crea por detrás una Regla de Distribución versionada.

**Regla de Distribución** — OT o línea de servicio, `versión`, fecha de vigencia, motivo (si reemplaza a una anterior), estado (`Vigente`/`Reemplazada`). Inmutable — cambios = nueva versión.

**Participante de la Regla** — regla_id, tipo (Asociado / **Cooperativa — opcional, no fija/obligatoria** / Subcontratista), referencia a esa entidad, forma de participación (% / importe fijo / **residual**), valor.

- **Validación de cierre:** si hay un participante Residual, siempre cierra por construcción. Si no lo hay, la suma de %+importes fijos debe cerrar exactamente el 100% del resultado distribuible, o el sistema **bloquea el guardado** mostrando cuánto falta o sobra.

**Instancia de Distribución** — se genera al **cobrar** (real; también existe el cálculo proyectado sobre presupuestado/facturado, en modo simulación, para comparación en Control de Gestión, sin mover plata). Guarda referencia al cobro, versión de regla usada, resultado distribuible calculado, detalle por participante.

- **Cobros parciales:** cada cobro parcial dispara **su propia instancia de distribución independiente**, no se espera a completar el 100% de la factura.
- El modo (`Proporcional` / `Costos primero`) viene de la OT dueña de la línea.

---

## 9. Módulo 6 — Facturación y Cobranza

Premisa: **este sistema no emite** comprobantes (eso vive en el sistema de ARCA) — solo registra y gestiona el cobro.

**Factura** — `tipo` (`Fiscal` / **`Interna`** — sin CAE, usada para el caso Regalía), número/CAE (nulo mientras está en Borrador o si es Interna), cliente, **cero, una o varias OT relacionadas** (cero OT = registro histórico migrado, ver Migración por Excel más abajo), **desglose neto + IVA**, monto (ARS + TC aplicado + USD calculado), quién factura, fecha de emisión, condición de pago, estado (**`Borrador`** → `Emitida → Parcialmente cobrada → Cobrada`). Una Factura en `Borrador` nace automáticamente cuando se aprueba una línea de Cotización con anticipo requerido — es un recordatorio accionable, no existe todavía en ARCA.

**Línea de Factura** — factura_id, referencia directa a la **Línea de Servicio de la OT** (no solo a la OT — necesario para que la distribución de un cobro parcial sobre una factura multi-OT/multi-línea se reparta con precisión), monto.

**Cobranza** — medio de pago, fecha de cobro, **fecha de disponibilidad** (según días de acreditación del medio, editable), monto (ARS + TC aplicado + USD), comprobante.

**Cobranza — Aplicación** — cobranza_id + (factura_id + monto) **o** (movimiento a Cuenta Corriente de Cliente + monto). Regla de guardado: la suma de lo aplicado a facturas + lo aplicado a cuenta corriente debe igualar el total cobrado; si no cierra, **bloquea con alerta** mostrando la diferencia. La aplicación entre varias facturas siempre es **manual**.

**Tipo de cambio por movimiento** *(aplica a Gasto, Factura, Cobranza)* — cada movimiento guarda `tipo_cambio_id` (referencia al maestro, puede quedar vacío si ese día no se cargó) + `tipo_cambio_aplicado` (valor numérico editable, autocompletado por defecto con el del maestro de esa fecha, pero modificable para el caso puntual — ej. factura cargada tarde). `monto_usd` se calcula y se **congela** con el valor aplicado en el momento, no se recalcula después.

---

### Diseño vigente de Distribución, Facturación y Cobranza (confirmado e implementado en el prototipo)

*Este bloque prevalece sobre el texto inicial de las secciones 8 y 9.*

1. **Una OT = un servicio.** La regla de distribución y la facturación son **por OT**. Un trabajo con varios servicios son varias OT. No hay "Línea de Servicio de la OT" como entidad aparte.
2. **Factura emitida (solo registro, no emite en ARCA)**: emisor (**Cooperativa o asociado**), cliente, tipo de comprobante (lista editable), punto de venta + número + CAE (clase *Fiscal*) o sin CAE (clase *Interna*, regalías), fecha, vencimiento (según condición de pago del cliente), detalle por OT (neto + alícuota de IVA), otros tributos, total. Estado de cobro **calculado** (Emitida / Parcial / Cobrada) a partir de cobranzas y notas de crédito. Unicidad por emisor + tipo + punto de venta + número. **Anticipo** = primera factura parcial de la OT (nace como Borrador y se completa); luego se factura el saldo sin netear.
3. **Notas de crédito y de débito**: documentos propios (tipo de comprobante de la lista) vinculados a la factura; **se pueden emitir aunque la factura ya esté cobrada**. La nota de crédito reduce lo facturado de la OT y el total vigente de la factura (no puede superarlo); la de débito lo aumenta. Si una nota de crédito deja un importe **cobrado de más**, se elige: **devolver al cliente** (quién paga, medio de pago y cuenta del cliente) o **dejarlo como saldo a favor**. En ambos casos se **revierte proporcionalmente la distribución** ya hecha (ajuste por NC). El saldo a favor se puede **aplicar a facturas nuevas**. Suman o restan del acumulado de monotributo del emisor.
4. **Cobranza**: cliente, **quién recibió el dinero** (Cooperativa o asociado) y **cuenta destino** (de las cuentas del titular), medio de pago, fecha de cobro, **fecha de disponibilidad** (según los días de acreditación del medio), importe, comprobante opcional y detalle de retenciones. Se **aplica a mano** a facturas con dos importes por factura: *efectivo* y *retenciones*; el efectivo aplicado más el sobrante a la cuenta corriente del cliente debe igualar el importe cobrado, y lo aplicado no puede superar el saldo.
5. **Retenciones sufridas**, separadas en dos tipos: **IVA** (se calcula sobre el IVA de la factura: es un pago a cuenta del IVA que el emisor ingresa igual, por eso no pertenece al pozo distribuible ni lo absorbe el emisor) y **Ganancias / IIBB / otras** (se calculan sobre el neto: reducen el efectivo y las **absorbe quien emitió la factura**). Ambas cancelan saldo; ninguna es efectivo.
6. **Distribución** (una instancia por cada cobro de cada OT, aunque sea parcial): regla por OT armada en el formulario de la OT, **versionada** (% / importe fijo / residual; Cooperativa opcional; un solo residual; debe cerrar 100 % o tener residual). **Base = neto cobrado sin IVA − costos con "afecta margen = Sí"**. Modo *Proporcional* (margen proporcional a cada cobro) o *Costos primero*. Los importes fijos se prorratean por neto cobrado / neto de la OT. **Subcontratistas solo como costo** (Subcontrato); la distribución es entre asociados y Cooperativa.
7. **Variación en el cobro**: la instancia precarga la regla vigente; si se modifica, se elige **cada vez** si vale **solo para ese cobro** o como **nueva versión** desde ahí, con motivo obligatorio. Si la OT no tenía regla, la del primer cobro queda como v1.
8. **Se calcula y registra aunque los fondos no hayan ingresado** (ej. e-cheq): no hay bloqueo por fecha de disponibilidad; la disponibilidad figura en el listado y en el Calendario.
9. **Cuentas corrientes**: cada instancia acredita a cada asociado participante su parte, descuenta a quien recibió el dinero el **efectivo neto que retuvo** y descuenta al **emisor asociado** las retenciones que absorbe. La liquidación se registra con **comprobante del asociado**: factura a la Cooperativa o transferencia sin factura.
10. **Ajuste al cerrar la OT**: si por costos cargados después el resultado real difiere de lo distribuido, al cerrar se ofrece generar una **distribución de ajuste** según la regla vigente (o cerrar sin ajuste).
11. **Regalía** (OT con modalidad Regalía): en un solo paso se crean la factura interna (sin CAE), la cobranza y la distribución; requiere regla definida. El ingreso se aísla contablemente en la cuenta 4.6.
12. **OT**: muestra Facturado y Cobrado (neto) calculados.
13. **Códigos**: `FAC-`, `COB-`, `DIS-`, `LIQ-` con año y 5 dígitos, más el código del origen en cada documento.
14. **Pendiente / a futuro**: la factura que un asociado le hace a la Cooperativa como **documento propio** (hoy se registra en la liquidación: número e importe); importar comprobantes emitidos desde "Mis Comprobantes" de ARCA (cliente por CUIT); cuenta de origen en pagos a proveedores y devoluciones (para conciliar).
15. **OT**: la tabla muestra **gastos** y **margen estimado**, y un indicador de **facturación** (Sin facturar / Parcial % / Completa / Excedida). El botón *Gastos* lista las cargas de la OT. Una OT **Finalizada** sin facturar completa genera una alerta en el Calendario, y al **cerrarla** avisa cuánto queda sin facturar.
16. **Servicio mensual**: al generarse la OT del período se crea automáticamente su **factura en borrador** (recordatorio para hoy), igual que el anticipo.
17. **Pagos a proveedores**: cada pago registra la **cuenta destino** (banco · CBU · alias) elegida entre las cuentas del proveedor; se puede ver el detalle de pagos de cada factura.
18. **Liquidación a asociado**: registra la **cuenta de origen** (Cooperativa) y la **cuenta de destino** (asociado), además del comprobante (factura o transferencia sin factura). Si es el asociado quien paga a la Cooperativa, el sentido se invierte.

### Propuesta para Bancos y Conciliación y para Contabilidad (pendiente de confirmar)

**Bancos y Conciliación**: las cuentas propias de la Cooperativa son las de titular "Cooperativa" (ya cargables); se les suma tipo (cuenta corriente, caja de ahorro, billetera, efectivo), saldo inicial con fecha y la cuenta contable asociada. Los extractos (xlsx/csv/txt) se importan con una **plantilla de columnas por banco**, detectando duplicados. La conciliación **asistida** propone coincidencias por importe, fecha y cuenta contra: cobranzas (efectivo; la fecha de acreditación manda en e-cheq), pagos a proveedores, liquidaciones, devoluciones y transferencias entre cuentas propias; y siempre se puede **conciliar a mano**. Los movimientos sin documento (comisiones, impuesto a los débitos y créditos, intereses) se pueden convertir en un gasto general al conciliar. Los cobros que entran a la cuenta de un asociado no se concilian contra extractos de la Cooperativa.

**Contabilidad — asientos automáticos propuestos** (cada uno es una Regla Contable configurable):

| Hecho económico | Debe | Haber |
|---|---|---|
| Factura emitida por la Cooperativa | Deudores por Servicios (total) | Ingresos por Servicios (neto) · IVA Débito Fiscal · tributos a depositar |
| Cobranza | Banco/Caja (efectivo) · Retenciones sufridas (por tipo) | Deudores por Servicios |
| Nota de crédito / débito | inversa / igual a la factura | inversa / igual a la factura |
| Devolución al cliente | Anticipos de clientes o Deudores | Banco |
| Distribución a socio cooperativo | Anticipos a Asociados a Cuenta de Retorno | Cuenta Corriente Asociados |
| Distribución a monotributista | Honorarios a Asociados | Cuenta Corriente Asociados |
| Gasto | Cuenta de la categoría · IVA Crédito Fiscal (si se discrimina) | Proveedores / Banco / Cuenta Corriente Asociados |
| Pago a proveedor | Proveedores | Banco |
| Liquidación a asociado | Cuenta Corriente Asociados | Banco |
| Regalía | Banco | Ingresos por Regalías (4.6) |

## 9.5. Módulo — Bancos y Conciliación

Conecta directo con Cobranza, Gasto y Liquidación a Asociado: conciliar es confirmar que esos registros realmente pasaron por el banco.

**Cuenta Bancaria** — banco, número de cuenta/alias/CBU, moneda, saldo inicial (monto + fecha, mismo patrón que Saldos Iniciales). Efectivo/Caja Chica se modela igual, sin extracto para importar (movimientos manuales).

**Importación de Extracto** — cuenta bancaria, archivo (Documento Adjunto: xlsx/csv/txt), fecha de importación, usuario, cantidad de movimientos importados/duplicados detectados.

**Movimiento Bancario** — cuenta bancaria, fecha, descripción (tal cual el extracto), importe, origen (`Importado`/`Manual`), estado (`Sin conciliar`/`Conciliado`/`Conciliado parcial`).

**Conciliación** — movimiento_bancario_id + referencia a un registro interno (Cobranza / Pago de Gasto / Liquidación a Asociado / Transferencia entre Cuentas propias / Ajuste Manual) + monto aplicado. Misma regla de cierre que se repite en todo el sistema: la suma aplicada debe igualar el importe del movimiento, o queda `Conciliado parcial`.

**Conciliación: ambos modos siempre disponibles** — asistida (el sistema propone coincidencias por importe+fecha cercana y el usuario confirma) y manual (el usuario elige la coincidencia a mano), sin que uno excluya al otro.

### Dashboards (vistas de consulta — no son tablas nuevas, se arman sobre lo ya modelado)

- **Resumen Contable** — ingresos/egresos del período, resultado, comparación contra el período anterior.
- **Centro de Salud Financiera** — liquidez (caja+bancos vs. deudas de corto plazo), cuentas por cobrar vencidas, cuentas por pagar próximas a vencer, flujo de caja proyectado (usando fecha de disponibilidad real del cobro, no fecha de cobro), saldo total de cuentas corrientes de asociados.
- **Estados Financieros** — Balance General y Estado de Resultados, generados desde Plan de Cuentas y Mayor.
- **Conciliación Bancaria** — saldo según banco vs. saldo según sistema, movimientos pendientes de conciliar.
- **Estado de Cartera** *(propuesto)* — facturado vs. cobrado vs. vencido por cliente, y por asociado (distribuido en el período cruzado con su % de uso del límite de monotributo).

---

## 10. Control de Monotributo (transversal)

Objetivo: que ningún asociado supere el límite de su categoría, repartiendo la facturación entre asociados y la Cooperativa. **Es un cálculo derivado** (no se duplican datos): el acumulado se arma al consultar.

**Acumulado del período de cada asociado** = suma de:
1. **Facturas emitidas por él** a clientes (menos sus notas de crédito), por fecha de emisión y total.
2. **Lo que le facturó a la Cooperativa por su parte**, o **lo que la Cooperativa le transfirió sin factura** (se carga en la liquidación; nunca se cuentan las dos cosas por el mismo pago).
3. **Ingresos por fuera del circuito**: facturas propias y transferencias recibidas (carga manual).
4. **Ajuste**: fija el acumulado a una fecha (por ejemplo, lo que ya llevaba al arrancar); desde ahí solo suman los movimientos posteriores (los del mismo día cuentan si se cargaron después).

**Período y límite**: cada asociado tiene su propio aniversario y periodicidad (semestral o anual). El **límite se versiona** (categoría, importe, vigente desde). Los umbrales de aviso y crítico son iguales para todos y se configuran.

**Alertas y recomendación**: semáforo por asociado en la vista de control. Al **elegir el emisor de una factura**, el sistema muestra el % de uso y, si excede el límite, indica en cuánto y sugiere asociados con margen disponible o la Cooperativa. Al armar o ajustar una regla de distribución, cada participante muestra el % de su límite que alcanzaría con su parte.

---

## 11. Módulo 7 — Contabilidad

**Plan de Cuentas (versión granular, códigos jerárquicos):**

```
1. ACTIVO
 1.1 Corriente
  1.1.1 Caja y Bancos: Caja (pesos) · Banco Cta.Cte. ARS · Banco Caja Ahorro ARS
        · Mercado Pago · Ualá/Otras billeteras · Valores a Depositar
  1.1.2 Créditos por Servicios: Deudores por Servicios · Documentos a Cobrar
        (cheques/letras) · Deudores en Gestión
  1.1.3 Otros Créditos: IVA Crédito Fiscal · Retenciones Sufridas (Ganancias/IIBB)
        · Anticipos a Asociados a Cuenta de Retorno · Anticipos a Proveedores
        · Gastos Pagados por Adelantado
 1.2 No Corriente
  1.2.1 Bienes de Uso: Equipos de Medición SyH (dosímetros, sonómetros) ·
        Equipos de Cómputo · Mobiliario · Rodados · Amortizaciones Acum. (contracuenta)
  1.2.2 Intangibles: Software y Licencias

2. PASIVO
 2.1 Corriente: Proveedores · Subcontratistas a Pagar · Cuenta Corriente
     Asociados · Anticipos de Clientes · Cargas Fiscales (IVA Débito, IIBB a
     Pagar, Retenciones a Depositar) · Remuneraciones (Sueldos, Cargas
     Sociales, SAC, Vacaciones a Pagar)
 2.2 No Corriente: Préstamos Bancarios LP

3. PATRIMONIO NETO (cooperativa)
  Capital Social (Cuotas Sociales) · Reservas (Reserva Legal, Fondo de Acción
  Social y Cultural, Fondo de Educación y Capacitación) · Resultados
  (Excedentes Acumulados, Excedente del Ejercicio)

4. INGRESOS
  Honorarios por Servicios de SyH · Ingresos por SM · Reembolso de Gastos
  Recuperables · Ingresos Financieros · Diferencia de Cambio Positiva ·
  **4.6 Ingresos por Regalías/Préstamo de Servicio** (cuenta exclusiva, aísla
  este ingreso del resto)

5. COSTOS Y GASTOS
 5.1 Costos Directos: Honorarios a Asociados (monotributistas) ·
     Subcontrataciones · Materiales y Suministros (no afectan margen) · Viáticos
 5.2 Gastos Administrativos (RRHH): Sueldos Empleados · Cargas Sociales
     Empleados · Capacitación Empleados · Seguros (ART, vida)
 5.3 Gastos Operativos: Alquileres · Servicios (luz/internet) · Mantenimiento
     de Activos · Amortizaciones · Calibraciones de Equipos
 5.4 Gastos Comerciales: Publicidad y Comisiones
 5.5 Gastos Financieros: Intereses · Diferencia de Cambio Negativa ·
     Comisiones Bancarias
 5.6 Impuestos: Ingresos Brutos propios · Otros impuestos
```

**Plan de cuentas configurable** — la Cuenta Contable es un Maestro editable (no hardcodeado): código, nombre, tipo, `cuenta_padre_id` (para el árbol jerárquico). Permite crear cuentas nuevas libremente.

**Reclasificación Contable** *(nueva)* — para "mover lo que hoy está en una cuenta hacia otra" sin romper la inmutabilidad de los asientos ya asentados: es un **Asiento Contable especial** (origen `Reclasificación`) que debita la cuenta de origen y acredita la de destino por el monto a mover, a una fecha dada. Los asientos históricos nunca se reescriben — quedan tal cual, y la reclasificación corrige el saldo acumulado desde ese punto en adelante. *(Pendiente de confirmar si también hace falta un modo más simple de "renombrar/reorganizar" cuentas sin movimiento real todavía, que no requeriría asiento.)*

**Tratamiento contable de la distribución (definición cerrada con el usuario):**
- Monotributista/autónomo → gasto real (`Honorarios a Asociados`), reduce el resultado del ejercicio.
- Socio cooperativo → **`Anticipos a Asociados a Cuenta de Retorno`** (activo, no gasto) — se acumula durante el año y se cancela contra el retorno real que apruebe la asamblea al cierre. La cuenta contable a usar se determina según el `tipo_de_vínculo` del Asociado, no está hardcodeada.

**Período Contable** — fecha inicio/fin, estado (`Abierto`/`Cerrado`). **Cierre mensual** (para poder sacar balances mes a mes). Cerrado bloquea nuevos asientos en fechas de ese período (reapertura auditada, mismo patrón que OT).

**Asiento Contable** — número correlativo, fecha, concepto, tipo de hecho económico origen (Factura/Cobro/Gasto/Distribución/Liquidación/**Reclasificación**/**Ajuste Manual**), referencia al documento origen, usuario, estado (`Contabilizado`/`Revertido`). Se admite carga de **asientos manuales libres**. Nunca se edita — error se corrige con reversión + asiento nuevo. **Validación universal: `SUM(líneas.Debe) = SUM(líneas.Haber)` o no se guarda** — protege el equilibrio contable sin importar el origen del asiento.

**Línea de Asiento** — asiento_id, cuenta_contable_id, debe, haber, centro_de_costo_id (opcional).

**Regla Contable** *(motor configurable)* — por tipo de hecho económico, qué cuenta va al debe y cuál al haber. Desacopla la lógica contable del código.

**Saldos Iniciales** — cuenta_contable_id, centro_de_costo_id (opcional), monto debe/haber, fecha de arranque. Permite empezar sin migrar movimiento por movimiento.

---

## 8. Módulo — Control de Gestión / BI

Capa de lectura sobre lo ya modelado. Los tres niveles de tu documento original salen de fuentes ya definidas:

```
PRESUPUESTADO ──→ COMPROMETIDO ──→ REAL ──→ FACTURADO ──→ COBRADO ──→ DISTRIBUIDO
    │                  │              │          │            │            │
 Línea de          Subcontrato    Gasto      Factura     Cobranza    Instancia de
 Costo Estimado    (contratado)   (pagado)                            Distribución
 (Cotización)      + Gasto
                   (aprobado,
                    no pagado)
```

- **Presupuestado**: `Línea de Costo Estimado` de la Cotización de origen.
- **Comprometido**: `Subcontrato.costo_contratado` + `Gasto` Aprobado-no-Pagado.
- **Real**: `Gasto.Pagado` + `Subcontrato.costo_real`.
- **Facturado/Cobrado/Distribuido**: de sus módulos respectivos.

**Vista Resumen por OT** *(vista/consulta, no tabla)* — junta los 6 números por OT. **Las alertas se calculan siempre al consultar, no se guardan ni se descartan.**

**Dashboards propuestos:**
- **Cockpit Ejecutivo** (home del Director): facturación del mes vs. mismo mes año anterior, cash on hand, cash proyectado 30/60/90 días, OT abiertas y % de avance, alertas críticas.
- **Salud Financiera**: liquidez inmediata (caja+bancos − deudas 30 días = colchón en días de autonomía), flujo de efectivo proyectado a 90 días (gráfico de entradas/salidas/saldo), cobranzas por aging (por vencer / vencidas 1-30 / +30), DSO.
- **Rentabilidad por OT**: margen previsto vs. real, desvío en % y en $, top 10 más/menos rentables.
- **Rentabilidad por Asociado**: facturación generada, % de uso de límite de monotributo (semáforo), distribuciones acumuladas, ranking de aporte al resultado.
- **Rentabilidad por Cliente**: facturación/margen/días de cobro, concentración (% del total que representa cada cliente).

**KPIs formales:**

| KPI | Fórmula | Alerta |
|---|---|---|
| DSO | (Cuentas por cobrar / Facturación) × días | > 60 días |
| Margen promedio OT | (Ingresos − Costos) / Ingresos | < 20% |
| Cash runway | Liquidez / Burn rate mensual | < 2 meses |
| Concentración cliente | Facturación cliente / Facturación total | > 30% |
| % uso monotributo | Acumulado / Límite | > 80% aviso, > 95% crítico |
| OT en rojo | OT con costo > presupuesto | > 10% del total |
| Rotación asociados | OT activas / Total asociados | < 50% |

**Flujo de caja proyectado** combina: cobranzas registradas con `fecha_disponibilidad`, facturas emitidas no cobradas con fecha esperada según condición de pago, OT en ejecución con presupuesto (proyección de facturación futura), gastos aprobados no pagados (salidas comprometidas), SM activos (ingresos recurrentes garantizados).

## 9. Módulo — Trazabilidad y Auditoría

No es una tabla de grafo genérica — es la cadena de FKs explícita que ya existe por diseño:

```
Cotización → OT → Línea de Servicio → { Gasto, Subcontrato, Línea de Factura }
                                              ↓
                                    Factura → Cobranza → Instancia de Distribución → Liquidación → Asiento Contable
```

"Seguir el hilo" se resuelve con consultas fijas que saltan de tabla en tabla por esas FKs conocidas.

**Hecho Económico (línea de tiempo unificada)** *(nueva)* — registro liviano y automático por cada evento relevante de una OT (gasto cargado, factura emitida/cobrada, distribuido, liquidado): OT relacionada, fecha, tipo de evento, entidad de origen (tipo+id), monto, usuario. Permite ver "todo lo que pasó con esta OT" en una sola consulta cronológica, sin unir 6 tablas. Complementa —no reemplaza— al **Log de Auditoría** (Módulo 1), que registra cambios a datos, no eventos de negocio.

## Calendario — eventos derivados del estado

**Revisión de diseño:** los recordatorios automáticos **no se guardan como filas propias**: se calculan a partir del estado de la entidad que los origina, así desaparecen solos al cumplirse y nunca quedan desactualizados (no depende de que cada pantalla acuerde "cerrar" su evento). Solo los **eventos manuales** viven en una tabla (`Evento Manual`: fecha, título, entidad relacionada opcional, estado Pendiente/Cumplido).

**Regla general:** un recordatorio automático está vigente mientras su entidad origen siga en el estado que lo genera.

| Recordatorio | Fecha | Vigente mientras… | Desaparece cuando… |
|---|---|---|---|
| Inicio de OT | fecha de inicio prevista | OT en `Autorizada` | pasa a En ejecución (sola al llegar la fecha, o antes con el botón manual), Cancelada, etc. |
| Completar factura de anticipo | fecha de la decisión | Factura en `Borrador` | se marca Emitida |
| Completar factura de servicio mensual | fecha de generación | Factura en `Borrador` | se completa como Emitida |
| Facturar saldo de una OT finalizada | hoy | OT `Finalizada` con neto sin facturar | se factura el saldo |
| Seguimiento de presupuesto | próximo_seguimiento | cabecera `Enviado` | se registra el seguimiento (se recalcula) o pasa a Procesado |
| Vencimiento de presupuesto | vence_el | cabecera `Enviado` | pasa a Procesado |
| Vencimiento de factura | según condición de pago | Factura con saldo sin cobrar | se cobra |
| Vencimiento de factura de proveedor | vencimiento de la factura | saldo sin pagar | se paga el total (los pagos parciales la mantienen) |
| Disponibilidad de cobro diferido | fecha de disponibilidad | fecha futura | llega la fecha |
| Pago comprometido (gasto/subcontrato) | fecha pactada | pago `Pendiente` | se paga |
| Generación de período SM | día de generación | SM `Activo` | se genera la OT del período |
| Fin previsto de SM | fecha_fin_prevista | SM `Activo` | se finaliza o se extiende la fecha |
| Vencimiento de matrícula / calibración | fecha de vencimiento | asociado o activo vigente | se actualiza la fecha de renovación |

Un recordatorio vencido y todavía pendiente se marca como atrasado. Un interruptor **Ver cumplidos** muestra también lo ya cumplido (OT iniciada, factura emitida, seguimientos realizados), en gris y tachado; también se derivan del estado de cada entidad.

Vista: **Lista** o **Mes** (grilla con color por categoría); ambas leen los mismos eventos.

---

## 11.4 Ajustes de Operaciones y Costos (última ronda)

- **OT sin presupuesto**: botón propio; el precio unitario se precarga del servicio y es **editable**; exige motivo y registra quién autorizó y cuándo. Si requiere anticipo, genera la Factura Borrador igual que una OT aprobada desde presupuesto.
- **OT**: guarda su monto neto (de la línea aprobada, del servicio × cantidad, o del precio del SM). `Pausada`, `Cancelada` y reapertura exigen **motivo** (queda en el Log de Auditoría). Se registra el **inicio real** al pasar a En ejecución.
- **SM**: "Generar período" pide el mes y crea la OT con el precio vigente del contrato, iniciando el día de generación; **un solo período activo por mes** (si no se prestó el servicio, se cancela esa OT y se puede regenerar). El establecimiento debe pertenecer al cliente.
- **Gasto**: el pago registra fecha y **medio de pago** (nuevo maestro *Medios de pago*, con días de acreditación). La imputación OT o Recuperable de Cliente exige una OT abierta; *(a confirmar)* los gastos generales con imputación Cooperativa no requieren OT.
- **Subcontrato**: "Registrar pago" suma al costo real y genera el Gasto en la OT con categoría Subcontrataciones.

- **Inicio automático de OT**: cuando llega la fecha de inicio prevista, la OT `Autorizada` pasa sola a `En ejecución` (se registra el inicio real y el cambio en el historial). El botón manual sigue disponible para adelantarla. Es una configuración activable/desactivable y, junto con la generación automática de SM, requiere una tarea programada diaria en el servidor.
- **Observación** (texto libre) en la OT y en el Servicio Mensual: la OT generada por un SM hereda la del contrato y puede editarse después (queda en el historial).
- **SM — modo de generación configurable**: Manual (botón) o Automático (la OT del período se crea sola el día definido), en Configuración. Se distingue el *día de generación* de la OT del *día de inicio del servicio* (por defecto el mismo).
- **OT — equipo**: la OT tiene un único **responsable** y, opcionalmente, un **equipo** (asociados o subcontratistas con un rol).
- **Prospecto → Cliente**: un prospecto pasa a Activo cuando se aprueba su primera línea. **Documentos únicos**: no se permiten dos clientes, asociados o proveedores con el mismo tipo y número de documento.

## 11.5 Módulo — Gestión de Activos (desacoplado de Seguridad e Higiene)

**Activo** — nombre/tipo (ej. dosímetro, sonómetro, equipo de cómputo), cuenta de Bienes de Uso asociada, fecha de alta, valor de alta, `requiere_calibración` (sí/no), `periodicidad_calibración`, `fecha_próxima_calibración`.

**Calibración/Mantenimiento** *(historial)* — activo_id, fecha realizada, próxima fecha, costo (puede generar un Gasto), comprobante (Documento Adjunto). Cada calibración próxima a vencer genera un Evento de Calendario (alerta 30 días antes).

## 11.6 Empleado (RRHH mínimo, máx. 5 personas)

**Empleado** — distinto de Asociado (relación de dependencia, no monotributista/autónomo ni socio): nombre, CUIL, fecha de ingreso, sueldo, estado. Alimenta directamente las cuentas de Remuneraciones del Plan de Cuentas. Sin legajos ni licencias por ahora — solo lo necesario para que Sueldos/Cargas Sociales tengan origen real.

## 11.7 Migración por Excel

- **Saldos Iniciales Contables**: import masivo hacia la tabla `Saldos Iniciales` ya definida (Módulo 7) — plantilla con cuenta contable, monto debe/haber, centro de costo opcional.
- **Registro de Facturas ya realizadas**: import hacia `Factura`, pero **sin exigir Presupuesto ni OT** — solo cliente, establecimiento, fecha, monto, concepto. Es el caso de Factura con **cero OT relacionadas** ya contemplado arriba. Sirve para tener el historial de ingresos por cliente/establecimiento sin forzar una reconstrucción retroactiva del circuito operativo completo.

## 12. Fuera de alcance de esta primera etapa

- **Módulo de Seguridad e Higiene** (visitas, informes técnicos, matrices de riesgo, vencimientos legales): hoy se gestiona en otra aplicación. Queda **diferido para una versión posterior** — todavía no está decidido si se integra a este ERP. Cuando se retome, colgaría naturalmente de OT/Establecimiento sin requerir cambios en lo ya diseñado.
- **Portal de Asociados y Notificaciones push/email**: decisiones de canal de acceso, no de modelo de datos — se resuelven cuando exista frontend real.
- **Gestión Documental (DMS) como módulo propio** y **Workflow de Aprobaciones como entidad propia**: cubiertos por patrones ya existentes (Documento Adjunto genérico, y el check configurable de aprobación en Organización) — no justifican un módulo nuevo a este tamaño.

## 13. Cierres de la última ronda

**Regalía — Factura Interna con cobro automático**: Factura tiene `tipo` (`Fiscal` / `Interna`). Cuando es `Interna` y proviene de una OT/SM `modalidad=Regalía`, al confirmarse la Regla de Distribución de esa factura se generan automáticamente, en un solo paso, la Cobranza (monto total, fecha de la factura) y la Instancia de Distribución — sin pasar por el flujo manual de cobro.

**Estados de Cotización — cabecera vs. línea**: cabecera `Borrador → Enviado → Procesado` (Procesado = todas las líneas tienen decisión final, sin importar la mezcla aprobada/rechazada). Reabrir una línea **Rechazada** la vuelve a `Pendiente` y regresa la cabecera a `Enviado` (auditado, mismo patrón que reaperturas de OT/Período Contable). Una línea **Aprobada** no se reabre así — ya generó una OT real; deshacerla es cancelar esa OT, una operación distinta.

**Plan de Cuentas — remapeo y reclasificación**: remapear a qué cuenta apunta un concepto (ej. Categoría de Gasto → otra cuenta) hacia adelante es editar la Regla Contable/categoría directamente — seguro por construcción, porque cada Línea de Asiento ya generada guarda su cuenta congelada (no se ve afectada retroactivamente) y toda Regla Contable define Debe y Haber juntos. Mover saldos ya acumulados usa el Asiento de Reclasificación formal — **no permitido si el Período Contable de la fecha está `Cerrado`** (misma regla general de períodos cerrados que ya aplica a cualquier asiento). No hace falta un modo "simple" de reorganizar cuentas sin movimiento real — todo pasa por el mismo mecanismo. **Validación general de Contabilidad (no solo para esto): ningún Asiento Contable se guarda si `SUM(Debe) ≠ SUM(Haber)` en sus líneas** — protege el equilibrio en cualquier escenario (automático, manual o reclasificación).

---

## 14. Decisiones de diseño transversales (para tener presente al pasar a tablas)

1. **Versionar, nunca editar** reglas de negocio sensibles (Distribución, Precio de SM, Límite de Monotributo, Cotizaciones).
2. **Cuentas corrientes como libros de movimientos**, nunca como un campo de saldo editable — el saldo siempre se calcula.
3. **Tipo de cambio congelado por movimiento**, no recalculado retroactivamente — permite corrección manual puntual sin alterar el maestro.
4. **Estados con efecto real** (ej. OT Cerrada bloquea gastos y cambios de distribución), con reapertura siempre auditada.
5. **Permisos por Puesto**, no por persona, con relación Usuario×Puesto muchos-a-muchos y overrides puntuales.
6. **Configuración activable por check** (ej. aprobación de gastos) en la tabla Organización — patrón reutilizable para futuras aprobaciones sin rediseñar el modelo.
7. **Separación Asociado (entidad de negocio) vs. Usuario (cuenta de acceso)** — no son lo mismo y se vinculan opcionalmente.
8. **Campo de comentarios libres** en todos los documentos principales: Cotización, OT, Factura, Cobranza, Gasto, Subcontrato, Liquidación a Asociado.
9. **Historial de maestros**: los datos descriptivos se editan en el lugar y cada cambio queda en el Log de Auditoría (campo, valor anterior/nuevo, usuario, fecha), consultable desde un botón Historial en cada registro. El versionado queda reservado para valores que afectan cálculos (precios, límites, reglas).
10. **Baja lógica**: un registro con movimientos nunca se borra; pasa a Inactivo/Baja con fecha. *(Propuesta: cambios en campos críticos —documento, razón social, condición IVA, CBU— requieren nivel Administrar y motivo obligatorio.)*
11. **Panel de Configuración general** (todo lo configurable vive acá): tipo de cambio diario; indexación de servicios al dólar (on/off); detalle del IVA en presupuestos (por línea / en subtotal final) y alícuota por defecto; validez de presupuestos (días); días entre seguimientos; reapertura de líneas rechazadas (on/off); aprobación de gastos (on/off); inicio automático de OT (on/off); generación de SM manual/automática; carga del tipo de cambio promedio por período; límites blandos de contactos y cuentas bancarias por titular; umbrales de aviso y crítico del control de monotributo.
12. **Recordatorios derivados, no almacenados**: los eventos automáticos del calendario se calculan desde el estado de la entidad origen (ver Calendario); solo los eventos manuales se guardan.
13. **Código en cada documento y registro** (ver sección 3.5), con el código del origen visible para la trazabilidad.
14. **Listas editables** para valores de uso variable (tipo de cliente, actividad/rubro, unidades, motivos de rechazo…).

## 15. Cierres de la ronda del 31/10/2026

**Contabilidad — decisiones confirmadas**
- **Condición frente al IVA de la Cooperativa:** hoy Responsable Inscripta. Queda *versionada* (historial con "rige desde"): cada documento y cada asiento usa la condición vigente en su fecha, y un cambio futuro no altera lo ya registrado. Con RI habrá Libro IVA Ventas y Libro IVA Compras como reportes.
- **Asociado que factura directo al cliente:** la contabilidad de la Cooperativa registra **solo su participación** (no el ingreso total).
- **Asociado con vínculo "Ambos":** en cada regla de distribución se elige **cómo participa** (Socio → retorno / Profesional → honorarios). Se precarga según el vínculo y es obligatorio elegirlo cuando es "Ambos". Cada instancia de distribución guarda ese dato.
- **Cierre del ejercicio:** parámetro en Datos de la Cooperativa (día/mes, por defecto 31/12).
- **Centro de costo:** la OT; los gastos sin OT van al centro "Administración".

**Factura del asociado a la Cooperativa**
- Se registra como una **factura de proveedor normal**, eligiendo al asociado como emisor (el selector agrupa Proveedores y Asociados). Ya no se carga dentro de la liquidación.
- La **liquidación** ofrece las facturas abiertas del asociado y se aplica como **pago** de la elegida (Parcial / Pagada). Sin factura, es una transferencia sin factura.
- **Monotributo:** cuenta la factura (por su fecha y total); la liquidación aplicada a esa factura no vuelve a contar. La transferencia sin factura cuenta por separado.

**Revertir un gasto mal cargado**
- Se **anula, no se borra**: motivo obligatorio, queda en el log, deja de contar en costos y margen, y se revierten sus movimientos de cuenta corriente.
- Si había generado una factura de proveedor sin otras imputaciones ni pagos de la Cooperativa, esa factura también queda Anulada.
- No se puede revertir si la Cooperativa ya registró un pago del gasto (primero hay que corregir el pago). **Pendiente:** revertir pagos.

**Costos posteriores a la distribución**
- Todo gasto que afecta el margen (al cargarlo, al aprobarlo o al revertirlo) recalcula la distribución de la OT y genera automáticamente una instancia de **Ajuste** que actualiza las cuentas corrientes de los asociados.
- En el modo *Costos primero* el ajuste registra el costo ya descontado, para no restarlo dos veces en cobros futuros.
- El ajuste al cerrar la OT queda como red de seguridad.

**Gastos operativos:** al elegir la OT se ven la tarea, el cliente / establecimiento, el responsable, el estado y el neto; y en toda la app la OT se muestra como *código · tarea · cliente / establecimiento*.

**Pendiente:** ejemplo de extracto bancario (lo envía el usuario) para cerrar Bancos y Conciliación.

## 16. Revertir pagos (implementado en el prototipo)

Principio: **se anula, no se borra**. Todo queda en el log con motivo obligatorio y el registro original sigue visible como *Anulado*.

| Qué se revierte | Efecto |
|---|---|
| **Cobranza** | La factura recupera el saldo. Se anulan las distribuciones de esa cobranza y se contrarrestan sus movimientos en las cuentas corrientes de los asociados. Se revierte el sobrante o el saldo a favor aplicado en la cuenta del cliente. Se recalcula el reparto de cada OT (si había ajustes por costos, se corrigen) y en *Costos primero* se devuelve el costo ya descontado. |
| **Pago de factura de proveedor** | El pago queda anulado y la factura recupera ese saldo (Pagada → Parcial → Pendiente). |
| **Pago de gastos sin factura** | Los conceptos vuelven a estar pendientes de pago. |
| **Liquidación a un asociado** | Se contrarresta su movimiento en la cuenta corriente; si estaba aplicada a una factura del asociado, esa factura recupera el saldo; deja de contar para el monotributo si era una transferencia sin factura. |
| **Pago a subcontratista** | Se revierte desde el gasto que generó: el costo real del subcontrato vuelve a bajar. |

Restricciones:
- Una cobranza **no se puede revertir** si alguna de sus facturas ya tiene nota de crédito, ni si su sobrante ya se aplicó o se devolvió: primero hay que deshacer eso. Revertir notas de crédito y devoluciones queda **pendiente**.
- Un gasto no se puede revertir si la Cooperativa ya lo pagó: primero se revierte el pago.
- Los pagos hechos por un asociado se revierten revirtiendo el gasto; los que vienen de una liquidación, revirtiendo la liquidación.
- Cuando exista conciliación bancaria, revertir un pago **libera el movimiento bancario** (vuelve a Pendiente).

## 17. Bancos y Conciliación — diseño a partir del extracto real

*Reemplaza la propuesta de la sección 9.5. Se basa en dos extractos de una cuenta corriente, con el mismo contenido en CSV y en XLS.*

**17.1 Qué muestran los archivos**
- **Columnas:** Fecha, Concepto, Nro.Cpbte., Débito, Crédito, Saldo, Cód.
- **CSV:** codificación Latin-1, separador coma, decimal con punto, sin separador de miles, fecha dd/mm/aaaa.
- **XLS:** columna A vacía, filas en blanco intercaladas, importes numéricos y códigos numéricos que **pierden los ceros** (01274 → 1274). Hay que normalizar el código como texto.
- **Orden:** del más reciente al más antiguo; no hay hora, así que el orden del archivo desempata dentro del día.
- **Saldo:** es el saldo *después* de cada movimiento. No hay saldo inicial ni final explícito: el inicial es el saldo de la fila más antigua − crédito + débito. En la muestra los 13 movimientos encadenan sin diferencia, y esa validación (saldo anterior + crédito − débito = saldo) detecta faltantes, duplicados o filas fuera de orden.
- **Sin identificador único por movimiento.** Clave anti-duplicados: fecha + código + Nro.Cpbte. + débito + crédito + saldo (el saldo la vuelve única). Reimportar un período solapado agrega solo lo nuevo y se frena si el saldo no empalma.
- **El código del banco (Cód.) identifica el tipo** de movimiento: IVA de comisiones, impuesto Ley 25.413 sobre débitos y sobre créditos, comisión por transferencias inmediatas, acreditación de valores por cámara, transferencia inmediata a terceros, transferencias entre cuentas propias (salida y entrada).
- **Transferencias a terceros:** el concepto incluye CUIT, la referencia tipeada ("FAC"), el nombre y el **CBU de destino** → se puede identificar al beneficiario contra las Cuentas Bancarias del sistema (asociado, proveedor, cliente) y proponer el pago pendiente que corresponde.
- **Cargos bancarios:** el IVA es el 21% de la comisión del mismo día; el impuesto Ley 25.413 es el 0,6% de cada débito y de cada crédito (incluidas la comisión y su IVA). Sirve para validar y agrupar.
- **Transferencias entre cuentas propias:** el concepto trae el **número de cuenta**, no el CBU. En la muestra una suma grande entra y sale el mismo día (la cuenta funciona de puente). Cuenta Bancaria necesita un campo *N.º de cuenta* y las dos patas se vinculan como transferencia interna (no es ingreso ni gasto).
- **Acreditación de valores por cámara:** es el cobro de cheques o e-cheq depositados; se concilia con cobranzas por importe y fecha de disponibilidad, y una acreditación puede agrupar varias cobranzas.

**17.2 Datos**
- **Cuenta Bancaria** (ampliada): + N.º de cuenta, tipo (CC/CA), moneda, saldo inicial y fecha de corte.
- **Plantilla de extracto** (por banco y formato): codificación, separador, fila de cabecera, columnas, formato de fecha y de decimal, orden, filas a ignorar. Un banco puede tener varias (CSV y XLS).
- **Regla por código de banco** (editable): código → tipo de movimiento → tratamiento (convertir en gasto con categoría X, proponer conciliación, transferencia interna, ignorar), con opción *hacer automáticamente*.
- **Lote de importación:** cuenta, archivo, huella del archivo, período, saldo inicial y final, usuario.
- **Movimiento bancario:** lote, cuenta, fecha, orden, concepto, nro. de comprobante, débito, crédito, saldo, código, CUIT / CBU / nombre extraídos, estado (Pendiente / Conciliado / Ignorado).
- **Conciliación** (N:M): movimiento ↔ documento (cobranza, pago de factura de proveedor, liquidación, devolución, gasto bancario generado, transferencia interna) con importe aplicado.

**17.3 Flujo**
1. **Importar** y previsualizar: se valida que el saldo empalme, se descartan duplicados y se pide la cuenta.
2. **Clasificar** por código del banco.
3. **Sugerir** conciliación puntuando CBU/CUIT, importe exacto, fecha cercana y nombre. El usuario confirma.
4. **Acciones**:
   - Débito a un tercero conocido → propone el pago pendiente (liquidación, pago de factura de proveedor o devolución a cliente). Si no existe, *Crear el pago desde el movimiento* con fecha, importe, cuenta de origen y cuenta de destino precargadas.
   - Crédito → propone cobranzas; si no existe, crea la cobranza.
   - Comisión + su IVA → **un solo gasto general "Gastos bancarios"** con IVA discriminado (genera crédito fiscal, porque la Cooperativa es Responsable Inscripta).
   - Impuesto Ley 25.413 → gasto general con cuenta contable propia (computable como pago a cuenta si corresponde). Opción: imputarlo a la OT del movimiento que lo originó.
   - Entre cuentas propias → se emparejan las dos patas.
   - Ignorar, con motivo.
5. **Saldo conciliado vs. saldo del banco** por cuenta y cierre de conciliación por período.

**17.4 A confirmar**
- Si las cuentas que aparecen en las transferencias entre cuentas propias son de la Cooperativa y cuántas cuentas y bancos tiene.
- Un extracto de cada otro banco (¿mismos formatos?) y uno con **créditos por transferencia recibida**: la muestra solo trae acreditaciones de cámara.
- Si "FAC" es una referencia que tipean ustedes (serviría para reconocer pagos de facturas).
- Si el impuesto Ley 25.413 va como gasto general simple o prorrateado por OT.
- Pagos en lote, cheques propios y efectivo / caja chica.

**17.5 Confirmaciones y e-cheq**
- Las cuentas 439-0251987 y 439-0299077 **son ambas de la Cooperativa**: las transferencias entre ellas son transferencias internas (ni ingreso ni gasto) y se emparejan por número de cuenta.
- **Todavía no hay ejemplo de transferencia recibida** (el cliente no lo envió). El diseño la cubre con la misma lógica que las demás (CUIT / CBU del ordenante contra clientes e importe contra facturas pendientes), pero queda **sin validar contra un extracto real**.
- **Descarga de e-cheq (Excel, encabezado en A1):** Nro. de Cheque, Carácter, Fecha de Pago, Fecha Ult. Modificación, Moneda, Monto, Cuenta Emisor, Emisor, CUIT-CUIL CDI, Motivo, Id. Cheque, Endosado Por, CUIT Endosante, Cedido Por, Código Banco, Banco, Estado, Código Postal.
  - **Id. Cheque es único** → clave natural para no duplicar al reimportar (a diferencia del extracto bancario).
  - **Formatos distintos al extracto:** monto con punto de miles y coma decimal (3.873.452,00), CUIT con guiones, Motivo con espacios al final y texto libre ("Factura", "OP 9570", "OPCIT …": referencia a la factura o a la orden de pago del cliente), banco truncado, Cuenta Emisor vacía.
  - **Fecha de Pago = fecha de disponibilidad** de la cobranza. Un e-cheq futuro es plata comprometida que todavía no ingresó (coincide con la regla vigente de generar la distribución de cada cobro aunque los fondos no hayan ingresado).
- **Modelo:** entidad *Cheque electrónico* (id de cheque único, número, librador, CUIT, banco librador, importe, fecha de pago, motivo, endosante / cedente, estado: En cartera / Depositado / Acreditado / Rechazado / Endosado / Cedido). El librador se reconoce por CUIT contra el cliente; el cheque se aplica a facturas de ese cliente y genera la cobranza con medio *e-cheq* y disponibilidad = fecha de pago.
- **Conciliación:** una acreditación de valores por cámara del extracto agrupa uno o varios e-cheq por importe y fecha. Un e-cheq **rechazado** se resuelve con *Revertir cobranza* (sección 16).

## 18. Plan de construcción en Supabase (parte operativa, sin conciliaciones)

**Arquitectura.** Supabase (Postgres + Auth + Storage + RLS) y el frontend en Vercel (Next.js) replicando Yacamba. Las operaciones críticas (cobranza → distribución → cuentas corrientes, reversiones, ajustes por costos, generación de OT desde SM, aprobación de líneas del presupuesto) se escriben como **funciones de Postgres transaccionales**, no en el cliente: así el reparto y los saldos nunca quedan a medias. Lo derivado (cobrado y saldo de factura, costos y margen de OT, saldos de cuentas corrientes, estados, calendario) son **vistas**.

**Decisiones técnicas.**
- Importes `numeric(18,2)` y tipo de cambio `numeric(18,6)`; zona horaria America/Argentina/Buenos_Aires.
- Cuentas corrientes y movimientos de distribución **solo de inserción** (sin update ni delete); lo anulado se marca y se contrarresta.
- Auditoría genérica por trigger (tabla, campo, valor anterior y nuevo, usuario, fecha, motivo).
- Numeración `PREFIJO-AAAA-NNNNN` con reinicio anual mediante una función con bloqueo.
- Permisos Puesto × Módulo × Nivel como función `tiene_permiso(modulo, nivel)` usada en las políticas RLS de cada tabla.
- Migraciones versionadas en un repositorio (Supabase CLI) con datos semilla de las listas.

**Fases.**
1. **Fundaciones:** extensiones, auditoría, numeración, listas editables, Organización, usuarios, puestos y permisos.
2. **Maestros:** clientes, establecimientos, contactos, cuentas bancarias, asociados, proveedores, servicios, categorías, medios y condiciones de pago, tipos de cambio, adjuntos.
3. **Comercial y operaciones:** presupuestos (versiones, líneas, seguimiento), OT y SM.
4. **Costos y gastos:** gastos, facturas de proveedor, subcontratos, ajustes por costos y reversiones.
5. **Facturación, cobranza y distribución:** facturas, NC / ND, cobranzas, reglas, distribuciones, cuentas corrientes, monotributo y revertir pagos.
6. **Frontend** en Vercel (sidebar, claro / oscuro, calendario derivado) conectado a Supabase.
7. **Después:** Bancos y Conciliación (extractos, e-cheq), Contabilidad (asientos, libros de IVA), PDF de presupuestos.

Cada fase se prueba antes de entregarse contra un Postgres local con los mismos escenarios del prototipo (cobros, ajustes, reversiones, monotributo).

## 19. Migración 0003 — Comercial y Operaciones (en la base de datos)

**Modelo.** `presupuesto` (una fila por versión: mismo código, versión aparte), `presupuesto_linea`, `presupuesto_seguimiento`, `ot`, `ot_equipo`, `sm`, `sm_precio`; vistas `presupuesto_resumen` (totales, vence el, próximo seguimiento) y `sm_resumen`.

**Reglas que hace cumplir la base (no el frontend).**
- Los estados del presupuesto, de sus líneas y de la OT **no se cambian con un update**: solo con las funciones `enviar_presupuesto`, `aprobar_linea`, `rechazar_linea`, `reabrir_linea`, `nueva_version_presupuesto`, `cambiar_estado_ot`, `generar_ot_sm`.
- Un presupuesto enviado no se edita (solo sus comentarios): se crea una nueva versión.
- Aprobar una línea crea la OT, pasa el cliente prospecto a activo y, si todas las líneas tienen decisión, el presupuesto queda procesado. Reabrir una línea rechazada lo devuelve a enviado (configurable).
- Rechazar exige motivo (lista editable). El descuento por línea solo se admite si está habilitado en Organización.
- Un asociado dado de baja no puede ser emisor, responsable ni integrar el equipo.
- OT sin presupuesto: motivo obligatorio y queda registrado quién la autorizó.
- OT cerrada: no se modifica; reabrirla exige permiso de administración y motivo, y queda auditada.
- Precio del SM: solo hacia adelante (no se puede ajustar un período ya generado); una sola OT activa por SM y período; si se cancela, se puede regenerar a mano (la generación automática nunca la regenera).

**Supuestos tomados que conviene confirmar.**
1. Una *nueva versión* se crea solo desde un presupuesto **enviado** y **sin líneas aprobadas** (si ya hay OT, no se versiona).
2. Estados de OT: pendiente → en ejecución → finalizada → cerrada, más cancelada. Se puede reanudar una finalizada (con motivo) y reabrir una cerrada (con motivo y permiso de administración en Operaciones).
3. El **anticipo** se guarda en la OT (`requiere_anticipo`, monto opcional); la **factura en borrador** del anticipo y la de cada OT de SM se generan cuando exista Facturación (migración 0005).
4. Los presupuestos se emiten en pesos; el precio de la línea sale del precio ARS vigente del servicio.
5. La generación automática de SM crea la OT del mes desde el día de generación y no espera a la fecha de fin (que solo genera una alerta).
