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

Además, dos optimizaciones del traductor de sql2rdf. No cambian resultados, pero sí el tamaño del SQL. YARRRML
obliga a tener un triples map por cada datatype/idioma, y el traductor arma un UNION con todos ellos en cada
patrón: con 16 maps, `q3` (3 patrones y 2 FILTER) generaba 373 KB de SQL, y DuckDB tardaba más en planificarlo
que en ejecutarlo.

| Optimización | Dónde |
|---|---|
| Un patrón con objeto (o sujeto) constante descarta los maps que no pueden producir ese término: `wd:Q5` no puede salir de un map de literales `@es`, ni `"x"@fr` de uno `@en` | `termMapCannotProduce` en `TriplePatternTranslator.cpp` |
| Un FILTER empujado a una rama cuyo tipo es estático, y que nunca puede ser verdadero ahí, elimina la rama: `LANG(?l) = "es"` en la rama `@en`; `?nac >= "1900"^^xsd:dateTime` en una rama decimal (error de tipo de SPARQL) | `neverTrue` en `ir/Optimizer.cpp` |

Solo deciden con variables y constantes cuyo tipo fija el mapping, y en los mismos casos en que el SQL dinámico
que se generaba antes evaluaba a FALSE/NULL en todas las filas. Pasan los 833 tests de sql2rdf, incluidos tests
nuevos que fallan sin los parches. En el benchmark de la raíz, q3 bajó de 686 a 253 ms (POS) y de 7.2 a 1.3 s
(SPO), y q5 de 503 a 235 ms, con el mismo número de filas.


El build no está firmado, así que el frontend abre DuckDB con `allowUnsignedExtensions: true` y lo carga con
`LOAD '<origen>/duckdb/extensions/v1.5.6/wasm_eh/rdf.duckdb_extension.wasm'`.
