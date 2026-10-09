# Final evaluation

This chapter presents the results of the checks and evaluates the final system: its strengths, its weaknesses and the main decisions behind it.

## Results of the checks

### Security and validation

On 7 October the current code was started with Docker Compose, and each case below was sent to it over real HTTP.
The last column counts how many readings of the case were stored in the cloud afterwards.
The first eight cases show the protections working: nothing changed, outdated or invalid was stored.
The last four were accepted; they are known weaknesses, discussed below.

| Case | Answer | Stored |
|---------------------------------------------------|---------|------|
| valid reading through the gateway | 200 | 1 |
| changed KEM ciphertext, nonce or encrypted reading | 400 | 0 |
| reading encrypted for a different public key | 400 | 0 |
| timestamp 60 seconds old | 401 | 0 |
| decrypts, but is not JSON | 400 | 0 |
| decrypts, but the temperature is missing or `NaN` | 422 | 0 |
| `NaN` sent to the gateway | 422 | 0 |
| plaintext reading to the closed plaintext endpoint | 403 | 0 |
| the same encrypted message sent 3 times within 30 seconds | 200 ×3 | 3 |
| forged reading: an outsider encrypts their own reading with the public key | 200 | 1 |
| −500 °C sent to the gateway | 200 | 1 |
| DS18B20 error code 85 sent to the gateway | 200 | 1 |

: Security and validation results (7 October, current code).

### Latency

The time from sending a reading to the gateway until the reply arrives was measured for four versions on the same machine, with 200 readings each.
Using a new key for every reading roughly doubled the latency compared with sessions.
The current version is even slower, even though its OpenSSL implementation of ML-KEM should be faster than the educational library used before.
The likely cause is the switch from memory to an SQLite database, meaning every reading has to be written to disk before the cloud replies.
At one reading every five seconds, a latency of about 11 ms has no practical effect.

| Version | Protection | Storage | Median | 95th percentile |
|---------|------------------------------------------|--------|-------:|------:|
| v1.0.0 | none (plaintext) | memory | 4.75 ms | 8.14 ms |
| v2.2.0 | ML-KEM sessions (OpenSSL) | memory | 3.75 ms | 5.37 ms |
| v3.0.0 | ML-KEM per reading (`kyber-py`) | memory | 9.05 ms | 10.39 ms |
| v3.2.0 | ML-KEM per reading (OpenSSL) | SQLite | 11.40 ms | 17.27 ms |

: Latency of one reading.

## Strengths

The final system was evaluated against the weaknesses of the baseline listed in *Baseline system*.

| Area | Baseline (v1.0.0) | Final system (v3.2.0) | Evidence |
|--------------|------------------|----------------------|----------------------|
| gateway–cloud link | plaintext | encrypted with ML-KEM-768 | all 7 attacks and invalid inputs rejected, nothing stored |
| cost of protection | 4.75 ms per reading | 11.4 ms per reading | negligible at one reading every 5 s |
| tests and CI | manual checks only | 164 automated tests, CI on every change | all tests pass; two test environments per change |
| validation | very minimal | readings checked in both the gateway and the cloud | `NaN` and malformed readings answered `422`, nothing stored |
| storage | in-memory list, lost on restart | SQLite on a Docker volume | 224 readings kept after the container was recreated |
| monitoring | no metrics | metrics, dashboard and 9 alerts | stopping the cloud raised an alert after about 150 s |

: The baseline compared with the final system.

## Weaknesses

None of the following is required by the course brief, but each would matter in real use.

| Weakness | What would fix it |
|------------------------------------------|----------------------------------------|
| anyone with the public key can send a forged reading | authentication of the gateway, for example with a signature |
| a message can be replayed within 30 seconds | remembering recently seen messages, or sequence numbers |
| the cloud's response is not protected | authenticated responses |
| storage grows without limit and `GET /data` returns everything | retention rules and paging |

: Weaknesses of the final system.

## Key decisions

| Decision | Why | Cost |
|------------------------------|--------------------------------------|------------------------------|
| protect only the gateway–cloud link | the legacy device cannot be changed | the device link stays plaintext |
| rebuild instead of patching v2 | v2 was hard to review and had a security bug | removed safety nets had to be added back |
| a new ML-KEM key for every reading | no session state, no nonce counter | latency doubled |
| ML-KEM from OpenSSL | maintained and constant-time | *none* |
| plaintext endpoint closed by default | plaintext must be a deliberate choice | old clients must be enabled explicitly |
| optional monitoring stack | monitoring is added only when needed | system must be tested both with and without it |

: Main design decisions.

## Conclusion

The final system meets the goals of the project.
Readings leave the gateway protected by ML-KEM encryption, the legacy device works unchanged, and the whole system is built, tested, deployed and monitored automatically.
Its main remaining gap is that the cloud cannot tell who sent a reading.
Closing it would require authenticating the gateway, which the course brief did not ask for, and also it would make the system noticeably more complex.
