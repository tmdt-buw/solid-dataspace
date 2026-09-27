import { createServer, transformWithEsbuild } from '../../../../solid-tours/node_modules/vite/dist/node/index.js';
import react from '../../../../solid-tours/node_modules/@vitejs/plugin-react/dist/index.js';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const tours = fileURLToPath(new URL('../../../../solid-tours/', import.meta.url));
const server = await createServer({
  configFile: false,
  root,
  cacheDir: `${root}/.vite`,
  plugins: [{ name: 'manager-jsx-preview', enforce: 'pre', async transform(code, id) {
    if (id.replaceAll('\\', '/').includes('/solid-dataspace-manager/src/') && id.endsWith('.js')) return transformWithEsbuild(code, id, { loader: 'jsx', jsx: 'automatic' });
  } }, react()],
  resolve: {
    alias: {
      react: `${tours}/node_modules/react`,
      'react-dom': `${tours}/node_modules/react-dom`,
    },
  },
  optimizeDeps: { esbuildOptions: { loader: { '.js': 'jsx' } } },
  define: { 'process.env': {} },
  server: { host: '127.0.0.1', port: 4306, strictPort: true, fs: { allow: [root, tours, fileURLToPath(new URL("../../../../solid-dataspace-manager/", import.meta.url))] } },
});
await server.listen();
server.printUrls();
