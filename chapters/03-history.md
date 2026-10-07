# Project history

<!--
WRITING NOTES (not printed in the PDF)

Purpose: explain how the system evolved, and in particular why it was rebuilt.

Include:
- v1.0.0: plaintext baseline (device -> gateway -> cloud).
- v2.0.0-v2.2.0: first ML-KEM design: sessions with a handshake, PSK-HMAC
  mutual authentication, counter nonces, mode switch off/enabled/required,
  Prometheus/Grafana. About 9,000 lines of Python.
- Problems with v2: hard to read and review; a confirmed AES-GCM nonce-reuse
  bug after a lost response (S1) caused by the session/counter design.
- The rewrite (v3.0.0, 5 Oct): about 1,150 lines; per-message ML-KEM
  encapsulation, no sessions. Where the 8,000 lines went: ~4,000 tests,
  ~1,240 crypto session protocol, ~1,200 tooling, ~1,400 operational code.
- What v3 lost and what was added back: v3.1.0 (SQLite persistence, legacy
  closed by default, sensor-state metrics, monitoring overlay); v3.2.0 (keys
  out of the repository, OpenSSL ML-KEM, NaN fix, device logs).
- Note that tags v1.0.0-v2.2.0 belong to the earlier architecture.

Sources: git history and tags; docs/archive/ in the code repo; GitHub releases.
-->
