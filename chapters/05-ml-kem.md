# ML-KEM integration and migration

<!--
WRITING NOTES (not printed in the PDF)

Purpose: the security core. What is protected, how, and what is not.

Include:
- Protected link: gateway -> cloud only. Device -> gateway stays plaintext
  (legacy device cannot be changed) - say why and what that exposes.
- Library and why: ML-KEM-768 from `cryptography` (OpenSSL), FIPS 203.
  Earlier choice kyber-py replaced (educational, not constant-time).
- Message protection, step by step: encapsulate -> shared secret (32 bytes)
  used as AES-256-GCM key, random 12-byte nonce, timestamp inside the
  ciphertext; envelope {kem_ciphertext, nonce, ciphertext}.
- Key management: scripts/generate_keys.py -> untracked .env; public key
  pre-shared (no runtime fetch); the key pair committed up to v3.1.0 is
  compromised and replaced.
- Replay protection: 30 s timestamp window (limitation: replay within window).
- Failure behaviour: decryption failure 400, bad payload 400, stale 401,
  invalid reading 422, storage failure 503; all counted by reason.
- Migration and fallback strategy: legacy POST /data off by default
  (CLOUD_ALLOW_LEGACY_INGESTION); opt-in during migration; watch
  legacy_data_received_total; close when zero; roll back by setting true.
- Threat model and known gaps: anyone with the public key can send readings
  (no sender authentication); the cloud's reply is not authenticated;
  no forward secrecy; device link plaintext.

Sources: cloud/app/{crypto,keys,main,models}.py, gateway/app/{crypto,keys,
cloud_client}.py, config.py; documentation/phases/v2.0.0.md.
-->
