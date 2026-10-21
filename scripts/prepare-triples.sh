#!/bin/sh
# Reescribe un parquet de tripletas como las tres permutaciones ordenadas que usa execute_sparql en el browser:
# <prefijo>_spo.parquet, <prefijo>_pos.parquet y <prefijo>_osp.parquet en data/, con columnas
# s, p, o, kind ('iri' | 'lit'), datatype, lang.
#
# Uso: scripts/prepare-triples.sh <parquet|url> <prefijo>
#   scripts/prepare-triples.sh /ruta/wikidata.parquet wiki
#
# Acepta dos formas de entrada:
#   - ya separada: columnas s, p, o, kind, datatype, lang (se reordena y se reescribe tal cual);
#   - términos N-Triples en s, p, o: <iri>, _:b, "lit", "lit"@es, "lit"^^<datatype>.
set -eu

[ $# -eq 2 ] || { sed -n '5,6p' "$0" | sed 's/^# //' >&2; exit 1; }
cd "$(dirname "$0")/.."
src=$(printf '%s' "$1" | sed "s/'/''/g")
prefix=$2

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

# Row groups de 100k tripletas: las estadísticas min/max por row group son las que permiten saltarse
# casi todo el archivo cuando el patrón fija la primera columna de la permutación.
duckdb -c "
  SET preserve_insertion_order = true;
  CREATE TEMP TABLE triples AS $triples;
  COPY (FROM triples ORDER BY s, p, o) TO 'data/${prefix}_spo.parquet' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 100000);
  COPY (FROM triples ORDER BY p, o, s) TO 'data/${prefix}_pos.parquet' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 100000);
  COPY (FROM triples ORDER BY o, s, p) TO 'data/${prefix}_osp.parquet' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 100000);
  SELECT kind, datatype, lang, count(*) AS tripletas FROM triples GROUP BY ALL ORDER BY tripletas DESC;
"
ls -la "data/${prefix}"_*.parquet
