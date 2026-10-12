import { copyFileSync, existsSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join } from 'node:path';

const require = createRequire(import.meta.url);
const out = join(process.cwd(), 'public', 'duckdb');
// Build propio con el fork de duckpgq (ver tools/duckdb-wasm-pgq). Si existe, tiene prioridad sobre npm.
const vendor = join(process.cwd(), 'vendor', 'duckdb-wasm-pgq');

const files = [
  'duckdb-mvp.wasm',
  'duckdb-browser-mvp.worker.js',
  'duckdb-eh.wasm',
  'duckdb-browser-eh.worker.js',
];

mkdirSync(out, { recursive: true });
for (const file of files) {
  const custom = join(vendor, file);
  const fromVendor = existsSync(custom);
  copyFileSync(fromVendor ? custom : require.resolve(`@duckdb/duckdb-wasm/dist/${file}`), join(out, file));
  console.log(`duckdb-wasm: ${file} <- ${fromVendor ? 'vendor/duckdb-wasm-pgq' : 'npm'}`);
}
