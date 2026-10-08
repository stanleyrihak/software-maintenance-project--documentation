# Final evaluation

## Strengths

- **Post-quantum protection on the link that leaves the site.** Readings between gateway and cloud are encrypted with keys established by ML-KEM-768 from an established library, and tampering, wrong keys and old messages are rejected (see the security results).
- **A design that is hard to get wrong.** One key per message removes session state and with it the nonce-reuse problem that affected v2.
- **Readable code.** About 1,000 lines of application code, small modules, one responsibility each; every team member can follow a reading from sensor to database.
- **Legacy compatibility with a safe default.** The plaintext endpoint still exists for migration, but is closed unless deliberately opened, and every use is visible.
- **Operations.** Ten CI jobs including end-to-end checks; basic CD (images published to GHCR on every push to `main` — the full deployment pipeline is still open, see Technical debt); persistent storage; health checks, logs, metrics without per-device labels; and an optional monitoring stack with tested alert rules.
- **Evidence.** 164 automated tests, security checks against the running system, latency measured with one procedure across four versions, and a recorded decision for each significant AI-generated artefact.

## Weaknesses and known limitations

- **No sender authentication.** Anyone holding the public key can submit a valid reading for any device (demonstrated).
  A shared secret or signature for the gateway would be needed.
- **Replay within 30 seconds.** The same encrypted message is accepted again inside the timestamp window (demonstrated, stored three times).
  Gateway and cloud clocks must also agree within 30 seconds.
- **Unauthenticated replies and plaintext device link.** A forged `{"status": "stored"}` would be believed by the gateway; the device-to-gateway link is plaintext by design.
- **No forward secrecy and no key rotation.** A stolen private key exposes all traffic encrypted with it; replacing keys is a manual step.
- **Limited validation of values.** The cloud rejects `NaN` and malformed data, but stores physically impossible temperatures (−500 °C was stored), and the gateway forwards DS18B20 error codes as readings while counting them.
- **Single instance, unbounded storage.** One cloud and one gateway process, no retention limit and no paging on `GET /data`.

## Key decisions and why

| Decision | Reason | Trade-off |
|----------------------|------------------------------------------|------------------------------------|
| Protect only gateway → cloud | The legacy device cannot be changed; the gateway is the realistic place to add protection. | The local device link stays exposed. |
| Rebuild instead of patching v2 | v2 was hard to read and review, and its complexity had produced a security bug. | Lost tests and safety nets had to be re-added. |
| One ML-KEM encapsulation per message | No session state, no nonce counter; each message independent. | 1,088 extra bytes and one encapsulation per reading. |
| Public key distributed with the deployment | Nothing to intercept or substitute at runtime. | Changing keys means redeploying both services. |
| Keys generated per machine, never committed | A committed private key had made the encryption worthless. | One extra setup step for every team member. |
| OpenSSL's ML-KEM instead of `kyber-py` | Maintained, constant-time implementation; suits the brief's "suitable implementation". | Private key format changed; keys regenerated. |
| Legacy plaintext endpoint off by default | Plaintext must be a deliberate, visible choice. | Old clients need explicit opt-in. |
| Monitoring stack optional | The base system stays small; operators add monitoring when needed. | Alerts exist only when the overlay runs. |

: Main design decisions.

## Technical debt and risks

**Technical debt.** No sender authentication; timestamp-only replay protection; no key rotation; no range check on stored temperatures; unbounded storage and unpaginated reads; sensor state lost when the gateway restarts; the ML-KEM shared secret used directly as the AES key, where a key-derivation step (HKDF) would bind it to its purpose at almost no cost and is needed for any extension such as encrypted replies; and the evaluation scripts and monitoring overlay added in v3.1.0 are larger than the rest of the system and were merged without a human review.

**Risks.** The old key pair is public in the repository history, so anything recorded while it was in use must be considered readable.
AI-generated code merged without review proved to contain a defect that its own tests missed; the same may apply to parts not yet reviewed.
And the system has only been run on team members' machines, never on a shared or production-like environment.

**For real production use** the project would need: authentication of the gateway (and of devices where possible), a nonce cache or sequence numbers against replay, TLS around the HTTP links, managed key storage and rotation, retention and backup for the database, and monitoring that notifies people.
