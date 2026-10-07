# Operations

<!--
WRITING NOTES (not printed in the PDF)

Purpose: how the system is built, tested, deployed and observed.

Include:
- CI pipeline (.github/workflows/ci.yml): the jobs, what each checks, what
  fails a build.
- CD: versioned images on GHCR, deployment of the published images into an
  isolated test environment (CI job + local script), verification, rollback.
  Why local/CI and not an online server (course instruction).
- Health checks (/health), logs (what is logged where), metrics (table:
  metric -> meaning -> when to worry), optional Prometheus/Grafana/Alertmanager
  overlay with alert rules.
- How to run it (short; refer to the README).
- What is not production-ready: single host, no TLS, manual key handling.

Sources: ci.yml, docker-compose*.yml, monitoring/,
documentation/operations/reliability-monitoring.md in the code repo.
-->
