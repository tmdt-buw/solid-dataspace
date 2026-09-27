import { createServer } from '../../../../solid-tours/node_modules/vite/dist/node/index.js';
import react from '../../../../solid-tours/node_modules/@vitejs/plugin-react/dist/index.js';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));
const tours = fileURLToPath(new URL('../../../../solid-tours/', import.meta.url));
const server = await createServer({
  configFile: false,
  root,
  cacheDir: `${root}/.vite`,
  plugins: [react()],
  resolve: {
    alias: {
      react: `${tours}/node_modules/react`,
      'react-dom': `${tours}/node_modules/react-dom`,
    },
  },
  server: { host: '127.0.0.1', port: 4306, strictPort: true, fs: { allow: [root, tours] } },
});
await server.listen();
server.printUrls();
