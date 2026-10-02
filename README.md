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
- API S3: http://localhost:9000
- Consola MinIO: http://localhost:9001
