const { execFileSync } = require('node:child_process');
const path = require('node:path');

const sourceFiles = [
  'src/index.js',
  'src/auth.js',
  'src/config.js'
];

for (const file of sourceFiles) {
  execFileSync(process.execPath, ['--check', path.join(__dirname, '..', file)], {
    stdio: 'inherit'
  });
}

console.log('api build passed');
