type CsvDownloadButtonProps = {
  rows: Record<string, unknown>[];
  filename?: string;
  className?: string;
};

export default function CsvDownloadButton({ rows, filename = "data", className = "download-csv-btn" }: CsvDownloadButtonProps) {
  const handleDownload = () => {
    if (rows.length === 0) return;
    const columns = Object.keys(rows[0]);
    const csvContent = [
      columns.join(","),
      ...rows.map(row =>
        columns.map(col => {
          const val = row[col] ?? "";
          const str = String(val);
          return str.includes(",") || str.includes('"') ? `"${str.replace(/"/g, '""')}"` : str;
        }).join(",")
      )
    ].join("\n");

    const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${filename.replace(/\s+/g, "_")}.csv`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  return (
    <button className={className} onClick={handleDownload} disabled={rows.length === 0}>
      Download CSV
    </button>
  );
}