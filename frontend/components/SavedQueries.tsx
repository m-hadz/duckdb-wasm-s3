'use client';
import { useState } from "react";
import styles from "./SavedQueries.module.css";

interface SavedQuery {
  id: string;
  name: string;
  description?: string;
  sql: string;
  createdAt: number;
}

interface Props {
  onSelect: (sql: string) => void;
  currentQuery: string;
}

export default function SavedQueries({ onSelect, currentQuery }: Props) {
  const [open, setOpen] = useState(false);
  const [queries, setQueries] = useState<SavedQuery[]>(() => {
    if (typeof window === "undefined") return [];
    try {
      return JSON.parse(localStorage.getItem("savedQueries") ?? "[]");
    } catch { return []; }
  });
  const [saveName, setSaveName] = useState("");
  const [saveDescription, setSaveDescription] = useState("");

  function save() {
    if (!currentQuery.trim() || !saveName.trim()) return;
    const newQuery: SavedQuery = {
      id: crypto.randomUUID(),
      name: saveName.trim(),
      description: saveDescription.trim(),
      sql: currentQuery,
      createdAt: Date.now(),
    };
    const updated = [newQuery, ...queries];
    setQueries(updated);
    localStorage.setItem("savedQueries", JSON.stringify(updated));
    setSaveName("");
    setSaveDescription("");
  }

  function remove(id: string) {
    const updated = queries.filter(q => q.id !== id);
    setQueries(updated);
    localStorage.setItem("savedQueries", JSON.stringify(updated));
  }

  return (
    <div>
      <button className={styles.triggerBtn} onClick={() => setOpen(true)}>
        Saved queries
      </button>

      {open && (
        <div className={styles.overlay} onClick={() => setOpen(false)}>
          <div className={styles.panel} onClick={e => e.stopPropagation()}>

            <div className={styles.panelHeader}>
              <span className={styles.panelTitle}>Saved queries</span>
              <button className={styles.closeBtn} onClick={() => setOpen(false)}>✕</button>
            </div>

            <div className={styles.saveRow}>
              <input
                className={styles.saveInput}
                placeholder="Query name..."
                value={saveName}
                onChange={e => setSaveName(e.target.value)}
                onKeyDown={e => { if (e.key === 'Enter') save(); }}
              />
              <input
                className={styles.saveInput}
                placeholder="Description (optional)..."
                value={saveDescription}
                onChange={e => setSaveDescription(e.target.value)}
              />
              <button
                className={styles.saveBtn}
                onClick={save}
                disabled={!saveName.trim() || !currentQuery.trim()}
              >
                Save current
              </button>
            </div>

            <div className={styles.list}>
              {queries.length === 0 && (
                <span className={styles.empty}>No saved queries</span>
              )}
              {queries.map(q => (
                <div key={q.id} className={styles.item}>
                  <div className={styles.itemInfo}>
                    <span className={styles.itemName}>{q.name}</span>
                    <span className={styles.itemPreview}>
                      {q.description ? q.description : q.sql.slice(0, 80) + '...'}
                    </span>
                  </div>
                  <div className={styles.itemActions}>
                    <button className={styles.loadBtn} onClick={() => { onSelect(q.sql); setOpen(false); }}>Load</button>
                    <button className={styles.deleteBtn} onClick={() => remove(q.id)}>Delete</button>
                  </div>
                </div>
              ))}
            </div>

          </div>
        </div>
      )}
    </div>
  );
}