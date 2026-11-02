import fs from 'node:fs';
process.env.WORKER_DB_SECRET = fs.readFileSync('/secrets/worker-db.key', 'utf8').trim();
await import('/app/src/index.js');
