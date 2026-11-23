# Taste

## Tooling

- Prefers Cloudflare R2 (S3-compatible, managed) over self-hosted MinIO for object storage — explicitly correcting a plan that used MinIO locally. Confidence: 0.65

## Workflow

- Prefers real deployment/verification on his own Oracle Cloud VPS over SSH (`opc@84.12.88.79`), with repos cloned under `/home/opc/compose` and using the Docker/Compose already installed there instead of stopping at local-only checks or local container tooling. Confidence: 0.6
