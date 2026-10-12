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
