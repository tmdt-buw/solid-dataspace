const fs = require('node:fs');
const path = require('node:path');
const pkg = JSON.parse(fs.readFileSync('/app/dist/package.json', 'utf8'));
for (const key of ['./embed', './embed.css']) {
  const value = pkg.exports?.[key];
  const files = typeof value === 'string' ? [value] : Object.values(value || {});
  if (!files.length) throw Error('Missing City Tours export: ' + key);
  for (const file of files) if (!fs.statSync(path.resolve('/app/dist', file)).size) throw Error('Empty export');
}
if (!process.argv.includes('--build-only')) {
  if (!fs.existsSync('/tmp/local-tours-ready')) process.exit(1);
  fetch('http://127.0.0.1:3006/city-tours/').then(r => { if (!r.ok) process.exit(1); }).catch(() => process.exit(1));
}
