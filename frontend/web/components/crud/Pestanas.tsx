'use client';

import { useState, type ReactNode } from 'react';

export function Pestanas({ items }: { items: { titulo: string; contenido: ReactNode }[] }) {
  const [i, setI] = useState(0);
  return (
    <div>
      <div className="tabs" role="tablist">
        {items.map((t, k) => (
          <button key={t.titulo} role="tab" aria-selected={k === i} className={k === i ? 'on' : ''} onClick={() => setI(k)}>{t.titulo}</button>
        ))}
      </div>
      <div role="tabpanel" style={{ paddingTop: 12 }}>{items[i].contenido}</div>
    </div>
  );
}
