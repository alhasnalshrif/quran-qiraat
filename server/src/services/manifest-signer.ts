import { createPrivateKey, createPublicKey, sign, verify, type KeyObject } from 'node:crypto';

/**
 * Ed25519 manifest signing (D7, 01 §3). The payload is signed as bytes, so the
 * server never re-serialises it between signing and sending.
 */
export class ManifestSigner {
  constructor(
    private readonly privateKey: KeyObject,
    readonly keyId: string,
  ) {}

  /** Builds a signer from the base64 32-byte seed in `MANIFEST_SIGNING_KEY`. */
  static fromSeed(seedBase64: string, keyId: string): ManifestSigner {
    const seed = Buffer.from(seedBase64, 'base64');
    if (seed.length !== 32) {
      throw new Error('MANIFEST_SIGNING_KEY must be a base64 32-byte seed.');
    }
    // PKCS#8 prefix for an Ed25519 private key built from a raw seed.
    const prefix = Buffer.from('302e020100300506032b657004220420', 'hex');
    const key = createPrivateKey({
      key: Buffer.concat([prefix, seed]),
      format: 'der',
      type: 'pkcs8',
    });
    return new ManifestSigner(key, keyId);
  }

  /** The matching public key as base64, for the app's trustedKeys list. */
  get publicKeyBase64(): string {
    const publicKey = createPublicKey(this.privateKey);
    const der = publicKey.export({ format: 'der', type: 'spki' });
    return Buffer.from(der.subarray(der.length - 32)).toString('base64');
  }

  /** Wraps payload bytes in the signed envelope of 01 §2.2. */
  signPayload(payloadBytes: Buffer): {
    keyId: string;
    payload: string;
    signature: string;
  } {
    const signature = sign(null, payloadBytes, this.privateKey);
    return {
      keyId: this.keyId,
      payload: payloadBytes.toString('base64'),
      signature: signature.toString('base64'),
    };
  }
}

/** Verifies an envelope with a base64 public key (used by the tests). */
export function verifyEnvelope(
  envelope: { payload: string; signature: string },
  publicKeyBase64: string,
): boolean {
  const raw = Buffer.from(publicKeyBase64, 'base64');
  const prefix = Buffer.from('302a300506032b6570032100', 'hex');
  const key = createPublicKey({
    key: Buffer.concat([prefix, raw]),
    format: 'der',
    type: 'spki',
  });
  return verify(
    null,
    Buffer.from(envelope.payload, 'base64'),
    key,
    Buffer.from(envelope.signature, 'base64'),
  );
}
