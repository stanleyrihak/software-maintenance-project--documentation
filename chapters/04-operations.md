# Operations

This chapter describes how the system is built, tested and deployed automatically, and how it can be watched while it runs.
The results of the tests are evaluated in *Final evaluation*.

## Build, test and deployment pipeline

The pipeline runs on GitHub Actions for every push and pull request (`.github/workflows/ci.yml`).
A change is accepted only when every step passes.

![The three stages of the pipeline.](figures/ci-pipeline.pdf){width=100%}

### Checks

Every Python file must compile, and each service runs its own unit tests.
The three Docker images are built, and the configuration of the optional monitoring stack (Prometheus) is validated, including tests of its alert rules.

### Test environments

The system is not deployed to an online server.
Instead, deployment is simulated: CI starts the system from scratch in an isolated test environment on a clean machine and checks it as a user would.
Each run generates its own throwaway keys, so no key is ever stored in the repository or in CI.

Two such environments are created, because the monitoring stack is optional: the first checks the system as it is normally run, and only the second can check the alerts.

- **Without monitoring:** CI checks that readings are encrypted and stored and that faults are handled.
- **With monitoring:** CI also checks that stored readings survive a restart, that plaintext is rejected, that sensor states are detected, and that stopping the cloud raises an alert that clears again after recovery.

The results are kept as files attached to the CI run, and the environment, including its data, is removed at the end.

### Publish

After all other steps have passed on the `main` branch, the three images are pushed to the GitHub Container Registry (GHCR), so the tested version is available as published images.

## Monitoring

### Health checks and logs

Both the gateway and the cloud answer `GET /health` with `{"status": "healthy"}` while they run.
CI uses this to wait until a started service is ready.

All services write their logs to the standard output, where `docker compose logs` shows them.
The gateway logs every received reading, every failure to reach the cloud and every disconnect report.
The cloud logs every stored reading, every use of the plaintext endpoint and every rejected encrypted request with its reason.

### Metrics and alerts

The gateway and the cloud expose metrics in the Prometheus format on `/metrics/`.
The table lists what is measured and when an alert is raised.

| What is watched | Metrics | Alert raised when |
|--------------------------|--------------------------------------|---------------------------|
| gateway or cloud down | — | the service cannot be reached for 2 minutes |
| readings received by the gateway | `device_messages_total` | — |
| forwarding to the cloud | `cloud_forward_attempts_total`, `cloud_forward_failures_total` | more than 5 % fail for 5 minutes |
| DS18B20 error codes | `sensor_fault_readings_total` | more than 20 % of readings for 5 minutes |
| disconnected sensors | `sensor_disconnected_devices`, `sensor_read_failures_total` | a sensor is disconnected for 30 seconds |
| stuck sensors | `sensor_suspected_stuck_devices`, `sensor_stuck_episodes_total` | a sensor is suspected to be stuck |
| silent sensors | `sensor_silent_devices` | a sensor stays silent for another 30 seconds |
| readings stored by the cloud | `secure_data_received_total` | — |
| rejected encrypted requests | `secure_data_rejected_total` (by reason) | any request is rejected |
| plaintext endpoint | `legacy_data_received_total`, `legacy_data_rejected_total` | it is used, or a request to it is refused |

: Metrics and alerts.

### Monitoring stack

The monitoring stack is optional and is started with a second Compose file, `docker-compose.monitoring.yml`.
It contains Prometheus, which collects the metrics every 15 seconds and keeps them for 30 days.
Grafana, with a ready-made dashboard and Alertmanager with a small local inbox that keeps the raised and resolved alerts.
All of it is reachable only from the local machine.

## Testing

### Automated tests

Each service has its own test bundle, written with `pytest`.
In total there are 164 automated tests.
Every bug fixed in the later versions got a regression test, which was first shown to fail on the old code.

![Number of tests for each part of the system.](figures/tests.svg){width=55%}

### Checks of the running system

Besides the unit tests, the running system was checked from the outside.
Tampered, outdated and invalid messages were sent to it over real HTTP, the cloud was restarted to check that stored readings survive, and the latency of one reading was measured for four versions of the system.
The results are presented in *Final evaluation*.