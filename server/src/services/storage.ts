import { createHash } from 'node:crypto';

import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

import type { Env } from '../env.js';

export interface StorageConfig {
  endpoint: string;
  region: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
}

/** Bucket object key for one pack file (02 §3 `pack_files`). */
export function objectKey(packId: string, version: number, filePath: string): string {
  return `packs/${packId}/${version}/${filePath}`;
}

export function sha256Hex(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

/** Presigned PUT validity, per 02 §5. */
export const uploadUrlTtlSeconds = 15 * 60;

/**
 * Cloudflare R2 storage (D4). R2 is S3-compatible, so the AWS SDK talks to it
 * directly with a custom endpoint and region "auto".
 */
export class PackStorage {
  constructor(
    readonly client: S3Client,
    readonly bucket: string,
  ) {}

  static fromEnv(env: Env): PackStorage {
    const config: StorageConfig = {
      endpoint: env.S3_ENDPOINT,
      region: env.S3_REGION,
      bucket: env.S3_BUCKET,
      accessKeyId: env.S3_ACCESS_KEY_ID,
      secretAccessKey: env.S3_SECRET_ACCESS_KEY,
    };
    return PackStorage.fromConfig(config);
  }

  static fromConfig(config: StorageConfig, client?: S3Client): PackStorage {
    const s3 =
      client ??
      new S3Client({
        endpoint: config.endpoint,
        region: config.region,
        credentials: {
          accessKeyId: config.accessKeyId,
          secretAccessKey: config.secretAccessKey,
        },
        forcePathStyle: true,
      });
    return new PackStorage(s3, config.bucket);
  }

  /** A presigned PUT the browser uploads to (02 §5 `/pack-versions/:vid/files`). */
  async presignedUploadUrl(key: string): Promise<string> {
    return getSignedUrl(
      this.client,
      new PutObjectCommand({ Bucket: this.bucket, Key: key }),
      { expiresIn: uploadUrlTtlSeconds },
    );
  }

  /** A presigned GET, used by the CDN fallback route (02 §4). */
  async presignedDownloadUrl(key: string, expiresIn = 300): Promise<string> {
    return getSignedUrl(
      this.client,
      new GetObjectCommand({ Bucket: this.bucket, Key: key }),
      { expiresIn },
    );
  }

  /**
   * Reads an object's bytes, or null when it is absent. Validation needs the
   * bytes to match size and sha256 (02 §5 `/validate`).
   */
  async readObject(key: string): Promise<Uint8Array | null> {
    try {
      const response = await this.client.send(
        new GetObjectCommand({ Bucket: this.bucket, Key: key }),
      );
      const body = response.Body;
      if (!body) return null;
      return await body.transformToByteArray();
    } catch (error) {
      if (isNotFound(error)) return null;
      throw error;
    }
  }

  /** Bytes, size and digest together, the shape validation compares against. */
  async inspectObject(
    key: string,
  ): Promise<{ bytes: Uint8Array; size: number; sha256: string } | null> {
    const bytes = await this.readObject(key);
    if (bytes === null) return null;
    return { bytes, size: bytes.byteLength, sha256: sha256Hex(bytes) };
  }
}

function isNotFound(error: unknown): boolean {
  if (typeof error !== 'object' || error === null) return false;
  const candidate = error as { name?: string; $metadata?: { httpStatusCode?: number } };
  return (
    candidate.name === 'NoSuchKey' ||
    candidate.name === 'NotFound' ||
    candidate.$metadata?.httpStatusCode === 404
  );
}
