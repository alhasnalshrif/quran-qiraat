import { createHash } from 'node:crypto';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';

/**
 * A tiny in-process S3-compatible server for storage tests (D4).
 *
 * The AWS SDK talks to it over real HTTP, so presigned URLs, path-style
 * addressing and the GetObject/PutObject round trip are exercised for real
 * without Docker or MinIO.
 */
export interface FakeS3 {
  endpoint: string;
  bucket: string;
  objects: Map<string, Uint8Array>;
  requests: { method: string; key: string }[];
  close: () => Promise<void>;
}

export async function startFakeS3(bucket = 'quran-test'): Promise<FakeS3> {
  const objects = new Map<string, Uint8Array>();
  const requests: { method: string; key: string }[] = [];

  const server: Server = createServer(
    async (request: IncomingMessage, response: ServerResponse) => {
      const url = new URL(request.url ?? '/', 'http://localhost');
      // Path-style: /<bucket>/<key...>
      const parts = url.pathname.replace(/^\//, '').split('/');
      const requestBucket = parts.shift() ?? '';
      const key = decodeURIComponent(parts.join('/'));
      requests.push({ method: request.method ?? 'GET', key });

      if (requestBucket !== bucket) {
        response.writeHead(404).end('no such bucket');
        return;
      }

      if (request.method === 'PUT') {
        const chunks: Uint8Array[] = [];
        for await (const chunk of request) chunks.push(chunk as Uint8Array);
        objects.set(key, new Uint8Array(Buffer.concat(chunks)));
        response.writeHead(200).end();
        return;
      }

      if (request.method === 'HEAD' || request.method === 'GET') {
        const body = objects.get(key);
        if (!body) {
          response.writeHead(404).end();
          return;
        }
        const etag = `"${createHash('md5').update(body).digest('hex')}"`;
        response.writeHead(200, {
          'content-type': 'application/octet-stream',
          'content-length': String(body.byteLength),
          etag,
        });
        response.end(Buffer.from(body));
        return;
      }

      response.writeHead(405).end();
    },
  );

  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address() as AddressInfo;

  return {
    endpoint: `http://127.0.0.1:${address.port}`,
    bucket,
    objects,
    requests,
    close: () =>
      new Promise<void>((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      ),
  };
}
