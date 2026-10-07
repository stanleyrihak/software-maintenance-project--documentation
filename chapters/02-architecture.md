# Architecture

<!--
WRITING NOTES (not printed in the PDF)

Purpose: how the system is built and how a reading travels through it.

Include:
- Diagram: device -> gateway -> cloud, plus the optional monitoring stack
  (diagrams/architecture.mmd).
- Each component, its job and its endpoints:
  - device (device/device.py): DS18B20 simulation (drift 15-30 C, error codes
    85/-127, stuck periods, disconnects), sends every 5 s;
  - gateway (gateway/app/): POST /device-data, validation, sensor-state
    tracking, encryption, forwarding; /health, /metrics;
  - cloud (cloud/app/): POST /data/secure, legacy POST /data (off by default),
    GET /data, SQLite storage on the cloud-data volume; /health, /metrics.
- Sequence diagram for one protected reading (gateway encapsulates, encrypts,
  cloud decapsulates, decrypts, checks timestamp, stores).
- Configuration: environment variables and .env (keys, legacy switch, DB path).

Sources: code repo at the submitted tag; README.md; docker-compose.yml.
-->
