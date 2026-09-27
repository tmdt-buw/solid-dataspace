import { createServer, transformWithEsbuild } from '../../../../solid-tours/node_modules/vite/dist/node/index.js';
import react from '../../../../solid-tours/node_modules/@vitejs/plugin-react/dist/index.js';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('.', import.meta.url));
const manager = fileURLToPath(new URL('../../../../solid-dataspace-manager/', import.meta.url));
const server = await createServer({
  configFile: false, root, cacheDir: root + '/.vite',
  plugins: [{ name: 'isolated-access-ui', enforce: 'pre',
    resolveId(source, importer) {
      if (source === '@inrupt/solid-client') return root + '/sdk.js';
      if (source === '../solidSession') return root + '/session.js';
      if (source === '../config/runtimeConfig') return root + '/config.js';
      if (source === '../accessRequestModel' && /(?:Notifications|DecisionInbox)\.jsx$/.test(importer || '')) return root + '/model.js';
    },
    async transform(code, id) {
      if (!id.includes('/node_modules/') && id.endsWith('.js')) return transformWithEsbuild(code, id, { loader: 'jsx', jsx: 'automatic' });
    },
  }, react()],
  resolve: { alias: { react: manager + '/node_modules/react', 'react-dom': manager + '/node_modules/react-dom' } },
  optimizeDeps: { esbuildOptions: { loader: { '.js': 'jsx' } } },
  define: { 'process.env': {} },
  server: { host: '127.0.0.1', port: 4308, strictPort: true, fs: { allow: [root, manager] } },
});
await server.listen();
server.printUrls();
