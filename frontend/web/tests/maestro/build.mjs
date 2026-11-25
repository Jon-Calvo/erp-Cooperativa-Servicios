// Compila la prueba de interfaz del componente de maestros con un Supabase simulado.
import { build } from 'esbuild';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const aca = path.dirname(fileURLToPath(import.meta.url));
const web = path.resolve(aca, '../..');
await build({
  entryPoints: [path.join(aca, 'mtest.tsx')], bundle: true, platform: 'node', format: 'cjs', outfile: path.join(aca, '.out/mtest.cjs'),
  jsx: 'automatic', logLevel: 'error', tsconfig: path.join(web, 'tsconfig.json'),
  alias: { react: path.join(web, 'node_modules/react'), 'react-dom': path.join(web, 'node_modules/react-dom') },
  plugins: [{ name: 'simulados', setup(b) {
    b.onResolve({ filter: /^@\/lib\/supabase$/ }, () => ({ path: path.join(aca, 'mock/supabase.ts') }));
    b.onResolve({ filter: /AuthProvider$/ }, () => ({ path: path.join(aca, 'mock/auth.tsx') }));
  } }],
});
