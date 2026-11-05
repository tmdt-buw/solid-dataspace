const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const hash = createHash('sha256');
for (const name of ['package.json', 'package-lock.json']) hash.update(fs.readFileSync(name));
hash.update(`${process.version}:${process.platform}:${process.arch}`);
const packageDirectory = process.env.LOCAL_NPM_PACKAGE_DIR;
const bundled = packageDirectory
  ? JSON.parse(fs.readFileSync(path.join(packageDirectory, 'packages.json'), 'utf8')) : [];
const lock = JSON.parse(fs.readFileSync('package-lock.json', 'utf8'));
for (const pkg of bundled) {
  const entry = lock.packages?.['node_modules/' + pkg.name];
  if (!entry || entry.version !== pkg.version) {
    throw Error(`${pkg.name}: checkout requires ${entry?.version || 'an unknown version'}, Manager image provides ${pkg.version}. Select a matching LOCAL_MANAGER_IMAGE or update the City Tours checkout.`);
  }
  const archive = path.join(packageDirectory, path.basename(pkg.filename));
  const integrity = 'sha512-' + createHash('sha512').update(fs.readFileSync(archive)).digest('base64');
  if (integrity !== pkg.integrity) throw Error('Bundled package checksum mismatch: ' + pkg.name);
  entry.resolved = 'file:' + archive;
  entry.integrity = integrity;
  hash.update(integrity);
}
const wanted = hash.digest('hex'), marker = 'node_modules/.local-install-sha256';
if (fs.existsSync(marker) && fs.readFileSync(marker, 'utf8') === wanted) {
  console.log('Reusing installed dependencies.');
} else {
  fs.rmSync(marker, { force: true });
  // Keep the checkout manifests unchanged when resolving bundled packages.
  const staging = bundled.length ? fs.mkdtempSync(path.join(os.tmpdir(), 'local-npm-')) : null;
  try {
    if (staging) {
      fs.copyFileSync('package.json', path.join(staging, 'package.json'));
      fs.writeFileSync(path.join(staging, 'package-lock.json'), JSON.stringify(lock));
    }
    const result = spawnSync('npm', ['ci', '--no-audit', '--no-fund'], {
      cwd: staging || process.cwd(), stdio: 'inherit',
    });
    if (result.status !== 0) throw Error('Dependency installation failed; see npm output above.');
    if (staging) {
      fs.mkdirSync('node_modules', { recursive: true });
      for (const name of fs.readdirSync('node_modules')) fs.rmSync(path.join('node_modules', name), { recursive: true, force: true });
      fs.cpSync(path.join(staging, 'node_modules'), 'node_modules', { recursive: true, verbatimSymlinks: true });
    }
    fs.mkdirSync('node_modules', { recursive: true });
    fs.writeFileSync(marker, wanted);
  } finally {
    if (staging) fs.rmSync(staging, { recursive: true, force: true });
  }
}
