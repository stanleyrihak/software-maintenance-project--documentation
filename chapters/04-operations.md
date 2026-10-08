# Operations

## Continuous integration

The pipeline is defined in `.github/workflows/ci.yml` and runs on every push and pull request.
A change is only accepted when all jobs pass.

| Job | What it checks |
|-----------------------------|------------------------------------------------------|
| `static-checks` | Every Python file compiles. |
| `test-device`, `test-gateway`, `test-cloud` | The service's unit tests, plus a check that the required libraries import. Results are summarised in the job and fail the build if any test is skipped. |
| `test-tooling` | Tests for the evaluation and CI helper scripts. |
| `build` | The Compose configuration is valid and all three images build. |
| `smoke` | Starts the gateway and cloud in an isolated Compose project and checks encrypted delivery and fault handling end to end. |
| `monitoring-config` | The monitoring overlay is valid; Prometheus rules pass their unit tests (`promtool`); Alertmanager routing is valid (`amtool`). |
| `reliability-smoke` | Starts the full stack with monitoring and checks persistence across restarts, rejection of plaintext, sensor states, and that an outage raises and clears an alert. |
| `publish` | After all of the above, on pushes to `main`: builds the three images and pushes them to the GitHub Container Registry (GHCR). |

: CI jobs.

Jobs that start containers first generate throwaway ML-KEM keys with `scripts/generate_keys.py`, so no key is ever stored in the repository or in CI settings.

## Continuous delivery and the test environment

> **TODO before submission:** this section describes the planned continuous delivery.
> It must be updated once the deployment job and script exist, with the actual run results.

The course instructions rule out an online server, so the test environment is a **clean, isolated environment created from the published images**, in CI and on a team member's machine, rather than a hosted machine:

1. **Versioned images.** Pushing a release tag (for example `v3.2.0`) publishes the images with that version as well as `latest`, so a specific version can be deployed and an older one restored.
2. **Deployment job.** After publishing, a CI job on a fresh runner pulls exactly those images, generates keys, starts them under a separate project name, waits for `/health`, sends one reading through the gateway and confirms that it is stored in the cloud, and then removes the environment.
   A failed check fails the release.
3. **Local deployment script.** The same steps as a script, so the test environment can be recreated on any machine with Docker; running it with an earlier version tag is the rollback.

What separates this from development: the images are the published artefacts, not a local build; the environment is created the same way every time; and the deployment is verified automatically.
It is not production: a single host, no TLS, and keys created by hand.

## Health checks, logs and metrics

**Health checks.** Both services answer `GET /health` with `{"status": "healthy"}`.
CI and the evaluation scripts use it to wait for a started service.

**Logs.** All services log to standard output (`docker compose logs`).
The gateway logs each received reading, every forwarding failure with its traceback, and every disconnect report.
The cloud logs every stored reading, every use or rejection of the legacy endpoint, and every rejected secure request with its reason.
The device prints each reading and the response it received.

**Metrics.** Both services expose Prometheus metrics on `/metrics/`.

| Metric | Service | Meaning | Worth attention when |
|--------------------------------------|---------|---------------------------|----------------------|
| `device_messages_total` | gateway | readings received | it stops increasing |
| `cloud_forward_attempts_total` / `cloud_forward_failures_total` | gateway | forwarding attempts / failures | failures exceed 5 % |
| `sensor_fault_readings_total{type}` | gateway | DS18B20 error codes (`power_on_reset` 85, `crc_failure` −127) | more than 20 % of readings |
| `sensor_read_failures_total`, `sensor_disconnected_devices` | gateway | disconnect reports / devices currently disconnected | any device disconnected |
| `sensor_suspected_stuck_devices`, `sensor_stuck_episodes_total` | gateway | same value repeated (default three times) | any |
| `sensor_silent_devices` | gateway | devices without contact for 30 s | any |
| `secure_data_received_total` | cloud | readings stored through the encrypted path | it stops increasing |
| `secure_data_rejected_total{reason}` | cloud | rejected encrypted requests by reason | any, especially `decryption_failed` |
| `legacy_data_received_total` / `legacy_data_rejected_total` | cloud | plaintext readings stored / refused | any (see migration strategy) |

: Metrics and when they matter.

**Monitoring stack (optional).** `docker-compose.monitoring.yml` adds Prometheus (scraping every 15 seconds, 30 days of history), Grafana with a provisioned twelve-panel dashboard, Alertmanager, and a small local "alert inbox" that keeps firing and resolved alerts.
Nine alert rules cover unavailable services, delivery failures, rejected secure requests, use or blocking of the legacy endpoint, a high sensor-fault rate, and disconnected, stuck or silent sensors.
The rules have unit tests run by `promtool` in CI.
All monitoring ports are bound to the local machine only.

## Testing and verification

**Automated tests.** Each service has its own `pytest` suite, run separately because the gateway and the cloud both name their package `app`.
At commit `0bb6d84` (7 October) all 164 tests pass:

| Suite | Tests | Covers |
|-------------|------:|--------------------------------------------------------------|
| device | 9 | the simulated sensor (drift, error codes, stuck values, disconnects) and sending |
| gateway | 50 | validation, error codes, sensor state, metrics, encryption of every forwarded reading, fresh ML-KEM material per reading |
| cloud | 71 | decryption, tampering with each field, wrong key, stale and malformed payloads, `NaN` on both endpoints, legacy switch, SQLite storage and its failures, metrics |
| tooling | 34 | the evaluation and CI helper scripts |

: Test suites.

Bugs fixed in the later versions received regression tests that were first shown to fail on the old code — for example the three `NaN` tests on the legacy endpoint added in v3.2.0.

**Security and validation checks against the running system.** On 7 October the current code was started with Docker Compose and each case below was sent over real HTTP; "stored" counts the readings of that case found in `GET /data` afterwards.

| Case | Expected | Actual | Stored |
|---------------------------------------------------|---------|---------|------|
| Valid reading through the gateway | 200 | 200 | 1 |
| Tampered AES ciphertext / KEM ciphertext / nonce | 400 | 400 | 0 |
| Encrypted for a different public key | 400 | 400 | 0 |
| Timestamp 60 s old | 401 | 401 | 0 |
| Decrypts, but is not JSON | 400 | 400 | 0 |
| Decrypts, temperature missing | 422 | 422 | 0 |
| Decrypts, temperature `NaN` | 422 | 422 | 0 |
| `NaN` sent to the gateway | 422 | 422 | 0 |
| Plaintext `POST /data` with legacy ingestion off | 403 | 403 | 0 |
| Same encrypted message sent 3 times within 30 s | — | 200, 200, 200 | 3 |
| Reading encrypted by an outsider with the public key | — | 200 | 1 |
| −500 °C sent to the gateway | — | 200 | 1 |
| DS18B20 error code 85 sent to the gateway | — | 200 | 1 |

: Security and validation results (7 October, current code).

The first nine rows show the protections working: nothing invalid or tampered was stored, and every rejection appeared in `secure_data_rejected_total` or `legacy_data_rejected_total` with the right reason.
The last four rows are known limitations, listed in the final evaluation.
After the checks, recreating the cloud container left all 224 stored readings in place (persistence).

**End-to-end checks.** The CI `smoke` and `reliability-smoke` jobs were also run locally on the current code and passed: encrypted delivery, rejection of plaintext, sensor states, persistence of data and monitoring history across restarts, and an outage alert that fired (about 150 seconds after the cloud was stopped) and resolved after recovery.

**Latency.** The same procedure was run for four versions on the same machine on 7 October: 200 readings sent from the host to the gateway after 10 warm-up readings, each answered only after the cloud stored it.

| Version | Protection | Storage | Median | 95th percentile |
|---------|------------------------------------------|--------|-------:|------:|
| v1.0.0 | none (plaintext) | memory | 4.75 ms | 8.14 ms |
| v2.2.0 | ML-KEM sessions (OpenSSL), key reused for 5 min | memory | 3.75 ms | 5.37 ms |
| v3.0.0 | ML-KEM per message (`kyber-py`) | memory | 9.05 ms | 10.39 ms |
| v3.2.0 | ML-KEM per message (OpenSSL) | SQLite | 11.40 ms | 17.27 ms |

: Latency of one reading, device-side view.

The session design added no measurable cost: one handshake is shared by many readings.
Encapsulating per message roughly doubled the latency in v3.0.0, where the pure-Python `kyber-py` library did the work on both sides. v3.2.0 uses the much faster OpenSSL implementation but is slower again; the likely cause is that each reading is now committed to SQLite on disk before the reply.
This was not measured in isolation.
At one reading every five seconds, 11 ms is irrelevant; at high message rates, per-message encapsulation and synchronous writes would both need to be reconsidered.

**Not tested.** No load or concurrency tests; no tests on a real network or constrained hardware; no independent test of the ML-KEM implementation itself (the earlier version ran NIST known-answer tests, the current one relies on the OpenSSL implementation); no deployment by a team member who did not write the setup.
