#!/bin/sh
# Compila la extensión rdf (duck_rdf) para duckdb-wasm v1.5.6 (wasm_eh) con los parches de este directorio
# y la deja en frontend/vendor/duckdb-rdf-wasm. Uso: tools/duckdb-rdf-wasm/build.sh [directorio-de-build]
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
work=$(mkdir -p "${1:-$repo/../build-rdf-wasm}" && cd "${1:-$repo/../build-rdf-wasm}" && pwd)

# Ref "variegata" (DuckDB 1.5.x) de extensions/rdf/description.yml en duckdb/community-extensions.
DUCK_RDF_REF=de345a85c40ccb023d09509181a597ba99c28ffe
SQL2RDF_TAG=v2.2.2
EMSDK_IMAGE=emscripten/emsdk:3.1.71

if [ ! -d "$work/duck_rdf" ]; then
  git clone https://github.com/nonodename/duck_rdf "$work/duck_rdf"
fi
cd "$work/duck_rdf"
git fetch origin "$DUCK_RDF_REF"
git checkout -f "$DUCK_RDF_REF"
git submodule update --init --recursive
git apply "$here/duck_rdf.patch"

if [ ! -d "$work/sql2rdf" ]; then
  git clone --branch "$SQL2RDF_TAG" https://github.com/nonodename/sql2rdf "$work/sql2rdf"
fi
cd "$work/sql2rdf"
git checkout -f "$SQL2RDF_TAG"
git submodule update --init --recursive
git apply "$here/sql2rdf.patch"

docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e SQL2RDF_SOURCE_DIR="$work/sql2rdf" \
  -v "$work:$work" -w "$work/duck_rdf" "$EMSDK_IMAGE" make wasm_eh

out="$repo/frontend/vendor/duckdb-rdf-wasm"
mkdir -p "$out/extensions/v1.5.6/wasm_eh"
cp "$work/duck_rdf/build/wasm_eh/repository/v1.5.6/wasm_eh/rdf.duckdb_extension.wasm" "$out/extensions/v1.5.6/wasm_eh/"

cat > "$out/BUILD_INFO.txt" <<EOF
extensión rdf (duck_rdf) compilada para duckdb-wasm, con los parches de tools/duckdb-rdf-wasm
built_at:   $(date -u +%Y-%m-%dT%H:%M:%SZ)
duck_rdf:   https://github.com/nonodename/duck_rdf @ $DUCK_RDF_REF + duck_rdf.patch
sql2rdf:    https://github.com/nonodename/sql2rdf @ $SQL2RDF_TAG + sql2rdf.patch
duckdb:     $(git -C "$work/duck_rdf/duckdb" describe --tags) ($(git -C "$work/duck_rdf/duckdb" rev-parse --short HEAD))
emscripten: $EMSDK_IMAGE
target:     wasm_eh (sin firma: requiere allowUnsignedExtensions)

sha256:
$(cd "$out" && sha256sum extensions/v1.5.6/wasm_eh/rdf.duckdb_extension.wasm)
EOF
cat "$out/BUILD_INFO.txt"
