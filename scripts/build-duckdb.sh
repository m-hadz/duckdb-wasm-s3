#!/bin/sh
# Genera un .duckdb con una tabla nativa por cada parquet (nombre de tabla = nombre del archivo).
# Uso: scripts/build-duckdb.sh [parquet|url ...]   (por defecto data/*.parquet)
#   OUT=data/otro.duckdb scripts/build-duckdb.sh http://localhost:9000/<bucket>/recipes.parquet
set -eu

cd "$(dirname "$0")/.."
out="${OUT:-data/tables.duckdb}"
tmp="$out.tmp"
rm -f "$tmp" "$tmp.wal"

[ $# -gt 0 ] || set -- data/*.parquet

sql=""
for f in "$@"; do
  case "$f" in
    http://* | https://* | s3://*) ;;
    *) [ -e "$f" ] || { echo "No existe: $f" >&2; exit 1; } ;;
  esac
  name=$(basename "$f" .parquet | sed 's/"/""/g')
  path=$(printf '%s' "$f" | sed "s/'/''/g")
  sql="$sql CREATE TABLE \"$name\" AS FROM read_parquet('$path');"
done

duckdb "$tmp" -c "$sql CHECKPOINT;"
mv "$tmp" "$out"
duckdb -readonly "$out" -c "SELECT table_name, estimated_size FROM duckdb_tables() ORDER BY 1;"
