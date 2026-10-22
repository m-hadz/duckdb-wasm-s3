#!/bin/sh
# Reescribe un parquet de tripletas como las tres permutaciones ordenadas que usa execute_sparql en el browser:
# <prefijo>_spo.parquet, <prefijo>_pos.parquet y <prefijo>_osp.parquet en data/, con columnas
# s, p, o, kind ('iri' | 'lit'), datatype, lang.
#
# Uso: scripts/prepare-triples.sh <parquet|url> <prefijo>
#      scripts/prepare-triples.sh --keep-order <parquet|url> <nombre>
#   scripts/prepare-triples.sh /ruta/wikidata.parquet wiki
#   scripts/prepare-triples.sh --keep-order data/wikidata_pos.parquet wden_pos   # -> data/wden_pos.parquet
#
# --keep-order decodifica un parquet que ya viene ordenado (una permutación) a data/<nombre>.parquet sin
# reordenar: lectura y escritura secuencial, sin tabla intermedia, para entradas de decenas de GB.
#
# Acepta dos formas de entrada:
#   - ya separada: columnas s, p, o, kind, datatype, lang (se reordena y se reescribe tal cual);
#   - términos N-Triples en s, p, o: <iri>, _:b, "lit", "lit"@es, "lit"^^<datatype>.
#
# ROW_GROUP_SIZE (por defecto 100000) fija las tripletas por row group: más chico poda mejor, pero el footer
# del parquet (que el browser baja entero al abrirlo) crece con la cantidad de row groups.
set -eu

keep_order=false
[ "${1:-}" = --keep-order ] && { keep_order=true; shift; }
[ $# -eq 2 ] || { sed -n '6,7p' "$0" | sed 's/^# //' >&2; exit 1; }
cd "$(dirname "$0")/.."
src=$(printf '%s' "$1" | sed "s/'/''/g")
name=$2
rg=${ROW_GROUP_SIZE:-100000}

cols=$(duckdb -noheader -list -c "SELECT string_agg(name, ',' ORDER BY name) FROM parquet_schema('$src') WHERE name IN ('s','p','o','kind','datatype','lang');")

case "$cols" in
  datatype,kind,lang,o,p,s)
    triples="SELECT s, p, o, kind, datatype, lang FROM read_parquet('$src')" ;;
  o,p,s)
    # Un literal N-Triples es "lexical" seguido opcionalmente de @lang o ^^<datatype>.
    term='^"(.*)"(@([A-Za-z0-9-]+)|\^\^<([^>]*)>)?$'
    # \" \' y \\ del lexical form (regex: \\(["'\\]) armada con chr() para no pelear con las comillas del shell)
    unescape="chr(92) || chr(92) || '([\"' || chr(39) || chr(92) || chr(92) || '])'"
    triples="
      WITH t AS (FROM read_parquet('$src'))
      SELECT regexp_replace(s, '^<(.*)>$', '\\1') AS s,
             regexp_replace(p, '^<(.*)>$', '\\1') AS p,
             CASE WHEN o LIKE '\"%' THEN regexp_replace(regexp_extract(o, '$term', 1), $unescape, '\\1', 'g')
                  ELSE regexp_replace(o, '^<(.*)>$', '\\1') END AS o,
             CASE WHEN o LIKE '\"%' THEN 'lit' ELSE 'iri' END AS kind,
             nullif(regexp_extract(o, '$term', 4), '') AS datatype,
             nullif(lower(regexp_extract(o, '$term', 3)), '') AS lang
      FROM t" ;;
  *)
    echo "Columnas no reconocidas en $1 (encontradas: ${cols:-ninguna}); se esperan s, p, o [, kind, datatype, lang]" >&2
    exit 1 ;;
esac

# Las estadísticas min/max por row group son las que permiten saltarse casi todo el archivo cuando el
# patrón fija la primera columna de la permutación.
if $keep_order; then
  out="data/$name.parquet"
  case "$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")" in
    "$(pwd)/$out") echo "La salida $out es la misma entrada; usa otro nombre" >&2; exit 1 ;;
  esac
  # Quitar <> y comillas casi no cambia el orden (las IRIs siguen ordenadas entre sí y los literales
  # también); preserve_insertion_order mantiene el de la entrada aunque DuckDB lea en paralelo.
  duckdb -c "
    SET preserve_insertion_order = true;
    COPY ($triples) TO '$out' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE $rg);
    SELECT count(DISTINCT row_group_id) AS row_groups, sum(row_group_num_rows) FILTER (column_id = 0) AS tripletas
    FROM parquet_metadata('$out');
  "
  ls -la "$out"
  exit
fi

# Base en disco y no en memoria: con ~100 M de tripletas la tabla no cabe en RAM.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/triples.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
duckdb "$tmp/triples.duckdb" -c "
  SET temp_directory = '$tmp/spill';
  CREATE TABLE triples AS $triples;
  COPY (FROM triples ORDER BY s, p, o) TO 'data/${name}_spo.parquet' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE $rg);
  COPY (FROM triples ORDER BY p, o, s) TO 'data/${name}_pos.parquet' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE $rg);
  COPY (FROM triples ORDER BY o, s, p) TO 'data/${name}_osp.parquet' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE $rg);
  SELECT kind, datatype, lang, count(*) AS tripletas FROM triples GROUP BY ALL ORDER BY tripletas DESC;
"
ls -la "data/${name}"_*.parquet
