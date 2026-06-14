const { execFileSync } = require('node:child_process');
const path = require('node:path');

const files = [
  'src/index.js',
  'src/auth.js',
  'src/config.js',
  'scripts/build.js',
  'scripts/lint.js',
  'test/auth-routes.test.js'
];

for (const file of files) {
  execFileSync(process.execPath, ['--check', path.join(__dirname, '..', file)], {
    stdio: 'inherit'
  });
}

console.log('api lint passed');
