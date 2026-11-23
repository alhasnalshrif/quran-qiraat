# Production deployment

Live on the VPS at **https://quran.alhasnalshrif.com** (admin at `/admin/`).

## What actually runs

The VPS already runs Traefik on 80/443, on a shared `proxy` network, with
Cloudflare in front of every site. This project joins that setup instead of
starting its own Caddy, and shares the `postgres` container on the `jwla`
network.

| Container | Purpose |
|---|---|
| `quran-server` | `/v1` API, `/admin` dashboard, `/healthz` |
| `quran-backup` | `pg_dump` to R2 `backups/`, keeping 30 days |

Repo checkout: `/home/opc/compose/quran`. Only `server/.env` holds secrets
(mode 600, never committed).

## Storage

D4 says Cloudflare R2. The available token can only write to the existing
`jwla` bucket and cannot create a bucket, so pack objects live under
`jwla/packs/...` and backups under `jwla/backups/...`. If a dedicated bucket is
created later, change `S3_BUCKET` and restart.

## Deploying an update

```sh
ssh opc@84.12.88.79
cd /home/opc/compose/quran
git pull
export POSTGRES_USER=admin POSTGRES_PASSWORD=admin123 POSTGRES_DB=quran
docker compose -f deploy/docker-compose.yml up -d --build quran-server
```

Migrations run with the migrator against `DATABASE_URL`; the schema is already
applied, so a pull that only changes code needs no extra step. After a schema
change, run the migrator the same way:

```sh
docker compose -f deploy/docker-compose.yml run --rm --no-deps quran-server \
  node --experimental-strip-types --input-type=module -e "
const { drizzle } = await import('drizzle-orm/postgres-js');
const { migrate } = await import('drizzle-orm/postgres-js/migrator');
const postgres = (await import('postgres')).default;
const sql = postgres(process.env.DATABASE_URL, { max: 1 });
await migrate(drizzle(sql), { migrationsFolder: './drizzle' });
await sql.end();"
```

## Backups and restore

The backup container dumps on start and every 24 hours. Restore rehearsal
(passed on 2026-11-23: 11 tables, the owner account and pack versions all came
back):

```sh
docker exec postgres psql -U admin -d postgres -c "CREATE DATABASE quran_restore_test"
set -a; . ./server/.env; set +a
docker run --rm -e AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID" \
  -e AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY" -e AWS_DEFAULT_REGION=auto \
  amazon/aws-cli --endpoint-url "$S3_ENDPOINT" \
  s3 cp s3://jwla/backups/<file>.sql.gz - | gunzip \
  | docker exec -i postgres psql -U admin -d quran_restore_test
```

## Monitoring

Point a free uptime checker at `https://quran.alhasnalshrif.com/healthz` every
5 minutes; it returns 200 only when the database answers.

## Still needed before app release

- Replace the placeholder OneSignal ids and keys in `server/.env` (N-01).
- Put the manifest public key in `lib/updates/trusted_keys.dart` under `k1`;
  until then the app rejects every manifest, by design.
