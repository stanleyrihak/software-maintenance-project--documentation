# Baseline analysis

**The initial system (v1.0.0, 14 September).** The baseline was generated with
ChatGPT (GPT-4o) from the course brief and then reviewed. It had the three
services wired together by Docker Compose: a device script posting a random
temperature every five seconds, a FastAPI gateway on port 8000 that validated
the reading and forwarded it, and a FastAPI cloud service on port 8001 that kept
readings in a Python list in memory. Every link was plaintext HTTP. The LLM had
also proposed adding ML-KEM straight away; we deferred it, so that a simple,
working system existed first as a reference to compare against.

**How it was run and checked.** `docker compose up --build -d` started the three
containers. Manual checks confirmed that both `/health` endpoints answered, that
a valid reading travelled from the device to the cloud and appeared in
`GET /data`, and that an invalid reading (empty `device_id`) was rejected by the
gateway with `422` before reaching the cloud. After about an hour the cloud
held over 400 readings, with none lost.

**Baseline measurement.** The time for one reading to travel through the
gateway to the cloud and back was measured as the reference for later versions.
The same procedure was repeated for every later version on the same machine
(200 requests after 10 warm-up requests, from the host to the gateway's
published port): the plaintext baseline answered in a median of **4.75 ms**
(95th percentile 8.14 ms). Section *Testing and verification* compares all
versions.

**Weaknesses in the baseline.** The baseline was deliberately kept minimal, so
that it was easy to follow and could serve as a clear reference for later
versions. Its limitations were known and accepted from the start, and they
became the starting list for the improvements that followed:

- all traffic was plaintext, including the link from the gateway to the cloud;
- there were no automated tests and no CI pipeline;
- the gateway and the cloud validated readings differently (the cloud accepted
  an empty `device_id`), with no shared rule;
- storage was an unbounded in-memory list, lost on every restart;
- no endpoint was authenticated: anyone reaching ports 8000 or 8001 could send
  data for any device;
- the cloud had no metrics, and the gateway's `/metrics` answered with a
  redirect.
