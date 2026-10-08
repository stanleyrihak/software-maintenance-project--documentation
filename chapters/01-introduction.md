# Introduction

## The task and why it matters

The course asked each group to modernise a small legacy edge–cloud system for
the transition to post-quantum cryptography. The system has three parts: a
simulated legacy temperature sensor, an edge gateway that receives its readings,
and a cloud service that stores them. The starting version worked, but had
limited tests, no automated pipeline, little monitoring and no protection of the
data in transit. The task was not to implement ML-KEM ourselves, but to
integrate an existing implementation safely into this legacy environment, and to
build, test, deploy and monitor the result.

A second goal ran through all of the work: a large language model (LLM) was used
as an assistant, and its output had to be treated as untrusted. Every generated
artefact had to be reviewed, tested and either accepted, modified or rejected,
with the reasoning recorded.

**Why this matters.** Most data on the internet today is protected by key
exchange based on RSA or elliptic curves. A sufficiently large quantum computer
could break both. An attacker does not need to wait for that computer: traffic
recorded today can be stored and decrypted later ("harvest now, decrypt
later"). Data with a long shelf life — industrial measurements, health data,
infrastructure telemetry — is therefore already at risk. NIST standardised the
first post-quantum key-encapsulation mechanism, ML-KEM, in 2024 (FIPS 203).

Legacy devices make the migration hard. A sensor in the field often cannot be
updated: its firmware is fixed, its hardware too small, or nobody is responsible
for it any more. The realistic approach, and the one taken here, is to leave the
device unchanged and add protection around it, at the gateway that connects it to
the cloud.

## System overview

![The final system: components and communication paths.](diagrams/architecture.pdf){width=72%}

The **device** simulates a DS18B20 temperature sensor and sends a reading to
the gateway every five seconds, in plaintext, exactly as the legacy device
would. The **gateway** validates the reading, keeps track of each sensor's
state, encrypts the reading with ML-KEM-768 and AES-256-GCM, and forwards it to
the **cloud**, which decrypts it, validates it again and stores it in an SQLite
database. The plaintext path into the cloud still exists for clients that have
not been migrated, but it is closed unless explicitly enabled. Both services
expose metrics; an optional monitoring stack collects them, shows them in a
dashboard and raises alerts.

## Components

The system runs as three containers defined in `docker-compose.yml`. All
services are written in Python 3.12; the gateway and the cloud use FastAPI.

| Service | Code | Endpoints | Responsibility |
|---------|------------|--------------------------|----------------------------------------|
| Device | `device/` | (client only) | Simulates a DS18B20: a reading drifting between 15 and 30 °C every 5 s; with configurable probabilities a disconnect (reported to `/device-status`), an error code (85 or −127) or a stuck value repeated 3–8 times. |
| Gateway | `gateway/` | `POST /device-data`, `POST /device-status`, `GET /health`, `/metrics` | Validates readings (finite number, `device_id` 1–100 characters), counts DS18B20 error codes, tracks per-device state, encrypts and forwards each reading. |
| Cloud | `cloud/` | `POST /data/secure`, `POST /data` (legacy, off by default), `GET /data`, `GET /health`, `/metrics` | Decrypts and validates readings, stores them in SQLite (`/data/readings.sqlite3` on the `cloud-data` volume), returns stored readings. |

: Services, their code and endpoints.

The gateway's **sensor state** (`gateway/app/sensor_state.py`) is kept in memory
per device: whether its last report was a disconnect, whether it has sent the
same value three times in a row (suspected stuck), and whether it has been
silent for more than 30 seconds. The counts are exposed as metrics without
device IDs as labels, so the number of metric series stays bounded.

Configuration is passed as environment variables. The ML-KEM keys come from an
untracked `.env` file that Docker Compose reads automatically; everything else
has defaults in `docker-compose.yml` (see *Configuration reference*).

## How to read this document

The chapters follow the course brief's list of required work, one chapter per item:

| Course requirement | Where |
|------------------------------|------------------------------------------|
| AI-assisted development | 5 |
| Baseline analysis | 2 |
| Critical evaluation and maintenance | 6 |
| ML-KEM integration, migration and fallback | 3 |
| Operations: build, test, deployment, health, logs, metrics | 4 |
| Final evaluation | 7 |

: Where each course requirement is covered.
