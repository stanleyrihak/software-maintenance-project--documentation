# System architecture

The system consists of three services: the device, the gateway and the cloud.
Each lives in its own directory of the repository and runs in its own Docker container.
This chapter describes what each service does, in the order a reading passes through them.
The cryptographic details are in the chapter *ML-KEM integration*, and the metrics and logs in *Operations*.

## Overview

All three services are written in Python 3.12.
The gateway and the cloud are built with the FastAPI web framework and run under the uvicorn server; the device is a plain Python script.

| Service | Code | Endpoints | Role |
|---------|--------------|------------------------------|--------------------------------------|
| Device | `device/` | none: it only sends requests | simulates the legacy temperature sensor |
| Gateway | `gateway/` | `POST /device-data`, `POST /device-status`, `GET /health`, `GET /metrics/` | receives readings, tracks sensor state, encrypts and forwards |
| Cloud | `cloud/` | `POST /data/secure`, `POST /data`, `GET /data`, `GET /health`, `GET /metrics/` | decrypts, validates and stores readings |

: Services, their code and endpoints.

One reading travels as follows:

1. The device produces a temperature and sends it to the gateway as plaintext JSON.
2. The gateway validates it, updates the sensor's state, encrypts it and sends it to the cloud.
3. The cloud decrypts it, checks it again and commits it to its database.
4. The cloud's confirmation is passed back through the gateway to the device.

## Device

The device stands for legacy hardware that cannot be changed.
It behaves like a DS18B20 temperature sensor, including the ways a real one fails, and it acts only as a client: nothing can send requests to it.

### Sending readings

![What the device does every five seconds.](figures/device-loop.pdf){width=85%}

Every five seconds the device takes one reading and sends it.
A reading is sent as `{"device_id": ..., "temperature": ...}` to the gateway's `POST /device-data` with a timeout of five seconds; a disconnected sensor is reported to `POST /device-status` instead.
There is no retry and no buffer: if the gateway cannot be reached, the reading is lost and the device only prints the error.
For every reading the device prints what it sent and the status code it received.
With `PYTHONUNBUFFERED=1` in its container these lines appear in `docker compose logs device` as they happen.

### Simulated readings

The first temperature is a random value between 15 and 30 °C.
Each following reading changes it by a random step of at most ±0.3 °C, kept within 15–30 °C and rounded to two decimals, so the values drift slowly like a real room temperature.

For each reading the device draws one random number and decides, with configurable probabilities, which of four things happens:

| Outcome | Default probability | What the device sends |
|-------------------|------:|--------------------------------------------------|
| Disconnected sensor | 2 % | no reading and `status: disconnected` to the gateway's `/device-status` |
| Error code | 1 % | a reading with the faulty temperature `85.0` or `−127.0` [@ds18b20; @dallastemperature] |
| Stuck sensor | 3 % | the current value repeated for 3–8 readings in total |
| Normal reading | 94 % | the next value of the drifting temperature |

: Outcomes of one simulated reading.

## Gateway

The gateway is the edge component next to the device.
It is the only service the device talks to, and it is where protection is added before data leaves the site.

| Endpoint | Purpose |
|------------------------------|--------------------------------------------------|
| `POST /device-data` | receive a reading, process it and forward it to the cloud |
| `POST /device-status` | receive a disconnect report from the device |
| `GET /health` | answer `{"status": "healthy"}` while the process runs |
| `GET /metrics/` | expose metrics in the Prometheus format |

: Gateway endpoints.

### Processing a reading

![What the gateway does with a reading and what the device gets back.](figures/gateway-processing.pdf){width=100%}

A reading is valid if its `device_id` has 1–100 characters and its temperature is a finite number.
FastAPI checks this before any other step; a `NaN` value is shown as text in the error, because it cannot be written as JSON.

DS18B20 error codes (85.0 and −127.0) are recognised and counted as sensor faults, but the reading is still forwarded like any other.

Before sending, the gateway adds the current time to the reading and encrypts it with a key established by ML-KEM, as described in *ML-KEM integration*.
It waits at most five seconds for the cloud and does not retry; a failed attempt is logged with its full error.

The four possible answers, in detail:

| Situation | The device receives |
|------------------------------------------------|----------------------------------|
| the cloud stored the reading | `200` "forwarded", with the cloud's confirmation |
| the reading is invalid (missing field, `NaN`, wrong `device_id`) | `422` with the validation error |
| 1,000 devices are already tracked and a new one appears | `503` "Sensor state capacity reached" |
| the cloud is unreachable, too slow or answers with an error | `502` "Cloud service unavailable" |

: Gateway responses to `POST /device-data`.

### Disconnect reports

`POST /device-status` accepts `{"device_id": ..., "status": "disconnected"}`; no other status is valid.
The gateway marks the device as disconnected, counts the report, logs a warning and answers `{"status": "recorded"}`.

### Sensor state

The gateway keeps a small record per device in memory and derives three states from it:

| State | Set when | Cleared when |
|-----------------|--------------------------------------|----------------------------------|
| disconnected | a disconnect report arrives | the next reading arrives |
| suspected stuck | the same normal temperature arrives three times in a row | an error code or a different value arrives |
| silent | no contact for 30 seconds | any reading or report arrives |

: Sensor states tracked by the gateway.

The thresholds can be changed with `SENSOR_STUCK_THRESHOLD` (default 3 readings) and `SENSOR_SILENCE_TIMEOUT_SECONDS` (default 30).
The number of devices in each state is exposed as a metric; "silent" is evaluated whenever the metrics are read, so it changes even when no requests arrive.
Device IDs are never used as metric labels, so the number of metric series stays the same however many devices there are.
The state is lost when the gateway restarts, and at most 1,000 devices are tracked (`SENSOR_STATE_MAX_DEVICES`).

### Keys

At startup the gateway reads the cloud's ML-KEM public key from `CLOUD_ML_KEM_PUBLIC_KEY` and refuses to start if it is missing or malformed.

The metrics the gateway records at each of these steps are listed in *Operations*.

## Cloud

The cloud is the central service that stores readings and serves them.

| Endpoint | Purpose |
|------------------------------|--------------------------------------------------|
| `POST /data/secure` | receive an encrypted reading from the gateway |
| `POST /data` | legacy plaintext ingestion; `403` unless explicitly enabled |
| `GET /data` | return all stored readings |
| `GET /health` | answer `{"status": "healthy"}` while the process runs |
| `GET /metrics/` | expose metrics in the Prometheus format |

: Cloud endpoints.

### Encrypted ingestion

![What the cloud does with an encrypted reading and what the gateway gets back.](figures/cloud-ingestion.pdf){width=100%}

`POST /data/secure` receives the envelope `{kem_ciphertext, nonce, ciphertext}` from the gateway and decrypts it with the cloud's private key, as described in *ML-KEM integration*.
A reading is valid if it has a `device_id` string and a finite temperature.
The cloud does not check the length of `device_id`, which the gateway already does, nor the temperature range.
The cloud answers `200` only after the reading has been committed to the database.
Every rejection is logged and counted with its reason; *ML-KEM integration* lists the reasons in detail.

### Legacy ingestion

`POST /data` is the original plaintext endpoint, kept for clients that have not been migrated.
It is controlled by `CLOUD_ALLOW_LEGACY_INGESTION`.
With the default `false`, every request is answered with `403`, nothing is stored and the attempt is counted.
With `true`, the endpoint validates and stores readings like the encrypted path, logs a warning for each one and counts it.
Any value other than `true` or `false` stops the cloud at startup, so a typo cannot open the plaintext path by accident.

### Storage

Readings are stored in an SQLite database.
The database has one table, `readings`, with an increasing `id` and the reading as JSON text.
Each reading is committed before the cloud answers, so a confirmed reading survives a restart or a recreated container.
An empty path or an in-memory database is refused at startup, so persistence cannot be switched off by accident.
If the database cannot be written or read, the cloud answers `503` "Storage unavailable".
Nothing is ever deleted.

### Reading the data

`GET /data` returns all stored readings in the order they were stored:

```json
[{"device_id": "legacy-sensor-001", "temperature": 21.37}, ...]
```

It has no paging and no authentication.

### Keys

At startup the cloud reads its ML-KEM private key from `CLOUD_ML_KEM_PRIVATE_KEY` and refuses to start if it is missing or malformed.

## Deployment

The three services are started together by Docker Compose (`docker-compose.yml`).
Each has a small image based on `python:3.12-slim`; the gateway and the cloud start `uvicorn` on ports 8000 and 8001, the device runs `python device.py`.

| Service | Published port | Volume | Starts after | Key from `.env` |
|---------|------|--------------|---------|---------------------------|
| cloud | 8001 | `cloud-data` mounted at `/data` | — | `CLOUD_ML_KEM_PRIVATE_KEY` |
| gateway | 8000 | — | cloud | `CLOUD_ML_KEM_PUBLIC_KEY` |
| device | — | — | gateway | — |

: Containers in `docker-compose.yml`.

Inside Compose the services reach each other by name (`http://gateway:8000`, `http://cloud:8001`).
The start order only means that a container is started after the other one, not that the other one is already answering; until it is, the first readings may fail.
The keys come from the untracked `.env` file created by `scripts/generate_keys.py`, and Compose refuses to start without them.
The optional monitoring stack is added with a second Compose file and is described in *Operations*.
