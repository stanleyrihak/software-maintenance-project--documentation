# Baseline system

## Legacy endpoint

The initial system was generated with ChatGPT-4o from the course brief and then reviewed.
It had the same three services wired together by Docker Compose: a device script posting a random temperature every five seconds, a FastAPI gateway on port 8000 that validated the reading and forwarded it, and a FastAPI cloud service on port 8001 that kept readings in a Python list in memory.

### Running

Script `docker compose up --build -d` started the three containers.
Manual checks confirmed that both `/health` endpoints answered, that a valid reading travelled from the device to the cloud and appeared in `GET /data`, and that an invalid reading (empty `device_id`) was rejected by the gateway with `422` before reaching the cloud.
After about an hour the cloud held over 400 readings, with none lost.
The time for one reading to travel through the gateway to the cloud and back was measured as the reference for later versions.
The same procedure was repeated for every later version on the same machine (200 requests after 10 warm-up requests, from the host to the gateway's published port): the plaintext baseline answered in a median of **4.75 ms** (95th percentile 8.14 ms).

### Weaknesses

The baseline was deliberately kept minimal, so that it was easy to follow and could serve as a clear template for ML-KEM integration:

- all traffic was plaintext, including the link from the gateway to the cloud,
- there were no automated tests and no CI pipeline,
- validation of readings for both gateway and cloud was very minimal,
- storage was an unbounded in-memory list, lost on every restart,
- there were no metrics for monitoring purposes.
