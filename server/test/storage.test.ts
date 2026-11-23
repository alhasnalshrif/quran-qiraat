import { describe, expect, it, beforeEach, afterEach } from 'vitest';

import {
  PackStorage,
  objectKey,
  sha256Hex,
  uploadUrlTtlSeconds,
} from '../src/services/storage.js';
import { startFakeS3, type FakeS3 } from './helpers/fake-s3.js';

/**
 * S-06: presigned upload, read-back and sha256 against R2 semantics (D4).
 * The fake server speaks real S3 over HTTP, so the SDK path is under test.
 */
describe('pack storage on R2 (S-06)', () => {
  let s3: FakeS3;
  let storage: PackStorage;

  beforeEach(async () => {
    s3 = await startFakeS3();
    storage = PackStorage.fromConfig({
      endpoint: s3.endpoint,
      region: 'auto',
      bucket: s3.bucket,
      accessKeyId: 'test-key',
      secretAccessKey: 'test-secret',
    });
  });

  afterEach(async () => {
    await s3.close();
  });

  it('builds the object key from 02 §3', () => {
    expect(objectKey('qiraat-farsh', 2, 'variants.json')).toBe(
      'packs/qiraat-farsh/2/variants.json',
    );
  });

  it('issues a presigned upload URL valid for 15 minutes', async () => {
    const url = await storage.presignedUploadUrl(
      objectKey('qiraat-farsh', 2, 'variants.json'),
    );
    const parsed = new URL(url);

    expect(parsed.pathname).toBe('/quran-test/packs/qiraat-farsh/2/variants.json');
    expect(parsed.searchParams.get('X-Amz-Algorithm')).toBe('AWS4-HMAC-SHA256');
    expect(parsed.searchParams.get('X-Amz-Signature')).toBeTruthy();
    expect(parsed.searchParams.get('X-Amz-Credential')).toContain('test-key');
    expect(parsed.searchParams.get('X-Amz-SignedHeaders')).toContain('host');

    const expires = Number(parsed.searchParams.get('X-Amz-Expires'));
    expect(expires).toBe(uploadUrlTtlSeconds);
    expect(uploadUrlTtlSeconds).toBe(900);
  });

  it('uploads through the presigned URL and reads the bytes back', async () => {
    const key = objectKey('qiraat-farsh', 2, 'variants.json');
    const body = new TextEncoder().encode('{"schemaVersion":"1.0.0"}');
    const url = await storage.presignedUploadUrl(key);

    const upload = await fetch(url, { method: 'PUT', body });
    expect(upload.ok).toBe(true);

    const read = await storage.readObject(key);
    expect(read).not.toBeNull();
    expect(new TextDecoder().decode(read!)).toBe('{"schemaVersion":"1.0.0"}');
  });

  it('verifies size and sha256 of an uploaded file', async () => {
    const key = objectKey('hafs-text', 3, 'quran_hafs.json');
    const body = new TextEncoder().encode('[{"sura_no":1,"aya_no":1}]');
    await fetch(await storage.presignedUploadUrl(key), { method: 'PUT', body });

    const inspected = await storage.inspectObject(key);
    expect(inspected).not.toBeNull();
    expect(inspected!.size).toBe(body.byteLength);
    expect(inspected!.sha256).toBe(sha256Hex(body));
    expect(inspected!.sha256).toMatch(/^[0-9a-f]{64}$/);
  });

  it('detects a sha256 mismatch against the expected digest', async () => {
    const key = objectKey('hafs-text', 3, 'quran_hafs.json');
    const body = new TextEncoder().encode('actual');
    await fetch(await storage.presignedUploadUrl(key), { method: 'PUT', body });

    const inspected = await storage.inspectObject(key);
    const expected = sha256Hex(new TextEncoder().encode('expected'));
    expect(inspected!.sha256).not.toBe(expected);
    expect(inspected!.sha256).toBe(sha256Hex(body));
  });

  it('returns null for a missing object instead of throwing', async () => {
    expect(await storage.readObject('packs/none/1/missing.json')).toBeNull();
    expect(await storage.inspectObject('packs/none/1/missing.json')).toBeNull();
  });

  it('issues a presigned download URL for the CDN fallback', async () => {
    const key = objectKey('qiraat-farsh', 2, 'variants.json');
    await fetch(await storage.presignedUploadUrl(key), {
      method: 'PUT',
      body: new TextEncoder().encode('x'),
    });

    const url = await storage.presignedDownloadUrl(key);
    const response = await fetch(url);
    expect(response.status).toBe(200);
    expect(await response.text()).toBe('x');
  });

  it('signs each URL independently, so one cannot be reused for another key', async () => {
    const first = new URL(
      await storage.presignedUploadUrl(objectKey('qiraat-farsh', 2, 'a.json')),
    );
    const second = new URL(
      await storage.presignedUploadUrl(objectKey('qiraat-farsh', 2, 'b.json')),
    );

    expect(first.pathname).not.toBe(second.pathname);
    expect(first.searchParams.get('X-Amz-Signature')).not.toBe(
      second.searchParams.get('X-Amz-Signature'),
    );
  });
});
