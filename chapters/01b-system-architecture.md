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

**The loop:** Every five seconds the device takes one reading and sends it.
There is no retry and no buffer: if the gateway cannot be reached, the reading is lost and the device only prints the error.

**Normal readings:** The first temperature is a random value between 15 and 30 °C.
Each following reading changes it by a random step of at most ±0.3 °C, kept within 15–30 °C and rounded to two decimals, so the values drift slowly like a real room temperature.

**Faults:** For each reading the device draws one random number and decides, with configurable probabilities, which of four things happens:

| Outcome | Default probability | What the device sends |
|-------------------|------:|--------------------------------------------------|
| Disconnected sensor | 2 % | no reading and `status: disconnected` to the gateway's `/device-status` |
| Error code | 1 % | a reading with the faulty temperature `85.0` or `−127.0` [@ds18b20; @dallastemperature] |
| Stuck sensor | 3 % | the current value repeated for 3–8 readings in total |
| Normal reading | 94 % | the next value of the drifting temperature |

: Outcomes of one simulated reading.

**Sending:** A reading is sent as `{"device_id": ..., "temperature": ...}` to `POST /device-data` with a timeout of five seconds.
For every reading the device prints what it sent and the status code it received. With `PYTHONUNBUFFERED=1` in its container these lines appear in `docker compose logs device` as they happen.

## Gateway

The gateway is the edge component next to the device.
It is the only service the device talks to, and it is where protection is added before data leaves the site.

| Endpoint | Purpose |
|------------------------------|--------------------------------------------------|
| `POST /device-data` | receive a reading, process it and forward it to the cloud |
| `POST /device-status` | receive a disconnect report from the device |
| `GET /health` | answer `{"status": "healthy"}` while the process runs |
| `/metrics/` | expose metrics for Prometheus |

: Gateway endpoints.

**Processing a reading:** `POST /device-data` goes through these steps:

1. *Validation.* FastAPI checks the request against the `SensorData` model: `device_id` must be 1–100 characters and `temperature` a finite number.
   Anything else is answered with `422`, before any further processing; a `NaN` value is shown as text in the error, because it cannot be written as JSON.
2. *Counting.* The reading is counted in `device_messages_total`.
3. *Error codes.* If the temperature is 85.0 or −127.0, it is counted as a DS18B20 fault (`sensor_fault_readings_total{type="power_on_reset"}` or `{type="crc_failure"}`).
   The reading is still forwarded; it is only counted.
4. *Sensor state.* The device's state is updated (see below).
   If 1,000 devices are already tracked and a new one appears, the gateway answers `503`.
5. *Forwarding.* The attempt is counted in `cloud_forward_attempts_total`, and `send_to_cloud` (`gateway/app/cloud_client.py`) adds the current time as `timestamp`, encrypts the reading with a key established by ML-KEM and posts it to the cloud's `POST /data/secure`, with a timeout of five seconds.
6. *Answer.* If the cloud stores the reading, the device receives `200` with `{"status": "forwarded", "cloud_response": {"status": "stored"}}`.
   Any failure — the cloud unreachable, a timeout, or an error answer from the cloud — is counted in `cloud_forward_failures_total`, logged with its traceback and answered with `502` "Cloud service unavailable".
   The gateway does not retry.

**Disconnect reports.** `POST /device-status` accepts `{"device_id": ..., "status": "disconnected"}` (no other status is valid).
The gateway marks the device as disconnected, counts the report in `sensor_read_failures_total`, logs a warning and answers `{"status": "recorded"}`.

**Sensor state.** The gateway keeps a small record per device in memory (`gateway/app/sensor_state.py`):

- *Disconnected:* set by a disconnect report and cleared by the device's next reading.
- *Suspected stuck:* set when the same normal temperature arrives three times in a row (`SENSOR_STUCK_THRESHOLD`); each such episode is counted once in `sensor_stuck_episodes_total`.
  An error code or a changed value clears it.
- *Silent:* a device that has not been in contact for 30 seconds (`SENSOR_SILENCE_TIMEOUT_SECONDS`); this is evaluated whenever the metrics are read, so it changes even when no requests arrive.

The numbers of disconnected, suspected stuck and silent devices are exposed as gauges.
Device IDs are never used as metric labels, so the number of metric series stays the same however many devices there are.
The state is lost when the gateway restarts, and at most 1,000 devices are tracked (`SENSOR_STATE_MAX_DEVICES`).

**Keys.** At startup the gateway reads the cloud's ML-KEM public key from `CLOUD_ML_KEM_PUBLIC_KEY` and refuses to start if it is missing or malformed.

## Cloud

The cloud is the central service that stores readings and serves them.

| Endpoint | Purpose |
|------------------------------|--------------------------------------------------|
| `POST /data/secure` | receive an encrypted reading from the gateway |
| `POST /data` | legacy plaintext ingestion; `403` unless explicitly enabled |
| `GET /data` | return all stored readings |
| `GET /health` | answer `{"status": "healthy"}` while the process runs |
| `/metrics/` | expose metrics for Prometheus |

: Cloud endpoints.

**Encrypted ingestion.** `POST /data/secure` (`cloud/app/main.py`) receives the envelope `{kem_ciphertext, nonce, ciphertext}` and processes it in five steps: decrypt it with the cloud's private key; check that the result is a JSON object with a numeric timestamp; reject it if the timestamp is more than 30 seconds from the cloud's clock; validate the reading; and store it.
It answers `200` with `{"status": "stored"}` only after the reading has been committed.
Every rejection is logged and counted in `secure_data_rejected_total` with its reason; the chapter *ML-KEM integration* lists the reasons and their status codes.

**Validation.** The cloud's `SensorData` model requires a `device_id` string and a finite temperature.
The stricter length rule for `device_id` (1–100 characters) is applied by the gateway; the cloud does not check the temperature range.

**Legacy ingestion.** `POST /data` is the original plaintext endpoint, kept for clients that have not been migrated.
It is guarded by `CLOUD_ALLOW_LEGACY_INGESTION` (`cloud/app/config.py`): with the default `false` every request is answered with `403`, nothing is stored and the attempt is counted in `legacy_data_rejected_total`.
With `true` it validates and stores readings like the encrypted path, logs a warning for each one and counts it in `legacy_data_received_total`.
Any value other than `true` or `false` stops the cloud at startup.

**Storage.** Readings are stored in an SQLite database, the file `/data/readings.sqlite3` on the Docker volume `cloud-data` (`cloud/app/storage.py`).
The database has one table, `readings`, with an increasing `id` and the reading as JSON text.
Each reading is committed before the cloud answers, so a confirmed reading survives a restart or a recreated container.
Each storage operation opens its own connection, and the table is created on first use.
An empty path or an in-memory database is refused at startup, so persistence cannot be switched off by accident.
If the database cannot be written or read, the cloud answers `503` "Storage unavailable".
Nothing is ever deleted.

**Reading the data.** `GET /data` returns all stored readings in the order they were stored, as `[{"device_id": ..., "temperature": ...}, ...]`.
It has no paging and no authentication.

**Keys.** At startup the cloud reads its ML-KEM private key from `CLOUD_ML_KEM_PRIVATE_KEY` and refuses to start if it is missing or malformed.

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
