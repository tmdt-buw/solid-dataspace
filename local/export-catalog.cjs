// Reuse the catalog library already shipped with the selected Manager image.
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const source = '/app/node_modules/@hoelk-f/semantic-data-catalog';
const destination = '/packages';
const pkg = JSON.parse(fs.readFileSync(path.join(source, 'package.json'), 'utf8'));
fs.mkdirSync(destination, { recursive: true });
const result = spawnSync('npm', ['pack', '--ignore-scripts', '--json', '--pack-destination', destination], {
  cwd: source, encoding: 'utf8', env: { ...process.env, NPM_CONFIG_IGNORE_SCRIPTS: 'true' },
});
if (result.status !== 0) throw Error('Could not export the catalog package from the Manager image.');
const [{ filename }] = JSON.parse(result.stdout);
const integrity = 'sha512-' + createHash('sha512').update(fs.readFileSync(path.join(destination, filename))).digest('base64');
fs.writeFileSync(path.join(destination, 'packages.json'), JSON.stringify([
  { name: pkg.name, version: pkg.version, filename, integrity },
]) + '\n');
console.log(`Catalog ${pkg.version} ready for local City Tours development.`);
