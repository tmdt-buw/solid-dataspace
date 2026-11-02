const fs = require('node:fs');
const { randomBytes } = require('node:crypto');
for (const name of ['worker-access.key', 'worker-db.key']) {
  const file = '/secrets/' + name;
  try {
    fs.writeFileSync(file, randomBytes(48).toString('hex'), { flag: 'wx', mode: 0o640 });
    fs.chownSync(file, 1000, 1000);
  } catch (error) { if (error.code !== 'EEXIST') throw error; }
  if (fs.readFileSync(file).length < 32) throw Error('Invalid local secret: ' + name);
}
console.log('Persistent local worker keys ready.');
