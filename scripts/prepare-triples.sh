#!/bin/sh
# Reescribe un parquet de tripletas como las tres permutaciones ordenadas que usa execute_sparql en el browser:
# <prefijo>_spo.parquet, <prefijo>_pos.parquet y <prefijo>_osp.parquet en data/, con columnas
# s, p, o, kind ('iri' | 'lit'), datatype, lang.
#
# Uso: scripts/prepare-triples.sh <parquet|url> <prefijo>
#      scripts/prepare-triples.sh --keep-order [--compact] <parquet|url> <nombre>
#   scripts/prepare-triples.sh /ruta/wikidata.parquet wiki
#   scripts/prepare-triples.sh --keep-order data/wikidata_pos.parquet wden_pos   # -> data/wden_pos.parquet
#
# --keep-order decodifica un parquet que ya viene ordenado (una permutación) a data/<nombre>.parquet sin
# reordenar: lectura y escritura secuencial, sin tabla intermedia, para entradas de decenas de GB.
#
# Acepta tres formas de entrada:
#   - ya separada: columnas s, p, o, kind, datatype, lang (se reordena y se reescribe tal cual);
#   - términos N-Triples en s, p, o: <iri>, _:b, "lit", "lit"@es, "lit"^^<datatype>;
#   - --compact: IRIs como <iri> o prefijo:local (prefijos de PREFIXES, por defecto
#     scripts/prefixes-wikidata.csv), blank nodes como _:b y literales sueltos, sin comillas ni tipo.
#     Los literales quedan sin datatype ni idioma, con los escapes \uXXXX decodificados. Un valor con un
#     prefijo que no está en la tabla es un literal: "Category:Foo" o "urn:uuid:$1" son texto en Wikidata.
#     Los blank nodes quedan como IRIs con el texto "_:b" (kind 'iri'); los joins funcionan igual.
#
# ROW_GROUP_SIZE (por defecto 100000) fija las tripletas por row group: más chico poda mejor, pero el footer
# del parquet (que el browser baja entero al abrirlo) crece con la cantidad de row groups.
set -eu

keep_order=false
compact=false
while :; do
  case "${1:-}" in
    --keep-order) keep_order=true; shift ;;
    --compact) compact=true; shift ;;
    *) break ;;
  esac
done
[ $# -eq 2 ] || { sed -n '6,7p' "$0" | sed 's/^# //' >&2; exit 1; }
cd "$(dirname "$0")/.."
src=$(printf '%s' "$1" | sed "s/'/''/g")
name=$2
rg=${ROW_GROUP_SIZE:-100000}

cols=$(duckdb -noheader -list -c "SELECT string_agg(name, ',' ORDER BY name) FROM parquet_schema('$src') WHERE name IN ('s','p','o','kind','datatype','lang');")

macros=""
if $compact; then
  [ "$cols" = o,p,s ] || { echo "--compact espera columnas s, p, o (encontradas: ${cols:-ninguna})" >&2; exit 1; }
  cols=compact
  # La tabla de prefijos va como MAP literal dentro de una macro (y no como join): una expresión por
  # fila no altera el orden de la entrada, que --keep-order necesita.
  map=$(duckdb -noheader -list -c "
    CREATE MACRO q(x) AS chr(39) || replace(x, chr(39), chr(39) || chr(39)) || chr(39);
    SELECT 'MAP {' || string_agg(q(prefix) || ': ' || q(namespace), ', ') || '}'
    FROM read_csv('${PREFIXES:-scripts/prefixes-wikidata.csv}', header = true, all_varchar = true);")
  case "$map" in "MAP {'"*) ;; *) echo "No se pudo leer la tabla de prefijos" >&2; exit 1 ;; esac
  # p tiene pocos valores distintos, así que revisarlo es barato; un prefijo que falte en la tabla
  # dejaría esos predicados sin expandir (s se conserva igual, pero no se revisa: es la columna grande).
  missing=$(duckdb -noheader -list -c "
    SELECT coalesce(string_agg(DISTINCT x, ' '), '') FROM (
      SELECT regexp_extract(p, '^([A-Za-z][A-Za-z0-9_.-]*):', 1) AS x FROM read_parquet('$src')
      WHERE NOT starts_with(p, '<') AND NOT starts_with(p, '_:'))
    WHERE map_extract_value($map, x) IS NULL;")
  [ -z "$missing" ] || { echo "Prefijos de p sin namespace en la tabla: $missing (agrégalos a ${PREFIXES:-scripts/prefixes-wikidata.csv})" >&2; exit 1; }
  macros="
    CREATE MACRO pfx(v) AS regexp_extract(v, '^([A-Za-z][A-Za-z0-9_.-]*):', 1);
    CREATE MACRO iri(v) AS CASE
      WHEN v LIKE '<%>' THEN v[2:-2]
      WHEN starts_with(v, '_:') THEN v
      WHEN map_extract_value($map, pfx(v)) IS NOT NULL THEN map_extract_value($map, pfx(v)) || v[length(pfx(v)) + 2:]
    END;
    CREATE MACRO lit(v) AS CASE WHEN contains(v, chr(92))
      THEN coalesce(try(json_extract_string(chr(34) || v || chr(34), '\$')), v) ELSE v END;"
fi

case "$cols" in
  compact)
    triples="
      SELECT coalesce(iri(s), s) AS s, coalesce(iri(p), p) AS p, coalesce(iri(o), lit(o)) AS o,
             CASE WHEN iri(o) IS NULL THEN 'lit' ELSE 'iri' END AS kind,
             NULL::VARCHAR AS datatype, NULL::VARCHAR AS lang
      FROM read_parquet('$src')" ;;
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
  duckdb -c "$macros
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
duckdb "$tmp/triples.duckdb" -c "$macros
  SET temp_directory = '$tmp/spill';
  CREATE TABLE triples AS $triples;
  COPY (FROM triples ORDER BY s, p, o) TO 'data/${name}_spo.parquet' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE $rg);
  COPY (FROM triples ORDER BY p, o, s) TO 'data/${name}_pos.parquet' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE $rg);
  COPY (FROM triples ORDER BY o, s, p) TO 'data/${name}_osp.parquet' (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE $rg);
  SELECT kind, datatype, lang, count(*) AS tripletas FROM triples GROUP BY ALL ORDER BY tripletas DESC;
"
ls -la "data/${name}"_*.parquet
