/// Manifest signing keys this build trusts (01 §3).
///
/// The values are base64 Ed25519 public keys (32 bytes). Rotation: add `k2`
/// here in a store release, wait for it to spread, sign with `k2` on the
/// server, then remove `k1` in the following release.
///
/// `test` is deliberately absent: fixtures in `packages/contracts/fixtures/`
/// are signed with it and it must never be trusted by a released build.
library;

const Map<String, String> trustedKeys = {
  // 'k1': '<base64 public key>',
};
