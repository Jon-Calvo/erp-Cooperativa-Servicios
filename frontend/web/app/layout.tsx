import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';
import { Providers } from '@/components/Providers';
import { SCRIPT_INICIAL } from '@/lib/theme';
import './globals.css';

export const metadata: Metadata = { title: 'ERP Cooperativa', description: 'Gestión de la cooperativa de Seguridad e Higiene' };
export const viewport: Viewport = { width: 'device-width', initialScale: 1, viewportFit: 'cover', colorScheme: 'light dark' };

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="es" data-brand="azul" suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" />
        <script dangerouslySetInnerHTML={{ __html: SCRIPT_INICIAL }} />
      </head>
      <body><Providers>{children}</Providers></body>
    </html>
  );
}
