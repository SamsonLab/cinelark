'use strict';

const { mkdirSync, rmSync } = require('node:fs');
const { spawnSync } = require('node:child_process');
const { resolve } = require('node:path');

const root = resolve(__dirname, '..');
const outputDirectory = resolve(root, 'dist');
const output = resolve(outputDirectory, 'CineLark.iinaplgz');

mkdirSync(outputDirectory, { recursive: true });
rmSync(output, { force: true });

const result = spawnSync('zip', ['-q', '-r', output, 'Info.json', 'src'], {
  cwd: root,
  stdio: 'inherit',
});
if (result.status !== 0) {
  throw new Error('Unable to package the IINA plugin. Ensure zip is installed.');
}
console.log(output);
