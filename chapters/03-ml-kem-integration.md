# ML-KEM integration

## Design, keys and failure behaviour

**Protected link.** ML-KEM protects the link from the gateway to the cloud. The
link from the device to the gateway stays plaintext: the device stands for
legacy hardware that cannot be changed, so protection begins at the gateway,
which in a real installation would sit next to the sensor on a local network.

**Library.** ML-KEM-768 comes from the `cryptography` package (version 50.0.2),
which uses OpenSSL's implementation of FIPS 203. AES-256-GCM comes from the same
package. No cryptography is implemented in the project itself.

**How one reading is protected.**

![Path of one protected reading.](diagrams/protected-reading.pdf){width=100%}

1. The gateway adds the current time (`timestamp`) to the reading and serialises
   it to JSON.
2. `encapsulate(cloud public key)` returns a fresh 32-byte **shared secret** and
   a 1,088-byte **KEM ciphertext** that only the cloud's private key can open.
3. The reading is encrypted with AES-256-GCM, using the shared secret as the key
   and 12 random bytes as the nonce. Because the key is new for every message,
   a nonce can never repeat under the same key.
4. The gateway sends `{kem_ciphertext, nonce, ciphertext}`, each base64-encoded,
   to `POST /data/secure`. The shared secret itself is never sent.
5. The cloud decapsulates the KEM ciphertext with its private key, obtains the
   same shared secret and decrypts. If any byte of the three fields was changed,
   decryption fails: a changed KEM ciphertext silently yields a different
   secret (FIPS 203 "implicit rejection"), which then fails the AES-GCM tag
   check.
6. The cloud checks that the plaintext is a JSON object, that its timestamp is a
   number at most 30 seconds from the cloud's clock, and that the reading is
   valid, then stores it.

The 32-byte ML-KEM shared secret is used directly as the AES key. This is
acceptable because the secret is already uniformly random and of the right
length; a key-derivation step would add domain separation but no strength.

**Key management.** `scripts/generate_keys.py` creates a key pair and writes it
to `.env` with owner-only permissions; it refuses to overwrite an existing file.
The private key (a 64-byte seed) is given only to the cloud, the public key
only to the gateway. The public key is distributed with the deployment rather
than fetched at runtime, so an attacker on the network cannot substitute their
own key. Both services check their key at startup and refuse to start with a
missing or malformed one. Up to v3.1.0 a key pair was committed in
`docker-compose.yml` of the public repository; it is no longer used and must be
treated as compromised, because it remains in the Git history. There is no
automated key rotation: generating new keys and restarting both services
replaces them.

**Failure behaviour.** Every rejection is logged and counted in
`secure_data_rejected_total` with its reason, so attacks and faults are visible
in monitoring.

| Problem | Response | Metric reason |
|---------------------------------|----------|-------------------|
| Bad base64, tampered or wrong-key message | `400` | `decryption_failed` |
| Decrypts, but is not a JSON object or has no usable timestamp | `400` | `malformed_payload` |
| Timestamp more than 30 s from the cloud's clock | `401` | `stale_timestamp` |
| Reading invalid (missing field, `NaN`, wrong type) | `422` | `validation_failed` |
| Database unavailable | `503` | `storage_failed` |
| Cloud unreachable or answering with an error (seen by the gateway) | `502` to the device | gateway `cloud_forward_failures_total` |

: How the cloud and gateway react to failures.

## Migration and fallback strategy

The original plaintext endpoint `POST /data` is kept, so that clients which have
not been moved to the encrypted path can still deliver data during a migration.
In a real installation these would be gateways at other sites that have not
been upgraded yet; in this deployment there is only one gateway, already
migrated, so the endpoint is unused and exists for the migration and fallback
path.
Because it bypasses encryption completely, it is **closed by default**: the
cloud answers `403`, stores nothing and counts the attempt in
`legacy_data_rejected_total`. It is opened only by setting
`CLOUD_ALLOW_LEGACY_INGESTION=true`; any value other than `true` or `false` stops
the cloud at startup, so a typo cannot silently open it. When open, every use is
logged as a warning and counted in `legacy_data_received_total`. Both endpoints
apply the same validation.

The migration therefore runs in three steps:

1. **Transition.** Enable legacy ingestion while clients are moved to the
   gateway's encrypted path. The `LegacyIngestionUsed` alert and the counter
   show which traffic still uses plaintext.
2. **Cut-over.** When `legacy_data_received_total` stays at zero, set the switch
   back to `false` (the default) and restart the cloud. Attempts are now
   rejected and visible through `PlaintextIngestionBlocked`.
3. **Fallback.** If a client still depends on the plaintext path, set the switch
   to `true` again and restart; no code change or new image is needed. If the
   encrypted path itself failed, the current gateway could not fall back on its
   own, because it has no plaintext mode: a full rollback also means running an
   earlier gateway image, which is what versioned images make possible.

The device itself is not part of this migration: it always talks to the gateway,
and the gateway always encrypts. There is no switch to send plaintext from the
gateway to the cloud.

## Threat model and known gaps

| An attacker on the gateway–cloud network can… | Result |
|----------------------------------------|-----------------------------------------|
| read recorded traffic, now or with a future quantum computer | **No.** Readings are encrypted with keys established by ML-KEM-768. |
| change a message in transit | **No.** Detected by AES-GCM; rejected with `400`. |
| replace the cloud's public key | **No.** The key is distributed with the deployment, not fetched. |
| replay an old message | **Only within 30 seconds.** Older timestamps are rejected; within the window the same message is accepted again. |
| send a forged reading | **Yes.** Anyone who can reach the gateway's `POST /device-data` can submit a reading, which the gateway then encrypts and forwards like a real one; anyone holding the public key can also send one directly to the cloud. Encryption protects the content, not the identity of the sender. |
| fake the cloud's reply | **Yes.** The reply `{"status": "stored"}` is not authenticated, so a dropped reading could be reported as stored. |
| read or change device → gateway traffic | **Yes.** That link is plaintext by design (legacy device). |
| decrypt past traffic after stealing the cloud's private key | **Yes.** There is no forward secrecy; all traffic encrypted with that key is exposed. |

: What the protection does and does not cover.

The first three rows are the goals of the integration. The others are known,
documented limitations; they are discussed in the final evaluation.
