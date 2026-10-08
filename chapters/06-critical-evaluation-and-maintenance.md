# Critical evaluation and maintenance

## The evolution of the system

The system was built in three stages.
Each section below gives the goal of the version, what was built, how the LLM was used, and what went wrong and why.

| Version | Date | Main author | What it brought |
|-----------|---------|------------------|-------------------------------------------|
| v1.0.0 | 14 Sep | Stanislav Řihák, Roland Budzák | plaintext baseline |
| v2.0.0 | 24 Sep | Tom | ML-KEM with sessions and handshake, tests, CI/CD |
| v2.1.0 | 28 Sep | Stanislav Řihák | cryptographic metrics, Grafana, CI suites |
| v2.2.0 | 29 Sep | Roland Budzák | realistic DS18B20 simulation, `NaN` fix |
| v3.0.0 | 4–5 Oct | Roland Budzák | rewrite from the baseline: per-message ML-KEM |
| v3.1.0 | 5 Oct | Tom | SQLite persistence, legacy switch, sensor state, monitoring |
| v3.2.0 | 7 Oct | Stanislav Řihák | keys out of the repository, OpenSSL ML-KEM, `NaN` fix |

: Versions of the project.

### The first ML-KEM design (v2)

**v2.0.0 (24 September): the first ML-KEM design.** The gateway–cloud link was protected with ML-KEM-768 from the `cryptography` package (OpenSSL's implementation).
The design was *session-based*: the gateway fetched the cloud's public key, performed a handshake (`GET` and `POST /secure/handshake`), and both sides derived a session key that was reused for up to five minutes.
Each message used a counter as its AES-GCM nonce.
A pre-shared key authenticated the handshake in both directions, and a mode switch (`off`/`enabled`/`required`) allowed a gradual migration and a rollback.
The version also added retries, readiness checks, unit and integration tests, a CI pipeline and image publishing.
It was produced mainly with Codex and Claude Code (several agents in parallel).

**v2.1.0 (28 September)** connected the cryptographic metrics, which had been defined but never updated, added a Grafana dashboard, and ran the ML-KEM test suites in CI.
**v2.2.0 (29 September)** replaced the random device with a realistic DS18B20 simulation (sensor disconnects, error codes 85 and −127, stuck values, `NaN`) and fixed what it exposed: a `NaN` reading made the gateway and cloud fail with `500`.

**What went wrong.** An end-of-v2.1 review found a real security bug in the session design (detailed in the critical-evaluation cases): when the cloud stored a reading but its reply was lost, the gateway did not advance its counter, so the next, different reading was encrypted with the same key and nonce.
Reusing an AES-GCM nonce leaks information about both messages and allows forgeries; the cloud then also rejected every reading until the session expired, about five minutes later.
A fix was written and tested on a branch, together with startup checks, metric corrections and alert rules.

The larger problem was size.
By v2.2.0 the project contained about 9,000 lines of Python, of which 3,100 were application code: a handshake protocol, session management, a duplicated wire-format module, a mode switch, and long, heavily commented metric definitions.
The team found the code hard to read and hard to review — and the nonce bug showed that the complexity itself created risk.

### The rewrite (v3)

**Decision.** On 4–5 October the team rebuilt the system from the original v1.0.0 baseline instead of continuing to patch v2.
The aim was code that every team member could read and explain, with the same features where they mattered.
The rewrite was developed with Claude Code in small phases, each documented in `documentation/phases/` of the code repository.
**Note on numbering:** the rewrite reused the labels v1.1.0–v3.0.0 for its phases (tests; CI/CD and image publishing; DS18B20 simulation; ML-KEM; metrics).
Those phase labels are not the same releases as the Git tags v1.0.0–v2.2.0, which belong to the earlier architecture.

**The new design.** Instead of sessions, the gateway performs **one ML-KEM encapsulation per message** against the cloud's public key, which is distributed with the deployment instead of being fetched.
The resulting shared secret is the AES-256-GCM key for that one message, with a random nonce.
There is no handshake, no session state and no counter, so the class of bug found in v2 cannot occur: every message has its own key.
The cost is a 1,088-byte KEM ciphertext and one encapsulation per message.

**Where the code went.** The application code shrank from 3,102 lines (v2.2.0) to 464 (v3.0.0); the whole project from about 9,000 to about 1,150 lines of Python.
The largest reductions were tests (about 4,000 lines, including NIST known-answer tests for ML-KEM), the session protocol (about 1,240 lines, replaced by 33), evaluation scripts and CI tooling (about 1,200), and operational code such as retries, readiness checks and validation (about 1,400).
Some of the removed code was safety net rather than complexity, and part of it had to be added back later.

### Completing the rewrite (v3.1 and v3.2)

**v3.1.0 (5 October)** restored several of those safety nets in the simpler architecture: readings are stored in SQLite on a Docker volume and survive restarts; the plaintext `POST /data` endpoint is closed by default; the gateway tracks each sensor's state (disconnected, suspected stuck, silent) and the device reports disconnects explicitly; and an optional monitoring stack (Prometheus, Grafana, Alertmanager and a local alert inbox) with nine tested alert rules was added.
CI grew to ten jobs, including an end-to-end smoke test and a reliability check.
The earlier prompt records and validation reports were recovered into an archive in the repository.
This work was produced with Codex.

**v3.2.0 (7 October)** came out of a review of v3.0.0 and v3.1.0 by running the services and attacking them.
It fixed three problems the tests had not caught:

- the cloud's ML-KEM **private key was committed** in `docker-compose.yml` of a public repository; keys are now generated per machine into an untracked `.env` file by `scripts/generate_keys.py`, and the committed key pair is treated as compromised;
- the rewrite had used `kyber-py`, an **educational ML-KEM implementation** that is not constant-time; it was replaced by ML-KEM-768 from the `cryptography` package (OpenSSL), the library v2 had used;
- a `NaN` temperature sent to the legacy endpoint was **stored and then broke every `GET /data`**, permanently with SQLite storage; the finite-number rule now lives in the shared data model.

It also made the device's log output visible in Docker. v3.2.0 is the version this document describes.

## Problems found and how they were verified

The following cases show the main problems found in AI-generated code, how they were discovered and how the fixes were verified.
In each case the code ran and its own tests passed; the problem only became visible through review or by testing situations the generated tests did not cover.

**Case 1 — AES-GCM nonce reuse after a lost reply (v2).** *Generated:* the session-based secure channel, where each message's nonce was a counter advanced only after a successful reply.
*How found:* an end-of-version review traced what happens when the cloud stores a reading but the reply is lost.
An in-process reproduction against the real cloud code showed the next reading sent with the same nonce, followed by `409` errors until the session expired.
*Fix:* reserve the counter before sending, and start a new session on `409`.
Three regression tests failed on the old code and passed after the fix.
*Outcome:* the fix was made on a branch, but the rewrite replaced the session design entirely; per-message keys make this class of bug impossible.
It is the clearest example in the project of complexity creating risk.

**Case 2 — `NaN` breaking the read API (three times).** A `NaN` temperature cannot be written as JSON.
When one was stored, every later `GET /data` failed with `500`.
*First:* v2.2.0's realistic sensor sent `NaN` and exposed it; fixed with `422` and tests.
*Second:* the rewrite (v3.0.0) dropped that validation, and a review sending `NaN` to the running services showed it again.
*Third:* v3.1.0 added validation only to the encrypted endpoint, inside the request handler.
Testing the legacy endpoint with ingestion enabled showed `NaN` stored again — now in SQLite, so the API stayed broken even after a restart.
*Fix (v3.2.0):* the rule moved into the shared data model, so both endpoints apply it, and the error response itself was made safe for `NaN`.
Three regression tests failed on the old code first; the running system answered `422` and kept serving data.
*Lesson:* a rule placed in one code path is easily missed in another; generated tests checked the path they were written for.

**Case 3 — the ML-KEM private key in a public repository (v3.0.0).** The generated deployment put both keys directly into `docker-compose.yml`, and the phase document called it "acceptable for a course project".
*How found:* reviewing the repository's visibility together with the Compose file: anyone could download the key and decrypt every recorded reading, which defeats the purpose of post-quantum protection.
*Fix (v3.2.0):* a script generates keys per machine into an untracked `.env`; Compose stops with a clear message without them; CI generates throwaway keys.
*Verified* in Docker: without `.env` the stack refuses to start, with new keys it works.
*Remaining:* the old key stays in the Git history and is treated as compromised.

**Case 4 — an educational library as the "existing implementation" (v3.0.0).** The rewrite's design prompt asked for a simple structure, and the LLM proposed `kyber-py` because it needs no native build.
Its authors describe it as an educational implementation that is not constant-time.
The course asks for an existing, *suitable* implementation.
*Fix (v3.2.0):* ML-KEM-768 from `cryptography` (OpenSSL), which the project already used for AES-GCM.
All test suites passed in an environment without `kyber-py` installed, and the stack ran in Docker with the new library.

**Case 5 — what encryption does not give.** Testing the running v3 system as an attacker would showed two gaps no test covered: the same encrypted message is accepted again within the 30-second window (stored three times), and anyone with the public key can send a valid reading.
Both follow from the design (timestamp-only replay protection, no sender authentication).
They were documented as limitations rather than fixed; a nonce cache and a shared secret for the gateway are the small changes that would close them.

**Case 6 — the rewrite as a maintenance decision.** v2 met most requirements but had become hard to read and review.
Rebuilding from the baseline produced a system the whole team understands, and removed a whole class of bugs.
It also removed safety nets — validation, persistence, monitoring, many tests — some of which had to be added back in v3.1.0 and v3.2.0, and one of which (`NaN` handling) failed twice more in the process.
The decision was right for maintainability; the cost was paid in re-discovered bugs.
