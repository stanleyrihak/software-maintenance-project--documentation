# Appendix A: How to run the project {-}

Requirements: Docker with Compose, and Python 3.12 to generate keys and run the tests.

```sh
git clone https://github.com/Rolko6/Software-Development-and-Maintenance-Project.git
cd Software-Development-and-Maintenance-Project
pip install -r requirements-dev.txt

python scripts/generate_keys.py      # once per machine: ML-KEM keys into .env
docker compose up --build -d         # start device, gateway and cloud

docker compose ps                    # all three "Up"
curl http://localhost:8000/health    # gateway: {"status":"healthy"}
curl http://localhost:8001/health    # cloud:   {"status":"healthy"}
curl http://localhost:8000/metrics/  # gateway Prometheus metrics
curl http://localhost:8001/metrics/  # cloud Prometheus metrics
docker compose logs -f device        # a "Sent data ... Response: 200" line every 5 s
curl http://localhost:8001/data      # stored readings

docker compose down                  # stop (data stays in the cloud-data volume)
```

Run the tests (each suite separately):

```sh
python -m pytest device/tests
python -m pytest gateway/tests
python -m pytest cloud/tests
python -m pytest tests/tooling
```

Optional monitoring (Grafana on http://localhost:3000, Prometheus on http://localhost:9090):

```sh
GRAFANA_ADMIN_PASSWORD=<choose one> \
  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up --build -d
```

## Configuration reference {-}

| Variable | Service | Default | Meaning |
|------------------------------------|---------|----------------------|-----------------------------|
| `CLOUD_ML_KEM_PRIVATE_KEY` | cloud | from `.env` (required) | base64 64-byte ML-KEM-768 seed |
| `CLOUD_ML_KEM_PUBLIC_KEY` | gateway | from `.env` (required) | base64 1,184-byte ML-KEM-768 public key |
| `CLOUD_ALLOW_LEGACY_INGESTION` | cloud | `false` | `true` opens plaintext `POST /data`; any other value than `true`/`false` stops the cloud |
| `CLOUD_DB_PATH` | cloud | `/data/readings.sqlite3` | SQLite file; in-memory databases are refused |
| `CLOUD_URL` | gateway | `http://cloud:8001/data/secure` (set in Compose) | where readings are forwarded |
| `SENSOR_STUCK_THRESHOLD` | gateway | `3` | identical readings before a sensor counts as stuck |
| `SENSOR_SILENCE_TIMEOUT_SECONDS` | gateway | `30` | time without contact before a sensor counts as silent |
| `SENSOR_STATE_MAX_DEVICES` | gateway | `1000` | maximum number of tracked devices |
| `GATEWAY_URL` / `DEVICE_STATUS_URL` | device | `http://gateway:8000/device-data` (set in Compose) / derived from it | where readings and disconnect reports are sent |
| `DEVICE_ID` | device | `legacy-sensor-001` | the device's identifier |
| `DISCONNECT_RATE`, `ERROR_RATE`, `STUCK_START_RATE` | device | `0.02`, `0.01`, `0.03` | probability per reading of each simulated fault |

: Configuration variables.
