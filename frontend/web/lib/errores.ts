/** Convierte un error de Supabase/PostgREST en un mensaje claro para la persona. */
export function mensajeError(e: unknown): string {
  const err = e as { message?: string; code?: string; details?: string } | null;
  const msg = (err?.message ?? (typeof e === 'string' ? e : '') ?? '').trim();
  const code = err?.code ?? '';
  if (/failed to fetch|networkerror|load failed/i.test(msg)) return 'No hay conexión con el servidor. Revisá tu internet y volvé a intentar.';
  if (/jwt expired|invalid jwt/i.test(msg)) return 'Tu sesión venció. Volvé a iniciar sesión.';
  if (code === '23505' || /duplicate key/i.test(msg)) {
    if (/nro_doc|tipo_doc/.test(msg + (err?.details ?? ''))) return 'Ya existe un registro con ese documento.';
    if (/cbu/.test(msg + (err?.details ?? ''))) return 'Ya existe una cuenta con ese CBU.';
    if (/nro_cuenta/.test(msg + (err?.details ?? ''))) return 'Ya existe una cuenta con ese número.';
    return 'Ya existe un registro con esos datos.';
  }
  if (/row-level security|permission denied/i.test(msg)) return 'No tenés permiso para esta operación.';
  if (/violates foreign key/i.test(msg)) return 'El dato elegido ya no existe o está en uso en otro lugar.';
  if (/violates check constraint/i.test(msg)) return 'Hay datos que no cumplen las reglas del sistema. Revisá los campos.';
  if (/null value in column/i.test(msg)) return 'Falta completar un dato obligatorio.';
  if (/invalid input syntax/i.test(msg)) return 'Hay un dato con formato inválido.';
  return msg || 'Ocurrió un error inesperado.';
}
