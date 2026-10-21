# Extensión rdf para duckdb-wasm

Build propio de [duck_rdf](https://github.com/nonodename/duck_rdf) (`rdf` en community-extensions) para
duckdb-wasm v1.5.6 (`wasm_eh`). La versión publicada en community-extensions no sirve en el navegador para
`read_rdf` sobre HTTP ni para nada que use un mapping (`execute_sparql`, `sparql_to_sql`, `is_valid_r2rml`, ...).

```bash
tools/duckdb-rdf-wasm/build.sh   # deja el .wasm en frontend/vendor/duckdb-rdf-wasm
```

Necesita Docker; usa `emscripten/emsdk:3.1.71`, la misma versión con la que se compilan las extensiones de la
comunidad. El build queda en `../build-rdf-wasm` (varios GB).

## Qué corrigen los parches

| Problema en WASM | Causa | Parche |
|---|---|---|
| `execute_sparql` & co. se caen con `function signature mismatch` / `table index is out of bounds` | El link final del side module (`emcc -sSIDE_MODULE=2`) solo incluye las libs de `LINKED_LIBS`, y faltaban `sql2rdf_rdf` y `sql2rdf_type_catalog_loader`: `rdf::Term::*` y `loadTypeCatalog` quedaban sin resolver | `extension_config.cmake` |
| `Mapping file not found` aunque el mapping exista en S3/HTTP | El mapping se busca con `FileSystem::CreateLocal()` y lo lee sql2rdf con `fopen`/`ifstream` | `ResolveMappingFiles`/`ParseR2RMLOrYarrrmlMapping` usan el FileSystem de DuckDB (httpfs, S3, archivos registrados) y parsean desde string (`MappingParser::parseMultipleFromStrings`, nuevo en sql2rdf) |
| `read_rdf` por HTTP: `SERD parsing error` en el byte 16383 | serd toma una lectura corta como fin de archivo y el FileSystem HTTP de duckdb-wasm entrega bloques de 16 KiB | `ReadFully` en `serd_buffer.cpp`/`serd_range_buffer.cpp` |

El build no está firmado, así que el frontend abre DuckDB con `allowUnsignedExtensions: true` y lo carga con
`LOAD '<origen>/duckdb/extensions/v1.5.6/wasm_eh/rdf.duckdb_extension.wasm'`.
