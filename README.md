## Estructura

```
.
├── docker-compose.yaml   # minio + minio-init + frontend
├── minio/init.sh         # crea el bucket, policy de solo lectura, sube ./data
├── data/                 # archivos a subir al bucket
└── frontend/             # app Next.js
```

## Levantar todo

```bash
cp .env.example .env
cp /ruta/a/archivos.parquet data/
docker compose up -d --build
```

- App: http://localhost:3000
- Archivos (proxy de Next a MinIO): http://localhost:3000/s3/<archivo>.parquet
- Consola MinIO: http://localhost:9001

## Preparar los parquet

DuckDB-wasm descarga row groups completos, así que un parquet con un solo row
group obliga a bajar el archivo entero aunque la query tenga `LIMIT 10`.
Antes de subirlos, conviene reescribirlos con row groups chicos (~3-5 MB cada
uno) y ZSTD:

```sql
COPY (FROM 'original.parquet') TO 'data/tabla.parquet'
  (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 25000);
```

Para filas anchas (texto largo, listas) baja `ROW_GROUP_SIZE`; `recipes` usa 10000.
Para revisar el tamaño de cada row group:

```sql
SELECT row_group_id, row_group_num_rows, sum(total_compressed_size) / 1e6 AS mb
FROM parquet_metadata('data/tabla.parquet') GROUP BY ALL ORDER BY 1;
```

## Tablas nativas (.duckdb)

Además de los parquet, el frontend adjunta en solo lectura cada `.duckdb` que
haya en la raíz del bucket, usando el nombre del archivo como catálogo. Para
generar uno con una tabla nativa por cada parquet de `data/`:

```bash
scripts/build-duckdb.sh            # crea data/tables.duckdb
docker compose up -d minio-init    # lo sube al bucket
```

En la app quedan ambas versiones para comparar:

```sql
SELECT count(*) FROM recipes;          -- vista sobre el parquet
SELECT count(*) FROM tables.recipes;   -- tabla nativa del .duckdb
```

Si se quieren las tablas completas en memoria del browser (una descarga al
inicio, queries posteriores sin red):

```sql
CREATE TABLE recipes_mem AS FROM tables.recipes;
```

## SPARQL sobre parquets de tripletas

`execute_sparql` (extensión rdf, ver `tools/duckdb-rdf-wasm`) traduce SPARQL a SQL usando un mapping YARRRML.
Para grafos grandes no hace falta crear tablas: el mapping puede leer directo de las vistas que el hook crea
para cada parquet, así que nada se pierde con F5 y DuckDB lee por rangos solo los row groups que necesita.

1. Reescribir las tripletas como tres permutaciones ordenadas, con columnas `s, p, o, kind, datatype, lang`:

   ```bash
   scripts/prepare-triples.sh /ruta/wikidata.parquet wiki   # data/wiki_spo, wiki_pos, wiki_osp
   ```

   Acepta un parquet con esas columnas o con términos N-Triples en `s, p, o` (`<iri>`, `"x"@es`, `"5"^^<...>`).

2. Generar un mapping por permutación:

   ```bash
   scripts/sparql-mapping.py data/wiki_pos.parquet wiki_pos data/mapping-pos.yml
   scripts/sparql-mapping.py data/wiki_spo.parquet wiki_spo data/mapping-spo.yml
   docker compose up -d minio-init   # sube parquets y mappings al bucket
   ```

   YARRRML solo permite datatype e idioma constantes, así que el script emite un triples map por cada
   combinación presente en los datos (`iri`, `plain`, `lang_es`, `dt_dateTime`, ...), cada uno con una fuente
   `query: "SELECT s, p, o FROM wiki_pos WHERE ..."` sobre la vista.

3. Consultar:

   ```sql
   SELECT * FROM execute_sparql('
     PREFIX wd: <http://www.wikidata.org/entity/>
     PREFIX wdt: <http://www.wikidata.org/prop/direct/>
     SELECT ?s WHERE { ?s wdt:P31 wd:Q5 } LIMIT 100', 'http://localhost:3000/s3/mapping-pos.yml');
   ```

### Qué permutación usar

El orden del parquet decide qué row groups puede saltarse DuckDB (estadísticas min/max por row group).
Medido en el browser contra MinIO con un Wikidata sintético de 5.25 M tripletas (31 MB por permutación,
53 row groups); warm = segunda ejecución en la misma instancia:

| Consulta | patrón | POS warm | SPO warm | leído en frío (POS / SPO) |
|---|---|---:|---:|---:|
| q1 | `wd:Q42 ?p ?o` | 849 ms | **171 ms** | 17.8 / **0.6** MB |
| q2 | `?s wdt:P31 wd:Q5` | **127 ms** | 387 ms | **1.1** / 30.2 MB |
| q3 | estrella P31 + P569 + label `@es` | **253 ms** | 1276 ms | **7.7** / 31.5 MB |
| q4 | `CONTAINS` sobre labels | **887 ms** | 3723 ms | **4.1** / 31.5 MB |
| q5 | `?s ?p wd:Q4242` | **235 ms** | 439 ms | **12.7** / 24.2 MB |
| q6 | `COUNT` por predicado | **4.2 s** | 6.6 s | 32.5 / 31.4 MB |

POS sirve para casi todo (los patrones casi siempre fijan el predicado); SPO solo gana cuando el sujeto es
constante. La primera consulta de una instancia (en frío) suma la lectura de red y de metadatos del parquet.

El hook carga `httpfs`, y es necesario: sin esa extensión duckdb-wasm descarga cada parquet entero al
crear la vista.
