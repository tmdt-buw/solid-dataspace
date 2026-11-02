import http from 'node:http';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createAccessGateway } from './access.mjs';

const origin = new URL(process.env.LOCAL_ORIGIN || 'http://localhost:8080');
if (origin.protocol !== 'http:' || origin.hostname !== 'localhost') throw Error('Local mode requires http://localhost with an optional port.');
const issuer = new URL(process.env.LOCAL_ISSUER || 'https://solid-community-server.tmdt.info');
if (issuer.protocol !== 'https:' || issuer.username || issuer.password || issuer.port) throw Error('Use a public HTTPS Solid issuer.');
const registry = process.env.LOCAL_REGISTRY_URL || '';
if (registry && new URL(registry).protocol !== 'https:') throw Error('LOCAL_REGISTRY_URL must be an HTTPS registry URL.');
const admins = JSON.parse(process.env.LOCAL_ADMIN_WEBIDS_JSON || '[]');
if (!Array.isArray(admins) || admins.some(x => typeof x !== 'string' || !x.startsWith('https://'))) throw Error('Invalid local administrator WebIDs.');
const workspaceApps = [
  { id: 'plasma', enabled: process.env.LOCAL_PLASMA_ENABLED === 'true' },
  { id: 'node-red', enabled: process.env.LOCAL_NODERED_ENABLED === 'true' },
];
const providers = [{ id: 'local-issuer', label: 'Solid provider', issuer: issuer.href.replace(/\/$/, ''), enabled: true, recommended: true }];
const applications = [
  ['environmental-monitoring', 'Environmental Monitoring', 'temperature', 15],
  ['solid-health-app', 'Health App', 'health', 20],
  ['city-tours', 'City Tours', 'tour', 22],
  ['solid-health-questionnaire', 'Health Questionnaire', 'questionnaire', 24],
].map(([id, title, iconKey, order]) => ({ id, title, iconKey, order, href: '/web/' + id, section: 'applications', visible: true, enabled: true, linkType: 'internal' }));
applications.push(...workspaceApps.map(app => ({ ...app, visible: app.enabled })));
const registries = registry ? [{ id: 'test', label: 'Local development', url: registry }] : [];
const config = {
  dataspaceId: 'test', accessGateway: true, loginMode: 'oidc', plasmaUrl: '/plasma/modelings',
  providers, apps: applications, registries,
  branding: { projectName: 'TMDT Local', logoUrl: '/project-logos/Logo_TMDT.png', logoAlt: 'TMDT', logoWidth: '95px' },
  fundingLogos: [], cityToursLegacyContinuousWebIds: [],
  syncWorker: { enabled: true, apiUrl: '/sync-worker', serviceWebId: process.env.SOLID_SYNC_WORKER_WEBID || '', intervalMinutes: 10 },
  statistics: { enabled: false, adminWebIds: [] },
  administration: { enabled: false },
  catalog: { defaultRegistry: registry },
};
const profile = {
  id: 'test', environment: 'test', domains: [origin.host],
  public: { ...config, apps: workspaceApps },
  administration: { enabled: admins.length > 0, adminWebIds: admins },
};
const source = await fs.mkdtemp(path.join(os.tmpdir(), 'dataspace-local-'));
await fs.mkdir(path.join(source, 'profiles'));
await fs.writeFile(path.join(source, 'profiles/test.yaml'), JSON.stringify(profile));
const gateway = createAccessGateway({ source, environment: 'test', publicOrigin: origin.origin,
  keyFile: '/secrets/worker-access.key', resolveUpstream(_profile, app, requestPath) {
    let host, targetPath = requestPath;
    if (app === 'worker') host = 'solid-data-connection-sync-worker:8080';
    else if (app === 'node-red') host = 'node-red:1880';
    else {
      targetPath = requestPath.slice('/plasma'.length) || '/';
      host = /^\/api\/sms(?:\/|\?|$)/.test(targetPath) ? 'plasma-sms:8181'
        : /^\/api\/dps(?:\/|\?|$)/.test(targetPath) ? 'plasma-dps:8182' : 'plasma-frontend:80';
    }
    const url = new URL('http://' + host);
    const q = targetPath.indexOf('?');
    url.pathname = q < 0 ? targetPath : targetPath.slice(0, q);
    url.search = q < 0 ? '' : targetPath.slice(q);
    return url.href;
  },
});
if (gateway.publicOrigin !== origin.origin) throw Error('Update LOCAL_GATEWAY_IMAGE to the published local-development release (0.4.17 or newer).');
const server = http.createServer({ requestTimeout: 15000, headersTimeout: 10000, maxHeaderSize: 40000 }, async (req, res) => {
  try {
    if (req.url === '/health') { res.end('{"status":"ok"}'); return; }
    if (req.headers.host !== origin.host) { res.writeHead(421); res.end('Open ' + origin.origin); return; }
    const scripts = {
      '/local/config.js': 'window.__APP_CONFIG__ = ' + JSON.stringify(config) + ';\n',
      '/local/env.js': 'window._env_ = ' + JSON.stringify({ PUBLIC_CACHE_URL: '/sync-worker/public-cache', CATALOG_REGISTRIES: registries, CATALOG_DEFAULT_REGISTRY: registry, STATISTICS_ENABLED: false, STATISTICS_REGISTRY_CONTEXT: 'test' }) + ';\n',
    };
    const script = scripts[req.url.split('?')[0]];
    if (script !== undefined && ['GET', 'HEAD'].includes(req.method)) {
      res.writeHead(200, { 'Content-Type': 'application/javascript', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }); res.end(script); return;
    }
    if (!await gateway.handle(req, res)) { res.writeHead(404); res.end(); }
  } catch { if (!res.headersSent) res.writeHead(500); res.end(); }
});
server.on('upgrade', gateway.upgrade);
server.listen(3012, '0.0.0.0', () => console.log('Local gateway ready for ' + origin.origin));
for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => {
  gateway.close(); server.closeAllConnections(); server.close();
  fs.rm(source, { recursive: true, force: true }).finally(() => process.exit(0));
});
