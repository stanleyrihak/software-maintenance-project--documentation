# Definitions {-}

| Term | Meaning in this document |
|-----------|----------------------------------------------------------------------|
| Legacy device | A device whose software cannot be changed; here a simulated DS18B20 temperature sensor. |
| Edge gateway | The service next to the device that receives its readings and forwards them to the cloud. |
| Plaintext / ciphertext | Data before / after encryption. |
| KEM | Key-encapsulation mechanism: with a public key, anyone can create a random shared secret together with an encapsulation (the *KEM ciphertext*); only the holder of the private key can recover the secret from it. |
| ML-KEM-768 | The post-quantum KEM standardised in FIPS 203, at the security level NIST recommends for general use. |
| Shared secret | The 32 random bytes both sides end up with after encapsulation and decapsulation; used as the encryption key. |
| AES-256-GCM | Symmetric authenticated encryption: it encrypts the data and adds a tag, so any change is detected on decryption. |
| Nonce | "Number used once": a value that must never repeat for the same AES-GCM key. Here 12 random bytes per message. |
| Replay attack | Recording a valid message and sending it again later. |
| Legacy ingestion | The original plaintext `POST /data` endpoint of the cloud, kept for clients that are not migrated yet. |
| CI / CD | Continuous integration (every change is built and tested automatically) / continuous delivery (what passes is published and deployed automatically). |
| Metric | A number a service exposes on `/metrics` for Prometheus, for example a counter of rejected requests. |
