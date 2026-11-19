import { createClient, type SupabaseClient } from '@supabase/supabase-js';

let cliente: SupabaseClient | null = null;

/** Cliente de Supabase para el navegador (una sola instancia). */
export function supabase(): SupabaseClient {
  if (cliente) return cliente;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) {
    throw new Error('Faltan las variables NEXT_PUBLIC_SUPABASE_URL y NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY.');
  }
  cliente = createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true } });
  return cliente;
}
