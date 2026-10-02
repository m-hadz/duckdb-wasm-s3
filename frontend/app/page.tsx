'use client';
import { useState } from "react";
import { useDuckDb } from "@/hooks/useDuckDb";
import CsvDownloadButton from "@/components/CsvDownloadButton";
import SavedQueries from "@/components/SavedQueries";
import styles from "./page.module.css";

export default function Home() {
  const { conn, error: duckDbError, loading } = useDuckDb();
  const [queryUser, setQueryUser] = useState<string>("");
  const [result, setResult] = useState<Record<string, unknown>[]>([]);
  const [columns, setColumns] = useState<string[]>([]);
  const [executing, setExecuting] = useState<boolean>(false);
  const [error, setError] = useState<Error | null>(null);

  async function run() {
    if (!conn) return;
    setExecuting(true);
    setError(null);
    setResult([]);
    setColumns([]);
    try {
      const res = await conn.query(queryUser);
      setColumns(res.schema.fields.map((field) => field.name));
      setResult(res.toArray().map((row) => row.toJSON()));
    } catch (error) {
      setError(error instanceof Error ? error : new Error(String(error)));
    } finally {
      setExecuting(false);
    }
  }

  const isLoading = loading || executing;

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <span className={styles.title}>DuckDB Query</span>
        <span className={styles.titleAccent}>web embedded</span>
      </div>
      {duckDbError && (
        <div className={styles.errorBox}>
          <span className={styles.errorLabel}>Init error</span>
          <span className={styles.errorMessage}>{duckDbError.message}</span>
        </div>
      )}
      <div className={styles.editorWrapper}>
        <div className={styles.editorHeader}>
          <span className={styles.editorLabel}>SQL</span>
          <SavedQueries
            currentQuery={queryUser}
            onSelect={(sql) => setQueryUser(sql)}
          />
        </div>
        <textarea
          className={styles.textarea}
          value={queryUser}
          onChange={(e) => setQueryUser(e.target.value)}
          placeholder={`SELECT * FROM recipes LIMIT 10;`}
          spellCheck={false}
          onKeyDown={(e) => {
            if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') run();
          }}
        />
      </div>
      <div className={styles.actions}>
        <button
          className={styles.runButton}
          onClick={run}
          disabled={isLoading || !queryUser.trim()}
        >
          {isLoading ? 'Running...' : 'Run'}
        </button>
      </div>
      {error && (
        <div className={styles.errorBox}>
          <span className={styles.errorLabel}>Error</span>
          <span className={styles.errorMessage}>{error.message}</span>
        </div>
      )}
      <div className={styles.resultsWrapper}>
        <div className={styles.resultsHeader}>
          <span className={styles.resultsLabel}>Results</span>
          {isLoading && (
            <span className={styles.statusText}>
              <span className={styles.statusDot} />
              {loading ? 'loading duckdb' : 'executing'}
            </span>
          )}
          {result.length > 0 && (
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <span className={styles.rowCount}>{columns.length} cols × {result.length} rows</span>
              <CsvDownloadButton rows={result} filename="query_result" className={styles.downloadBtn} />
            </div>
          )}
        </div>
        {result.length === 0 ? (
          <div className={styles.resultsEmpty}>no results</div>
        ) : (
          <div className={styles.tableScroll}>
            <table className={styles.table}>
              <thead>
                <tr>{columns.map((col) => <th key={col}>{col}</th>)}</tr>
              </thead>
              <tbody>
                {result.map((row, i) => (
                  <tr key={i}>
                    {columns.map((col) => (
                      <td key={col}>
                        {row[col] === null || row[col] === undefined
                          ? <span className={styles.nullValue}>null</span>
                          : String(row[col])}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
