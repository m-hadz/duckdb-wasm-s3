'use client';

import { useEffect, useState } from 'react';
import type { AsyncDuckDB, AsyncDuckDBConnection } from '@duckdb/duckdb-wasm';

type DuckDbInstance = {
  db: AsyncDuckDB;
  conn: AsyncDuckDBConnection;
};

let instancePromise: Promise<DuckDbInstance> | null = null;

function sqlString(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

function sqlIdentifier(value: string): string {
  return `"${value.replace(/"/g, '""')}"`;
}

async function listParquetKeys(): Promise<string[]> {
  const keys: string[] = [];
  let token: string | null = null;
  do {
    const params = new URLSearchParams({ 'list-type': '2', delimiter: '/' });
    if (token) params.set('continuation-token', token);
    const res = await fetch(`/s3?${params}`);
    if (!res.ok) throw new Error(`No se pudo listar el bucket (${res.status})`);
    const xml = new DOMParser().parseFromString(await res.text(), 'application/xml');
    for (const el of xml.querySelectorAll('Contents > Key')) {
      const key = el.textContent ?? '';
      if (key.endsWith('.parquet')) keys.push(key);
    }
    token =
      xml.querySelector('IsTruncated')?.textContent === 'true'
        ? xml.querySelector('NextContinuationToken')?.textContent ?? null
        : null;
  } while (token);
  return keys;
}

async function createInstance(): Promise<DuckDbInstance> {
  const duckdb = await import('@duckdb/duckdb-wasm');

  const bundle = await duckdb.selectBundle({
    mvp: {
      mainModule: '/duckdb/duckdb-mvp.wasm',
      mainWorker: '/duckdb/duckdb-browser-mvp.worker.js',
    },
    eh: {
      mainModule: '/duckdb/duckdb-eh.wasm',
      mainWorker: '/duckdb/duckdb-browser-eh.worker.js',
    },
  });

  const worker = new Worker(bundle.mainWorker!);
  const logger = new duckdb.ConsoleLogger(duckdb.LogLevel.WARNING);
  const db = new duckdb.AsyncDuckDB(logger, worker);

  try {
    await db.instantiate(bundle.mainModule, bundle.pthreadWorker);
    const conn = await db.connect();

    const views = (await listParquetKeys())
      .map(
        (key) =>
          `CREATE OR REPLACE VIEW ${sqlIdentifier(key.slice(0, -'.parquet'.length))} AS
            SELECT * FROM read_parquet(${sqlString(new URL(`/s3/${encodeURIComponent(key)}`, window.location.origin).href)});`,
      )
      .join('\n');
    await conn.query(`
      SET home_directory='/tmp';
      SET autoinstall_known_extensions=true;
      SET autoload_known_extensions=true;
      LOAD httpfs;
      ${views}
    `);

    await conn.query(`
      INSTALL duckpgq FROM community;
      LOAD duckpgq;
    `);

    try {
      await conn.query(`
        SET enable_http_metadata_cache=true;
        SET enable_object_cache=true;
      `);
    } catch (e) {
      console.warn('DuckDB: no se pudieron activar las cachés de metadatos', e);
    }

    return { db, conn };
  } catch (error) {
    await db.terminate().catch(() => { });
    throw error;
  }
}

export function getDuckDb(): Promise<DuckDbInstance> {
  if (!instancePromise) {
    instancePromise = createInstance().catch((error) => {
      instancePromise = null;
      throw error;
    });
  }
  return instancePromise;
}

type State = {
  instance: DuckDbInstance | null;
  error: Error | null;
  loading: boolean;
};

export function useDuckDb() {
  const [state, setState] = useState<State>({
    instance: null,
    error: null,
    loading: true,
  });

  useEffect(() => {
    let cancelled = false;

    getDuckDb().then(
      (instance) => {
        if (!cancelled) setState({ instance, error: null, loading: false });
      },
      (error) => {
        if (cancelled) return;
        console.error('Failed to initialize DuckDB:', error);
        setState({
          instance: null,
          error: error instanceof Error ? error : new Error(String(error)),
          loading: false,
        });
      },
    );

    return () => {
      cancelled = true;
    };
  }, []);

  return {
    duckDb: state.instance?.db ?? null,
    conn: state.instance?.conn ?? null,
    error: state.error,
    loading: state.loading,
  };
}
