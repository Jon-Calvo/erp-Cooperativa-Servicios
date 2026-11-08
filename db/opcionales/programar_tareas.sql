-- =====================================================================
-- OPCIONAL · Programar las tareas automáticas (se corre una sola vez)
-- No es una migración. Requiere habilitar la extensión pg_cron:
--   Supabase → Database → Extensions → buscar "pg_cron" → activar.
-- Los horarios de pg_cron son UTC: 03:05 UTC = 00:05 en Argentina.
-- Cada tarea respeta la configuración de Organización: si el inicio
-- automático de OT o la generación automática de SM están apagados, no hace nada.
-- =====================================================================
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise exception 'Primero activá la extensión pg_cron (Database → Extensions).';
  end if;
  perform cron.schedule('erp-iniciar-ots-vencidas',   '5 3 * * *',  'select public.iniciar_ots_vencidas()');
  perform cron.schedule('erp-generar-ots-sm',         '10 3 * * *', 'select public.generar_ots_sm_pendientes()');
end $$;

-- Para ver o quitar las tareas:
--   select * from cron.job;
--   select cron.unschedule('erp-iniciar-ots-vencidas');
--   select cron.unschedule('erp-generar-ots-sm');
