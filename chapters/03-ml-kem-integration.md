# ML-KEM integration

ML-KEM protects the link from the gateway to the cloud.
The link from the device to the gateway stays plaintext, because the device emulates a piece of hardware that can not be altered.
Both algorithms used for encryption in this project come from the `cryptography` package (version 50.0.2), which uses OpenSSL's implementation of FIPS 203 [@pycacryptography].

## How a reading is protected

To encrypt a reading, the gateway and the cloud need the same secret key.
A symmetric cipher such as AES-256-GCM uses one key both to encrypt and to decrypt, and it is fast, so it is the right tool for protecting the reading itself [@sp80038d].
The difficulty is getting the same key to both sides.
If the gateway simply sent it over the network, anyone listening could copy it and read every message.

ML-KEM, a key-encapsulation mechanism, solves exactly this problem [@fips203].
The cloud has a key pair: a public key, which anyone may know, and a private key, which never leaves the cloud.
One reading is then protected in five steps:


1. From the cloud's public key and a random value, the gateway uses ML-KEM algorithm to compute a new secret key, called the `shared secret`, and a `KEM ciphertext`.
2. The gateway encrypts the reading with the `shared secret` using symmetric cipher (in our case AES). As an outcome it gets `ciphertext` and `nonce` value.
3. The gateway sends the `KEM ciphertext`, `ciphertext` and `nonce` to the cloud (the `shared secret` itself is never sent).
4. From the `KEM ciphertext` and its `private key`, the cloud computes the same `shared secret`.
5. Using `shared secret` and `nonce` the cloud decrypts the `ciphertext` and can finally read the message.

Both sides used the same key (`shared secret`), although the key itself never travelled over the network.
ML-KEM itself is therefore used only to agree on the key.
It cannot encrypt the reading directly, because it only produces a key and has no message input.

![Path of one protected reading.](figures/protected-reading.pdf){width=100%}

## Key management

The key pair is created with the script `scripts/generate_keys.py`, which writes it to the `.env` file.
The cloud gets the private key and the gateway the public key.
Both services check their key at startup and refuse to start if it is missing or malformed.

## Migration and fallback strategy

In a real installation, not all sites would be upgraded at once.
Gateways that have not been migrated yet still send plaintext readings to the cloud's original endpoint `POST /data`, so this endpoint is kept.
Because it bypasses encryption, it is **closed by default** and opened only with the setting `CLOUD_ALLOW_LEGACY_INGESTION=true`.
Every reading it accepts or refuses is logged and counted, so it is always visible which traffic still uses plaintext.

The migration runs in three steps:

1. **Transition:** Open the plaintext endpoint while the clients are moving to the encrypted path one by one.
2. **Cut-over:** When no plaintext readings arrive anymore, close the endpoint and restart the cloud.
3. **Fallback:** If a client still turns out to need the plaintext path, open it again.

An alert fires in step 1 whenever the plaintext endpoint is used, and in step 2 whenever a client is refused.
The device is not affected by the migration, since it always sends message to the gateway and the gateway always encrypts.

## Threat model and known gaps

| An attacker on the gateway–cloud network can… | Result |
|----------------------------------------|-----------------------------------------|
| read recorded traffic, now or with a future quantum computer | **No.** Readings are encrypted with keys established by ML-KEM-768. |
| change a message in transit | **No.** Detected by AES-GCM. |
| replace the cloud's public key | **No.** The key is distributed with the deployment, not fetched. |
| replay an old message | **Only within 30 seconds.** Older timestamps are rejected - within the window the same message is accepted again. |
| send a forged reading | **Yes.** Encryption protects the content of the message, not the identity of the sender. |
| fake the cloud's reply | **Yes.** The reply `{"status": "stored"}` is not authenticated, so a dropped reading could be reported as stored. |
| read or change device → gateway traffic | **Yes.** That link is plaintext by design. |
| decrypt past traffic after stealing the cloud's private key | **Yes.** All traffic encrypted with that key is exposed. |

: What the protection does and does not cover.