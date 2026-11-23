# Production deployment (S-12)

Everything here runs on one VPS with Docker Compose and Caddy for automatic
HTTPS (D5). Pack files live on Cloudflare R2 (D4), not on this machine.

## First deployment

1. Copy the environment files and fill them in:

   ```sh
   cp deploy/.env.example deploy/.env          # DOMAIN, ACME_EMAIL, POSTGRES_*
   cp server/.env.example server/.env          # S3_*, signing key, OneSignal, secrets
   ```

   Generate the two secrets:

   ```sh
   node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"  # MANIFEST_SIGNING_KEY
   node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"  # SESSION_SECRET
   ```

   Put the matching public key in the app's `lib/updates/trusted_keys.dart`
   under the same `MANIFEST_KEY_ID`. Generate it with:

   ```sh
   pnpm --filter @quran/server exec tsx -e "
     import('./src/services/manifest-signer.ts').then(({ ManifestSigner }) => {
       const s = ManifestSigner.fromSeed(process.env.MANIFEST_SIGNING_KEY, process.env.MANIFEST_KEY_ID);
       console.log(s.publicKeyBase64);
     });
   "
   ```

2. Create the R2 bucket and an API token with object read/write on it.

3. Start the database, apply migrations, and create the first owner:

   ```sh
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d postgres
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml run --rm server \
     node --experimental-strip-types drizzle-kit migrate
   ```

   Migrations also apply on start-up through `db:migrate` when you prefer that;
   the run-once step above is the explicit path.

4. Build and start everything:

   ```sh
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build
   ```

5. Create the first owner inside the running container:

   ```sh
   docker compose --env-file deploy/.env -f deploy/docker-compose.yml exec server \
     node dist/create-owner.js --email you@example.com
   ```

6. Open `https://<DOMAIN>/admin/` and sign in.

## What runs

| Service | Purpose |
|---|---|
| `postgres` | PostgreSQL 16 with a persistent volume |
| `server` | Hono API (`/v1`), dashboard (`/admin`), `/healthz` |
| `caddy` | HTTPS termination and reverse proxy |
| `backup` | `pg_dump` to R2 `backups/` daily, keeping 30 days |

## Updating

```sh
git pull
docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build
```

Never deploy before `tool/verify.sh` passes locally (D21: there is no CI).

## Backups

`backup` runs immediately on start and then every 24 hours. To restore:

```sh
aws --endpoint-url "$S3_ENDPOINT" s3 cp s3://"$S3_BUCKET"/backups/<file>.sql.gz - \
  | gunzip | docker compose exec -T postgres psql -U quran -d quran
```

Rehearse the restore before the first real release, and record that it worked
(spec 02 §9 requires a successful trial restore).

## Monitoring

`/healthz` returns 200 only when the database answers. Point a free uptime
checker at `https://<DOMAIN>/healthz` every 5 minutes.
