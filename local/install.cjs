const fs = require('node:fs');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const hash = createHash('sha256');
for (const name of ['package.json', 'package-lock.json']) hash.update(fs.readFileSync(name));
hash.update(`${process.version}:${process.platform}:${process.arch}`);
const wanted = hash.digest('hex'), marker = 'node_modules/.local-install-sha256';
if (fs.existsSync(marker) && fs.readFileSync(marker, 'utf8') === wanted) {
  console.log('Reusing installed dependencies.');
} else {
  fs.rmSync(marker, { force: true });
  const result = spawnSync('npm', ['ci', '--no-audit', '--no-fund'], { stdio: 'inherit' });
  if (result.status !== 0) process.exit(result.status || 1);
  fs.writeFileSync(marker, wanted);
}
