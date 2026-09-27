import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('.', import.meta.url));
const repo = path.resolve(root, '../../../solid-dataspace-manager');
const require = createRequire(path.join(repo, 'package.json'));
const { parse } = require('@babel/parser');
const generate = require('@babel/generator').default;
const canonical = node => generate(node, { comments: false, compact: true }).code;
for (const name of ['Notifications', 'DecisionInbox']) {
  const file = 'src/components/' + name + '.jsx';
  const old = execFileSync('git', ['-c', 'safe.directory=' + repo.replaceAll('\\', '/'), '-C', repo, 'show', 'a04a1de4d66cd551d50056d3b780636a8c04ced6:' + file], { encoding: 'utf8' });
  const next = fs.readFileSync(path.join(repo, file), 'utf8');
  const parseComponent = source => parse(source, { sourceType: 'module', plugins: ['jsx'] }).program.body.find(node => node.type === 'VariableDeclaration' && node.declarations[0].id.name === name).declarations[0].init;
  const before = parseComponent(old);
  const after = parseComponent(next);
  const businessCode = component => component.body.body.slice(0, -1).map(canonical).join('\n');
  if (businessCode(before) !== businessCode(after)) throw new Error(name + ': business logic changed');
  console.log(name + ': data loading, validation, state, filtering and action handlers unchanged.');
}
for (const file of ['src/components/Notifications.jsx', 'src/components/DecisionInbox.jsx', 'src/components/AccessInboxUi.jsx', 'src/components/AccessConfirmDialog.jsx', 'src/i18n.js']) {
  parse(fs.readFileSync(path.join(repo, file), 'utf8'), { sourceType: 'module', plugins: ['jsx'] });
}
require('postcss').parse(fs.readFileSync(path.join(repo, 'src/components/Notifications.css'), 'utf8'));
console.log('JavaScript/JSX and CSS parsed.');
