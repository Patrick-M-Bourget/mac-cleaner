# License key format

The byte layout of a CacheDrop license key, shared by the app (#594, CacheDropCore `LicenseKey`, `LicenseVerifier`) and the issuing function (Patrick-M-Bourget/cachedrop-website#64). Both must agree byte for byte; the test vectors below are the check. The rules behind it are Decision 135 in [docs/RESET.md](../RESET.md); this format is Decision 136.

## The key

```
CD1-<base32(payload ‖ signature)>
```

- `CD1-` names format version 1. It is part of the key users paste, not of the signed bytes.
- `payload` is 21 bytes (below); `signature` is the 64-byte Ed25519 signature (RFC 8032) of exactly those 21 bytes, made with the production private key.
- The 85 bytes are encoded in RFC 4648 base32: alphabet `A–Z 2–7`, upper case, **no padding**. 85 bytes are exactly 136 characters with no spare bits, so every key has one spelling and is 140 characters long with its prefix.

Why base32: it has no `+ / = - _` that mail clients, URLs or double-click selection break on, and it reads the same in any case, so a retyped key needs no shift key. Deno's standard library has it (`jsr:@std/encoding/base32`, `encodeBase32`), and it is a few lines anywhere else. base64url would be 114 characters but case-sensitive, and its `-` and `_` break selection.

The app reads a key leniently and checks it strictly: it ignores case, spaces and line breaks, then requires `CD1-` and exactly 136 base32 characters. The issuing function always writes the canonical form: upper case, one line.

## Payload (21 bytes, big-endian)

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 1 | format version | `1` |
| 1 | 16 | license ID | a UUID's 16 bytes in RFC 4122 order (`crypto.randomUUID()` with its hyphens removed, read as hex) |
| 17 | 1 | edition | `1` = standard |
| 18 | 1 | Macs | `3`; 1–255, honour-based and never enforced |
| 19 | 2 | issue date | whole days since 1970-01-01 UTC, unsigned 16-bit (lasts until 2149) |

No email, name or app version (Decision 135): a future 2.0 tells older licenses apart by the issue date. The license ID, written as a lower-case hyphenated UUID, is what the revocation list holds (docs/RELEASING.md).

A key is **invalid** in the app unless its signature verifies against the built-in public key, its version byte is `1`, its edition is one the app knows and its Mac count is at least 1. A valid key whose license ID is on the revocation list is **revoked**. Adding a field or edition means a new format version, a new prefix (`CD2-`) and an app release that reads it.

## Test key pair

**Test only.** Its private half signs test keys and is committed as a test fixture (`LicenseTestKeyPair` in `Packages/CacheDropCore/Tests/CacheDropCoreTests/LicenseKeyTests.swift`). It is not, and never becomes, the production key; the app never trusts it in a release. The production private key never enters this repository or the website's.

| | Hex |
|---|---|
| Private key seed (32 bytes, RFC 8032) | `8ad278073221015096d53c67edfe8c6adf17680b519f6d7e1febd21f875ae5ae` |
| Public key (32 bytes) | `281edbf56bcb31e08ce7365ddfc3c2b7e48543b62e182a97f68c5dbd359100ea` |

## Test vector

License ID `5f0c2a8e-3b1d-4c6f-9a7e-2d4b8c1e6f30`, edition standard, 3 Macs, issued 2026-11-01 (day 20758, `0x5116`).

```
payload    015f0c2a8e3b1d4c6f9a7e2d4b8c1e6f3001035116
signature  5a06ae0e5baa1793f8c6a705ae078604dd363203e5aea45ecdd2095eb7b431e2c40f7b5d28fae438607aead677f38afab782f600209197698d9a0d7175445909
key        CD1-AFPQYKUOHMOUY342PYWUXDA6N4YACA2RCZNANLQOLOVBPE7YY2TQLLQHQYCN2NRSAPS25JC6ZXJASXVXWQY6FRAPPNOSR6XEHBQHV2WWO7ZYV6VXQL3AAIERS5UY3GQNOF2UIWIJ
```

Ed25519 signing is deterministic, so Web Crypto with the test seed reproduces this signature exactly. The app's tests check that this key verifies as above and that changing any one of its 85 bytes makes it invalid (`LicenseKeyTests`).

## Reference encoder (TypeScript, Web Crypto)

What the issuing function does, runnable in Deno or Node 24. It produced the vector above from the test seed.

```ts
const BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
function base32(bytes: Uint8Array): string {
  let out = "", buffer = 0, bits = 0;
  for (const byte of bytes) {
    buffer = ((buffer << 8) | byte) & 0xffff; bits += 8;
    while (bits >= 5) { bits -= 5; out += BASE32[(buffer >> bits) & 31]; }
  }
  return out; // 85 bytes leave no spare bits
}

/** `privateKey` is an Ed25519 CryptoKey with the "sign" usage. */
async function licenseKey(privateKey: CryptoKey, id: string, macs: number, issued: Date): Promise<string> {
  const payload = new Uint8Array(21);
  payload[0] = 1;                                                   // format version
  payload.set(id.replaceAll("-", "").match(/../g)!.map((h) => parseInt(h, 16)), 1); // license ID
  payload[17] = 1;                                                  // edition: standard
  payload[18] = macs;                                               // Macs
  new DataView(payload.buffer).setUint16(19, Math.floor(issued.getTime() / 86_400_000)); // UTC days
  const signature = new Uint8Array(await crypto.subtle.sign("Ed25519", privateKey, payload));
  const all = new Uint8Array(85); all.set(payload); all.set(signature, 21);
  return "CD1-" + base32(all);
}
```

To import the test seed for a check, wrap it as PKCS#8: the DER prefix `302e020100300506032b657004220420` followed by the 32 seed bytes, then `crypto.subtle.importKey("pkcs8", der, { name: "Ed25519" }, false, ["sign"])`.
