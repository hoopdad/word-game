const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');

const rootDir = path.resolve(__dirname, '..');
const targetDirs = ['src', 'test', 'scripts'];

function collectJsFiles(dirPath, files = []) {
  if (!fs.existsSync(dirPath)) {
    return files;
  }

  const entries = fs.readdirSync(dirPath, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      collectJsFiles(fullPath, files);
      continue;
    }
    if (entry.isFile() && fullPath.endsWith('.js')) {
      files.push(fullPath);
    }
  }

  return files;
}

const files = targetDirs.flatMap((target) => collectJsFiles(path.join(rootDir, target)));
for (const filePath of files) {
  const check = cp.spawnSync(process.execPath, ['--check', filePath], { cwd: rootDir, encoding: 'utf8' });
  if (check.status !== 0) {
    process.stdout.write(check.stdout || '');
    process.stderr.write(check.stderr || '');
    throw new Error(`Syntax check failed for ${path.relative(rootDir, filePath)}`);
  }
}

console.log(`lint ok (${files.length} files checked)`);
