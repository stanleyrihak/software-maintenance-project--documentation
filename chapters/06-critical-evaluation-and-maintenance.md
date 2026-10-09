# Critical evaluation and maintenance

This chapter describes how the system changed over time, which problems were found in the AI-generated code, and what they taught us about maintaining it.

## How the system evolved

| Version | Date | Main author | What it brought |
|-----------|---------|------------------|-------------------------------------------|
| v1.0.0 | 14 Sep | Stanislav Řihák, Roland Budzák | plaintext baseline |
| v2.0.0 | 24 Sep | Tom | ML-KEM with sessions, tests, CI |
| v2.1.0 | 28 Sep | Stanislav Řihák | metrics, Grafana dashboard |
| v2.2.0 | 29 Sep | Roland Budzák | realistic DS18B20 simulation |
| rewrite | 4–5 Oct | Roland Budzák | the system rebuilt from v1.0.0 with ML-KEM per message |
| v3.1.0 | 5 Oct | Tom | persistent storage, plaintext endpoint switch, sensor state, monitoring |
| v3.2.0 | 7 Oct | Stanislav Řihák | keys out of the repository, OpenSSL ML-KEM, `NaN` fix |

: Versions of the project.

The rewrite was built in five internal phases, documented in `documentation/phases/` of the code repository.
Those phases reused the labels v1.1.0–v3.0.0, but they are not the Git tags of the same names.

### The first design: ML-KEM sessions (v2)

In v2, the gateway first fetched the cloud's public key and performed a handshake with it.
Both sides then derived a session key that was used for all readings for up to five minutes, with a counter as the AES-GCM nonce.
The version also added retries, readiness checks, tests, CI, metrics and a realistic sensor simulation.

The design worked, but it had two problems.
First, a review found a security bug: when the cloud's reply was lost, the counter was not advanced, so the next reading was encrypted with the same key and nonce.
Second, the project had grown to about 9,000 lines of Python, which the team found hard to read and review.

### The rewrite (v3)

On 4–5 October the team decided to rebuild the system from the v1.0.0 baseline instead of patching v2 further.
The goal was code that every team member could read and explain.

The new design uses a new ML-KEM key for every reading, as described in *ML-KEM integration*.
There is no handshake, no session and no counter, so the bug from v2 cannot occur.
The project shrank from about 9,000 to about 1,150 lines of Python.

Some of the removed code was useful, however: validation, persistence, monitoring and many tests.
Versions 3.1.0 and 3.2.0 added the important parts back in the simpler design.

## Problems found in AI-generated code

In each of the following cases the code ran and its own tests passed.
The problem became visible only through a review or by testing situations the generated tests did not cover.

| Problem | How it was found | Fix |
|------------------------------|------------------------------|------------------------------|
| **Nonce reuse after a lost reply** (v2) | a review traced what happens when a reply is lost, and reproduced it against the real cloud code | fixed on a branch; made impossible by the rewrite |
| **`NaN` breaking `GET /data`** (three times) | `NaN` sent to the running services; once stored, every read of the data failed | the rule moved into the data model shared by both endpoints |
| **Private key in the public repository** (rewrite) | a review of the Compose file in a public repository | keys generated per machine into an untracked `.env`; the old key treated as compromised |
| **Educational ML-KEM library** (rewrite) | a review of the chosen library: `kyber-py` is not constant-time | replaced by ML-KEM from OpenSSL |
| **Replay and forged readings** (v3) | attacking the running system | documented as known limitations |

: Main problems found in AI-generated code.

Every fix was verified twice: by regression tests that first failed on the old code, and by running the system in Docker.

## Lessons for maintenance

- **Simpler code is easier to keep correct.** The rewrite removed a whole class of bugs, because there was no longer any state that could go wrong.
- **Removing code also removes protection.** The `NaN` problem returned twice after code was removed or rewritten, because the rule lived in only one place.
- **Generated tests check what the code was written to do.** The problems were found by people asking what could go wrong, not by the tests that came with the code.
