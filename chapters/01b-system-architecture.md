# System architecture

This chapter describes how the device, the gateway and the cloud work, in the order a reading passes through them.
Each service lives in its own directory of the repository (`device/`, `gateway/`, `cloud/`) and runs in its own Docker container.
All three services are written in Python 3.12.
The gateway and the cloud are built with the FastAPI web framework and run under the uvicorn server.
Device is a plain Python script.
The cryptographic details are in the chapter *ML-KEM integration*, and the metrics and logs in *Operations*.

![The final system overview.](figures/architecture.pdf){width=72%}

## Device

The device stands for legacy hardware that cannot be changed.
It behaves like a DS18B20 temperature sensor, including the ways a real one fails, and it acts only as a client (nothing can send requests to it).

### Behaviour

Every five seconds the device takes one reading and sends it.
A reading is sent in a format `{"device_id": ..., "temperature": ...}` to the gateway's `POST /device-data` with a timeout of five seconds.
A disconnected sensor sends to `POST /device-status` instead.
If the gateway is unavailable, the reading is lost and the device only prints the error.
For every reading the device prints what it sent and the status code it received.
You can view past logs (prints) via `docker compose logs device`.

![Device behaviour.](figures/device-loop.pdf){width=85%}

### Real-life sensor simulation

The code is trying to emulate behaviour of real sensors.
The first temperature is a random value between 15 and 30 °C.
Each following reading changes it by a random step of at most ±0.3 °C, kept within 15–30 °C and rounded to two decimals, so the values change slowly like a real room temperature.

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

Every reading goes through four steps.
First, the gateway checks that the reading has a `device_id` with 1–100 characters and a `temperature` that is a finite number.
Second, the gateway checks that it can track the device.
It keeps the state of at most 1,000 devices.
Third, the gateway updates the sensor's state, adds a `timestamp` with the current time, encrypts it and forwards the message.
Finally, the gateway waits at most five seconds for the cloud's response and does not retry.

![What the gateway does with a reading and what the device gets back.](figures/gateway-processing.pdf){width=100%}

### Sensor state

The gateway keeps a small record per device and derives three states from it. The state is kept in memory only, so it is lost when the gateway restarts:

| State | Set when | Cleared when |
|-----------------|--------------------------------------|----------------------------------|
| disconnected | a disconnect report arrives | the next reading arrives |
| suspected stuck | the same normal temperature arrives three times in a row | an error code or a different value arrives |
| silent | no contact for 30 seconds | any reading or report arrives |

: Sensor states tracked by the gateway.

## Cloud

The cloud is the storage with a database system that receives readings from the gateway and stores them.

| Endpoint | Purpose |
|------------------------------|--------------------------------------------------|
| `POST /data/secure` | receives an encrypted sensor reading from the gateway |
| `POST /data` | receives legacy plaintext sensor reading |
| `GET /data` | return all stored sensor readings |
| `GET /health` | answer `{"status": "healthy"}` while the process runs |
| `GET /metrics/` | expose metrics for Prometheus |

: Cloud endpoints.

### Encrypted ingestion

On endpoint `POST /data/secure` cloud receives an encrypted reading from the gateway and decrypts it.
A message is valid if it has a `device_id` string and a finite temperature.
The cloud does not check the length of `device_id`, nor the temperature range (since gateway already does that).
The cloud answers `200` only after the reading has been committed to the database.

![What the cloud does with an encrypted reading and what the gateway gets back.](figures/cloud-ingestion.pdf){width=100%}

### Legacy endpoint

`POST /data` is the original plaintext endpoint, kept for clients that have not yet migrated.
It is controlled by `CLOUD_ALLOW_LEGACY_INGESTION` variable.
With the default `false`, every request is answered with `403`, nothing is stored and the attempt is counted.
With `true`, the endpoint validates and stores readings like the encrypted path, logs a warning for each one and counts it.

### Storage

Readings are stored in an SQLite database.
The database has one table called `readings` with an increasing `id` and the reading as `JSON` text.
The cloud confirms a reading only after it has been saved, so a confirmed reading is never lost, even when the container restarts.
If the database cannot be used, the cloud answers `503`.

### Reading the saved data

Endpoint `GET /data` returns a list of all stored readings in the order they were stored:

```json
[{"device_id": "legacy-sensor-001", "temperature": 21.37}, ...]
```

## Deployment

The three services are started together by Docker Compose (docker-compose.yml), each in its own container.
Inside Compose they reach each other by name (`http://gateway:8000` and `http://cloud:8001`).
Compose starts the cloud first, gateway second and the device last, however it does not wait until a service is ready, so the first readings may fail.
The cloud's database is kept on the Docker volume `cloud-data`, so stored readings survive when the containers are restarted or recreated.
The gateway gets the cloud's public key to encrypt readings, and the cloud gets the matching private key to decrypt them.

| Service | Port | Key from `.env` |
|---------|------|---------------------------|
| cloud | 8001 | `CLOUD_ML_KEM_PRIVATE_KEY` |
| gateway | 8000 | `CLOUD_ML_KEM_PUBLIC_KEY` |
| device | — | — |

: Containers in `docker-compose.yml`.
