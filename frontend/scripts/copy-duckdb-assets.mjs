import { copyFileSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join } from 'node:path';

const require = createRequire(import.meta.url);
const out = join(process.cwd(), 'public', 'duckdb');

const files = [
  'duckdb-mvp.wasm',
  'duckdb-browser-mvp.worker.js',
  'duckdb-eh.wasm',
  'duckdb-browser-eh.worker.js',
];

mkdirSync(out, { recursive: true });
for (const file of files) copyFileSync(require.resolve(`@duckdb/duckdb-wasm/dist/${file}`), join(out, file));
console.log(`duckdb-wasm: ${files.length} archivos copiados a public/duckdb`);
