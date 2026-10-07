# Testing and verification

<!--
WRITING NOTES (not printed in the PDF)

Purpose: the evidence that the system works and that its protections hold.

Include:
- Test suites and counts per service (device, gateway, cloud, tooling) and
  what they cover; how to run them.
- Security checks with expected vs actual results (tampering, wrong key,
  stale timestamp, legacy rejected, NaN, malformed payload, replay limitation).
- End-to-end checks in Docker (smoke test, reliability check).
- Measurements: latency plaintext vs ML-KEM.
- What was NOT tested and why.

Sources: */tests/, scripts/evaluation/, documentation/validation/ in the code
repo; CI runs on GitHub.
-->
