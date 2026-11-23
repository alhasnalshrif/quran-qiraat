#!/bin/sh
# Daily pg_dump uploaded to Cloudflare R2, keeping 30 days (02 §9).
#
# Runs in an alpine image with postgresql-client, aws-cli and dcron-free
# supervision: dump, upload, prune old objects, sleep until tomorrow.
set -eu

: "${S3_BUCKET:?set S3_BUCKET}"
: "${S3_ENDPOINT:?set S3_ENDPOINT}"
: "${S3_ACCESS_KEY_ID:?set S3_ACCESS_KEY_ID}"
: "${S3_SECRET_ACCESS_KEY:?set S3_SECRET_ACCESS_KEY}"

export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="${S3_REGION:-auto}"

backup() {
  stamp="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  file="/tmp/quran-$stamp.sql.gz"

  echo "Dumping to $file"
  pg_dump --no-owner --no-privileges | gzip -9 > "$file"

  echo "Uploading to s3://$S3_BUCKET/backups/$(basename "$file")"
  aws --endpoint-url "$S3_ENDPOINT" s3 cp "$file" "s3://$S3_BUCKET/backups/$(basename "$file")"
  rm -f "$file"

  # Keep 30 days. ISO dates sort lexically, so the cutoff is a plain string
  # comparison; compute "today - 30 days" from the epoch without GNU date.
  cutoff="$(date -u -d "@$(( $(date -u +%s) - 30 * 86400 ))" +%Y-%m-%d 2>/dev/null \
    || date -u -r "$(( $(date -u +%s) - 30 * 86400 ))" +%Y-%m-%d 2>/dev/null \
    || echo "")"
  if [ -z "$cutoff" ]; then
    echo "Cannot compute a 30-day cutoff with this date; skipping pruning."
    return 0
  fi

  echo "Pruning backups older than $cutoff"
  aws --endpoint-url "$S3_ENDPOINT" s3 ls "s3://$S3_BUCKET/backups/" \
    | awk '{print $1, $4}' \
    | while read -r day key; do
        [ -z "$key" ] && continue
        if [ "$day" \< "$cutoff" ]; then
          echo "Removing $key"
          aws --endpoint-url "$S3_ENDPOINT" s3 rm "s3://$S3_BUCKET/backups/$key"
        fi
      done
}

# One backup at start-up so a fresh deployment is protected immediately.
backup

while true; do
  sleep 86400
  backup || echo "Backup failed; retrying tomorrow."
done
