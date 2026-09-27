import { createServer, transformWithEsbuild } from '../../../../solid-tours/node_modules/vite/dist/node/index.js';
import react from '../../../../solid-tours/node_modules/@vitejs/plugin-react/dist/index.js';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const manager = fileURLToPath(new URL('../../../../solid-dataspace-manager/', import.meta.url));
const repos = ['solid-data-manager', 'semantic-data-catalog', 'solid-health-app', 'solid-chatbot', 'environmental-monitoring'].map(repo => fileURLToPath(new URL('../../../../' + repo + '/', import.meta.url)));
const server = await createServer({
  configFile: false, root, cacheDir: root + '/.vite',
  plugins: [{ name: 'local-language-fixture', enforce: 'pre',
    async transform(code, id) {
      if (!id.includes('/node_modules/') && id.endsWith('.js')) return transformWithEsbuild(code, id, { loader: 'jsx', jsx: 'automatic' });
    },
    configureServer(vite) {
      vite.middlewares.use((request, response, next) => {
        if (!request.url?.startsWith('/pod/')) return next();
        if (!['GET', 'HEAD'].includes(request.method)) { response.statusCode = 405; response.end(); return; }
        response.setHeader('Content-Type', request.url.endsWith('/') ? 'text/turtle' : 'text/plain');
        const resources = request.url === '/pod/' ? ['/pod/Settings/', '/pod/settings/', '/pod/Profile', '/pod/Sprache'] : ['/pod/Settings/Profile'];
        const body = request.url.endsWith('/')
          ? '@prefix ldp: <http://www.w3.org/ns/ldp#>. <> a ldp:Container; ldp:contains ' + resources.map(url => '<' + url + '>').join(', ') + '.'
          : 'Settings\nProfile\nSprache';
        response.setHeader('Content-Length', Buffer.byteLength(body));
        response.end(request.method === 'HEAD' ? undefined : body);
      });
    },
  }, react()],
  resolve: { alias: { react: manager + '/node_modules/react', 'react-dom': manager + '/node_modules/react-dom' } },
  optimizeDeps: { esbuildOptions: { loader: { '.js': 'jsx' } } },
  define: { 'process.env': {} },
  server: { host: '127.0.0.1', port: 4307, strictPort: true, fs: { allow: [root, manager, ...repos] } },
});
await server.listen();
server.printUrls();
