'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState, type FormEvent } from 'react';
import { useAuth } from '@/components/AuthProvider';
import { supabase } from '@/lib/supabase';

function traducir(msg: string): string {
  if (/invalid login credentials/i.test(msg)) return 'El e-mail o la contraseña no son correctos.';
  if (/email not confirmed/i.test(msg)) return 'Todavía no confirmaste tu e-mail. Revisá tu bandeja de entrada.';
  if (/rate limit|too many/i.test(msg)) return 'Demasiados intentos. Esperá unos minutos y volvé a probar.';
  if (/failed to fetch|network/i.test(msg)) return 'No hay conexión con el servidor. Revisá tu internet.';
  return msg;
}

export default function Login() {
  const router = useRouter();
  const { estado, session } = useAuth();
  const [email, setEmail] = useState('');
  const [clave, setClave] = useState('');
  const [error, setError] = useState('');
  const [aviso, setAviso] = useState('');
  const [enviando, setEnviando] = useState(false);

  useEffect(() => { if (session && estado !== 'cargando') router.replace('/panel'); }, [session, estado, router]);

  const entrar = async (e: FormEvent) => {
    e.preventDefault();
    setError(''); setAviso(''); setEnviando(true);
    try {
      const { error: err } = await supabase().auth.signInWithPassword({ email: email.trim(), password: clave });
      if (err) setError(traducir(err.message)); else router.replace('/panel');
    } catch (ex) {
      setError(ex instanceof Error ? ex.message : 'No se pudo iniciar sesión.');
    } finally { setEnviando(false); }
  };

  const olvide = async () => {
    setError(''); setAviso('');
    if (!email.trim()) { setError('Escribí tu e-mail y volvé a tocar "Olvidé mi contraseña".'); return; }
    const { error: err } = await supabase().auth.resetPasswordForEmail(email.trim(), { redirectTo: `${window.location.origin}/login` });
    if (err) setError(traducir(err.message)); else setAviso('Te enviamos un e-mail para restablecer la contraseña.');
  };

  return (
    <main className="center">
      <form className="card login" onSubmit={entrar} noValidate>
        <div className="brand"><div className="logo">C</div><div><b>ERP Cooperativa</b><small>Seguridad e Higiene</small></div></div>
        <div className="field"><label htmlFor="em">E-mail</label>
          <input id="em" type="email" autoComplete="username" required value={email} onChange={(e) => setEmail(e.target.value)} /></div>
        <div className="field"><label htmlFor="cl">Contraseña</label>
          <input id="cl" type="password" autoComplete="current-password" required value={clave} onChange={(e) => setClave(e.target.value)} /></div>
        {error && <div className="alert" role="alert">{error}</div>}
        {aviso && <div className="alert info" role="status">{aviso}</div>}
        <button className="btn p" type="submit" disabled={enviando || !email || !clave} style={{ justifyContent: 'center' }}>{enviando ? 'Ingresando…' : 'Ingresar'}</button>
        <button type="button" className="btn" onClick={() => void olvide()}>Olvidé mi contraseña</button>
      </form>
    </main>
  );
}
