'use client';

import { usePathname } from 'next/navigation';
import { tituloDeRuta } from '@/lib/menu';

export default function EnConstruccion() {
  const ruta = usePathname();
  return (
    <section className="card" style={{ maxWidth: 640, display: 'grid', gap: 8 }}>
      <h2 style={{ margin: 0 }}>{tituloDeRuta(ruta)}</h2>
      <p className="muted" style={{ margin: 0 }}>
        Esta pantalla se construye en la próxima etapa. Las reglas y los datos de este módulo ya están en la base de datos.
      </p>
    </section>
  );
}
